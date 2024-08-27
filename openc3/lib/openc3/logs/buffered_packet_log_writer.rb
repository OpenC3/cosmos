# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/logs/packet_log_writer'

module OpenC3
  # Creates a packet log. Can automatically cycle the log based on an elapsed
  # time period or when the log file reaches a predefined size.
  class BufferedPacketLogWriter < PacketLogWriter
    # @param remote_log_directory [String] The path to store the log files
    # @param label [String] Label to apply to the log filename
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
    # @param buffer_depth [Integer] Number of packets to buffer before writing to file
    def initialize(
      remote_log_directory,
      label,
      logging_enabled = true,
      cycle_time = nil,
      cycle_size = 1_000_000_000,
      cycle_hour = nil,
      cycle_minute = nil,
      enforce_time_order = true,
      buffer_depth = 60, # Default assumes 1 minute of 1Hz data
      scope: $openc3_scope
    )
      super(
        remote_log_directory,
        label,
        logging_enabled,
        cycle_time,
        cycle_size,
        cycle_hour,
        cycle_minute,
        enforce_time_order,
        scope: scope
      )
      @buffer_depth = Integer(buffer_depth)
      @buffer = []
    end

    # Write a packet to the log file.
    #
    # If no log file currently exists in the filesystem, a new file will be
    # created.
    #
    # @param entry_type [Symbol] Type of entry to write. Must be one of
    #   :TARGET_DECLARATION, :PACKET_DECLARATION, :RAW_PACKET, :JSON_PACKET, :OFFSET_MARKER, :KEY_MAP
    # @param cmd_or_tlm [Symbol] One of :CMD or :TLM
    # @param target_name [String] Name of the target
    # @param packet_name [String] Name of the packet
    # @param time_nsec_since_epoch [Integer] 64 bit integer nsecs since EPOCH
    # @param stored [Boolean] Whether this data is stored telemetry
    # @param data [String] Binary string of data
    # @param id [Integer] Target ID
    # @param redis_offset [Integer] The offset of this packet in its Redis stream
    def buffered_write(entry_type, cmd_or_tlm, target_name, packet_name, time_nsec_since_epoch, stored, data, id = nil, redis_topic = nil, redis_offset = '0-0', received_time_nsec_since_epoch: nil, extra: nil)
      case entry_type
      when :RAW_PACKET, :JSON_PACKET
        # If we have data in the buffer, a file should always be open so that cycle time logic will run
        unless @file
          @mutex.synchronize { start_new_file() }
        end

        @buffer << [entry_type, cmd_or_tlm, target_name, packet_name, time_nsec_since_epoch, stored, data, id, redis_topic, redis_offset, received_time_nsec_since_epoch, extra]
        @buffer.sort! {|entry1, entry2| entry1[4] <=> entry2[4] }
        if @buffer.length >= @buffer_depth
          entry = @buffer.shift
          write(*entry[0..-3], received_time_nsec_since_epoch: entry[-2], extra: entry[-1])
        end
      else
        write(entry_type, cmd_or_tlm, target_name, packet_name, time_nsec_since_epoch, stored, data, id, redis_topic, redis_offset, received_time_nsec_since_epoch: received_time_nsec_since_epoch, extra: extra)
      end
    end

    def buffered_first_time_nsec
      return @first_time if @first_time
      return @buffer[0][4] if @buffer[0]
      return nil
    end

    def close_file(take_mutex = true)
      @mutex.lock if take_mutex
      begin
        # Need to write out the buffer before closing out the file
        if @buffer.length > 0
          start_new_file() unless @file
          write_buffer()
        end
        return super(false) # Someone has already taken mutex here
      ensure
        @mutex.unlock if take_mutex
      end
    end

    # Mutex is already taken when this is called so we need to adjust
    # prepare_write and write accordingly
    def write_buffer
      begin
        @buffer.each do |entry|
          write(*entry[0..-3], allow_new_file: false, take_mutex: false, received_time_nsec_since_epoch: entry[-2], extra: entry[-1])
        end
      rescue => e
        Logger.instance.error "Error writing out buffer : #{e.formatted}"
      end
      @buffer = []
    end
  end
end
