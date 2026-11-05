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

# Verify the INST decom microservice (Ruby) recovers when limits events are
# trimmed from the limits event stream before it can read them.
#
# Decom microservices read limits events between batches of packets. The stream
# only keeps ~1000 events, so a decom microservice that falls behind during a
# flood of LIMITS_CHANGE events can lose control events like a limits group
# disable. It must detect the gap and reload the limits settings from the store.
#
# 1. Stall the INST decom microservice by injecting the DECOM_STALL packet
# 2. Disable the INST_TEMP2 limits group while decom is stalled
# 3. Flood the stream with LIMITS_CHANGE events from INST2 until the group
#    event is trimmed
# 4. After decom resumes, verify it stopped checking limits on INST TEMP2
#
# Look for "Limits events were trimmed before they could be read, resyncing limits"
# from DEFAULT__DECOM__INST in the log messages. See procedures/limits_resync.py
# in INST2 for the same test of a Python decom microservice.

STALL_SECONDS = 30 # Long enough to flood the stream (max 300)
TARGET = 'INST'
FLOOD_TARGET = 'INST2' # Must have its own decom microservice
GROUP = 'INST_TEMP2'
FLOOD_ITEMS = %w(TEMP2 TEMP3 TEMP4) # TEMP1 has a limits response which sends commands

def stream_id(id)
  id.split('-').map(&:to_i)
end

def newest_limits_event_id
  newest = get_limits_events()
  newest.empty? ? '0-0' : newest[0][0]
end

# Script Runner instruments each line, so keep each condition on a single line
def group_event?(event)
  # Older versions send a LIMITS_ENABLE_STATE event per item instead of a group event
  return event['group_name'] == GROUP if event['type'] == 'LIMITS_GROUP_ENABLE_STATE'
  event['type'] == 'LIMITS_ENABLE_STATE' && event['target_name'] == TARGET && event['item_name'] == 'TEMP2'
end

def temp2_change?(event)
  return false unless event['type'] == 'LIMITS_CHANGE' && !event['new_limits_state'].to_s.empty?
  event['target_name'] == TARGET && event['packet_name'] == 'HEALTH_STATUS' && event['item_name'] == 'TEMP2'
end

begin
  enable_limits_group(GROUP)
  FLOOD_ITEMS.each { |item| enable_limits("#{FLOOD_TARGET} HEALTH_STATUS #{item}") }
  wait(2) # Let decom apply the enables

  # 1. Stall decom. Its CVT stops updating while it's stalled.
  stall_start = Time.now
  inject_tlm(TARGET, 'DECOM_STALL', { 'SECONDS' => STALL_SECONDS })
  wait(3)
  count = tlm("#{TARGET} HEALTH_STATUS RECEIVED_COUNT")
  wait(2)
  unless tlm("#{TARGET} HEALTH_STATUS RECEIVED_COUNT") == count
    raise "#{TARGET} decom microservice did not stall. Was the demo plugin upgraded with the DECOM_STALL packet?"
  end
  puts "#{TARGET} decom microservice stalled for #{STALL_SECONDS}s"

  # 2. Disable the group while decom can't read the event
  offset = newest_limits_event_id()
  disable_limits_group(GROUP)
  group_event = get_limits_events(offset, count: 1000).find { |_id, event| group_event?(event) }
  raise "Limits group event not found" unless group_event
  group_event_id = group_event[0]
  puts "Disabled #{GROUP} with event #{group_event_id}, limits_enabled? reports #{limits_enabled?("#{TARGET} HEALTH_STATUS TEMP2")}"

  # 3. Flood until the group event is trimmed from the stream
  trimmed = false
  injected = 0
  disable_instrumentation do
    while Time.now < stall_start + STALL_SECONDS - 3
      value = injected.even? ? 90.0 : 0.0 # RED_HIGH then GREEN
      # Call the API directly because inject_tlm prints every call, which overflows the script output
      $api_server.inject_tlm(FLOOD_TARGET, 'HEALTH_STATUS', FLOOD_ITEMS.to_h { |item| [item, value] }, type: :CONVERTED)
      injected += 1
      puts "Injected #{injected} #{FLOOD_TARGET} HEALTH_STATUS packets" if injected % 100 == 0
      next unless injected % 25 == 0

      oldest = get_limits_events('0-0', count: 1)
      if !oldest.empty? && (stream_id(oldest[0][0]) <=> stream_id(group_event_id)) > 0
        trimmed = true
        break
      end
    end
  end
  puts "Injected #{injected} #{FLOOD_TARGET} HEALTH_STATUS packets"
  raise "Group event was not trimmed before decom resumed. Increase STALL_SECONDS." unless trimmed
  puts "Group event #{group_event_id} trimmed from the limits event stream"

  # 4. Wait for decom to resume and work through its backlog
  remaining = stall_start + STALL_SECONDS + 30 - Time.now
  unless wait("#{TARGET} HEALTH_STATUS RECEIVED_COUNT > #{count}", remaining)
    raise "#{TARGET} decom microservice did not resume"
  end
  wait(3)

  # A decom microservice still checking TEMP2 reports these state changes
  offset = newest_limits_event_id()
  inject_tlm(TARGET, 'HEALTH_STATUS', { 'TEMP2' => 0.0 })
  wait(1)
  inject_tlm(TARGET, 'HEALTH_STATUS', { 'TEMP2' => 90.0 })
  wait(3)
  changes = get_limits_events(offset, count: 1000).select { |_id, event| temp2_change?(event) }
  if changes.empty?
    puts "PASS: #{TARGET} decom microservice resynced and stopped checking limits on TEMP2"
  else
    changes.each { |_id, event| puts event['message'] }
    raise "FAIL: #{TARGET} decom microservice missed the group event and is still checking limits on TEMP2"
  end
ensure
  enable_limits_group(GROUP)
end
