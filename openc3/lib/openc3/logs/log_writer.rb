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

require 'openc3/config/config_parser'
require 'openc3/topics/topic'
require 'openc3/utilities/bucket_utilities'

module OpenC3
  # Creates a log. Can automatically cycle the log based on an elapsed
  # time period or when the log file reaches a predefined size.
  class LogWriter
    # @return [String] The filename of the packet log
    attr_reader :filename

    # @return [true/false] Whether logging is enabled
    attr_reader :logging_enabled

    # @return cycle_time [Integer] The amount of time in seconds before creating
    #   a new log file. This can be combined with cycle_size.
    attr_reader :cycle_time

    # @return cycle_size [Integer] The amount of data in bytes before creating
    #   a new log file. This can be combined with cycle_time.
    attr_reader :cycle_size

    # @return cycle_hour [Integer] The time at which to cycle the log. Combined with
    #   cycle_minute to cycle the log daily at the specified time. If nil, the log
    #   will be cycled hourly at the specified cycle_minute.
    attr_reader :cycle_hour

    # @return cycle_minute [Integer] The time at which to cycle the log. See cycle_hour
    #   for more information.
    attr_reader :cycle_minute

    # @return [Time] Time that the current log file started
    attr_reader :start_time

    # @return [Mutex] Instance mutex protecting file
    attr_reader :mutex

    # Redis offsets for each topic to cleanup
    attr_accessor :cleanup_offsets

    # Time at which to cleanup
    attr_accessor :cleanup_times

    # The cycle time interval. Cycle times are only checked at this level of
    # granularity.
    CYCLE_TIME_INTERVAL = 10

    # Delay in seconds before trimming Redis streams
    CLEANUP_DELAY = 60

    # Mutex protecting class variables
    @@mutex = Mutex.new

    # Array of instances used to keep track of cycling logs
    @@instances = []

    # Thread used to cycle logs across all log writers
    @@cycle_thread = nil

    # Sleeper used to delay cycle thread
    @@cycle_sleeper = nil

    # @param remote_log_directory [String] The path to store the log files
    # @param logging_enabled [Boolean] Whether to start with logging enabled
    # @param cycle_time [Integer] The amount of time in seconds before creating
    #   a new log file. This can be combined with cycle_size.
    # @param cycle_size [Integer] The size in bytes before creating a new log
    #   file. This can be combined with cycle_time.
    # @param cycle_hour [Integer] The time at which to cycle the log. Combined with
    #   cycle_minute to cycle the log daily at the specified time. If nil, the log
    #   will be cycled hourly at the specified cycle_minute.
    # @param cycle_minute [Integer] The time at which to cycle the log. See cycle_hour
    #   for more information.
    def initialize(
      remote_log_directory,
      logging_enabled = true,
      cycle_time = nil,
      cycle_size = 1_000_000_000,
      cycle_hour = nil,
      cycle_minute = nil,
      enforce_time_order = true
    )
      @remote_log_directory = remote_log_directory
      @logging_enabled = ConfigParser.handle_true_false(logging_enabled)
      @cycle_time = ConfigParser.handle_nil(cycle_time)
      if @cycle_time
        @cycle_time = Integer(@cycle_time)
        raise "cycle_time must be >= #{CYCLE_TIME_INTERVAL}" if @cycle_time < CYCLE_TIME_INTERVAL
      end
      @cycle_size = ConfigParser.handle_nil(cycle_size)
      @cycle_size = Integer(@cycle_size) if @cycle_size
      @cycle_hour = ConfigParser.handle_nil(cycle_hour)
      @cycle_hour = Integer(@cycle_hour) if @cycle_hour
      @cycle_minute = ConfigParser.handle_nil(cycle_minute)
      @cycle_minute = Integer(@cycle_minute) if @cycle_minute
      @enforce_time_order = ConfigParser.handle_true_false(enforce_time_order)
      @out_of_order = false
      @mutex = Mutex.new
      @file = nil
      @file_size = 0
      @filename = nil
      @start_time = Time.now.utc
      @first_time = nil
      @last_time = nil
      @cancel_threads = false
      @last_offsets = {}
      @cleanup_offsets = []
      @cleanup_times = []
      @previous_time_nsec_since_epoch = nil
      @tmp_dir = Dir.mktmpdir

      # This is an optimization to avoid creating a new entry object
      # each time we create an entry which we do a LOT!
      @entry = String.new

      # Always make sure there is a cycle thread - (because it does trimming)
      @@mutex.synchronize do
        @@instances << self

        unless @@cycle_thread
          @@cycle_thread = OpenC3.safe_thread("Log cycle") do
            cycle_thread_body()
          end
        end
      end
    end

    # Starts a new log file by closing the existing log file. New log files are
    # not created until packets are written by {#write} so this does not
    # immediately create a log file on the filesystem.
    def start
      @mutex.synchronize { close_file(false); @logging_enabled = true }
    end

    # Stops all logging and closes the current log file.
    def stop
      threads = nil
      @mutex.synchronize { threads = close_file(false); @logging_enabled = false; }
      return threads
    end

    # Stop all logging, close the current log file, and kill the logging threads.
    def shutdown
      threads = stop()
      @@mutex.synchronize do
        @@instances.delete(self)
        if @@instances.length <= 0
          @@cycle_sleeper.cancel if @@cycle_sleeper
          OpenC3.kill_thread(self, @@cycle_thread) if @@cycle_thread
          @@cycle_thread = nil
        end
      end
      return threads
    end

    def graceful_kill
      @cancel_threads = true
    end

    # implementation details

    def create_unique_filename(ext = extension)
      # Create a filename that doesn't exist
      attempt = nil
      while true
        filename_parts = [attempt]
        filename_parts.unshift @label if @label
        filename = File.join(@tmp_dir, File.build_timestamped_filename([@label, attempt], ext))
        if File.exist?(filename)
          attempt ||= 0
          attempt += 1
          Logger.warn("Unexpected file name conflict: #{filename}")
        else
          return filename
        end
      end
    end

    def cycle_thread_body
      @@cycle_sleeper = Sleeper.new
      while true
        start_time = Time.now
        @@mutex.synchronize do
          @@instances.each do |instance|
            # The check against start_time needs to be mutex protected to prevent a packet coming in between the check
            # and closing the file
            instance.mutex.synchronize do
              utc_now = Time.now.utc
              # Logger.debug("start:#{@start_time.to_f} now:#{utc_now.to_f} cycle:#{@cycle_time} new:#{(utc_now - @start_time) > @cycle_time}")
              if instance.logging_enabled and instance.filename # Logging and file opened
                # Cycle based on total time logging
                if (instance.cycle_time and (utc_now - instance.start_time) > instance.cycle_time)
                  Logger.debug("Log writer start new file due to cycle time")
                  instance.close_file(false)
                # Cycle daily at a specific time
                elsif (instance.cycle_hour and instance.cycle_minute and utc_now.hour == instance.cycle_hour and utc_now.min == instance.cycle_minute and instance.start_time.yday != utc_now.yday)
                  Logger.debug("Log writer start new file daily")
                  instance.close_file(false)
                # Cycle hourly at a specific time
                elsif (instance.cycle_minute and not instance.cycle_hour and utc_now.min == instance.cycle_minute and instance.start_time.hour != utc_now.hour)
                  Logger.debug("Log writer start new file hourly")
                  instance.close_file(false)
                end
              end

              # Check for cleanup time
              indexes_to_clear = []
              instance.cleanup_times.each_with_index do |cleanup_time, index|
                if cleanup_time <= utc_now
                  # Now that the file is in S3, trim the Redis stream up until the previous file.
                  # This keeps one minute of data in Redis
                  instance.cleanup_offsets[index].each do |redis_topic, cleanup_offset|
                    Topic.trim_topic(redis_topic, cleanup_offset)
                  end
                  indexes_to_clear << index
                end
              end
              if indexes_to_clear.length > 0
                indexes_to_clear.each do |index|
                  instance.cleanup_offsets[index] = nil
                  instance.cleanup_times[index] = nil
                end
                instance.cleanup_offsets.compact!
                instance.cleanup_times.compact!
              end
            end
          end
        end

        # Only check whether to cycle at a set interval
        run_time = Time.now - start_time
        sleep_time = CYCLE_TIME_INTERVAL - run_time
        sleep_time = 0 if sleep_time < 0
        break if @@cycle_sleeper.sleep(sleep_time)
      end
    end

    # Starting a new log file is a critical operation so the entire method is
    # wrapped with a rescue and handled with handle_critical_exception
    # Assumes mutex has already been taken
    def start_new_file
      close_file(false) if @file

      # Start log file
      @filename = create_unique_filename()
      @file = File.new(@filename, 'wb')
      @file_size = 0

      @start_time = Time.now.utc
      @out_of_order = false
      @first_time = nil
      @last_time = nil
      @previous_time_nsec_since_epoch = nil
      Logger.debug "Log File Opened : #{@filename}"
    rescue => e
      Logger.error "Error starting new log file: #{e.formatted}"
      @logging_enabled = false
      OpenC3.handle_critical_exception(e)
    end

    # @enforce_time_order requires the timestamps on each write to be greater than the previous
    # process_out_of_order ignores the timestamps for the current entry (used to ignore timestamps on metadata entries, vs actual packets)
    def prepare_write(time_nsec_since_epoch, data_length, redis_topic = nil, redis_offset = nil, allow_new_file: true, process_out_of_order: true)
      # This check includes logging_enabled again because it might have changed since we acquired the mutex
      # Ensures new files based on size, and ensures always increasing time order in files
      if @logging_enabled
        if !@file
          Logger.debug("Log writer start new file because no file opened")
          start_new_file() if allow_new_file
        elsif @cycle_size and ((@file_size + data_length) > @cycle_size)
          Logger.debug("Log writer start new file due to cycle size #{@cycle_size}")
          start_new_file() if allow_new_file
        elsif process_out_of_order and @enforce_time_order and @previous_time_nsec_since_epoch and (@previous_time_nsec_since_epoch > time_nsec_since_epoch)
          # Warning: Creating new files here can cause lots of files to be created if packets make it through out of order
          # Changed to just a error to prevent file thrashing
          unless @out_of_order
            Logger.error("Log writer out of order time detected (increase buffer depth?): #{Time.from_nsec_from_epoch(@previous_time_nsec_since_epoch)} #{Time.from_nsec_from_epoch(time_nsec_since_epoch)}")
            @out_of_order = true
          end
        end
      end
      @last_offsets[redis_topic] = redis_offset if redis_topic and redis_offset # This is needed for the redis offset marker entry at the end of the log file
      @previous_time_nsec_since_epoch = time_nsec_since_epoch if process_out_of_order
    end

    # Closing a log file isn't critical so we just log an error. NOTE: This also trims the Redis stream
    # to keep a full file's worth of data in the stream. This is what prevents continuous stream growth.
    # Returns thread that moves log to bucket
    def close_file(take_mutex = true)
      threads = []
      @mutex.lock if take_mutex
      begin
        if @file
          begin
            @file.close unless @file.closed?
            Logger.debug "Log File Closed : #{@filename}"
            date = first_timestamp[0..7] # YYYYMMDD
            bucket_key = File.join(@remote_log_directory, date, bucket_filename())
            # Cleanup timestamps here so they are unset for the next file
            @first_time = nil
            @last_time = nil
            threads << BucketUtilities.move_log_file_to_bucket(@filename, bucket_key)
            # Now that the file is in storage, trim the Redis stream after a delay
            @cleanup_offsets << {}
            @last_offsets.each do |redis_topic, last_offset|
              @cleanup_offsets[-1][redis_topic] = last_offset
            end
            @cleanup_times << (Time.now + CLEANUP_DELAY)
            @last_offsets.clear
          rescue Exception => e
            Logger.error "Error closing #{@filename} : #{e.formatted}"
          end

          @file = nil
          @file_size = 0
          @filename = nil
        end
      ensure
        @mutex.unlock if take_mutex
      end
      return threads
    end

    def bucket_filename
      "#{first_timestamp}__#{last_timestamp}" + extension
    end

    def extension
      '.log'.freeze
    end

    def first_timestamp
      Time.from_nsec_from_epoch(@first_time).to_timestamp # "YYYYMMDDHHmmSSNNNNNNNNN"
    end

    def last_timestamp
      Time.from_nsec_from_epoch(@last_time).to_timestamp # "YYYYMMDDHHmmSSNNNNNNNNN"
    end
  end
end
