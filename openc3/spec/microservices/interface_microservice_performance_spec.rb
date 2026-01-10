# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Performance and profiling tests for InterfaceMicroservice critical path
# These tests are gated behind ENV['CI'] and are not run in CI pipelines
#
# Usage:
#   # Run benchmarks only:
#   bundle exec rspec spec/microservices/interface_microservice_performance_spec.rb
#
#   # Run with profiling (ruby-prof):
#   PROFILE=1 bundle exec rspec spec/microservices/interface_microservice_performance_spec.rb
#
#   # Run with flamegraph output:
#   FLAMEGRAPH=1 bundle exec rspec spec/microservices/interface_microservice_performance_spec.rb
#
#   # Customize iteration count:
#   PERF_ITERATIONS=50000 bundle exec rspec spec/microservices/interface_microservice_performance_spec.rb
#
#   # Compare Ruby versions (run in different environments):
#   rbenv shell 3.2.0 && bundle exec rspec spec/microservices/interface_microservice_performance_spec.rb
#   rbenv shell 3.3.0 && bundle exec rspec spec/microservices/interface_microservice_performance_spec.rb
#   rbenv shell 3.4.0 && bundle exec rspec spec/microservices/interface_microservice_performance_spec.rb

require 'spec_helper'
require 'benchmark'

# Only load profiling gems when requested
if ENV['PROFILE'] || ENV['FLAMEGRAPH']
  begin
    require 'ruby-prof'
    if ENV['FLAMEGRAPH']
      begin
        require 'ruby-prof-flamegraph'
        FLAMEGRAPH_AVAILABLE = true
      rescue LoadError
        puts "Warning: ruby-prof-flamegraph not available. Install with: gem install ruby-prof-flamegraph"
        FLAMEGRAPH_AVAILABLE = false
      end
    else
      FLAMEGRAPH_AVAILABLE = false
    end
    PROFILE_AVAILABLE = true
  rescue LoadError
    puts "Warning: ruby-prof not available"
    PROFILE_AVAILABLE = false
    FLAMEGRAPH_AVAILABLE = false
  end
else
  PROFILE_AVAILABLE = false
  FLAMEGRAPH_AVAILABLE = false
end

if ENV['BENCHMARK_IPS']
  begin
    require 'benchmark/ips'
    BENCHMARK_IPS_AVAILABLE = true
  rescue LoadError
    puts "Warning: benchmark-ips not available"
    BENCHMARK_IPS_AVAILABLE = false
  end
else
  BENCHMARK_IPS_AVAILABLE = false
end

require 'openc3/interfaces/interface'
require 'openc3/microservices/interface_microservice'
require 'openc3/topics/telemetry_decom_topic'

# Skip all tests in CI environment
RSpec.describe OpenC3::InterfaceMicroservice, unless: ENV['CI'] do
  # Performance test interface that can generate packets at high speed
  # with minimal overhead for accurate benchmarking
  class PerformanceTestInterface < OpenC3::Interface
    attr_accessor :packet_data, :packet_count, :packets_to_generate

    def initialize
      super()
      @packet_count = 0
      @packets_to_generate = 1000
      @connected = false
      # Pre-generate HEALTH_STATUS packet data for fast reads
      # This is the INST HEALTH_STATUS packet structure
      @packet_data = generate_health_status_packet
    end

    def connection_string
      "perf_test"
    end

    def connect
      super
      @connected = true
    end

    def connected?
      @connected
    end

    def disconnect
      @connected = false
      super
    end

    def read_interface
      if @packet_count < @packets_to_generate
        @packet_count += 1
        # Return pre-generated packet data with no delay
        return @packet_data.dup, nil
      else
        # Signal end of packets
        return nil, nil
      end
    end

    def write_interface(data, extra = nil)
      # No-op for telemetry-only testing
    end

    private

    # Generate a valid INST HEALTH_STATUS packet buffer
    # Based on inst_tlm.txt definition
    def generate_health_status_packet
      # HEALTH_STATUS packet structure:
      # CCSDSVER (3 bits), CCSDSTYPE (1 bit), CCSDSSHF (1 bit), CCSDSAPID (11 bits) = ID 1
      # CCSDSSEQFLAGS (2 bits), CCSDSSEQCNT (14 bits)
      # CCSDSLENGTH (16 bits)
      # TIMESEC (32 bits), TIMEUS (32 bits)
      # PKTID (16 bits) = ID 1
      # COLLECTS (16 bits)
      # TEMP1-4 (16 bits each)
      # ARY (80 bits = 10 bytes)
      # DURATION (32 bits float)
      # COLLECT_TYPE (16 bits)
      # ARY2 (640 bits = 80 bytes)
      # ASCIICMD (2048 bits = 256 bytes)
      # GROUND1STATUS (8 bits)
      # GROUND2STATUS (8 bits)
      # BLOCKTEST (80 bits = 10 bytes)
      # Total packet is quite large, let's generate the minimum needed for identification

      data = "\x00" * 400 # Allocate enough space
      # Set CCSDSAPID to 1 (ID_ITEM at bit 5, 11 bits) - packed as big endian
      # Byte 0: CCSDSVER (3) | CCSDSTYPE (1) | CCSDSSHF (1) | CCSDSAPID high 3 bits
      # Byte 1: CCSDSAPID low 8 bits
      data[0] = "\x00" # CCSDSVER=0, CCSDSTYPE=0 (TLM), CCSDSSHF=0, APID high=0
      data[1] = "\x01" # APID low = 1
      # CCSDSSEQFLAGS (2 bits) = 3 (NOGROUP), CCSDSSEQCNT (14 bits) = 0
      data[2] = "\xC0" # SEQFLAGS = 3 (11 binary), SEQCNT high = 0
      data[3] = "\x00" # SEQCNT low = 0
      # CCSDSLENGTH (16 bits) - packet data length minus 1
      data[4..5] = [390].pack('n') # Length field
      # TIMESEC (32 bits) - set to current time
      data[6..9] = [Time.now.to_i].pack('N')
      # TIMEUS (32 bits)
      data[10..13] = [0].pack('N')
      # PKTID (16 bits) = 1 (ID_ITEM)
      data[14..15] = [1].pack('n')
      # COLLECTS (16 bits)
      data[16..17] = [100].pack('n')
      # TEMP1-4 (16 bits each) - set to middle of valid range
      data[18..19] = [32768].pack('n') # TEMP1
      data[20..21] = [32768].pack('n') # TEMP2
      data[22..23] = [32768].pack('n') # TEMP3
      data[24..25] = [32768].pack('n') # TEMP4

      data
    end
  end

  # Minimal mocking setup for performance testing
  before(:all) do
    @original_no_simplecov = ENV['OPENC3_NO_SIMPLECOV']
    # Disable simplecov during performance tests to avoid overhead
    ENV['OPENC3_NO_SIMPLECOV'] = 'true'
  end

  after(:all) do
    ENV['OPENC3_NO_SIMPLECOV'] = @original_no_simplecov
  end

  before(:each) do
    mock_redis()
    setup_system()

    # Create target model
    model = OpenC3::TargetModel.new(folder_name: 'INST', name: 'INST', scope: 'DEFAULT')
    model.create
    model.update_store(OpenC3::System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))

    # Initialize a packet in the telemetry topic
    packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
    packet.received_time = Time.now.sys
    packet.stored = false
    OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
    sleep(0.01)

    # Setup interface and microservice models
    allow(OpenC3::System).to receive(:setup_targets).and_return(nil)
    @interface_double = double("Interface").as_null_object
    allow(@interface_double).to receive(:connected?).and_return(true)
    allow(OpenC3::System).to receive(:targets).and_return({ "INST" => @interface_double })

    int_model = OpenC3::InterfaceModel.new(
      name: "PERF_INT",
      scope: "DEFAULT",
      target_names: ["INST"],
      cmd_target_names: ["INST"],
      tlm_target_names: ["INST"],
      config_params: ["PerformanceTestInterface"]
    )
    int_model.create

    ms_model = OpenC3::MicroserviceModel.new(
      folder_name: "INST",
      name: "DEFAULT__INTERFACE__PERF_INT",
      scope: "DEFAULT",
      target_names: ["INST"]
    )
    ms_model.create

    # Initialize CVT for packet count tracking
    OpenC3::System.telemetry.packets("INST").each do |_packet_name, packet|
      json_hash = OpenC3::CvtModel.build_json_from_packet(packet)
      OpenC3::CvtModel.set(json_hash, target_name: packet.target_name, packet_name: packet.packet_name, scope: "DEFAULT")
    end
  end

  after(:each) do
    kill_leftover_threads()
    sleep 0.1
  end

  describe "performance benchmarks" do
    let(:iterations) { (ENV['PERF_ITERATIONS'] || 10000).to_i }

    context "handle_packet path" do
      it "benchmarks packet identification and handling" do
        im = OpenC3::InterfaceMicroservice.new("DEFAULT__INTERFACE__PERF_INT")
        interface = im.instance_variable_get(:@interface)

        # Generate a test packet
        packet = OpenC3::Packet.new('INST', 'HEALTH_STATUS')
        packet.buffer = interface.send(:generate_health_status_packet)

        # Warm up
        5.times { im.handle_packet(packet.clone) }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: handle_packet"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        # Benchmark
        result = Benchmark.measure do
          iterations.times do
            im.handle_packet(packet.clone)
          end
        end

        packets_per_second = iterations / result.real
        usec_per_packet = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  User CPU time:     #{result.utime.round(4)} seconds"
        puts "  System CPU time:   #{result.stime.round(4)} seconds"
        puts "  Packets/second:    #{packets_per_second.round(2)}"
        puts "  Microseconds/pkt:  #{usec_per_packet.round(2)}"
        puts "=" * 70

        # Store results for comparison
        File.open("perf_results_#{RUBY_VERSION}.txt", "a") do |f|
          f.puts "#{Time.now.iso8601},handle_packet,#{RUBY_VERSION},#{iterations},#{result.real},#{packets_per_second}"
        end

        im.shutdown
        expect(result.real).to be < iterations # Sanity check - should process faster than 1 per second
      end

      it "benchmarks packet identification only (identify!)" do
        im = OpenC3::InterfaceMicroservice.new("DEFAULT__INTERFACE__PERF_INT")
        interface = im.instance_variable_get(:@interface)

        # Generate a test packet buffer
        buffer = interface.send(:generate_health_status_packet)

        # Warm up
        5.times { OpenC3::System.telemetry.identify!(buffer.dup, ['INST']) }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: packet identify!"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times do
            OpenC3::System.telemetry.identify!(buffer.dup, ['INST'])
          end
        end

        packets_per_second = iterations / result.real
        usec_per_packet = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Packets/second:    #{packets_per_second.round(2)}"
        puts "  Microseconds/pkt:  #{usec_per_packet.round(2)}"
        puts "=" * 70

        File.open("perf_results_#{RUBY_VERSION}.txt", "a") do |f|
          f.puts "#{Time.now.iso8601},identify!,#{RUBY_VERSION},#{iterations},#{result.real},#{packets_per_second}"
        end

        im.shutdown
      end

      it "benchmarks pre-identified packet update (update!)" do
        im = OpenC3::InterfaceMicroservice.new("DEFAULT__INTERFACE__PERF_INT")
        interface = im.instance_variable_get(:@interface)

        buffer = interface.send(:generate_health_status_packet)

        # Warm up
        5.times { OpenC3::System.telemetry.update!('INST', 'HEALTH_STATUS', buffer.dup) }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: packet update! (pre-identified)"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times do
            OpenC3::System.telemetry.update!('INST', 'HEALTH_STATUS', buffer.dup)
          end
        end

        packets_per_second = iterations / result.real
        usec_per_packet = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Packets/second:    #{packets_per_second.round(2)}"
        puts "  Microseconds/pkt:  #{usec_per_packet.round(2)}"
        puts "=" * 70

        File.open("perf_results_#{RUBY_VERSION}.txt", "a") do |f|
          f.puts "#{Time.now.iso8601},update!,#{RUBY_VERSION},#{iterations},#{result.real},#{packets_per_second}"
        end

        im.shutdown
      end
    end

    context "full read loop simulation", if: BENCHMARK_IPS_AVAILABLE do
      it "measures iterations per second with benchmark-ips" do
        im = OpenC3::InterfaceMicroservice.new("DEFAULT__INTERFACE__PERF_INT")
        interface = im.instance_variable_get(:@interface)

        packet = OpenC3::Packet.new('INST', 'HEALTH_STATUS')
        packet.buffer = interface.send(:generate_health_status_packet)

        puts "\n" + "=" * 70
        puts "Benchmark IPS: handle_packet"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "=" * 70

        Benchmark.ips do |x|
          x.config(time: 5, warmup: 2)

          x.report("handle_packet") do
            im.handle_packet(packet.clone)
          end

          x.report("identify!") do
            OpenC3::System.telemetry.identify!(packet.buffer.dup, ['INST'])
          end

          x.report("update! (pre-id)") do
            OpenC3::System.telemetry.update!('INST', 'HEALTH_STATUS', packet.buffer.dup)
          end

          x.compare!
        end

        im.shutdown
      end
    end
  end

  describe "profiling", if: PROFILE_AVAILABLE do
    let(:profile_iterations) { (ENV['PROFILE_ITERATIONS'] || 1000).to_i }

    it "profiles handle_packet with ruby-prof" do
      im = OpenC3::InterfaceMicroservice.new("DEFAULT__INTERFACE__PERF_INT")
      interface = im.instance_variable_get(:@interface)

      packet = OpenC3::Packet.new('INST', 'HEALTH_STATUS')
      packet.buffer = interface.send(:generate_health_status_packet)

      # Warm up
      10.times { im.handle_packet(packet.clone) }

      puts "\n" + "=" * 70
      puts "Profiling: handle_packet"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      # Profile using new API (avoids deprecation warnings)
      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([
        Integer, :times,
        Kernel, :dup,
        Kernel, :clone
      ])
      profile.start
      profile_iterations.times do
        im.handle_packet(packet.clone)
      end
      result = profile.stop

      # Output directory
      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      # Generate call tree profile
      File.open(File.join(profile_dir, "handle_packet_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      # Generate call graph
      File.open(File.join(profile_dir, "handle_packet_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      # Generate call stack (for potential flamegraph conversion)
      File.open(File.join(profile_dir, "handle_packet_#{RUBY_VERSION}_callstack.html"), 'w') do |f|
        printer = RubyProf::CallStackPrinter.new(result)
        printer.print(f)
      end

      if FLAMEGRAPH_AVAILABLE
        # Generate flamegraph-compatible output
        File.open(File.join(profile_dir, "handle_packet_#{RUBY_VERSION}.flamegraph"), 'w') do |f|
          printer = RubyProf::FlameGraphPrinter.new(result)
          printer.print(f)
        end
        puts "\nFlamegraph data written to: profile/handle_packet_#{RUBY_VERSION}.flamegraph"
        puts "Convert to SVG with: flamegraph.pl < profile/handle_packet_#{RUBY_VERSION}.flamegraph > profile/handle_packet_#{RUBY_VERSION}.svg"
      end

      puts "\nProfile output written to profile/ directory"
      puts "  - handle_packet_#{RUBY_VERSION}.txt (flat profile)"
      puts "  - handle_packet_#{RUBY_VERSION}.html (call graph)"
      puts "  - handle_packet_#{RUBY_VERSION}_callstack.html (call stack)"

      im.shutdown
    end

    it "profiles packet identification" do
      im = OpenC3::InterfaceMicroservice.new("DEFAULT__INTERFACE__PERF_INT")
      interface = im.instance_variable_get(:@interface)

      buffer = interface.send(:generate_health_status_packet)

      # Warm up
      10.times { OpenC3::System.telemetry.identify!(buffer.dup, ['INST']) }

      puts "\n" + "=" * 70
      puts "Profiling: identify!"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([Integer, :times, Kernel, :dup])
      profile.start
      profile_iterations.times do
        OpenC3::System.telemetry.identify!(buffer.dup, ['INST'])
      end
      result = profile.stop

      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      File.open(File.join(profile_dir, "identify_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      File.open(File.join(profile_dir, "identify_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      if FLAMEGRAPH_AVAILABLE
        File.open(File.join(profile_dir, "identify_#{RUBY_VERSION}.flamegraph"), 'w') do |f|
          printer = RubyProf::FlameGraphPrinter.new(result)
          printer.print(f)
        end
      end

      puts "\nProfile output written to profile/ directory"

      im.shutdown
    end
  end

  describe "memory profiling" do
    it "measures memory allocation during packet handling" do
      im = OpenC3::InterfaceMicroservice.new("DEFAULT__INTERFACE__PERF_INT")
      interface = im.instance_variable_get(:@interface)

      packet = OpenC3::Packet.new('INST', 'HEALTH_STATUS')
      packet.buffer = interface.send(:generate_health_status_packet)

      iterations = 1000

      # Warm up and force GC
      10.times { im.handle_packet(packet.clone) }
      GC.start

      puts "\n" + "=" * 70
      puts "Memory Profiling: handle_packet"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{iterations}"
      puts "=" * 70

      # Measure memory before
      GC.start
      mem_before = `ps -o rss= -p #{Process.pid}`.to_i

      iterations.times do
        im.handle_packet(packet.clone)
      end

      # Measure memory after
      GC.start
      mem_after = `ps -o rss= -p #{Process.pid}`.to_i

      mem_delta_kb = mem_after - mem_before
      mem_per_iteration = mem_delta_kb.to_f / iterations

      puts "\nResults:"
      puts "  Memory before:     #{mem_before} KB"
      puts "  Memory after:      #{mem_after} KB"
      puts "  Memory delta:      #{mem_delta_kb} KB"
      puts "  KB per iteration:  #{mem_per_iteration.round(4)}"
      puts "=" * 70

      im.shutdown
    end
  end

  describe "comparative benchmarks" do
    it "compares identified vs unidentified packet performance" do
      im = OpenC3::InterfaceMicroservice.new("DEFAULT__INTERFACE__PERF_INT")
      interface = im.instance_variable_get(:@interface)
      iterations = (ENV['PERF_ITERATIONS'] || 5000).to_i

      buffer = interface.send(:generate_health_status_packet)

      # Pre-identified packet (fast path)
      pre_identified = OpenC3::Packet.new('INST', 'HEALTH_STATUS')
      pre_identified.buffer = buffer.dup

      # Unidentified packet (slow path - needs identification)
      unidentified = OpenC3::Packet.new(nil, nil)
      unidentified.buffer = buffer.dup

      puts "\n" + "=" * 70
      puts "Comparative Benchmark: Pre-identified vs Unidentified"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{iterations}"
      puts "=" * 70

      # Warm up
      5.times do
        im.handle_packet(pre_identified.clone)
        im.handle_packet(unidentified.clone)
      end

      # Benchmark pre-identified
      pre_id_result = Benchmark.measure do
        iterations.times { im.handle_packet(pre_identified.clone) }
      end

      # Benchmark unidentified
      unid_result = Benchmark.measure do
        iterations.times { im.handle_packet(unidentified.clone) }
      end

      pre_id_pps = iterations / pre_id_result.real
      unid_pps = iterations / unid_result.real
      speedup = pre_id_pps / unid_pps

      puts "\nPre-identified packets:"
      puts "  Time:              #{pre_id_result.real.round(4)} seconds"
      puts "  Packets/second:    #{pre_id_pps.round(2)}"

      puts "\nUnidentified packets:"
      puts "  Time:              #{unid_result.real.round(4)} seconds"
      puts "  Packets/second:    #{unid_pps.round(2)}"

      puts "\nSpeedup factor:      #{speedup.round(2)}x (pre-identified is faster)"
      puts "=" * 70

      im.shutdown
    end
  end
end
