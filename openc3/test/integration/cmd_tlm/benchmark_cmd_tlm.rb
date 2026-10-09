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

# Times how long PacketConfig takes to process the definition created by
# generate_cmd_tlm.rb, plus the as_json / JSON.generate step TargetModel
# performs on every packet when it stores the target in Redis.
#
# Usage (from the openc3 directory):
#   bundle exec ruby test/integration/cmd_tlm/benchmark_cmd_tlm.rb [--no-descriptions] [generated_dir] [target]
#
# --no-descriptions drops descriptions while parsing, as the decom and interface
# microservices do. The JSON step then reflects that smaller definition.

ENV['OPENC3_NO_STORE'] = '1'

require 'json'
require 'openc3'
require 'openc3/packets/packet_config'

OpenC3::Logger.stdout = false

descriptions = !ARGV.delete('--no-descriptions')
dir = ARGV[0] || File.join(__dir__, 'generated')
target = (ARGV[1] || 'BIG').upcase
cmd_tlm_dir = File.join(dir, 'targets', target, 'cmd_tlm')
tlm_file = File.join(cmd_tlm_dir, 'tlm.txt')
cmd_file = File.join(cmd_tlm_dir, 'cmd.txt')
[tlm_file, cmd_file].each do |file|
  abort "#{file} not found. Run generate_cmd_tlm.rb first." unless File.exist?(file)
end

def rss_mb
  (`ps -o rss= -p #{Process.pid}`.to_i / 1024.0).round(1)
end

def measure(label)
  GC.start
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = yield
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  puts format('%-28s %9.2fs  RSS %8.1f MB', label, elapsed, rss_mb)
  [result, elapsed]
end

puts "Ruby #{RUBY_VERSION}#{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? ' +YJIT' : ''}" \
     "#{ENV['OPENC3_NO_EXT'] ? ' (no C ext)' : ''}#{descriptions ? '' : ' (no descriptions)'}"
puts format('%-28s %10s  RSS %8.1f MB', 'start', '', rss_mb)

total = 0.0
pc = OpenC3::PacketConfig.new(descriptions: descriptions)
_, t = measure('process tlm.txt') { pc.process_file(tlm_file, target) }
total += t
_, t = measure('process cmd.txt') { pc.process_file(cmd_file, target) }
total += t

tlm = pc.telemetry[target]
cmd = pc.commands[target]
num_items = tlm.values.sum { |p| p.sorted_items.length }
num_states = tlm.values.sum { |p| p.sorted_items.sum { |i| i.states ? i.states.length : 0 } }
num_params = cmd.values.sum { |p| p.sorted_items.length }

bytes = 0
_, t = measure('tlm as_json + JSON') do
  tlm.each_value { |packet| bytes += JSON.generate(packet.as_json, allow_nan: true).bytesize }
end
total += t
_, t = measure('cmd as_json + JSON') do
  cmd.each_value { |packet| bytes += JSON.generate(packet.as_json, allow_nan: true).bytesize }
end
total += t

puts format('%-28s %9.2fs', 'total', total)
puts "Parsed #{tlm.length} tlm packets, #{num_items} items (incl. derived), #{num_states} states; " \
     "#{cmd.length} cmd packets, #{num_params} params (incl. derived)"
puts "JSON size #{(bytes / 1_048_576.0).round(1)} MB"
