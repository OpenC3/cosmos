# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

require 'openc3/logs/log_writer'

module OpenC3
  # Creates a log file of stream data for either reads or writes. Can automatically
  # cycle the log based on when the log file reaches a predefined size or based on time.
  class StreamLog < LogWriter
    # @return [String] Original name passed to stream log
    attr_reader :orig_name

    # The allowable log types
    LOG_TYPES = [:READ, :WRITE]

    # @param log_name [String] The name of the stream log. Typically matches the
    #    name of the corresponding interface
    # @param log_type [Symbol] The type of log to create. Must be :READ
    #   or :WRITE.
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
      log_name,
      log_type,
      cycle_time = 600, # 5 minutes, matches time in target_model
      cycle_size = 50_000_000, # 50MB, matches size in target_model
      cycle_hour = nil,
      cycle_minute = nil
    )
      raise "log_type must be :READ or :WRITE" unless LOG_TYPES.include? log_type

      super(
        "#{ENV['OPENC3_SCOPE']}/stream_logs/",
        true, # Start with logging enabled
        cycle_time,
        cycle_size,
        cycle_hour,
        cycle_minute
      )

      @log_type = log_type
      self.name = log_name
    end

    # Set the stream log name
    # @param log_name [String] new name
    def name=(log_name)
      @orig_name = log_name
      @log_name = (log_name.to_s.downcase + '_stream_' + @log_type.to_s.downcase).freeze
    end

    # Create a clone of this object with a new name
    def clone
      stream_log = super()
      stream_log.name = stream_log.orig_name
      stream_log
    end

    # Write to the log file.
    #
    # If no log file currently exists in the filesystem, a new file will be
    # created.
    #
    # @param data [String] String of data
    def write(data)
      return if !@logging_enabled
      return if !data or data.length <= 0

      @mutex.synchronize do
        time_nsec_since_epoch = Time.now.to_nsec_from_epoch
        prepare_write(time_nsec_since_epoch, data.length)
        write_entry(time_nsec_since_epoch, data) if @file
      end
    rescue => err
      Logger.instance.error "Error writing #{@filename} : #{err.formatted}"
      OpenC3.handle_critical_exception(err)
    end

    def write_entry(time_nsec_since_epoch, data)
      @file.write(data)
      @file_size += data.length
      @first_time = time_nsec_since_epoch unless @first_time
      @last_time = time_nsec_since_epoch
    end

    def bucket_filename
      "#{first_timestamp}__#{@log_name}" + extension
    end

    def extension
      '.bin'.freeze
    end
  end
end
