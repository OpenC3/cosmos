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

require 'openc3/logs/log_writer'
require 'openc3/logs/packet_log_constants'
require 'cbor'

module OpenC3
  # Creates a packet log. Can automatically cycle the log based on an elasped
  # time period or when the log file reaches a predefined size.
  class PacketLogWriter < LogWriter
    include PacketLogConstants

    attr_accessor :data_format

    # @param remote_log_directory [String] The path to store the log files
    # @param label [String] Label to apply to the log filename
    # @param logging_enabled [Boolean] Whether to start with logging enabled
    # @param cycle_time [Integer] The amount of time in seconds before creating
    #   a new log file. This can be combined with cycle_size but is better used
    #   independently.
    # @param cycle_size [Integer] The size in bytes before creating a new log
    #   file. This can be combined with cycle_time but is better used
    #   independently.
    # @param cycle_hour [Integer] The time at which to cycle the log. Combined with
    #   cycle_minute to cycle the log daily at the specified time. If nil, the log
    #   will be cycled hourly at the specified cycle_minute.
    # @param cycle_minute [Integer] The time at which to cycle the log. See cycle_hour
    #   for more information.
    def initialize(
      remote_log_directory,
      label,
      logging_enabled = true,
      cycle_time = nil,
      cycle_size = 1_000_000_000,
      cycle_hour = nil,
      cycle_minute = nil
    )
      super(
        remote_log_directory,
        logging_enabled,
        cycle_time,
        cycle_size,
        cycle_hour,
        cycle_minute
      )
      @label = label
      @index_file = nil
      @index_filename = nil
      @cmd_packet_table = {}
      @tlm_packet_table = {}
      @key_map_table = {}
      @target_dec_entries = []
      @packet_dec_entries = []
      @key_map_entries = []
      @next_packet_index = 0
      @target_indexes = {}
      @next_target_index = 0
      @data_format = :CBOR # Default to CBOR for improved compression

      # This is an optimization to avoid creating a new entry object
      # each time we create an entry which we do a LOT!
      @index_entry = String.new
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
    def write(entry_type, cmd_or_tlm, target_name, packet_name, time_nsec_since_epoch, stored, data, id = nil, redis_topic = nil, redis_offset = '0-0')
      return if !@logging_enabled

      @mutex.synchronize do
        prepare_write(time_nsec_since_epoch, data.length, redis_topic, redis_offset)
        write_entry(entry_type, cmd_or_tlm, target_name, packet_name, time_nsec_since_epoch, stored, data, id) if @file
      end
    rescue => err
      Logger.instance.error "Error writing #{@filename} : #{err.formatted}"
      OpenC3.handle_critical_exception(err)
    end

    # Starting a new index file is a critical operation so the entire method is
    # wrapped with a rescue and handled with handle_critical_exception
    # Assumes mutex has already been taken
    def start_new_file
      super
      @file.write(OPENC3_FILE_HEADER)
      @file_size += OPENC3_FILE_HEADER.length

      # Start index log file
      @index_filename = create_unique_filename('.idx'.freeze)
      @index_file = File.new(@index_filename, 'wb')
      @index_file.write(OPENC3_INDEX_HEADER)

      @cmd_packet_table = {}
      @tlm_packet_table = {}
      @key_map_table = {}
      @next_packet_index = 0
      @target_indexes = {}
      @target_dec_entries = []
      @packet_dec_entries = []
      @key_map_entries = []
      Logger.debug "Index Log File Opened : #{@index_filename}"
    rescue => err
      Logger.error "Error starting new log file: #{err.formatted}"
      @logging_enabled = false
      OpenC3.handle_critical_exception(err)
    end

    # Closing a log file isn't critical so we just log an error
    # Returns threads that moves log to bucket
    def close_file(take_mutex = true)
      threads = []
      @mutex.lock if take_mutex
      begin
        # Need to write the OFFSET_MARKER for each packet
        @last_offsets.each do |redis_topic, last_offset|
          write_entry(:OFFSET_MARKER, nil, nil, nil, nil, nil, last_offset + ',' + redis_topic, nil) if @file
        end

        threads << super(false)

        if @index_file
          begin
            write_index_file_footer()
            @index_file.close unless @index_file.closed?
            Logger.debug "Index Log File Closed : #{@index_filename}"
            date = first_timestamp[0..7] # YYYYMMDD
            bucket_key = File.join(@remote_log_directory, date, "#{first_timestamp}__#{last_timestamp}__#{@label}.idx")
            threads << BucketUtilities.move_log_file_to_bucket(@index_filename, bucket_key)
          rescue Exception => err
            Logger.instance.error "Error closing #{@index_filename} : #{err.formatted}"
          end

          @index_file = nil
          @index_filename = nil
        end
      ensure
        @mutex.unlock if take_mutex
      end
      return threads
    end

    def get_packet_index(cmd_or_tlm, target_name, packet_name, entry_type, data)
      if cmd_or_tlm == :CMD
        target_table = @cmd_packet_table[target_name]
      else
        target_table = @tlm_packet_table[target_name]
      end
      if target_table
        packet_index = target_table[packet_name]
        return packet_index if packet_index
      else
        # New packet_table entry needed
        target_table = {}
        if cmd_or_tlm == :CMD
          @cmd_packet_table[target_name] = target_table
        else
          @tlm_packet_table[target_name] = target_table
        end
        id = nil
        target = System.targets[target_name]
        id = target.id if target
        write_entry(:TARGET_DECLARATION, cmd_or_tlm, target_name, packet_name, nil, nil, nil, id)
      end

      # New target_table entry needed
      packet_index = @next_packet_index
      if packet_index > OPENC3_MAX_PACKET_INDEX
        raise "Packet Index Overflow"
      end

      target_table[packet_name] = packet_index
      @next_packet_index += 1

      id = nil
      begin
        if cmd_or_tlm == :CMD
          id = System.commands.packet(target_nam, packet_name).config_name
        else
          id = System.telemetry.packet(target_name, packet_name).config_name
        end
      rescue
        # No packet def
      end
      write_entry(:PACKET_DECLARATION, cmd_or_tlm, target_name, packet_name, nil, nil, nil, id)
      if entry_type == :JSON_PACKET
        key_map = @key_map_table[packet_index]
        unless key_map
          parsed = data
          parsed = JSON.parse(data, :allow_nan => true, :create_additions => true) if String === parsed
          keys = parsed.keys
          key_map = {}
          reverse_key_map = {}
          keys.each_with_index do |key, index|
            key_map[index.to_s] = key
            reverse_key_map[key] = index.to_s
          end
          @key_map_table[packet_index] = reverse_key_map
          if @data_format == :CBOR
            write_entry(:KEY_MAP, cmd_or_tlm, target_name, packet_name, nil, nil, key_map.to_cbor, nil)
          else # JSON
            write_entry(:KEY_MAP, cmd_or_tlm, target_name, packet_name, nil, nil, JSON.generate(key_map, :allow_nan => true), nil)
          end
        end
      end
      return packet_index
    end

    def write_entry(entry_type, cmd_or_tlm, target_name, packet_name, time_nsec_since_epoch, stored, data, id)
      raise ArgumentError.new("Length of id must be 64, got #{id.length}") if id and id.length != 64 # 64 hex digits, gets packed to 32 bytes with .pack('H*')

      length = OPENC3_PRIMARY_FIXED_SIZE
      flags = 0
      flags |= OPENC3_STORED_FLAG_MASK if stored
      flags |= OPENC3_ID_FLAG_MASK if id
      case entry_type
      when :TARGET_DECLARATION
        target_index = @next_target_index
        @target_indexes[target_name] = target_index
        @next_target_index += 1
        if target_index > OPENC3_MAX_TARGET_INDEX
          raise "Target Index Overflow"
        end

        flags |= OPENC3_TARGET_DECLARATION_ENTRY_TYPE_MASK
        length += OPENC3_TARGET_DECLARATION_SECONDARY_FIXED_SIZE + target_name.length
        length += OPENC3_ID_FIXED_SIZE if id
        @entry.clear
        @entry << [length, flags].pack(OPENC3_TARGET_DECLARATION_PACK_DIRECTIVE) << target_name
        @entry << [id].pack('H*') if id
        @target_dec_entries << @entry.dup
      when :PACKET_DECLARATION
        target_index = @target_indexes[target_name]
        flags |= OPENC3_PACKET_DECLARATION_ENTRY_TYPE_MASK
        if cmd_or_tlm == :CMD
          flags |= OPENC3_CMD_FLAG_MASK
        end
        length += OPENC3_PACKET_DECLARATION_SECONDARY_FIXED_SIZE + packet_name.length
        length += OPENC3_ID_FIXED_SIZE if id
        @entry.clear
        @entry << [length, flags, target_index].pack(OPENC3_PACKET_DECLARATION_PACK_DIRECTIVE) << packet_name
        @entry << [id].pack('H*') if id
        @packet_dec_entries << @entry.dup
      when :KEY_MAP
        flags |= OPENC3_KEY_MAP_ENTRY_TYPE_MASK
        flags |= OPENC3_CBOR_FLAG_MASK if @data_format == :CBOR
        length += OPENC3_KEY_MAP_SECONDARY_FIXED_SIZE + data.length
        packet_index = get_packet_index(cmd_or_tlm, target_name, packet_name, entry_type, data)
        @entry.clear
        @entry << [length, flags, packet_index].pack(OPENC3_KEY_MAP_PACK_DIRECTIVE) << data
        @key_map_entries << @entry.dup
      when :OFFSET_MARKER
        flags |= OPENC3_OFFSET_MARKER_ENTRY_TYPE_MASK
        length += OPENC3_OFFSET_MARKER_SECONDARY_FIXED_SIZE + data.length
        @entry.clear
        @entry << [length, flags].pack(OPENC3_OFFSET_MARKER_PACK_DIRECTIVE) << data
      when :RAW_PACKET, :JSON_PACKET
        target_name = 'UNKNOWN'.freeze unless target_name
        packet_name = 'UNKNOWN'.freeze unless packet_name
        packet_index = get_packet_index(cmd_or_tlm, target_name, packet_name, entry_type, data)
        if entry_type == :RAW_PACKET
          flags |= OPENC3_RAW_PACKET_ENTRY_TYPE_MASK
        else
          flags |= OPENC3_JSON_PACKET_ENTRY_TYPE_MASK
          key_map = @key_map_table[packet_index]
          if key_map
            # Compress data using key map
            data = JSON.parse(data, :allow_nan => true, :create_additions => true) if String === data
            compressed = {}
            data.each do |key, value|
              compressed_key = key_map[key]
              compressed_key = key unless compressed_key
              compressed[compressed_key] = value
            end
            if @data_format == :CBOR
              flags |= OPENC3_CBOR_FLAG_MASK
              data = compressed.to_cbor
            else
              data = JSON.generate(compressed, :allow_nan => true)
            end
          end
        end
        if cmd_or_tlm == :CMD
          flags |= OPENC3_CMD_FLAG_MASK
        end
        length += OPENC3_PACKET_SECONDARY_FIXED_SIZE + data.length
        @entry.clear
        @index_entry.clear
        @index_entry << [length, flags, packet_index, time_nsec_since_epoch].pack(OPENC3_PACKET_PACK_DIRECTIVE)
        @entry << @index_entry << data
        @index_entry << [@file_size].pack('Q>')
        @index_file.write(@index_entry)
        @first_time = time_nsec_since_epoch if !@first_time or time_nsec_since_epoch < @first_time
        @last_time = time_nsec_since_epoch if !@last_time or time_nsec_since_epoch > @last_time
      else
        raise "Unknown entry_type: #{entry_type}"
      end
      @file.write(@entry)
      @file_size += @entry.length
    end

    def write_index_file_footer
      footer_length = 4 # Includes length of length field at end
      @index_file.write([@target_dec_entries.length].pack('n'))
      footer_length += 2
      @target_dec_entries.each do |target_dec_entry|
        @index_file.write(target_dec_entry)
        footer_length += target_dec_entry.length
      end
      @index_file.write([@packet_dec_entries.length].pack('n'))
      footer_length += 2
      @packet_dec_entries.each do |packet_dec_entry|
        @index_file.write(packet_dec_entry)
        footer_length += packet_dec_entry.length
      end
      @index_file.write([@key_map_entries.length].pack('n'))
      footer_length += 2
      @key_map_entries.each do |key_map_entry|
        @index_file.write(key_map_entry)
        footer_length += key_map_entry.length
      end
      @index_file.write([footer_length].pack('N'))
    end

    def bucket_filename
      "#{first_timestamp}__#{last_timestamp}__#{@label}" + extension
    end

    def extension
      '.bin'.freeze
    end
  end
end
