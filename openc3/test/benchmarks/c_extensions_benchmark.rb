# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Compares OpenC3's C extensions with their Ruby implementations. Each mode is
# run with YJIT in a fresh process because OPENC3_NO_EXT must be set before
# OpenC3 loads.

require 'json'
require 'open3'
require 'rbconfig'

ROOT = File.expand_path('../..', __dir__)

if ARGV.delete('--worker')
  ENV['OPENC3_NO_STORE'] = '1'

  require 'stringio'
  require 'tempfile'
  require 'openc3'
  require 'openc3/config/config_parser'
  require 'openc3/conversions/polynomial_conversion'
  require 'openc3/core_ext/stringio'
  require 'openc3/interfaces/protocols/burst_protocol'
  require 'openc3/io/buffered_file'
  require 'openc3/packets/telemetry'
  require 'openc3/utilities/crc'

  OpenC3::Logger.stdout = false

  native_mode = !ENV.key?('OPENC3_NO_EXT')

  # This extension is no longer required by Ruby production code and has no
  # checked-in fallback. Define the direct Ruby equivalent for comparison.
  if native_mode
    require 'openc3/ext/tabbed_plots_config'
  else
    module OpenC3
      class TabbedPlotsConfig
        def process_packet_in_each_data_object(data_objects, packet, packet_count)
          data_objects.each { |data_object| data_object.process_packet(packet, packet_count) }
          nil
        end
      end
    end
  end

  Case = Struct.new(:extension, :name, :units, :run, :signature, keyword_init: true)
  cases = []

  add_case = lambda do |extension, name, units, run, signature|
    cases << Case.new(extension: extension, name: name, units: units,
                      run: run, signature: signature)
  end

  numbers = Array.new(1_024) { |index| (index * 7919) % 65_521 }
  add_case.call('array', 'max_with_index (1K values)', 100,
                -> { 100.times { numbers.max_with_index } },
                -> { numbers.max_with_index })
  add_case.call('array', 'min_with_index (1K values)', 100,
                -> { 100.times { numbers.min_with_index } },
                -> { numbers.min_with_index })

  quoted = '"telemetry value with spaces"'
  add_case.call('string', 'remove_quotes', 10_000,
                -> { 10_000.times { quoted.remove_quotes } },
                -> { quoted.remove_quotes })

  polynomial = OpenC3::PolynomialConversion.new(1.25, -0.5, 0.125, 0.01, -0.001)
  add_case.call('polynomial_conversion', 'call (5 coefficients)', 10_000,
                -> { 10_000.times { polynomial.call(12.5, nil, nil) } },
                -> { polynomial.call(12.5, nil, nil) })

  crc32 = OpenC3::Crc32.new
  crc_small = (0...32).map { |index| index.chr }.join.b
  crc_large = crc_small * 128
  add_case.call('crc', 'CRC32.new', 100,
                -> { 100.times { OpenC3::Crc32.new } },
                -> { OpenC3::Crc32.new.calc('123456789') })
  add_case.call('crc', 'CRC32 (32 bytes)', 500,
                -> { 500.times { crc32.calc(crc_small) } },
                -> { crc32.calc(crc_small) })
  add_case.call('crc', 'CRC32 (4KB)', 10,
                -> { 10.times { crc32.calc(crc_large) } },
                -> { crc32.calc(crc_large) })

  binary_data = (0...64).map { |index| index.chr }.join.b
  add_case.call('packet/structure', 'BinaryAccessor.read UINT32', 10_000,
                -> { 10_000.times { OpenC3::BinaryAccessor.read(13, 32, :UINT, binary_data, :BIG_ENDIAN) } },
                -> { OpenC3::BinaryAccessor.read(13, 32, :UINT, binary_data, :BIG_ENDIAN) })
  add_case.call('packet/structure', 'BinaryAccessor.write UINT32', 10_000,
                -> { 10_000.times { OpenC3::BinaryAccessor.write(0x12345678, 13, 32, :UINT, binary_data, :BIG_ENDIAN, :ERROR) } },
                -> do
                  data = binary_data.dup
                  OpenC3::BinaryAccessor.write(0x12345678, 13, 32, :UINT, data, :BIG_ENDIAN, :ERROR)
                  data.unpack1('H*')
                end)

  packet = OpenC3::Packet.new('target', 'packet', :BIG_ENDIAN)
  packet.define_item('VALUE', 0, 16, :UINT)
  packet.write('VALUE', 42)
  item = packet.get_item('VALUE')
  add_case.call('packet/structure', 'Structure#read_item', 10_000,
                -> { 10_000.times { packet.read_item(item) } },
                -> { packet.read_item(item) })
  add_case.call('packet/structure', 'Packet.new', 1_000,
                -> { 1_000.times { OpenC3::Packet.new('target', 'packet', :BIG_ENDIAN) } },
                -> do
                  result = OpenC3::Packet.new('target', 'packet', :BIG_ENDIAN)
                  [result.target_name, result.packet_name, result.received_count]
                end)

  telemetry_config = Struct.new(:telemetry).new({ 'TARGET' => { 'PACKET' => packet } })
  telemetry = OpenC3::Telemetry.new(telemetry_config)
  add_case.call('telemetry', 'packet lookup', 10_000,
                -> { 10_000.times { telemetry.packet('target', 'packet') } },
                -> { telemetry.packet('target', 'packet').packet_name })
  add_case.call('telemetry', 'value lookup and read', 5_000,
                -> { 5_000.times { telemetry.value('target', 'packet', 'value', :RAW) } },
                -> { telemetry.value('target', 'packet', 'value', :RAW) })

  framed_payload = '0123456789ABCDEF'.b
  framed_data = ([framed_payload.bytesize].pack('n') + framed_payload) * 256
  framed_io = StringIO.new(framed_data)
  add_case.call('openc3_io', 'read_length_bytes (16-byte frames)', 256,
                -> do
                  framed_io.rewind
                  256.times { framed_io.read_length_bytes(2) }
                end,
                -> do
                  io = StringIO.new([framed_payload.bytesize].pack('n') + framed_payload)
                  io.read_length_bytes(2)
                end)

  config_text = 500.times.map do |index|
    %(KEYWORD#{index % 10} PARAM#{index} "description #{index}" # comment\n)
  end.join
  config_io = StringIO.new(config_text)
  parser = OpenC3::ConfigParser.new
  parsed_count = 0
  parse_config = lambda do
    config_io.rewind
    parsed_count = 0
    parser.send(:parse_loop, config_io, false, true, config_text.bytesize.to_f,
                OpenC3::ConfigParser::PARSING_REGEX) { parsed_count += 1 }
    parsed_count
  end
  add_case.call('config_parser', 'parse_loop (config lines)', 500,
                parse_config, parse_config)

  burst = OpenC3::BurstProtocol.new(4, '1ACFFC1D', false, nil)
  burst_data = "\x1A\xCF\xFC\x1D".b + ('x'.b * 252)
  add_case.call('burst_protocol', 'read_data (256-byte synced burst)', 1_000,
                -> { 1_000.times { burst.read_data(burst_data) } },
                -> { burst.read_data(burst_data).first.bytesize })

  buffered_tempfile = Tempfile.new('openc3-c-extension-benchmark')
  buffered_tempfile.binmode
  buffered_tempfile.write(('0123456789ABCDEF'.b * 4_096))
  buffered_tempfile.flush
  buffered_file = OpenC3::BufferedFile.open(buffered_tempfile.path, 'rb')
  at_exit do
    buffered_file.close unless buffered_file.closed?
    buffered_tempfile.close!
  end
  read_buffered_file = lambda do
    buffered_file.seek(0)
    1_024.times { buffered_file.read(16) }
  end
  add_case.call('buffered_file', 'small sequential reads', 1_024,
                read_buffered_file,
                -> do
                  buffered_file.seek(0)
                  [buffered_file.read(16), buffered_file.pos]
                end)

  data_object_class = Class.new do
    def process_packet(packet_arg, count_arg)
      packet_arg ^ count_arg
    end
  end
  data_objects = Array.new(20) { data_object_class.new }
  tabbed_config = OpenC3::TabbedPlotsConfig.new
  process_plot_objects = lambda do
    1_000.times do
      tabbed_config.process_packet_in_each_data_object(data_objects, 0x55, 100)
    end
  end
  verify_plot_dispatch = lambda do
    verifier_class = Class.new do
      attr_reader :calls

      def initialize
        @calls = 0
      end

      def process_packet(_packet, _packet_count)
        @calls += 1
      end
    end
    verifiers = Array.new(20) { verifier_class.new }
    tabbed_config.process_packet_in_each_data_object(verifiers, 0x55, 100)
    verifiers.sum(&:calls)
  end
  add_case.call('tabbed_plots_config', 'dispatch to 20 data objects', 20_000,
                process_plot_objects, verify_plot_dispatch)

  if native_mode
    native_methods = {
      'array' => Array.instance_method(:max_with_index),
      'buffered_file' => OpenC3::BufferedFile.instance_method(:read),
      'burst_protocol' => OpenC3::BurstProtocol.instance_method(:read_data),
      'config_parser' => OpenC3::ConfigParser.instance_method(:parse_loop),
      'crc' => OpenC3::Crc32.instance_method(:calc),
      'openc3_io' => OpenC3IO.instance_method(:read_length_bytes),
      'packet' => OpenC3::Packet.instance_method(:initialize),
      'polynomial_conversion' => OpenC3::PolynomialConversion.instance_method(:call),
      'string' => String.instance_method(:remove_quotes),
      'tabbed_plots_config' => OpenC3::TabbedPlotsConfig.instance_method(:process_packet_in_each_data_object),
      'telemetry' => OpenC3::Telemetry.instance_method(:packet)
    }
    not_native = native_methods.filter_map { |name, method| name if method.source_location }
    raise "Expected native methods, but Ruby methods loaded for: #{not_native.join(', ')}" unless not_native.empty?
  end

  warmup_seconds = Float(ENV.fetch('OPENC3_BENCHMARK_WARMUP', '0.25'))
  sample_seconds = Float(ENV.fetch('OPENC3_BENCHMARK_TIME', '0.5'))
  sample_count = Integer(ENV.fetch('OPENC3_BENCHMARK_SAMPLES', '5'))
  filter = ENV.fetch('OPENC3_BENCHMARK_FILTER', nil)
  cases.select! { |benchmark| benchmark.extension.include?(filter) || benchmark.name.include?(filter) } if filter
  raise "No benchmarks matched OPENC3_BENCHMARK_FILTER=#{filter.inspect}" if cases.empty?

  clock = Process::CLOCK_MONOTONIC
  results = cases.map do |benchmark|
    warmup_started = Process.clock_gettime(clock)
    warmup_runs = 0
    begin
      benchmark.run.call
      warmup_runs += 1
    end while Process.clock_gettime(clock) - warmup_started < warmup_seconds
    warmup_elapsed = Process.clock_gettime(clock) - warmup_started
    runs_per_sample = [(warmup_runs * sample_seconds / warmup_elapsed).ceil, 1].max

    samples = Array.new(sample_count) do
      GC.start
      started = Process.clock_gettime(clock)
      runs_per_sample.times { benchmark.run.call }
      elapsed = Process.clock_gettime(clock) - started
      (runs_per_sample * benchmark.units) / elapsed
    end.sort

    median = samples[samples.length / 2]
    mean = samples.sum / samples.length
    variance = samples.sum { |sample| (sample - mean)**2 } / samples.length
    {
      extension: benchmark.extension,
      name: benchmark.name,
      ips: median,
      cv_percent: mean.zero? ? 0.0 : Math.sqrt(variance) / mean * 100.0,
      signature: benchmark.signature.call
    }
  end

  puts JSON.generate(
    mode: native_mode ? 'c_extension' : 'pure_ruby',
    ruby: RUBY_DESCRIPTION,
    warmup_seconds: warmup_seconds,
    sample_seconds: sample_seconds,
    sample_count: sample_count,
    results: results
  )
  exit
end

def run_worker(native_mode)
  environment = {
    'OPENC3_NO_STORE' => '1',
    'OPENC3_NO_EXT' => native_mode ? nil : '1'
  }
  command = [RbConfig.ruby, '--yjit', '-I', File.join(ROOT, 'lib'), __FILE__, '--worker']
  stdout, stderr, status = Open3.capture3(environment, *command, chdir: ROOT)
  unless status.success?
    warn stderr unless stderr.empty?
    abort "#{native_mode ? 'C extension' : 'Pure Ruby'} benchmark failed (#{status.exitstatus})"
  end
  warn stderr unless stderr.empty?
  JSON.parse(stdout, symbolize_names: true)
rescue JSON::ParserError => error
  abort "Could not parse benchmark worker output: #{error.message}\n#{stdout}"
end

puts 'Running C extension benchmarks...'
native = run_worker(true)
puts 'Running pure Ruby benchmarks...'
ruby = run_worker(false)

native_by_name = native[:results].to_h { |result| [[result[:extension], result[:name]], result] }
ruby_by_name = ruby[:results].to_h { |result| [[result[:extension], result[:name]], result] }

mismatches = []
rows = native_by_name.map do |key, native_result|
  ruby_result = ruby_by_name.fetch(key)
  if native_result[:signature] != ruby_result[:signature]
    mismatches << [key, native_result[:signature], ruby_result[:signature]]
  end
  ratio = native_result[:ips] / ruby_result[:ips]
  [native_result[:extension], native_result[:name], native_result[:ips],
   ruby_result[:ips], ratio, native_result[:cv_percent], ruby_result[:cv_percent]]
end

unless mismatches.empty?
  mismatches.each do |(extension, name), native_signature, ruby_signature|
    warn "Correctness mismatch for #{extension}: #{name}: C=#{native_signature.inspect}, Ruby=#{ruby_signature.inspect}"
  end
  abort 'Refusing to compare implementations with different results.'
end

def format_rate(rate)
  if rate >= 1_000_000
    format('%.2fM', rate / 1_000_000.0)
  elsif rate >= 1_000
    format('%.1fk', rate / 1_000.0)
  else
    format('%.1f', rate)
  end
end

puts
puts "Ruby: #{native[:ruby]}"
puts "Median of #{native[:sample_count]} samples; #{native[:sample_seconds]}s/sample after #{native[:warmup_seconds]}s warmup"
puts 'Rates are native-method calls, parsed lines, reads, or dispatches per second as named.'
puts
header = format('%-23s %-43s %12s %12s %10s %10s',
                'Extension', 'Workload', 'C ext', 'Pure Ruby', 'C speedup', 'sample CV')
puts header
puts '-' * header.length
rows.each do |extension, name, native_ips, ruby_ips, ratio, native_cv, ruby_cv|
  puts format('%-23s %-43s %12s %12s %9.2fx %4.1f/%4.1f%%',
              extension, name, format_rate(native_ips), format_rate(ruby_ips), ratio,
              native_cv, ruby_cv)
end

puts
puts 'Per-extension geometric mean (values above 1.00x favor C):'
rows.group_by(&:first).each do |extension, extension_rows|
  ratios = extension_rows.map { |row| row[4] }
  geometric_mean = Math.exp(ratios.sum { |ratio| Math.log(ratio) } / ratios.length)
  verdict = if geometric_mean >= 1.05
              'C faster'
            elsif geometric_mean <= (1.0 / 1.05)
              'Ruby faster'
            else
              'roughly even'
            end
  puts format('  %-23s %7.2fx  %s', extension, geometric_mean, verdict)
end

puts
puts 'Not timed: platform (installs SIGSEGV/SIGILL handlers; it has no callable hot path or Ruby equivalent).'
puts 'Correctness signatures matched for every timed workload.'
