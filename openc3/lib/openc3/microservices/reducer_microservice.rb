# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/microservices/microservice'
require 'openc3/topics/topic'
require 'openc3/topics/telemetry_reduced_topics'
require 'openc3/packets/json_packet'
require 'openc3/utilities/bucket_file_cache'
require 'openc3/utilities/throttle'
require 'openc3/models/reducer_model'
require 'openc3/logs/buffered_packet_log_writer'
require 'openc3/ext/reducer_microservice' if RUBY_ENGINE == 'ruby' and !ENV['OPENC3_NO_EXT']
require 'rufus-scheduler'
require 'thread'

module OpenC3
  class ReducerState
    attr_accessor :reduced
    attr_accessor :raw_keys
    attr_accessor :converted_keys
    attr_accessor :entry_time
    attr_accessor :entry_samples
    attr_accessor :current_time
    attr_accessor :previous_time
    attr_accessor :raw_values
    attr_accessor :raw_max_values
    attr_accessor :raw_min_values
    attr_accessor :raw_avg_values
    attr_accessor :raw_stddev_values
    attr_accessor :converted_values
    attr_accessor :converted_max_values
    attr_accessor :converted_min_values
    attr_accessor :converted_avg_values
    attr_accessor :converted_stddev_values
    attr_accessor :first

    def initialize
      @reduced = {}
      @raw_keys = nil
      @converted_keys = nil
      @entry_time = nil
      @entry_samples = nil
      @current_time = nil
      @previous_time = nil
      @raw_values = nil
      @raw_max_values = nil
      @raw_min_values = nil
      @raw_avg_values = nil
      @raw_stddev_values = nil
      @converted_values = nil
      @converted_max_values = nil
      @converted_min_values = nil
      @converted_avg_values = nil
      @converted_stddev_values = nil
      @first = true
    end
  end

  class ReducerMicroservice < Microservice
    MINUTE_METRIC = 'reducer_minute_processing'
    HOUR_METRIC = 'reducer_hour_processing'
    DAY_METRIC = 'reducer_day_processing'

    # How long to wait for any currently running jobs to complete before killing them
    SHUTDOWN_DELAY_SECS = 5
    MINUTE_ENTRY_NSECS = 60 * 1_000_000_000
    MINUTE_FILE_NSECS = 3600 * 1_000_000_000
    HOUR_ENTRY_NSECS = 3600 * 1_000_000_000
    HOUR_FILE_NSECS = 3600 * 24 * 1_000_000_000
    DAY_ENTRY_NSECS = 3600 * 24 * 1_000_000_000
    DAY_FILE_NSECS = 3600 * 24 * 5 * 1_000_000_000

    # @param name [String] Microservice name formatted as <SCOPE>__REDUCER__<TARGET>
    #   where <SCOPE> and <TARGET> are variables representing the scope name and target name
    def initialize(name)
      super(name, is_plugin: false)

      if @config['options']
        @config['options'].each do |option|
          case option[0].upcase
          when 'BUFFER_DEPTH' # Buffer depth to write in time order
            @buffer_depth = option[1].to_i
          when 'MAX_CPU_UTILIZATION'
            @max_cpu_utilization = Float(option[1])
          else
            @logger.error("Unknown option passed to microservice #{@name}: #{option}")
          end
        end
      end

      @buffer_depth = 60 unless @buffer_depth
      @max_cpu_utilization = 30.0 unless @max_cpu_utilization
      @target_name = name.split('__')[-1]
      @packet_logs = {}
      @mutex = Mutex.new
      @previous_metrics = {}

      @error_count = 0

      # Initialize metrics
      @metric.set(name: 'reducer_minute_total', value: 0, type: 'counter')
      @metric.set(name: 'reducer_hour_total', value: 0, type: 'counter')
      @metric.set(name: 'reducer_day_total', value: 0, type: 'counter')
      @metric.set(name: 'reducer_minute_error_total', value: 0, type: 'counter')
      @metric.set(name: 'reducer_hour_error_total', value: 0, type: 'counter')
      @metric.set(name: 'reducer_day_error_total', value: 0, type: 'counter')
      @metric.set(name: 'reducer_minute_processing_sample_seconds', value: 0.0, type: 'gauge', unit: 'seconds')
      @metric.set(name: 'reducer_hour_processing_sample_seconds', value: 0.0, type: 'gauge', unit: 'seconds')
      @metric.set(name: 'reducer_day_processing_sample_seconds', value: 0.0, type: 'gauge', unit: 'seconds')
      @metric.set(name: 'reducer_minute_processing_max_seconds', value: 0.0, type: 'gauge', unit: 'seconds')
      @metric.set(name: 'reducer_hour_processing_max_seconds', value: 0.0, type: 'gauge', unit: 'seconds')
      @metric.set(name: 'reducer_day_processing_max_seconds', value: 0.0, type: 'gauge', unit: 'seconds')
    end

    def run
      # Note it takes several seconds to create the scheduler
      @scheduler = Rufus::Scheduler.new
      # Run every minute
      @scheduler.cron '* * * * *', first: :now do
        reduce_minute
      end
      # Run every 15 minutes
      @scheduler.cron '*/15 * * * *', first: :now do
        reduce_hour
      end
      # Run hourly at minute 5 to allow the hour reducer to finish
      @scheduler.cron '5 * * * *', first: :now do
        reduce_day
      end

      # Let the current thread join the scheduler thread and
      # block until shutdown is called
      @scheduler.join
    end

    def shutdown
      @logger.info("Shutting down reducer microservice: #{@name}")
      @scheduler.shutdown(wait: SHUTDOWN_DELAY_SECS) if @scheduler

      # Make sure all the existing logs are properly closed down
      threads = []
      @packet_logs.each do |name, log|
        threads.concat(log.shutdown)
      end
      # Wait for all the logging threads to move files to buckets
      threads.flatten.compact.each do |thread|
        thread.join
      end
      super()
    end

    def metric(name)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      processed = yield
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start # seconds as a float
      if processed
        sample_name = name + '_sample_seconds'
        @metric.set(name: sample_name, value: elapsed, type: 'gauge', unit: 'seconds')
        max_name = name + '_max_seconds'
        previous_max = @previous_metrics[max_name] || 0.0
        if elapsed > previous_max
          @metric.set(name: max_name, value: elapsed, type: 'gauge', unit: 'seconds')
          @previous_metrics[max_name] = elapsed
        end
      end
    end

    def reduce_minute
      @mutex.synchronize do
        metric(MINUTE_METRIC) do
          processed = false
          ReducerModel
            .all_files(type: :DECOM, target: @target_name, scope: @scope)
            .each do |file|
              process_file(file, 'minute', MINUTE_ENTRY_NSECS, MINUTE_FILE_NSECS)
              ReducerModel.rm_file(file)
              processed = true
          end
          processed # return to yield
        end
      end
    end

    def reduce_hour
      @mutex.synchronize do
        metric(HOUR_METRIC) do
          processed = false
          ReducerModel
            .all_files(type: :MINUTE, target: @target_name, scope: @scope)
            .each do |file|
              process_file(file, 'hour', HOUR_ENTRY_NSECS, HOUR_FILE_NSECS)
              ReducerModel.rm_file(file)
              processed = true
          end
          processed # return to yield
        end
      end
    end

    def reduce_day
      @mutex.synchronize do
        metric(DAY_METRIC) do
          processed = false
          ReducerModel
            .all_files(type: :HOUR, target: @target_name, scope: @scope)
            .each do |file|
              process_file(file, 'day', DAY_ENTRY_NSECS, DAY_FILE_NSECS)
              ReducerModel.rm_file(file)
              processed = true
          end
          processed # return to yield
        end
      end
    end

    def process_file(filename, type, entry_nanoseconds, file_nanoseconds)
      throttle = OpenC3::Throttle.new(@max_cpu_utilization)
      file = BucketFile.new(filename)
      file.retrieve
      unless File.exist?(file.local_path)
        @logger.warn("Reducer Warning: #{file.local_path}: Does not exist")
        return
      end
      unless File.size(file.local_path) > 0
        @logger.warn("Reducer Warning: #{file.local_path}: Is zero bytes")
        return
      end
      throttle.throttle_sleep

      # Determine if we already have a PacketLogWriter created
      _, _, scope, target_name, _, rt_or_stored, _ = File.basename(filename).split('__')
      stored = (rt_or_stored == "stored")

      if @target_name != target_name
        raise "Target name in file #{filename} does not match microservice target name #{@target_name}"
      end
      plw = @packet_logs["#{scope}__#{target_name}__#{rt_or_stored}__#{type}"]
      unless plw
        # Create a new PacketLogWriter for this reduced data
        # e.g. DEFAULT/reduced_minute_logs/tlm/INST/20220101/
        # 20220101204857274290500__20220101205857276524900__DEFAULT__INST__ALL__rt__reduced_minute.bin
        remote_log_directory = "#{scope}/reduced_#{type}_logs/tlm/#{target_name}"
        label = "#{scope}__#{target_name}__ALL__#{rt_or_stored}__reduced_#{type}"
        plw = BufferedPacketLogWriter.new(remote_log_directory, label, true, nil, 1_000_000_000, nil, nil, true, @buffer_depth)
        @packet_logs["#{scope}__#{target_name}__#{rt_or_stored}__#{type}"] = plw
      end

      # The lifetime of all these variables is a single file - single target / multiple packets
      reducer_state = {}
      plr = OpenC3::PacketLogReader.new
      throttle.throttle_sleep
      plr.each(file.local_path) do |packet|
        # Check to see if we should start a new log file before processing this packet
        current_time = packet.packet_time.to_nsec_from_epoch
        check_new_file(reducer_state, plw, type, target_name, stored, current_time, file_nanoseconds)
        state = setup_state(reducer_state, packet, current_time)

        # Determine if we've rolled over a entry boundary
        # We have to use current % entry_nanoseconds < previous % entry_nanoseconds because
        # we don't know the data rates. We also have to check for current - previous >= entry_nanoseconds
        # in case the data rate is so slow we don't have multiple samples per entry
        if state.previous_time &&
          (
            (state.current_time % entry_nanoseconds < state.previous_time % entry_nanoseconds) || # Try to create at perfect intervals
              (state.current_time - state.previous_time >= entry_nanoseconds)                 # Handle big gaps
          )
          write_entry(state, plw, type, target_name, packet.packet_name, stored)
          if check_new_file(reducer_state, plw, type, target_name, stored, current_time, file_nanoseconds)
            state = setup_state(reducer_state, packet, current_time)
          end
        end

        if type == 'minute'
          get_min_samples(packet, state)
        else
          get_hour_day_samples(packet, state)
        end

        reduced = state.reduced
        if type == 'minute'
          update_min_stats(reduced, state)
        else
          update_raw_hour_day_stats(reduced, state)
          update_converted_hour_day_stats(packet, reduced, state)
        end
        state.first = false

        throttle.throttle_sleep
      end
      file.delete # Remove the local copy

      write_all_entries(reducer_state, plw, type, target_name, stored, throttle)

      @logger.debug("Reducer Throttle: #{filename}: total_time: #{Time.now - throttle.reset_time}, sleep_time: #{throttle.total_sleep_time}")

      @count += 1
      if type == 'minute'
        metric_name = 'reducer_minute_total'
      elsif type == 'hour'
        metric_name = 'reducer_hour_total'
      else
        metric_name = 'reducer_day_total'
      end
      @previous_metrics[metric_name] ||= 0
      @previous_metrics[metric_name] += 1
      @metric.set(name: metric_name, value: @previous_metrics[metric_name], type: 'counter')

      true
    rescue => e
      if file.local_path and File.exist?(file.local_path)
        @logger.error("Reducer Error: #{file.local_path}: #{File.size(file.local_path)} bytes: \n#{e.formatted}")
      else
        @logger.error("Reducer Error: #{filename}: \n#{e.formatted}")
      end

      @error_count += 1
      if type == 'minute'
        metric_name = 'reducer_minute_error_total'
      elsif type == 'hour'
        metric_name = 'reducer_hour_error_total'
      else
        metric_name = 'reducer_day_error_total'
      end
      @previous_metrics[metric_name] ||= 0
      @previous_metrics[metric_name] += 1
      @metric.set(name: metric_name, value: @previous_metrics[metric_name], type: 'counter')

      file.delete
      false
    end

    def get_min_samples(packet, state)
      state.entry_samples ||= packet.json_hash.dup # Grab all the samples from the first packet
      if state.first
        state.raw_values = packet.read_all(:RAW, nil, packet.read_all_names(:RAW)).select { |key, value| value.is_a?(Numeric) }
        state.raw_keys ||= state.raw_values.keys
        state.converted_values = packet.read_all(:CONVERTED, nil, packet.read_all_names(:CONVERTED)).select { |key, value| value.is_a?(Numeric) }
        state.converted_keys ||= state.converted_values.keys
      else
        state.raw_values = packet.read_all(:RAW, nil, state.raw_keys).select { |key, value| value.is_a?(Numeric) }
        state.converted_values = packet.read_all(:CONVERTED, nil, state.converted_keys).select { |key, value| value.is_a?(Numeric) }
      end
    end

    def get_hour_day_samples(packet, state)
      # Hour or Day
      state.entry_samples ||= extract_entry_samples(packet)
      if state.first
        state.raw_max_values = packet.read_all(:RAW, :MAX, packet.read_all_names(:RAW, :MAX))
        state.raw_keys = state.raw_max_values.keys
        state.converted_max_values = packet.read_all(:CONVERTED, :MAX, packet.read_all_names(:CONVERTED, :MAX))
        state.converted_keys = state.converted_max_values.keys
      else
        state.raw_max_values = packet.read_all(:RAW, :MAX, state.raw_keys)
        state.converted_max_values = packet.read_all(:CONVERTED, :MAX, state.converted_keys)
      end
      state.raw_min_values = packet.read_all(:RAW, :MIN, state.raw_keys)
      state.raw_avg_values = packet.read_all(:RAW, :AVG, state.raw_keys)
      state.raw_stddev_values = packet.read_all(:RAW, :STDDEV, state.raw_keys)
      state.converted_min_values = packet.read_all(:CONVERTED, :MIN, state.converted_keys)
      state.converted_avg_values = packet.read_all(:CONVERTED, :AVG, state.converted_keys)
      state.converted_stddev_values = packet.read_all(:CONVERTED, :STDDEV, state.converted_keys)
    end

    if RUBY_ENGINE != 'ruby' or ENV['OPENC3_NO_EXT']
      def update_min_stats(reduced, state)
        # Update statistics for this packet's raw values
        state.raw_values.each do |key, value|
          if value
            vals_key = "#{key}__VALS"
            reduced[vals_key] ||= []
            reduced[vals_key] << value
            n_key = "#{key}__N"
            reduced[n_key] ||= value
            reduced[n_key] = value if value < reduced[n_key]
            x_key = "#{key}__X"
            reduced[x_key] ||= value
            reduced[x_key] = value if value > reduced[x_key]
          end
        end

        # Update statistics for this packet's converted values
        state.converted_values.each do |key, value|
          if value
            cvals_key = "#{key}__CVALS"
            reduced[cvals_key] ||= []
            reduced[cvals_key] << value
            cn_key = "#{key}__CN"
            reduced[cn_key] ||= value
            reduced[cn_key] = value if value < reduced[cn_key]
            cx_key = "#{key}__CX"
            reduced[cx_key] ||= value
            reduced[cx_key] = value if value > reduced[cx_key]
          end
        end
      end
    end

    def update_raw_hour_day_stats(reduced, state)
      # Update statistics for this packet's raw values
      state.raw_max_values.each do |key, value|
        if value
          max_key = "#{key}__X"
          reduced[max_key] ||= value
          reduced[max_key] = value if value > reduced[max_key]
        end
      end
      state.raw_min_values.each do |key, value|
        if value
          min_key = "#{key}__N"
          reduced[min_key] ||= value
          reduced[min_key] = value if value < reduced[min_key]
        end
      end
      state.raw_avg_values.each do |key, value|
        if value
          avg_values_key = "#{key}__AVGVALS"
          reduced[avg_values_key] ||= []
          reduced[avg_values_key] << value
        end
      end
      state.raw_stddev_values.each do |key, value|
        if value
          stddev_values_key = "#{key}__STDDEVVALS"
          reduced[stddev_values_key] ||= []
          reduced[stddev_values_key] << value
        end
      end
    end

    def update_converted_hour_day_stats(packet, reduced, state)
      # Update statistics for this packet's converted values
      state.converted_max_values.each do |key, value|
        if value
          max_key = "#{key}__CX"
          reduced[max_key] ||= value
          reduced[max_key] = value if value > reduced[max_key]
        end
      end
      state.converted_min_values.each do |key, value|
        if value
          min_key = "#{key}__CN"
          reduced[min_key] ||= value
          reduced[min_key] = value if value < reduced[min_key]
        end
      end
      state.converted_avg_values.each do |key, value|
        if value
          avg_values_key = "#{key}__CAVGVALS"
          reduced[avg_values_key] ||= []
          reduced[avg_values_key] << value
        end
      end
      state.converted_stddev_values.each do |key, value|
        if value
          stddev_values_key = "#{key}__CSTDDEVVALS"
          reduced[stddev_values_key] ||= []
          reduced[stddev_values_key] << value
        end
      end

      reduced["_NUM_SAMPLES__VALS"] ||= []
      reduced["_NUM_SAMPLES__VALS"] << packet.read('_NUM_SAMPLES')
    end

    def check_new_file(reducer_state, plw, type, target_name, stored, current_time, file_nanoseconds)
      plw_first_time_nsec = plw.buffered_first_time_nsec
      if plw_first_time_nsec && ((current_time - plw_first_time_nsec) >= file_nanoseconds)
        # Write out all entries in progress
        write_all_entries(reducer_state, plw, type, target_name, stored)
        reducer_state.clear
        plw.close_file
        return true
      else
        return false
      end
    end

    def setup_state(reducer_state, packet, current_time)
      # Get state for this packet
      state = reducer_state[packet.packet_name]
      unless state
        state = ReducerState.new
        reducer_state[packet.packet_name] = state
      end

      # Update state timestamps
      state.previous_time = state.current_time # Will be nil first packet
      state.current_time = current_time
      state.entry_time ||= state.current_time # Sets the entry time from the first packet
      return state
    end

    def write_all_entries(reducer_state, plw, type, target_name, stored, throttle = nil)
      reducer_state.each do |packet_name, state|
        write_entry(state, plw, type, target_name, packet_name, stored)
        throttle.throttle_sleep if throttle
      end
    end

    def write_entry(state, plw, type, target_name, packet_name, stored)
      return unless state.reduced.length > 0
      reduce(type, state.raw_keys, state.converted_keys, state.reduced)
      state.reduced.merge!(state.entry_samples)
      time = state.entry_time
      data = JSON.generate(state.reduced.as_json(:allow_nan => true))
      if type == "minute"
        redis_topic, redis_offset = TelemetryReducedMinuteTopic.write(target_name: target_name, packet_name: packet_name, stored: stored, time: time, data: data, scope: @scope)
      elsif type == "hour"
        redis_topic, redis_offset = TelemetryReducedHourTopic.write(target_name: target_name, packet_name: packet_name, stored: stored, time: time, data: data, scope: @scope)
      else
        redis_topic, redis_offset = TelemetryReducedDayTopic.write(target_name: target_name, packet_name: packet_name, stored: stored, time: time, data: data, scope: @scope)
      end
      plw.buffered_write(
        :JSON_PACKET,
        :TLM,
        target_name,
        packet_name,
        time,
        stored,
        data,
        nil,
        redis_topic,
        redis_offset
      )

      # Reset necessary state variables
      state.entry_time = state.current_time # This packet starts the next entry
      state.entry_samples = nil
      state.reduced = {}
    end

    def reduce(type, raw_keys, converted_keys, reduced)
      # We've collected all the values so calculate the AVG and STDDEV
      if type == 'minute'
        raw_keys.each do |key|
          if reduced["#{key}__VALS"]
            reduced["_NUM_SAMPLES"] ||= reduced["#{key}__VALS"].length # Keep a single sample count per packet
            reduced["#{key}__A"], reduced["#{key}__S"] =
              Math.stddev_population(reduced["#{key}__VALS"])
            # Remove the raw values as they're only used for AVG / STDDEV calculation
            reduced.delete("#{key}__VALS")
          end
        end

        converted_keys.each do |key|
          if reduced["#{key}__CVALS"]
            reduced["_NUM_SAMPLES"] ||= reduced["#{key}__CVALS"].length # Keep a single sample count per packet
            reduced["#{key}__CA"], reduced["#{key}__CS"] =
              Math.stddev_population(reduced["#{key}__CVALS"])

            # Remove the converted values as they're only used for AVG / STDDEV calculation
            reduced.delete("#{key}__CVALS")
          end
        end
      else
        samples = reduced["_NUM_SAMPLES__VALS"]
        samples_sum = samples.sum
        reduced["_NUM_SAMPLES"] = samples_sum
        reduced.delete("_NUM_SAMPLES__VALS")

        raw_keys.each { |key| reduce_running(key, reduced, samples, samples_sum, "__A", "__S", "__AVGVALS", "__STDDEVVALS") }
        converted_keys.each { |key| reduce_running(key, reduced, samples, samples_sum, "__CA", "__CS", "__CAVGVALS", "__CSTDDEVVALS") }
      end
    end

    def reduce_running(key, reduced, samples, samples_sum, avg_key, stddev_key, avgvals_key, stddevvals_key)
      # Calculate Average
      weighted_sum = 0
      avg = reduced["#{key}#{avgvals_key}"]
      if avg
        avg.each_with_index do |val, i|
          weighted_sum += (val * samples[i])
        end
        reduced["#{key}#{avg_key}"] = weighted_sum / samples_sum
      end

      # Do the STDDEV calc last so we can use the previously calculated AVG
      # See https://math.stackexchange.com/questions/1547141/aggregating-standard-deviation-to-a-summary-point
      s2 = 0
      stddev = reduced["#{key}#{stddevvals_key}"]
      if stddev
        stddev.each_with_index do |val, i|
          # puts "i:#{i} val:#{val} samples[i]:#{samples[i]} avg[i]:#{avg[i]}"
          s2 += (samples[i] * avg[i]**2 + val**2)
        end

        # Note: For very large numbers with very small deviations this sqrt can fail.
        # If so then just set the stddev to 0.
        begin
          reduced["#{key}#{stddev_key}"] =
            Math.sqrt(s2 / samples_sum - reduced["#{key}#{avg_key}"])
        rescue Exception
          reduced["#{key}#{stddev_key}"] = 0.0
        end
      end

      reduced.delete("#{key}#{avgvals_key}")
      reduced.delete("#{key}#{stddevvals_key}")
    end

    # Extract just the not reduced fields from a JsonPacket
    def extract_entry_samples(packet)
      result = {}
      packet.json_hash.each do |key, value|
        key_split = key.split('__')
        if (not key_split[1] or not ['N', 'X', 'A', 'S'].include?(key_split[1][-1])) and key != '_NUM_SAMPLES'
          result[key] = value
        end
      end
      return result
    end

  end
end

if __FILE__ == $0
  OpenC3::ReducerMicroservice.run
  ThreadManager.instance.shutdown
  ThreadManager.instance.join
end