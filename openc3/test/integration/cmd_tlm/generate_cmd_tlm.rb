# encoding: ascii-8bit

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

# Generates a very large command and telemetry definition used to benchmark
# how long PacketConfig takes to process it. The output is deterministic for
# a given seed so runs can be compared across commits. The output directory is
# also a complete plugin that can be built into a gem and installed in COSMOS.
#
# Usage: ruby generate_cmd_tlm.rb [options]
# See --help for the options and their defaults.

require 'fileutils'
require 'optparse'

# Limits groups are nested rollups. Each level lists how many of it are in
# one of the level above, e.g. 10 payloads per vehicle. Only boards contain
# telemetry items, every other level contains the groups of the level below.
# One vehicle is about 1000 groups and 840 boards (~30 items each by default).
LIMITS_GROUP_LEVELS = [
  ['VEHICLE', 1],
  ['PAYLOAD', 10],
  ['SUBSYSTEM', 3],
  ['BOX', 4],
  ['BOARD', 7],
].freeze
# 1 + 10 + 10*3 + 10*3*4 + 10*3*4*7 = 1 + 10 + 30 + 120 + 840 = 1001
LIMITS_GROUPS_PER_VEHICLE = LIMITS_GROUP_LEVELS.each_index.sum { |i| LIMITS_GROUP_LEVELS[1..i].map(&:last).inject(1, :*) }
BOARDS_PER_VEHICLE = LIMITS_GROUP_LEVELS[1..].map(&:last).inject(1, :*)

options = {
  output: File.join(__dir__, 'generated'),
  target: 'BIG',
  language: 'ruby',
  # Sized so the installed target and QuestDB fit in a 16 GB Docker VM. Each
  # BIG microservice loads the whole definition and QuestDB keeps a writer
  # (~2.6 MB for a 532 column table) open for 10 minutes after each write.
  tlm_packets: 500,
  tlm_items: 125_000,
  tlm_states: 500_000,
  cmd_packets: 500,
  cmd_params: 125_000,
  vehicles: 1,
  limits_group_items: 25_000,
  desc_min: 50,
  desc_max: 250,
  seed: 1234,
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{File.basename(__FILE__)} [options]"
  opts.on('-o', '--output DIR', "Output directory (default: #{options[:output]})") { |v| options[:output] = v }
  opts.on('--target NAME', "Target name (default: #{options[:target]})") { |v| options[:target] = v.upcase }
  opts.on('--language LANG', %w(ruby python), "Plugin language: ruby or python (default: #{options[:language]})") { |v| options[:language] = v }
  opts.on('--tlm-packets N', Integer, "Telemetry packets (default: #{options[:tlm_packets]})") { |v| options[:tlm_packets] = v }
  opts.on('--tlm-items N', Integer, "Total telemetry items (default: #{options[:tlm_items]})") { |v| options[:tlm_items] = v }
  opts.on('--tlm-states N', Integer, "Total telemetry states (default: #{options[:tlm_states]})") { |v| options[:tlm_states] = v }
  opts.on('--cmd-packets N', Integer, "Command packets (default: #{options[:cmd_packets]})") { |v| options[:cmd_packets] = v }
  opts.on('--cmd-params N', Integer, "Total command parameters (default: #{options[:cmd_params]})") { |v| options[:cmd_params] = v }
  opts.on('--vehicles N', Integer, "Vehicles of #{LIMITS_GROUPS_PER_VEHICLE} nested limits groups, 0 for none (default: #{options[:vehicles]})") { |v| options[:vehicles] = v }
  opts.on('--limits-group-items N', Integer, "Telemetry items spread over the board limits groups (default: #{options[:limits_group_items]})") { |v| options[:limits_group_items] = v }
  opts.on('--desc-min N', Integer, "Min description length (default: #{options[:desc_min]})") { |v| options[:desc_min] = v }
  opts.on('--desc-max N', Integer, "Max description length (default: #{options[:desc_max]})") { |v| options[:desc_max] = v }
  opts.on('--seed N', Integer, "Random seed (default: #{options[:seed]})") { |v| options[:seed] = v }
end.parse!

if options[:tlm_items] < options[:tlm_packets] or options[:cmd_params] < options[:cmd_packets]
  abort "Every packet needs at least one item/parameter for its ID field"
end
vehicles = options[:vehicles]
options[:limits_group_items] = 0 if vehicles <= 0
if options[:limits_group_items] > options[:tlm_items]
  abort "--limits-group-items must be <= --tlm-items"
end
# Every other limits group item gets LIMITS, the rest get colored states
limits_value_items = (options[:limits_group_items] + 1) / 2
if limits_value_items == options[:tlm_items] and options[:tlm_states] > 0
  abort "--tlm-items must leave items for the states"
end
if vehicles > 0 and options[:limits_group_items] < vehicles * BOARDS_PER_VEHICLE
  abort "--limits-group-items must be at least one per board (#{vehicles * BOARDS_PER_VEHICLE} boards)"
end
if options[:desc_min] > options[:desc_max]
  abort "--desc-min must be <= --desc-max"
end

WORDS = %w(
  telemetry command sensor voltage current temperature pressure status mode
  counter register heater battery panel solar thruster valve wheel gyro star
  tracker antenna transmitter receiver payload instrument detector channel
  primary secondary redundant enable disable nominal fault safe hold reset
  bus power thermal attitude orbit housekeeping diagnostic calibrated raw
  measured commanded estimated filtered average minimum maximum the of for
  and from on in with value reported by subsystem controller interface
).freeze

$rng = Random.new(options[:seed])

# Random description between min and max characters made of words
def description(min, max)
  length = $rng.rand(min..max)
  desc = +''
  while desc.length < length
    desc << ' ' unless desc.empty?
    desc << WORDS[$rng.rand(WORDS.length)]
  end
  desc[0...length].rstrip.ljust(length, '.')
end

# Split total into count parts that differ by at most one
def distribute(total, count)
  base, extra = total.divmod(count)
  Array.new(count) { |i| i < extra ? base + 1 : base }
end

target = options[:target]
target_dir = File.join(options[:output], 'targets', target)
cmd_tlm_dir = File.join(target_dir, 'cmd_tlm')
FileUtils.mkdir_p(cmd_tlm_dir)
File.write(File.join(target_dir, 'target.txt'), "LANGUAGE #{options[:language]}\n")

start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# Telemetry: every packet starts with an ID item. The limits group items are
# spread evenly over every item (ID items included). Every other one gets
# LIMITS and the rest get GREEN, YELLOW and RED states. Items with STATE
# can't have LIMITS, so the states are spread evenly over every item without
# LIMITS so the totals are exact.
tlm_file = File.join(cmd_tlm_dir, 'tlm.txt')
items_per_packet = distribute(options[:tlm_items], options[:tlm_packets])
states_per_item = distribute(options[:tlm_states], options[:tlm_items] - limits_value_items)
STATE_COLORS = %w(GREEN YELLOW RED).freeze
item_index = 0
state_item_index = 0
limits_group_items = []
File.open(tlm_file, 'w') do |file|
  items_per_packet.each_with_index do |num_items, packet_index|
    file.puts "TELEMETRY #{target} PKT#{packet_index} BIG_ENDIAN \"#{description(options[:desc_min], options[:desc_max])}\""
    num_items.times do |i|
      grouped = ((item_index + 1) * options[:limits_group_items]) / options[:tlm_items] > (item_index * options[:limits_group_items]) / options[:tlm_items]
      item_index += 1
      limits = (grouped and limits_group_items.length.even?)
      limits_group_items << "PKT#{packet_index} #{i == 0 ? 'PKT_ID' : "ITEM#{i}"}" if grouped
      if limits
        num_states = 0
      else
        num_states = states_per_item[state_item_index]
        state_item_index += 1
        # With too few states to go around a grouped item without states
        # gets LIMITS instead so every grouped item is checked
        limits = (grouped and num_states == 0)
      end
      colors = (grouped and !limits)
      # Enough bits to hold a unique value for every state (and the packet ID)
      max_value = [num_states - 1, i == 0 ? packet_index : 0, 1].max
      bit_size = [16, max_value.bit_length].max
      bit_size = ((bit_size + 7) / 8) * 8
      desc = description(options[:desc_min], options[:desc_max])
      if i == 0
        file.puts "  APPEND_ID_ITEM PKT_ID #{bit_size} UINT #{packet_index} \"#{desc}\""
      else
        file.puts "  APPEND_ITEM ITEM#{i} #{bit_size} UINT \"#{desc}\""
      end
      if limits
        # Values from 0 up to half the range (including the packet ID) are
        # green, so a zero filled packet is green and rollups start green
        max = (1 << bit_size) - 1
        file.puts "    LIMITS DEFAULT 1 ENABLED -2 -1 #{max / 2} #{max * 3 / 4}"
      end
      num_states.times do |state|
        if colors
          file.puts "    STATE S#{state} #{state} #{STATE_COLORS[state % STATE_COLORS.length]}"
        else
          file.puts "    STATE S#{state} #{state}"
        end
      end
    end
    file.puts
  end
end

# Commands: every packet starts with an ID parameter. Packets and parameters
# get the same random descriptions as telemetry.
cmd_file = File.join(cmd_tlm_dir, 'cmd.txt')
params_per_packet = distribute(options[:cmd_params], options[:cmd_packets])
File.open(cmd_file, 'w') do |file|
  params_per_packet.each_with_index do |num_params, packet_index|
    file.puts "COMMAND #{target} CMD#{packet_index} BIG_ENDIAN \"#{description(options[:desc_min], options[:desc_max])}\""
    file.puts "  APPEND_ID_PARAMETER OPCODE 16 UINT MIN MAX #{packet_index} \"#{description(options[:desc_min], options[:desc_max])}\""
    (1...num_params).each do |i|
      file.puts "  APPEND_PARAMETER PARAM#{i} 32 UINT MIN MAX 0 \"#{description(options[:desc_min], options[:desc_max])}\""
    end
    file.puts
  end
end

# Limits groups: every vehicle is a tree of nested groups with the telemetry
# items in the boards at the bottom. Groups are written before the groups
# which contain them.
limits_groups_file = File.join(cmd_tlm_dir, 'limits_groups.txt')
num_limits_groups = 0
if vehicles > 0
  items_per_board = distribute(limits_group_items.length, vehicles * BOARDS_PER_VEHICLE)
  board_index = 0
  item_offset = 0
  File.open(limits_groups_file, 'w') do |file|
    write_group = lambda do |name, level|
      if level == LIMITS_GROUP_LEVELS.length - 1
        num_items = items_per_board[board_index]
        board_index += 1
        file.puts "LIMITS_GROUP #{name}"
        limits_group_items[item_offset, num_items].each { |item| file.puts "  LIMITS_GROUP_ITEM #{target} #{item}" }
        item_offset += num_items
      else
        child_name, count = LIMITS_GROUP_LEVELS[level + 1]
        children = Array.new(count) { |i| "#{name}_#{child_name}#{i}" }
        children.each { |child| write_group.call(child, level + 1) }
        file.puts "LIMITS_GROUP #{name}"
        children.each { |child| file.puts "  LIMITS_GROUP_ITEM #{child}" }
      end
      num_limits_groups += 1
      file.puts
    end
    vehicles.times { |i| write_group.call("#{LIMITS_GROUP_LEVELS[0][0]}#{i}", 0) }
  end
end
# The benchmark runs from Script Runner once the plugin is installed
benchmark_file = File.join(target_dir, 'procedures', 'limits_group_benchmark.rb')
if num_limits_groups > 0
  FileUtils.mkdir_p(File.dirname(benchmark_file))
  benchmark = File.read(File.join(__dir__, 'limits_group_benchmark.rb'))
  File.write(benchmark_file, benchmark.sub("TARGET = 'BIG'", "TARGET = '#{target}'"))
else
  FileUtils.rm_f(limits_groups_file)
  FileUtils.rm_f(benchmark_file)
end

# Plugin files so the output directory can be built into a gem and installed
# into an operational COSMOS. The interface connects to a TCP server that
# doesn't need to exist; it's there so COSMOS starts the interface and decom
# microservices that load the definition.
plugin_dir = options[:output]
plugin_name = "openc3-cosmos-#{target.downcase.tr('_', '-')}"
templates_dir = File.expand_path('../../../templates/plugin', __dir__)
FileUtils.cp(File.join(templates_dir, 'Rakefile'), plugin_dir)
FileUtils.cp(File.join(templates_dir, 'LICENSE.md'), plugin_dir)
Dir[File.join(plugin_dir, '*.gemspec')].each { |file| FileUtils.rm(file) }
requirements_file = File.join(plugin_dir, 'requirements.txt')
if options[:language] == 'python'
  File.write(requirements_file, "# Python dependencies\n")
  interface = 'openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 None BURST'
  extra_files = ' requirements.txt'
else
  FileUtils.rm_f(requirements_file)
  interface = 'tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST'
  extra_files = ''
end
target_var = "#{target.downcase}_target_name"
File.write(File.join(plugin_dir, 'plugin.txt'), <<~PLUGIN)
  # Generated by #{File.basename(__FILE__)}
  VARIABLE #{target_var} #{target}

  TARGET #{target} <%= #{target_var} %>
  INTERFACE <%= #{target_var} %>_INT #{interface}
    MAP_TARGET <%= #{target_var} %>
PLUGIN
File.write(File.join(plugin_dir, "#{plugin_name}.gemspec"), <<~GEMSPEC)
  # encoding: ascii-8bit

  Gem::Specification.new do |s|
    s.name = '#{plugin_name}'
    s.summary = 'OpenC3 #{plugin_name} plugin'
    s.description = <<-EOF
      Very large generated #{target} target (#{options[:language]}) for testing cmd/tlm processing
    EOF
    s.licenses = 'MIT'
    s.authors = ['OpenC3']
    s.email = ['support@openc3.com']
    s.homepage = 'https://github.com/OpenC3/cosmos'
    s.platform = Gem::Platform::RUBY
    s.required_ruby_version = '>= 3.0'

    if ENV['VERSION']
      s.version = ENV['VERSION'].dup
    else
      time = Time.now.strftime("%Y%m%d%H%M%S")
      s.version = '0.0.0' + ".\#{time}"
    end
    s.files = Dir.glob("targets/**/*") + %w(Rakefile README.md LICENSE.md plugin.txt#{extra_files})
  end
GEMSPEC
File.write(File.join(plugin_dir, 'README.md'), <<~README)
  # #{plugin_name}

  Generated by `openc3/test/integration/cmd_tlm/#{File.basename(__FILE__)}`.
  Contains the #{options[:language]} target #{target} with #{options[:tlm_packets]} telemetry
  packets (#{options[:tlm_items]} items, #{options[:tlm_states]} states) and
  #{options[:cmd_packets]} command packets (#{options[:cmd_params]} parameters).
  #{num_limits_groups} limits groups nested #{LIMITS_GROUP_LEVELS.map(&:first).reverse.join(' > ').downcase}
  contain #{limits_group_items.length} telemetry items.

  Run `targets/#{target}/procedures/limits_group_benchmark.rb` in Script Runner
  to benchmark the limits group microservice.

  Build from this directory with `rake build VERSION=1.0.0` (or
  `gem build #{plugin_name}.gemspec`) and install the resulting gem in COSMOS.
README

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "Generated #{options[:language]} plugin #{plugin_name} in #{elapsed.round(2)}s"
puts "  #{tlm_file} (#{(File.size(tlm_file) / 1_048_576.0).round(1)} MB): " \
     "#{options[:tlm_packets]} packets, #{options[:tlm_items]} items, #{options[:tlm_states]} states"
puts "  #{cmd_file} (#{(File.size(cmd_file) / 1_048_576.0).round(1)} MB): " \
     "#{options[:cmd_packets]} packets, #{options[:cmd_params]} parameters"
if num_limits_groups > 0
  puts "  #{limits_groups_file} (#{(File.size(limits_groups_file) / 1_048_576.0).round(1)} MB): " \
       "#{num_limits_groups} groups (#{vehicles} #{vehicles == 1 ? "vehicle" : "vehicles"}), #{limits_group_items.length} items"
end
