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
# a given seed so runs can be compared across commits.
#
# Usage: ruby generate_cmd_tlm.rb [options]
# See --help for the options and their defaults.

require 'fileutils'
require 'optparse'

options = {
  output: File.join(__dir__, 'generated'),
  target: 'BIG',
  tlm_packets: 2_000,
  tlm_items: 500_000,
  tlm_states: 2_000_000,
  cmd_packets: 2_000,
  cmd_params: 150_000,
  desc_min: 50,
  desc_max: 250,
  seed: 1234,
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby #{File.basename(__FILE__)} [options]"
  opts.on('-o', '--output DIR', "Output directory (default: #{options[:output]})") { |v| options[:output] = v }
  opts.on('--target NAME', "Target name (default: #{options[:target]})") { |v| options[:target] = v.upcase }
  opts.on('--tlm-packets N', Integer, "Telemetry packets (default: #{options[:tlm_packets]})") { |v| options[:tlm_packets] = v }
  opts.on('--tlm-items N', Integer, "Total telemetry items (default: #{options[:tlm_items]})") { |v| options[:tlm_items] = v }
  opts.on('--tlm-states N', Integer, "Total telemetry states (default: #{options[:tlm_states]})") { |v| options[:tlm_states] = v }
  opts.on('--cmd-packets N', Integer, "Command packets (default: #{options[:cmd_packets]})") { |v| options[:cmd_packets] = v }
  opts.on('--cmd-params N', Integer, "Total command parameters (default: #{options[:cmd_params]})") { |v| options[:cmd_params] = v }
  opts.on('--desc-min N', Integer, "Min description length (default: #{options[:desc_min]})") { |v| options[:desc_min] = v }
  opts.on('--desc-max N', Integer, "Max description length (default: #{options[:desc_max]})") { |v| options[:desc_max] = v }
  opts.on('--seed N', Integer, "Random seed (default: #{options[:seed]})") { |v| options[:seed] = v }
end.parse!

if options[:tlm_items] < options[:tlm_packets] or options[:cmd_params] < options[:cmd_packets]
  abort "Every packet needs at least one item/parameter for its ID field"
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
File.write(File.join(target_dir, 'target.txt'), "LANGUAGE ruby\n")

start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# Telemetry: every packet starts with an ID item. States are spread evenly
# over every item (ID items included) so the totals are exact.
tlm_file = File.join(cmd_tlm_dir, 'tlm.txt')
items_per_packet = distribute(options[:tlm_items], options[:tlm_packets])
states_per_item = distribute(options[:tlm_states], options[:tlm_items])
item_index = 0
File.open(tlm_file, 'w') do |file|
  items_per_packet.each_with_index do |num_items, packet_index|
    file.puts "TELEMETRY #{target} PKT#{packet_index} BIG_ENDIAN \"#{description(options[:desc_min], options[:desc_max])}\""
    num_items.times do |i|
      num_states = states_per_item[item_index]
      item_index += 1
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
      num_states.times do |state|
        file.puts "    STATE S#{state} #{state}"
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

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "Generated #{target} in #{elapsed.round(2)}s"
puts "  #{tlm_file} (#{(File.size(tlm_file) / 1_048_576.0).round(1)} MB): " \
     "#{options[:tlm_packets]} packets, #{options[:tlm_items]} items, #{options[:tlm_states]} states"
puts "  #{cmd_file} (#{(File.size(cmd_file) / 1_048_576.0).round(1)} MB): " \
     "#{options[:cmd_packets]} packets, #{options[:cmd_params]} parameters"
