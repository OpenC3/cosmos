# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Benchmarks the limits group microservice against the target made by
# generate_cmd_tlm.rb, which copies this script into the target's procedures
# so it can be run from Script Runner once the plugin is installed.
#
# It starts with an untimed warm-up which sets every item GREEN. Packets the
# target has never received are sent in batches, waiting for the system to
# settle in between, since each one makes QuestDB create a table and creating
# thousands at once overwhelms it.
#
# It then injects telemetry to turn limits group items YELLOW and RED and measures:
#   - Latency: one item changes, how long until its LIMITS_GROUP rollup changes
#   - Bursts: a percentage of the items change at once, how long until the
#     microservice has caught up, and its event rate
#   - Microservice metrics: events processed and the time spent processing
#     them, which excludes the interface, decom and Redis delays
# and checks every group's rollup against the colors the script set.
#
# Values are written RAW so the items must not have conversions (the generated
# ones don't). The script ends with every item GREEN.

TARGET = 'BIG'
LATENCY_SAMPLES = 20       # Single item changes to RED and back to GREEN
BURST_PERCENTS = [1, 5]    # Percent of the group items changed per burst
RED_PERCENT = 30           # Percent of the burst items set RED, the rest YELLOW
WARM_UP_PACKETS = 100      # Never received packets sent per warm-up batch
SEED = 1234
TIMEOUT = 1800             # Seconds to wait for the microservice to catch up
MAX_POLL_SECONDS = 0.25    # Slowest poll while waiting for the microservice
PROGRESS_SECONDS = 30      # How often to report progress during long waits
QUIET_SECONDS = 1.0        # Quiet means a sentinel round trip is this fast and
                           # the target's decom, log and TSDB counts stop changing
API_RETRY_SECONDS = 300    # How long to keep retrying API calls which time out

MICROSERVICE = "#{$openc3_scope || 'DEFAULT'}__LIMITSGROUP__#{$openc3_scope || 'DEFAULT'}"
COLORS = { 'GREEN' => 0, 'YELLOW' => 1, 'RED' => 2 }
COLOR_NAMES = COLORS.invert

def now
  Time.now.to_f
end

# The API times out when the system is busy (e.g. QuestDB creating the tables
# for a new target) so keep retrying. Retrying an inject is harmless since it
# writes the same values again.
def with_retry(description)
  deadline = now + API_RETRY_SECONDS
  delay = 1
  begin
    # Script Runner instruments each line, which makes a begin block return
    # the instrumentation's value rather than the last line's, so return explicitly
    return yield
  rescue OpenC3::JsonDRbError => e
    raise if now > deadline

    puts "  #{description} failed, retrying in #{delay}s: #{e.message[0, 150]}"
    sleep delay
    delay = [delay * 2, 30].min
    retry
  end
end

def stats(values)
  return 'no samples' if values.empty?

  sorted = values.sort
  pct = ->(p) { sorted[[(p * sorted.length).ceil - 1, 0].max] }
  format('min %.1f  avg %.1f  p50 %.1f  p95 %.1f  max %.1f ms', sorted.first * 1000, sorted.sum / sorted.length * 1000, pct.(0.5) * 1000, pct.(0.95) * 1000, sorted.last * 1000)
end

# @return [Hash] the limits group microservice's metric values
def microservice_metrics
  service = with_retry('get_metrics') { get_metrics(detailed: true) }['services'][MICROSERVICE]
  raise "No metrics for #{MICROSERVICE}. Is the limits group microservice running?" unless service

  service['values'].transform_values { |data| data['value'] }.merge('updated_at' => service['updated_at'])
end

# Metrics are published every few seconds so wait for a publish after time
def wait_for_metrics(time)
  deadline = now + 60
  loop do
    metrics = microservice_metrics()
    return metrics if metrics['updated_at'].to_i > time * 1_000_000_000
    raise "Timed out waiting for #{MICROSERVICE} metrics" if now > deadline

    sleep 1
  end
end

# Polls the group's rollup in the CVT until it's the given color. Polls
# quickly at first for latency and backs off during long waits so the API
# isn't flooded with requests. The published time comes from the packet so it
# doesn't depend on the poll rate.
# @return [Array(Float, Float)] when the script saw it and when the microservice published it
def wait_for_group(group, color, timeout: 30)
  names = ["#{TARGET}__LIMITS_GROUP__#{group}__RAW", "#{TARGET}__LIMITS_GROUP__RECEIVED_TIMESECONDS__RAW"]
  start = now
  deadline = start + timeout
  next_progress = start + PROGRESS_SECONDS
  delay = 0.002
  loop do
    value, received = with_retry('get_tlm_values') { get_tlm_values(names) }.map(&:first)
    return [now, received.to_f] if value == COLORS[color]
    raise "Timed out waiting for #{TARGET} LIMITS_GROUP #{group} to be #{color}" if now > deadline

    if now > next_progress
      events = (microservice_metrics()['limits_group_event_total'] rescue 'unknown')
      puts format("  Still waiting after %.0fs, microservice has processed %s events", now - start, events)
      next_progress = now + PROGRESS_SECONDS
    end
    sleep delay
    delay = [delay * 1.5, MAX_POLL_SECONDS].min
  end
end

# Calls the API directly since inject_tlm logs every item hash to the output
def inject(changes)
  changes.group_by { |item| item[:packet] }.each do |packet, items|
    with_retry("inject_tlm #{packet}") { $api_server.inject_tlm(TARGET, packet, items.to_h { |item| [item[:item], item[:value]] }, type: :RAW) }
  end
end

# Limits events are processed in order so once the sentinel's group changes
# every event injected before it has been processed. The sentinel's group only
# contains items no other test changes so it ends GREEN.
# @return [Array(Float, Float)] when the microservice published the sentinel's
#   change and when it had processed everything including the sentinel
def wait_for_microservice(timeout: TIMEOUT)
  inject([@sentinel.merge(value: @sentinel[:values]['RED'])])
  _seen, received = wait_for_group(@sentinel[:group], 'RED', timeout: timeout)
  inject([@sentinel.merge(value: @sentinel[:values]['GREEN'])])
  done, _published = wait_for_group(@sentinel[:group], 'GREEN')
  [received, done]
end

# Waits until every one of the target's microservices (decom, logs, TSDB) has
# published its metrics after time
# @return [Integer, nil] the sum of their *_total counts, nil if they have no metrics
def target_total_after(time)
  deadline = now + 60
  loop do
    services = with_retry('get_metrics') { get_metrics(detailed: true) }['services'].select { |name, _service| name.end_with?("__#{TARGET}") }
    return nil if services.empty?
    if services.all? { |_name, service| service['updated_at'].to_i > time * 1_000_000_000 } or now > deadline
      return services.sum { |_name, service| service['values'].sum { |metric, data| metric.end_with?('_total') ? data['value'].to_i : 0 } }
    end

    sleep 1
  end
end

# Waits until the system has caught up with earlier work so it doesn't slow
# down the next test. The sentinel covers the path to the microservice but not
# TSDB, so also wait for the target's counts to stop changing between metric
# updates (every 5s). Lag metrics can't be used since an idle service keeps its last lag.
def wait_for_quiet
  start = now
  loop do
    round_trip = now
    wait_for_microservice()
    round_trip = now - round_trip
    # The sentinel's own packets are counted once the services publish after it
    # (plus a second for TSDB to write them). Then compare with the next update.
    before = target_total_after(now + 1)
    changed = before ? target_total_after(now) - before : 0
    return if round_trip < QUIET_SECONDS and changed == 0
    raise "System still busy after #{TIMEOUT}s" if now - start > TIMEOUT

    puts format("  Waiting for the system to settle: sentinel took %.1fs, %s counts changed by %d in the last update", round_trip, TARGET, changed)
    sleep 5
  end
end

# Every group's rollup must be the most severe color of its members
def check_rollups(item_colors)
  expected = {}
  # Script Runner instruments each line, and a line like `end.max` makes the
  # block it closes return nil, so keep the block on one line
  rollup = lambda do |group|
    return expected[group] if expected.key?(group)

    colors = @groups[group].map { |_target, packet, item| packet == 'LIMITS_GROUP' ? rollup.(item) : COLORS[item_colors["#{packet} #{item}"] || 'GREEN'] }
    expected[group] = colors.max
  end
  @groups.each_key { |group| rollup.(group) }
  actual = with_retry('get_tlm_packet') { get_tlm_packet(TARGET, 'LIMITS_GROUP', type: :RAW) }.to_h { |name, value, _limits| [name, value] }
  wrong = expected.reject { |group, color| actual[group] == color }
  if wrong.empty?
    puts "  Rollups: all #{expected.length} groups correct"
  else
    wrong.first(5).each { |group, color| puts "  WRONG: #{group} is #{COLOR_NAMES[actual[group]]} but should be #{COLOR_NAMES[color]}" }
    @failures << "#{wrong.length} wrong rollups"
  end
end

# Changes the items, waits for the microservice and reports the rates
def burst(name, changes, item_colors)
  wait_for_quiet()
  before = wait_for_metrics(now)
  start = now
  inject(changes)
  injected = now
  received, done = wait_for_microservice()
  after = wait_for_metrics(done)
  # Less the sentinel's two events
  events = after['limits_group_event_total'].to_i - before['limits_group_event_total'].to_i - 2
  if events != changes.length
    puts "  WARN: #{events} events but expected #{changes.length}. Were the items already these colors?"
  end
  processing = after['limits_group_processing_seconds_total'].to_f - before['limits_group_processing_seconds_total'].to_f
  publishes = after['limits_group_publish_total'].to_i - before['limits_group_publish_total'].to_i
  @results << [name, changes.length, injected - start, received - start, events, processing, publishes, after['limits_group_topic_delta_seconds'].to_f]
  puts format("  %d items: inject %.2fs, caught up %.2fs after the first inject, %d events in %.2fs of processing (%.2f ms/event), %d publishes", changes.length, injected - start, received - start, events, processing, events > 0 ? processing / events * 1000 : 0, publishes)
  check_rollups(item_colors)
end

disable_instrumentation do
  @results = []
  @failures = []
  rng = Random.new(SEED)

  # Group definitions: board groups hold items, the others hold nested groups
  @groups = with_retry('get_limits_groups') { get_limits_groups(TARGET) }
  raise "#{TARGET} has no limits groups" if @groups.empty?
  item_group = {}
  @groups.each do |group, members|
    members.each { |_target, packet, item| item_group["#{packet} #{item}"] = group unless packet == 'LIMITS_GROUP' }
  end
  nested = @groups.values.flatten(1).select { |_target, packet, _item| packet == 'LIMITS_GROUP' }.map(&:last)
  top_groups = @groups.keys - nested
  puts "#{@groups.length} groups (top: #{top_groups.join(', ')}), #{item_group.length} items"

  # The RAW value which makes each item GREEN, YELLOW and RED
  puts "Reading packet definitions..."
  items = []
  packets = item_group.keys.map(&:split).group_by(&:first)
  packets.each_with_index do |(packet, packet_items), index|
    puts "  #{index} of #{packets.length} packets" if index > 0 and index % 250 == 0
    definitions = with_retry("get_tlm #{packet}") { get_tlm(TARGET, packet) }['items'].to_h { |item| [item['name'], item] }
    packet_items.each do |_packet, item|
      definition = definitions[item]
      values = {}
      if definition['states']
        definition['states'].each_value { |state| values[state['color']] ||= state['value'] if state['color'] }
      elsif (limits = definition.dig('limits', 'DEFAULT'))
        values['GREEN'] = (limits['yellow_low'] + limits['yellow_high']) / 2
        values['YELLOW'] = limits['yellow_high'] + 1 if limits['yellow_high'] + 1 < limits['red_high']
        values['RED'] = limits['red_high'] + 1
      end
      next unless values['GREEN'] and (values['YELLOW'] or values['RED'])

      items << { packet: packet, item: item, group: item_group["#{packet} #{item}"], values: values }
    end
  end
  puts "#{items.length} items can change color (#{items.count { |item| item[:values]['RED'] }} RED, #{items.count { |item| item[:values]['YELLOW'] }} YELLOW)"

  # The sentinel's group is left out of the tests so only the sentinel changes it
  @sentinel = items.reverse.find { |item| item[:values]['RED'] }
  raise "No item can go RED" unless @sentinel
  testable = items.reject { |item| item[:group] == @sentinel[:group] }

  # Warm-up: every item GREEN. Not timed since never received items raise
  # events and their packets create QuestDB tables.
  puts "\nWarm-up: every item GREEN"
  green = items.map { |item| item.merge(value: item[:values]['GREEN']) }
  counts = with_retry('get_tlm_values') { get_tlm_values(packets.keys.map { |packet| "#{TARGET}__#{packet}__RECEIVED_COUNT__RAW" }) }
  received = packets.keys.zip(counts).select { |_packet, (count, _limits)| count.to_i > 0 }.map(&:first).to_set
  green_received, green_new = green.partition { |item| received.include?(item[:packet]) }
  inject(green_received)
  new_packets = green_new.group_by { |item| item[:packet] }.to_a
  puts "  #{received.length} packets received before, #{new_packets.length} never received" unless new_packets.empty?
  new_packets.each_slice(WARM_UP_PACKETS).with_index do |batch, index|
    inject(batch.flat_map(&:last))
    puts "  Sent #{[(index + 1) * WARM_UP_PACKETS, new_packets.length].min} of #{new_packets.length} new packets, waiting for the system to settle"
    wait_for_quiet()
  end
  wait_for_quiet()
  check_rollups({})

  puts "\nLatency: one item to RED and back to GREEN, #{LATENCY_SAMPLES} times"
  wait_for_quiet()
  red = { 'seen' => [], 'published' => [] }
  green = { 'seen' => [], 'published' => [] }
  testable.select { |item| item[:values]['RED'] }.sample(LATENCY_SAMPLES, random: rng).each do |item|
    [['RED', red], ['GREEN', green]].each do |color, samples|
      start = now
      inject([item.merge(value: item[:values][color])])
      seen, published = wait_for_group(item[:group], color)
      samples['seen'] << seen - start
      samples['published'] << published - start
    end
  end
  puts "  To RED, published:  #{stats(red['published'])}"
  puts "  To RED, seen:       #{stats(red['seen'])}"
  puts "  To GREEN, published: #{stats(green['published'])}"
  puts "  To GREEN, seen:      #{stats(green['seen'])}"

  BURST_PERCENTS.each do |percent|
    selected = testable.sample((testable.length * percent / 100.0).round, random: rng)
    colors = {}
    changes = selected.map do |item|
      color = rng.rand(100) < RED_PERCENT ? 'RED' : 'YELLOW'
      color = (%w(RED YELLOW) - [color]).first unless item[:values][color]
      colors["#{item[:packet]} #{item[:item]}"] = color
      item.merge(value: item[:values][color])
    end
    puts "\nBurst #{percent}%: #{colors.values.tally.sort.map { |color, count| "#{count} #{color}" }.join(', ')}"
    burst("#{percent}% out", changes, colors)
    puts "Burst #{percent}%: back to GREEN"
    burst("#{percent}% back", selected.map { |item| item.merge(value: item[:values]['GREEN']) }, {})
  end

  puts "\nSummary (caught up = first inject until the microservice published the sentinel)"
  puts format("  %-12s %8s %9s %11s %8s %11s %9s %10s %9s", 'Test', 'Items', 'Inject s', 'Caught up s', 'Events', 'Process s', 'ms/event', 'Publishes', 'Lag s')
  @results.each do |name, count, inject_time, caught_up, events, processing, publishes, lag|
    puts format("  %-12s %8d %9.2f %11.2f %8d %11.2f %9.3f %10d %9.2f", name, count, inject_time, caught_up, events, processing, events > 0 ? processing / events * 1000 : 0, publishes, lag)
  end
  raise "FAILED: #{@failures.join(', ')}" unless @failures.empty?
end
