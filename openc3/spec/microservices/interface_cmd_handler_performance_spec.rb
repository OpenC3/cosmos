# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Performance and profiling tests for InterfaceCmdHandlerThread critical path
# These tests are opt-in and require PERFORMANCE=1 to run
#
# Usage:
#   # Run benchmarks only:
#   PERFORMANCE=1 bundle exec rspec spec/microservices/interface_cmd_handler_performance_spec.rb
#
#   # Run with profiling (ruby-prof):
#   PERFORMANCE=1 PROFILE=1 bundle exec rspec spec/microservices/interface_cmd_handler_performance_spec.rb
#
#   # Customize iteration count:
#   PERFORMANCE=1 PERF_ITERATIONS=50000 bundle exec rspec spec/microservices/interface_cmd_handler_performance_spec.rb

require 'spec_helper'
require 'benchmark'

# Only load profiling gems when requested
if ENV['PROFILE']
  begin
    require 'ruby-prof'
    PROFILE_AVAILABLE = true
  rescue LoadError
    puts "Warning: ruby-prof not available"
    PROFILE_AVAILABLE = false
  end
else
  PROFILE_AVAILABLE = false
end

require 'openc3/interfaces/interface'
require 'openc3/microservices/interface_microservice'
require 'openc3/topics/command_topic'
require 'openc3/topics/command_decom_topic'

# Only run when PERFORMANCE=1 is set (opt-in)
RSpec.describe OpenC3::InterfaceCmdHandlerThread, if: ENV['PERFORMANCE'] do
  # Performance test interface that captures written commands
  class CmdPerformanceTestInterface < OpenC3::Interface
    attr_accessor :written_data, :write_count

    def initialize
      super()
      @connected = false
      @write_count = 0
      @written_data = []
    end

    def connection_string
      "cmd_perf_test"
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
      sleep(0.1) # Simulate waiting for data
      return nil, nil
    end

    def write_interface(data, extra = nil)
      # Note: write_count is incremented by the parent Interface#write method
      # Don't store data to avoid memory growth during benchmarks
      data.length
    end
  end

  before(:all) do
    @original_no_simplecov = ENV['OPENC3_NO_SIMPLECOV']
    ENV['OPENC3_NO_SIMPLECOV'] = 'true'
  end

  after(:all) do
    ENV['OPENC3_NO_SIMPLECOV'] = @original_no_simplecov
  end

  before(:each) do
    mock_redis()
    setup_system()

    # Create target model with commands
    model = OpenC3::TargetModel.new(folder_name: 'INST', name: 'INST', scope: 'DEFAULT')
    model.create
    model.update_store(OpenC3::System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))

    # Setup interface and microservice models
    allow(OpenC3::System).to receive(:setup_targets).and_return(nil)

    @interface = CmdPerformanceTestInterface.new
    @interface.name = 'PERF_INT'
    @interface.connect
    @interface.target_names = ['INST']
    @interface.cmd_target_names = ['INST']
    @interface.tlm_target_names = ['INST']

    # Initialize target enabled flags
    @interface.cmd_target_enabled = { 'INST' => true }
    @interface.tlm_target_enabled = { 'INST' => true }
  end

  after(:each) do
    kill_leftover_threads()
    sleep 0.1
  end

  describe "command building benchmarks" do
    let(:iterations) { (ENV['PERF_ITERATIONS'] || 10000).to_i }

    context "build_cmd path" do
      it "benchmarks build_cmd with simple parameters" do
        # Warm up
        5.times { OpenC3::System.commands.build_cmd('INST', 'ABORT', {}) }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: build_cmd (simple - ABORT)"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times do
            OpenC3::System.commands.build_cmd('INST', 'ABORT', {})
          end
        end

        cmds_per_second = iterations / result.real
        usec_per_cmd = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  User CPU time:     #{result.utime.round(4)} seconds"
        puts "  System CPU time:   #{result.stime.round(4)} seconds"
        puts "  Commands/second:   #{cmds_per_second.round(2)}"
        puts "  Microseconds/cmd:  #{usec_per_cmd.round(2)}"
        puts "=" * 70

        expect(result.real).to be < iterations
      end

      it "benchmarks build_cmd with complex parameters" do
        params = { 'TYPE' => 'NORMAL', 'DURATION' => 5.0, 'OPCODE' => 0xAB, 'TEMP' => 10.0 }

        # Warm up
        5.times { OpenC3::System.commands.build_cmd('INST', 'COLLECT', params) }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: build_cmd (complex - COLLECT with params)"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times do
            OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
          end
        end

        cmds_per_second = iterations / result.real
        usec_per_cmd = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Commands/second:   #{cmds_per_second.round(2)}"
        puts "  Microseconds/cmd:  #{usec_per_cmd.round(2)}"
        puts "=" * 70

        expect(result.real).to be < iterations
      end

      it "benchmarks command identification" do
        # Build a command to get its buffer for identification
        cmd = OpenC3::System.commands.build_cmd('INST', 'COLLECT', { 'TYPE' => 'NORMAL' })
        buffer = cmd.buffer

        # Warm up
        5.times { OpenC3::System.commands.identify(buffer, ['INST']) }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: commands.identify"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times do
            OpenC3::System.commands.identify(buffer.dup, ['INST'])
          end
        end

        cmds_per_second = iterations / result.real
        usec_per_cmd = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Commands/second:   #{cmds_per_second.round(2)}"
        puts "  Microseconds/cmd:  #{usec_per_cmd.round(2)}"
        puts "=" * 70

        expect(result.real).to be < iterations
      end

      it "benchmarks hazardous check" do
        cmd = OpenC3::System.commands.build_cmd('INST', 'COLLECT', { 'TYPE' => 'NORMAL' })

        # Warm up
        5.times { OpenC3::System.commands.cmd_pkt_hazardous?(cmd) }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: cmd_pkt_hazardous?"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times do
            OpenC3::System.commands.cmd_pkt_hazardous?(cmd)
          end
        end

        cmds_per_second = iterations / result.real
        usec_per_cmd = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Commands/second:   #{cmds_per_second.round(2)}"
        puts "  Microseconds/cmd:  #{usec_per_cmd.round(2)}"
        puts "=" * 70

        expect(result.real).to be < iterations
      end
    end

    context "topic write benchmarks" do
      it "benchmarks CommandDecomTopic.write_packet" do
        params = { 'TYPE' => 'NORMAL', 'DURATION' => 1.0 }
        command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
        command.received_time = Time.now

        # Warm up
        5.times { OpenC3::CommandDecomTopic.write_packet(command, scope: 'DEFAULT') }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: CommandDecomTopic.write_packet"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times do
            OpenC3::CommandDecomTopic.write_packet(command, scope: 'DEFAULT')
          end
        end

        writes_per_second = iterations / result.real
        usec_per_write = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Writes/second:     #{writes_per_second.round(2)}"
        puts "  Microseconds/write: #{usec_per_write.round(2)}"
        puts "=" * 70

        expect(result.real).to be < iterations
      end

      it "benchmarks CommandTopic.write_packet" do
        params = { 'TYPE' => 'NORMAL', 'DURATION' => 1.0 }
        command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
        command.received_time = Time.now

        # Warm up
        5.times { OpenC3::CommandTopic.write_packet(command, scope: 'DEFAULT') }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: CommandTopic.write_packet"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times do
            OpenC3::CommandTopic.write_packet(command, scope: 'DEFAULT')
          end
        end

        writes_per_second = iterations / result.real
        usec_per_write = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Writes/second:     #{writes_per_second.round(2)}"
        puts "  Microseconds/write: #{usec_per_write.round(2)}"
        puts "=" * 70

        expect(result.real).to be < iterations
      end
    end

    context "full command handling simulation" do
      it "benchmarks the critical command path (build + write + topics)" do
        # Simulate what happens in InterfaceCmdHandlerThread#run for a normal command
        # This is the hot path: build_cmd -> write -> CommandDecomTopic -> CommandTopic

        params = { 'TYPE' => 'NORMAL', 'DURATION' => 1.0 }

        # Warm up
        5.times do
          command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
          command.received_time = Time.now
          command.received_count = 1
          @interface.write(command)
          OpenC3::CommandDecomTopic.write_packet(command, scope: 'DEFAULT')
          OpenC3::CommandTopic.write_packet(command, scope: 'DEFAULT')
        end

        puts "\n" + "=" * 70
        puts "Performance Benchmark: Full command path (build+write+topics)"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        @interface.write_count = 0

        result = Benchmark.measure do
          iterations.times do |i|
            command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
            command.received_time = Time.now
            command.received_count = i + 1
            @interface.write(command)
            OpenC3::CommandDecomTopic.write_packet(command, scope: 'DEFAULT')
            OpenC3::CommandTopic.write_packet(command, scope: 'DEFAULT')
          end
        end

        cmds_per_second = iterations / result.real
        usec_per_cmd = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  User CPU time:     #{result.utime.round(4)} seconds"
        puts "  System CPU time:   #{result.stime.round(4)} seconds"
        puts "  Commands/second:   #{cmds_per_second.round(2)}"
        puts "  Microseconds/cmd:  #{usec_per_cmd.round(2)}"
        puts "  Interface writes:  #{@interface.write_count}"
        puts "=" * 70

        expect(@interface.write_count).to eq(iterations)
      end

      it "benchmarks command path without topic writes" do
        # Isolate the build + interface write without Redis topic overhead
        params = { 'TYPE' => 'NORMAL', 'DURATION' => 1.0 }

        # Warm up
        5.times do
          command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
          command.received_time = Time.now
          @interface.write(command)
        end

        puts "\n" + "=" * 70
        puts "Performance Benchmark: Command build + interface write only"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        @interface.write_count = 0

        result = Benchmark.measure do
          iterations.times do
            command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
            command.received_time = Time.now
            @interface.write(command)
          end
        end

        cmds_per_second = iterations / result.real
        usec_per_cmd = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Commands/second:   #{cmds_per_second.round(2)}"
        puts "  Microseconds/cmd:  #{usec_per_cmd.round(2)}"
        puts "=" * 70

        expect(@interface.write_count).to eq(iterations)
      end
    end
  end

  describe "memory profiling" do
    it "measures memory allocation during command handling" do
      params = { 'TYPE' => 'NORMAL', 'DURATION' => 1.0 }
      iterations = 1000

      # Warm up and force GC
      10.times do
        command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
        @interface.write(command)
      end
      GC.start

      puts "\n" + "=" * 70
      puts "Memory Profiling: command build + write"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{iterations}"
      puts "=" * 70

      GC.start
      mem_before = `ps -o rss= -p #{Process.pid}`.to_i

      iterations.times do
        command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
        command.received_time = Time.now
        @interface.write(command)
      end

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
    end
  end

  describe "comparative benchmarks" do
    it "compares simple vs complex command building" do
      iterations = (ENV['PERF_ITERATIONS'] || 5000).to_i
      simple_params = {}
      complex_params = { 'TYPE' => 'NORMAL', 'DURATION' => 5.0, 'OPCODE' => 0xAB, 'TEMP' => 10.0 }

      puts "\n" + "=" * 70
      puts "Comparative Benchmark: Simple vs Complex command building"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{iterations}"
      puts "=" * 70

      # Warm up
      5.times do
        OpenC3::System.commands.build_cmd('INST', 'ABORT', simple_params)
        OpenC3::System.commands.build_cmd('INST', 'COLLECT', complex_params)
      end

      # Benchmark simple
      simple_result = Benchmark.measure do
        iterations.times { OpenC3::System.commands.build_cmd('INST', 'ABORT', simple_params) }
      end

      # Benchmark complex
      complex_result = Benchmark.measure do
        iterations.times { OpenC3::System.commands.build_cmd('INST', 'COLLECT', complex_params) }
      end

      simple_cps = iterations / simple_result.real
      complex_cps = iterations / complex_result.real
      ratio = simple_cps / complex_cps

      puts "\nSimple command (ABORT, no params):"
      puts "  Time:              #{simple_result.real.round(4)} seconds"
      puts "  Commands/second:   #{simple_cps.round(2)}"

      puts "\nComplex command (COLLECT, 4 params):"
      puts "  Time:              #{complex_result.real.round(4)} seconds"
      puts "  Commands/second:   #{complex_cps.round(2)}"

      puts "\nRatio:               #{ratio.round(2)}x (simple is faster)"
      puts "=" * 70
    end

    it "compares build_cmd vs identify performance" do
      iterations = (ENV['PERF_ITERATIONS'] || 5000).to_i
      params = { 'TYPE' => 'NORMAL' }

      # Get a buffer for identification
      cmd = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
      buffer = cmd.buffer

      puts "\n" + "=" * 70
      puts "Comparative Benchmark: build_cmd vs identify"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{iterations}"
      puts "=" * 70

      # Warm up
      5.times do
        OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
        OpenC3::System.commands.identify(buffer.dup, ['INST'])
      end

      # Benchmark build_cmd
      build_result = Benchmark.measure do
        iterations.times { OpenC3::System.commands.build_cmd('INST', 'COLLECT', params) }
      end

      # Benchmark identify
      identify_result = Benchmark.measure do
        iterations.times { OpenC3::System.commands.identify(buffer.dup, ['INST']) }
      end

      build_cps = iterations / build_result.real
      identify_cps = iterations / identify_result.real

      puts "\nbuild_cmd (with params):"
      puts "  Time:              #{build_result.real.round(4)} seconds"
      puts "  Commands/second:   #{build_cps.round(2)}"

      puts "\nidentify (from buffer):"
      puts "  Time:              #{identify_result.real.round(4)} seconds"
      puts "  Commands/second:   #{identify_cps.round(2)}"

      if build_cps > identify_cps
        puts "\nbuild_cmd is #{(build_cps / identify_cps).round(2)}x faster"
      else
        puts "\nidentify is #{(identify_cps / build_cps).round(2)}x faster"
      end
      puts "=" * 70
    end
  end

  describe "profiling", if: PROFILE_AVAILABLE do
    let(:profile_iterations) { (ENV['PROFILE_ITERATIONS'] || 1000).to_i }

    it "profiles CommandDecomTopic.write_packet" do
      params = { 'TYPE' => 'NORMAL', 'DURATION' => 1.0 }
      command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
      command.received_time = Time.now

      # Warm up
      10.times { OpenC3::CommandDecomTopic.write_packet(command, scope: 'DEFAULT') }

      puts "\n" + "=" * 70
      puts "Profiling: CommandDecomTopic.write_packet"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([Integer, :times])
      profile.start
      profile_iterations.times do
        OpenC3::CommandDecomTopic.write_packet(command, scope: 'DEFAULT')
      end
      result = profile.stop

      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      File.open(File.join(profile_dir, "decom_topic_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      File.open(File.join(profile_dir, "decom_topic_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      puts "\nProfile output written to profile/ directory"
      puts "  - decom_topic_#{RUBY_VERSION}.txt (flat profile)"
      puts "  - decom_topic_#{RUBY_VERSION}.html (call graph)"
    end

    it "profiles CommandTopic.write_packet" do
      params = { 'TYPE' => 'NORMAL', 'DURATION' => 1.0 }
      command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
      command.received_time = Time.now

      # Warm up
      10.times { OpenC3::CommandTopic.write_packet(command, scope: 'DEFAULT') }

      puts "\n" + "=" * 70
      puts "Profiling: CommandTopic.write_packet"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([Integer, :times])
      profile.start
      profile_iterations.times do
        OpenC3::CommandTopic.write_packet(command, scope: 'DEFAULT')
      end
      result = profile.stop

      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      File.open(File.join(profile_dir, "cmd_topic_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      File.open(File.join(profile_dir, "cmd_topic_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      puts "\nProfile output written to profile/ directory"
      puts "  - cmd_topic_#{RUBY_VERSION}.txt (flat profile)"
      puts "  - cmd_topic_#{RUBY_VERSION}.html (call graph)"
    end

    it "profiles build_cmd" do
      params = { 'TYPE' => 'NORMAL', 'DURATION' => 1.0 }

      # Warm up
      10.times { OpenC3::System.commands.build_cmd('INST', 'COLLECT', params) }

      puts "\n" + "=" * 70
      puts "Profiling: build_cmd"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([Integer, :times, Kernel, :dup])
      profile.start
      profile_iterations.times do
        OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
      end
      result = profile.stop

      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      File.open(File.join(profile_dir, "build_cmd_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      File.open(File.join(profile_dir, "build_cmd_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      puts "\nProfile output written to profile/ directory"
      puts "  - build_cmd_#{RUBY_VERSION}.txt (flat profile)"
      puts "  - build_cmd_#{RUBY_VERSION}.html (call graph)"
    end

    it "profiles full command path" do
      params = { 'TYPE' => 'NORMAL', 'DURATION' => 1.0 }

      # Warm up
      10.times do
        command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
        command.received_time = Time.now
        @interface.write(command)
        OpenC3::CommandDecomTopic.write_packet(command, scope: 'DEFAULT')
        OpenC3::CommandTopic.write_packet(command, scope: 'DEFAULT')
      end

      puts "\n" + "=" * 70
      puts "Profiling: full command path"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([Integer, :times, Kernel, :dup])
      profile.start
      profile_iterations.times do |i|
        command = OpenC3::System.commands.build_cmd('INST', 'COLLECT', params)
        command.received_time = Time.now
        command.received_count = i + 1
        @interface.write(command)
        OpenC3::CommandDecomTopic.write_packet(command, scope: 'DEFAULT')
        OpenC3::CommandTopic.write_packet(command, scope: 'DEFAULT')
      end
      result = profile.stop

      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      File.open(File.join(profile_dir, "cmd_path_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      File.open(File.join(profile_dir, "cmd_path_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      puts "\nProfile output written to profile/ directory"
      puts "  - cmd_path_#{RUBY_VERSION}.txt (flat profile)"
      puts "  - cmd_path_#{RUBY_VERSION}.html (call graph)"
    end
  end
end
