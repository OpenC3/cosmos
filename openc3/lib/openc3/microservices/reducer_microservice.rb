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

require 'openc3/microservices/microservice'
require 'openc3/topics/topic'
require 'openc3/topics/telemetry_reduced_topics'
require 'openc3/packets/json_packet'
require 'openc3/utilities/bucket_file_cache'
require 'openc3/models/reducer_model'
require 'rufus-scheduler'

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
    MINUTE_METRIC = 'reducer_minute_duration'
    HOUR_METRIC = 'reducer_hour_duration'
    DAY_METRIC = 'reducer_day_duration'

    # How long to wait for any currently running jobs to complete before killing them
    SHUTDOWN_DELAY_SECS = 5
    MINUTE_ENTRY_NSECS = 60 * 1_000_000_000
    MINUTE_FILE_NSECS = 3600 * 1_000_000_000
    HOUR_ENTRY_NSECS = 3600 * 1_000_000_000
    HOUR_FILE_NSECS = 3600 * 24 * 1_000_000_000
    DAY_ENTRY_NSECS = 3600 * 24 * 1_000_000_000
    DAY_FILE_NSECS = 3600 * 24 * 30 * 1_000_000_000

    # @param name [String] Microservice name formatted as <SCOPE>__REDUCER__<TARGET>
    #   where <SCOPE> and <TARGET> are variables representing the scope name and target name
    def initialize(name)
      super(name, is_plugin: false)
      @target_name = name.split('__')[-1]
      @packet_logs = {}
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
      @scheduler.shutdown(wait: SHUTDOWN_DELAY_SECS) if @scheduler

      # Make sure all the existing logs are properly closed down
      @packet_logs.each do |name, log|
        log.shutdown
      end
      super()
    end

    def metric(name)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start # seconds as a float
      @metric.add_sample(
        name: name,
        value: elapsed,
        labels: {
          'target' => @target_name,
        },
      )
    end

    def reduce_minute
      metric(MINUTE_METRIC) do
        ReducerModel
          .all_files(type: :DECOM, target: @target_name, scope: @scope)
          .each do |file|
            process_file(file, 'minute', MINUTE_ENTRY_NSECS, MINUTE_FILE_NSECS)
            ReducerModel.rm_file(file)
          end
      end
    end

    def reduce_hour
      metric(HOUR_METRIC) do
        ReducerModel
          .all_files(type: :MINUTE, target: @target_name, scope: @scope)
          .each do |file|
            process_file(file, 'hour', HOUR_ENTRY_NSECS, HOUR_FILE_NSECS)
            ReducerModel.rm_file(file)
          end
      end
    end

    def reduce_day
      metric(DAY_METRIC) do
        ReducerModel
          .all_files(type: :HOUR, target: @target_name, scope: @scope)
          .each do |file|
            process_file(file, 'day', DAY_ENTRY_NSECS, DAY_FILE_NSECS)
            ReducerModel.rm_file(file)
          end
      end
    end

    def process_file(filename, type, entry_nanoseconds, file_nanoseconds)
      file = BucketFile.new(filename)
      file.retrieve

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
        plw = PacketLogWriter.new(remote_log_directory, label)
        @packet_logs["#{scope}__#{target_name}__#{rt_or_stored}__#{type}"] = plw
      end

      # The lifetime of all these variables is a single file - single target / multiple packets
      reducer_state = {}
      plr = OpenC3::PacketLogReader.new
      plr.each(file.local_path) do |packet|
        state = reducer_state[packet.packet_name]
        unless state
          state = ReducerState.new
          reducer_state[packet.packet_name] = state
        end
        state.previous_time = state.current_time # Will be nil first packet
        state.current_time = packet.packet_time.to_nsec_from_epoch # to_f makes this nanoseconds instead of Time object
        state.entry_time ||= state.current_time # Sets the entry time from the first packet

        if type == 'minute'
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
        else
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

        # Determine if we've rolled over a entry boundary
        # We have to use current % entry_nanoseconds < previous % entry_nanoseconds because
        # we don't know the data rates. We also have to check for current - previous >= entry_nanoseconds
        # in case the data rate is so slow we don't have multiple samples per entry
        if state.previous_time &&
            (
              (state.current_time % entry_nanoseconds < state.previous_time % entry_nanoseconds) || # Try to create at perfect intervals
                (state.current_time - state.previous_time >= entry_nanoseconds)                 # Handle big gaps
            )
          Logger.debug("Reducer: Roll over entry boundary cur_time:#{state.current_time}")

          reduce(type, state.raw_keys, state.converted_keys, state.reduced)
          state.reduced.merge!(state.entry_samples)
          time = state.entry_time
          data = JSON.generate(state.reduced.as_json(:allow_nan => true))
          if type == "minute"
            redis_topic, redis_offset = TelemetryReducedMinuteTopic.write(target_name: target_name, packet_name: packet.packet_name, stored: stored, time: time, data: data, scope: @scope)
          elsif type == "hour"
            redis_topic, redis_offset = TelemetryReducedHourTopic.write(target_name: target_name, packet_name: packet.packet_name, stored: stored, time: time, data: data, scope: @scope)
          else
            redis_topic, redis_offset = TelemetryReducedDayTopic.write(target_name: target_name, packet_name: packet.packet_name, stored: stored, time: time, data: data, scope: @scope)
          end
          plw.write(
            :JSON_PACKET,
            :TLM,
            target_name,
            packet.packet_name,
            time,
            stored,
            data,
            nil,
            redis_topic,
            redis_offset
          )
          # Reset all our sample variables
          state.entry_time = state.current_time # This packet starts the next entry
          if type == 'minute'
            state.entry_samples = packet.json_hash.dup
          else
            state.entry_samples = extract_entry_samples(packet)
          end
          state.reduced = {}

          # Check to see if we should start a new log file
          # We compare the current entry_time to see if it will push us over
          if plw.first_time &&
              (state.entry_time - plw.first_time.to_nsec_from_epoch) >= file_nanoseconds
            Logger.debug("Reducer: (1) start new file! old filename: #{plw.filename}")
            plw.start_new_file # Automatically closes the current file
          end
        end

        reduced = state.reduced
        if type == 'minute'
          # Update statistics for this packet's raw values
          state.raw_values.each do |key, value|
            reduced["#{key}__VALS"] ||= []
            reduced["#{key}__VALS"] << value
            reduced["#{key}__N"] ||= value
            reduced["#{key}__N"] = value if value < reduced["#{key}__N"]
            reduced["#{key}__X"] ||= value
            reduced["#{key}__X"] = value if value > reduced["#{key}__X"]
          end

          # Update statistics for this packet's converted values
          state.converted_values.each do |key, value|
            reduced["#{key}__CVALS"] ||= []
            reduced["#{key}__CVALS"] << value
            reduced["#{key}__CN"] ||= value
            reduced["#{key}__CN"] = value if value < reduced["#{key}__CN"]
            reduced["#{key}__CX"] ||= value
            reduced["#{key}__CX"] = value if value > reduced["#{key}__CX"]
          end
        else
          # Update statistics for this packet's raw values
          state.raw_max_values.each do |key, value|
            max_key = "#{key}__X"
            reduced[max_key] ||= value
            reduced[max_key] = value if value > reduced[max_key]
          end
          state.raw_min_values.each do |key, value|
            min_key = "#{key}__N"
            reduced[min_key] ||= value
            reduced[min_key] = value if value < reduced[min_key]
          end
          state.raw_avg_values.each do |key, value|
            avg_values_key = "#{key}__AVGVALS"
            reduced[avg_values_key] ||= []
            reduced[avg_values_key] << value
          end
          state.raw_stddev_values.each do |key, value|
            stddev_values_key = "#{key}__STDDEVVALS"
            reduced[stddev_values_key] ||= []
            reduced[stddev_values_key] << value
          end

          # Update statistics for this packet's converted values
          state.converted_max_values.each do |key, value|
            max_key = "#{key}__CX"
            reduced[max_key] ||= value
            reduced[max_key] = value if value > reduced[max_key]
          end
          state.converted_min_values.each do |key, value|
            min_key = "#{key}__CN"
            reduced[min_key] ||= value
            reduced[min_key] = value if value < reduced[min_key]
          end
          state.converted_avg_values.each do |key, value|
            avg_values_key = "#{key}__CAVGVALS"
            reduced[avg_values_key] ||= []
            reduced[avg_values_key] << value
          end
          state.converted_stddev_values.each do |key, value|
            stddev_values_key = "#{key}__CSTDDEVVALS"
            reduced[stddev_values_key] ||= []
            reduced[stddev_values_key] << value
          end

          reduced["_NUM_SAMPLES__VALS"] ||= []
          reduced["_NUM_SAMPLES__VALS"] << packet.read('_NUM_SAMPLES')
        end

        state.first = false
      end
      file.delete # Remove the local copy

      reducer_state.each do |packet_name, state|
        # See if this last entry should go in a new file
        if plw.first_time &&
          (state.entry_time - plw.first_time.to_nsec_from_epoch) >= file_nanoseconds
          Logger.debug("Reducer: (2) start new file! old filename: #{plw.filename}")
          plw.start_new_file # Automatically closes the current file
        end

        # Write out the final data now that the file is done
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
        plw.write(
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
      end
      true
    rescue => e
      if file.local_path and File.exist?(file.local_path)
        Logger.error("Reducer Error: #{filename}: #{File.size(file.local_path)} bytes: \n#{e.formatted}")
      else
        Logger.error("Reducer Error: #{filename}: \n#{e.formatted}")
      end
      false
    end

    def reduce(type, raw_keys, converted_keys, reduced)
      # We've collected all the values so calculate the AVG and STDDEV
      if type == 'minute'
        raw_keys.each do |key|
          reduced["_NUM_SAMPLES"] ||= reduced["#{key}__VALS"].length # Keep a single sample count per packet
          reduced["#{key}__A"], reduced["#{key}__S"] =
            Math.stddev_population(reduced["#{key}__VALS"])
          # Remove the raw values as they're only used for AVG / STDDEV calculation
          reduced.delete("#{key}__VALS")
        end

        converted_keys.each do |key|
          reduced["_NUM_SAMPLES"] ||= reduced["#{key}__CVALS"].length # Keep a single sample count per packet
          reduced["#{key}__CA"], reduced["#{key}__CS"] =
            Math.stddev_population(reduced["#{key}__CVALS"])

          # Remove the converted values as they're only used for AVG / STDDEV calculation
          reduced.delete("#{key}__CVALS")
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
      avg.each_with_index do |val, i|
        weighted_sum += (val * samples[i])
      end
      reduced["#{key}#{avg_key}"] = weighted_sum / samples_sum

      # Do the STDDEV calc last so we can use the previously calculated AVG
      # See https://math.stackexchange.com/questions/1547141/aggregating-standard-deviation-to-a-summary-point
      s2 = 0
      reduced["#{key}#{stddevvals_key}"].each_with_index do |val, i|
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

      reduced.delete("#{key}#{avgvals_key}")
      reduced.delete("#{key}#{stddevvals_key}")
    end

    # Extract just the not reduced fields from a JsonPacket
    def extract_entry_samples(packet)
      result = {}
      packet.json_hash.each do |key, value|
        key_split = key.split('__')
        if not key_split[1] or not ['N', 'X', 'A', 'S'].include?(key_split[1][-1]) and key != '_NUM_SAMPLES'
          result[key] = value
        end
      end
      return result
    end

  end
end

OpenC3::ReducerMicroservice.run if __FILE__ == $0
