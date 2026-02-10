# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Performance and profiling tests for DecomMicroservice critical path
# These tests are opt-in and require PERFORMANCE=1 to run
#
# Usage:
#   # Run benchmarks only:
#   PERFORMANCE=1 bundle exec rspec spec/microservices/decom_microservice_performance_spec.rb
#
#   # Run with profiling (ruby-prof):
#   PERFORMANCE=1 PROFILE=1 bundle exec rspec spec/microservices/decom_microservice_performance_spec.rb
#
#   # Customize iteration count:
#   PERFORMANCE=1 PERF_ITERATIONS=50000 bundle exec rspec spec/microservices/decom_microservice_performance_spec.rb

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

require 'openc3/microservices/decom_microservice'
require 'openc3/topics/telemetry_topic'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/models/cvt_model'

# Only run when PERFORMANCE=1 is set (opt-in)
RSpec.describe OpenC3::DecomMicroservice, if: ENV['PERFORMANCE'] do
  before(:each) do
    mock_redis()
    setup_system()

    # Create target model
    model = OpenC3::TargetModel.new(folder_name: 'INST', name: 'INST', scope: 'DEFAULT')
    model.create
    model.update_store(OpenC3::System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))

    # Initialize CVT for all packets
    OpenC3::System.telemetry.packets("INST").each do |_packet_name, packet|
      packet.received_time = Time.now.sys
      json_hash = OpenC3::CvtModel.build_json_from_packet(packet)
      OpenC3::CvtModel.set(json_hash, target_name: packet.target_name, packet_name: packet.packet_name, scope: "DEFAULT")
    end
  end

  def generate_health_status_buffer
    # Generate a realistic HEALTH_STATUS packet buffer
    packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
    packet.write('TEMP1', 25.0)
    packet.write('TEMP2', 30.0)
    packet.write('TEMP3', 35.0)
    packet.write('TEMP4', 40.0)
    packet.write('GROUND1STATUS', 'CONNECTED')
    packet.write('GROUND2STATUS', 'CONNECTED')
    packet.buffer
  end

  describe "decom_packet benchmarks" do
    let(:iterations) { (ENV['PERF_ITERATIONS'] || 10000).to_i }

    context "component benchmarks" do
      it "benchmarks packet.decom (CvtModel.build_json_from_packet)" do
        packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.buffer = generate_health_status_buffer

        # Warm up
        10.times { packet.decom }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: packet.decom (HEALTH_STATUS)"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times { packet.decom }
        end

        ops_per_second = iterations / result.real
        usec_per_op = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  User CPU time:     #{result.utime.round(4)} seconds"
        puts "  System CPU time:   #{result.stime.round(4)} seconds"
        puts "  Decoms/second:     #{ops_per_second.round(2)}"
        puts "  Microseconds/decom: #{usec_per_op.round(2)}"
        puts "=" * 70
      end

      it "benchmarks packet.check_limits" do
        packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.buffer = generate_health_status_buffer

        # Warm up
        10.times { packet.check_limits(OpenC3::System.limits_set) }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: packet.check_limits"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times { packet.check_limits(OpenC3::System.limits_set) }
        end

        ops_per_second = iterations / result.real
        usec_per_op = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Checks/second:     #{ops_per_second.round(2)}"
        puts "  Microseconds/check: #{usec_per_op.round(2)}"
        puts "=" * 70
      end

      it "benchmarks TelemetryDecomTopic.write_packet" do
        packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
        packet.received_time = Time.now.sys
        packet.buffer = generate_health_status_buffer

        # Warm up
        10.times { OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT') }

        puts "\n" + "=" * 70
        puts "Performance Benchmark: TelemetryDecomTopic.write_packet"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times { OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT') }
        end

        ops_per_second = iterations / result.real
        usec_per_op = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  Writes/second:     #{ops_per_second.round(2)}"
        puts "  Microseconds/write: #{usec_per_op.round(2)}"
        puts "=" * 70
      end
    end

    context "full decom path simulation" do
      it "benchmarks simulated decom_packet path" do
        # Simulate what decom_packet does without the Redis topic reading
        packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
        buffer = generate_health_status_buffer

        # Warm up
        10.times do
          packet.stored = false
          packet.received_time = Time.now.sys
          packet.buffer = buffer
          packet.check_limits(OpenC3::System.limits_set)
          OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
        end

        puts "\n" + "=" * 70
        puts "Performance Benchmark: Full decom_packet path (simulated)"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations}"
        puts "=" * 70

        result = Benchmark.measure do
          iterations.times do
            # Simulate decom_packet without topic reading
            packet.stored = false
            packet.received_time = Time.now.sys
            packet.buffer = buffer
            # packet.process - skipped, no processors in HEALTH_STATUS
            packet.check_limits(OpenC3::System.limits_set)
            OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
          end
        end

        ops_per_second = iterations / result.real
        usec_per_op = (result.real * 1_000_000) / iterations

        puts "\nResults:"
        puts "  Total time:        #{result.real.round(4)} seconds"
        puts "  User CPU time:     #{result.utime.round(4)} seconds"
        puts "  System CPU time:   #{result.stime.round(4)} seconds"
        puts "  Packets/second:    #{ops_per_second.round(2)}"
        puts "  Microseconds/pkt:  #{usec_per_op.round(2)}"
        puts "=" * 70
      end

      it "benchmarks decom path breakdown" do
        packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
        buffer = generate_health_status_buffer
        iterations_local = iterations

        # Warm up
        10.times do
          packet.buffer = buffer
          packet.check_limits(OpenC3::System.limits_set)
          OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
        end

        puts "\n" + "=" * 70
        puts "Performance Benchmark: Decom path breakdown"
        puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
        puts "Iterations: #{iterations_local}"
        puts "=" * 70

        # Benchmark buffer assignment
        buffer_result = Benchmark.measure do
          iterations_local.times { packet.buffer = buffer }
        end

        # Benchmark check_limits
        limits_result = Benchmark.measure do
          iterations_local.times { packet.check_limits(OpenC3::System.limits_set) }
        end

        # Benchmark TelemetryDecomTopic.write_packet
        write_result = Benchmark.measure do
          iterations_local.times { OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT') }
        end

        total_time = buffer_result.real + limits_result.real + write_result.real

        puts "\nBreakdown:"
        puts "  packet.buffer=:           #{(buffer_result.real * 1_000_000 / iterations_local).round(2)} μs (#{(buffer_result.real / total_time * 100).round(1)}%)"
        puts "  packet.check_limits:      #{(limits_result.real * 1_000_000 / iterations_local).round(2)} μs (#{(limits_result.real / total_time * 100).round(1)}%)"
        puts "  TelemetryDecomTopic.write: #{(write_result.real * 1_000_000 / iterations_local).round(2)} μs (#{(write_result.real / total_time * 100).round(1)}%)"
        puts "  ----------------------------------------"
        puts "  Total:                    #{(total_time * 1_000_000 / iterations_local).round(2)} μs"
        puts "=" * 70
      end
    end
  end

  describe "profiling", if: PROFILE_AVAILABLE do
    let(:profile_iterations) { (ENV['PROFILE_ITERATIONS'] || 1000).to_i }

    it "profiles packet.decom" do
      packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
      packet.received_time = Time.now.sys
      packet.buffer = generate_health_status_buffer

      # Warm up
      10.times { packet.decom }

      puts "\n" + "=" * 70
      puts "Profiling: packet.decom"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([Integer, :times])
      profile.start
      profile_iterations.times { packet.decom }
      result = profile.stop

      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      File.open(File.join(profile_dir, "decom_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      File.open(File.join(profile_dir, "decom_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      puts "\nProfile output written to profile/ directory"
      puts "  - decom_#{RUBY_VERSION}.txt (flat profile)"
      puts "  - decom_#{RUBY_VERSION}.html (call graph)"
    end

    it "profiles TelemetryDecomTopic.write_packet" do
      packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
      packet.received_time = Time.now.sys
      packet.buffer = generate_health_status_buffer

      # Warm up
      10.times { OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT') }

      puts "\n" + "=" * 70
      puts "Profiling: TelemetryDecomTopic.write_packet"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([Integer, :times])
      profile.start
      profile_iterations.times { OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT') }
      result = profile.stop

      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      File.open(File.join(profile_dir, "tlm_decom_topic_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      File.open(File.join(profile_dir, "tlm_decom_topic_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      puts "\nProfile output written to profile/ directory"
      puts "  - tlm_decom_topic_#{RUBY_VERSION}.txt (flat profile)"
      puts "  - tlm_decom_topic_#{RUBY_VERSION}.html (call graph)"
    end

    it "profiles full decom path" do
      packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
      buffer = generate_health_status_buffer

      # Warm up
      10.times do
        packet.buffer = buffer
        packet.check_limits(OpenC3::System.limits_set)
        OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
      end

      puts "\n" + "=" * 70
      puts "Profiling: Full decom path"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([Integer, :times])
      profile.start
      profile_iterations.times do
        packet.stored = false
        packet.received_time = Time.now.sys
        packet.buffer = buffer
        packet.check_limits(OpenC3::System.limits_set)
        OpenC3::TelemetryDecomTopic.write_packet(packet, scope: 'DEFAULT')
      end
      result = profile.stop

      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      File.open(File.join(profile_dir, "full_decom_path_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      File.open(File.join(profile_dir, "full_decom_path_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      puts "\nProfile output written to profile/ directory"
      puts "  - full_decom_path_#{RUBY_VERSION}.txt (flat profile)"
      puts "  - full_decom_path_#{RUBY_VERSION}.html (call graph)"
    end

    it "profiles check_limits" do
      packet = OpenC3::System.telemetry.packet('INST', 'HEALTH_STATUS')
      packet.received_time = Time.now.sys
      packet.buffer = generate_health_status_buffer

      # Warm up
      10.times { packet.check_limits(OpenC3::System.limits_set) }

      puts "\n" + "=" * 70
      puts "Profiling: packet.check_limits"
      puts "Ruby Version: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
      puts "Iterations: #{profile_iterations}"
      puts "=" * 70

      profile = RubyProf::Profile.new(measure_mode: RubyProf::WALL_TIME)
      profile.exclude_methods!([Integer, :times])
      profile.start
      profile_iterations.times { packet.check_limits(OpenC3::System.limits_set) }
      result = profile.stop

      profile_dir = File.join(SPEC_DIR, '..', 'profile')
      FileUtils.mkdir_p(profile_dir)

      File.open(File.join(profile_dir, "check_limits_#{RUBY_VERSION}.txt"), 'w') do |f|
        printer = RubyProf::FlatPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      File.open(File.join(profile_dir, "check_limits_#{RUBY_VERSION}.html"), 'w') do |f|
        printer = RubyProf::GraphHtmlPrinter.new(result)
        printer.print(f, min_percent: 1)
      end

      puts "\nProfile output written to profile/ directory"
      puts "  - check_limits_#{RUBY_VERSION}.txt (flat profile)"
      puts "  - check_limits_#{RUBY_VERSION}.html (call graph)"
    end
  end
end
