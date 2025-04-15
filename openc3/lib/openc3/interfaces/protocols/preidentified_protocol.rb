# encoding: ascii-8bit

# Copyright 2025, OpenC3, Inc.
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

require 'stringio'
require 'openc3/interfaces/protocols/burst_protocol'
require 'openc3/logs/packet_log_constants'
require 'openc3/logs/packet_log_reader'
require 'openc3/logs/packet_log_writer'

module OpenC3
  # Delineates packets using the OpenC3 preidentification system
  class PreidentifiedProtocol < BurstProtocol
    include PacketLogConstants
    COSMOS4_STORED_FLAG_MASK = 0x80
    COSMOS4_EXTRA_FLAG_MASK = 0x40
    COSMOS4_HEADER_LENGTH = 128

    # @param sync_pattern (see BurstProtocol#initialize)
    # @param max_length [Integer] The maximum allowed value of the length field
    # @param version [Integer] COSMOS major version
    # @param file [true/false] Whether we're processing from a file (handle file headers)
    #   This is typically used in conjunction with the file_interface
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(sync_pattern = nil, max_length = nil, version = 6, file = false, allow_empty_data = nil)
      super(0, sync_pattern, false, allow_empty_data)
      @max_length = ConfigParser.handle_nil(max_length)
      @max_length = Integer(@max_length) if @max_length
      @version = Integer(version)
      @file = ConfigParser.handle_true_false(file)
    end

    def reset
      puts "PreidentifiedProtocol: RESET *********************"
      super()
      @reduction_state = :START
      @packet_log_reader = PacketLogReader.new
      @packet_log_writer = PacketLogWriter.new('', '', cycle_thread: false)
    end

    def read_packet(packet)
      packet.received_time = @read_received_time
      packet.target_name = @read_target_name
      packet.packet_name = @read_packet_name
      packet.stored = @read_stored
      return packet
    end

    def write_packet(packet)
      @packet_time = packet.packet_time
      @packet_time = Time.now unless @packet_time
      @received_time = packet.received_time
      @received_time = Time.now unless @received_time
      @write_time_seconds = [@received_time.tv_sec].pack('N') # UINT32
      @write_time_microseconds = [@received_time.tv_usec].pack('N') # UINT32
      @write_target_name = packet.target_name
      @write_target_name = 'UNKNOWN' unless @write_target_name
      @write_packet_name = packet.packet_name
      @write_packet_name = 'UNKNOWN' unless @write_packet_name
      case @version
      when 4
        @write_flags = 0
        @write_flags |= COSMOS4_STORED_FLAG_MASK if packet.stored
        @write_extra = nil
        if packet.extra
          @write_flags |= COSMOS4_EXTRA_FLAG_MASK
          @write_extra = packet.extra.as_json(:allow_nan => true).to_json(:allow_nan => true)
        end
      when 5, 6
        if packet.stored
          @packet_stored = true
        else
          @packet_stored = false
        end
        @write_extra = nil
        @write_extra = packet.extra if packet.extra
      else
        raise "PreidentifiedProtocol unsupported version: #{@version}"
      end
      return packet
    end

    def write_data(data, extra = nil)
      data_length = [data.length].pack('N') # UINT32
      data_to_send = ''
      data_to_send << @sync_pattern if @sync_pattern
      case @version
      when 4
        data_to_send << @write_flags
        if @write_extra
          data_to_send << [@write_extra.length].pack('N')
          data_to_send << @write_extra
        end
        data_to_send << @write_time_seconds
        data_to_send << @write_time_microseconds
        data_to_send << @write_target_name.length
        data_to_send << @write_target_name
        data_to_send << @write_packet_name.length
        data_to_send << @write_packet_name
        data_to_send << data_length
        data_to_send << data
      when 5, 6
        data_to_send << @packet_log_writer.build_entry(
          :RAW_PACKET,
          :TLM,
          @write_target_name,
          @write_packet_name,
          @packet_time.to_nsec_from_epoch,
          @packet_stored,
          data,
          nil,
          received_time_nsec_since_epoch: @received_time.to_nsec_from_epoch,
          extra: @write_extra
        )
      else
        raise "PreidentifiedProtocol unsupported version: #{@version}"
      end
      return data_to_send, extra
    end

    protected

    def read_length_field_followed_by_string(length_num_bytes)
      # Read bytes for string length
      return :STOP if @data.length < length_num_bytes

      string_length = @data[0..(length_num_bytes - 1)]

      case length_num_bytes
      when 1
        string_length = string_length.unpack('C')[0] # UINT8
      when 2
        string_length = string_length.unpack('n')[0] # UINT16
      when 4
        string_length = string_length.unpack('N')[0] # UINT32
        raise "Length value received larger than max_length: #{string_length} > #{@max_length}" if @max_length and string_length > @max_length
      else
        raise "Unsupported length given to read_length_field_followed_by_string: #{length_num_bytes}"
      end

      # Read String
      return :STOP if @data.length < (string_length + length_num_bytes)

      next_index = string_length + length_num_bytes
      string = @data[length_num_bytes..(next_index - 1)]

      # Remove data from current_data
      @data.replace(@data[next_index..-1])

      return string
    end

    # Called by the BurstProtocol in read_data to process the data
    def reduce_to_single_packet
      # File mode is special in that we're reading from a file and need to handle the file header
      if @file and @extra and @extra[:filename]
        # Check to see if we have built up more than the initial file size
        # this isn't the full files size, just the size of the data we have so far
        # If so it means we're staring a new file so we should replace our @data with the new file contents
        if @data.length > @extra[:size]
          @data.replace(@data[@extra[:size]..-1])
          @reduction_state = :START
        end
      end

      # Discard sync pattern if present
      if @sync_pattern
        if @reduction_state == :START
          return :STOP if @data.length < @sync_pattern.length

          @data.replace(@data[(@sync_pattern.length)..-1])
          @reduction_state = :SYNC_REMOVED
        end
      elsif @reduction_state == :START
        @reduction_state = :SYNC_REMOVED
      end

      if @file
        if @reduction_state == :SYNC_REMOVED
          # Ensure we have enough data to read the header
          return :STOP if @data.length < OPENC3_HEADER_LENGTH
          header = @data[0...OPENC3_HEADER_LENGTH]
          case @version
          when 4
            # If we're version 4 and we don't have a COSMOS4 header then start over
            if header != COSMOS4_FILE_HEADER
              @reduction_state = :START
              return :STOP
            else
              return :STOP if @data.length < COSMOS4_HEADER_LENGTH
              # Read and discard the rest of the header
              @data.replace(@data[(COSMOS4_HEADER_LENGTH)..-1])
            end
          when 5, 6
            # If we're version 5 or 6 and we don't have a COSMOS5 header then start over
            if header != OPENC3_FILE_HEADER
              @reduction_state = :START
              return :STOP
            end
            # NOTE: We keep the file header in the data stream because packet_log_reader handles it
          else
            raise "PreidentifiedProtocol unsupported version: #{@version}"
          end
          @reduction_state = :PACKETS
        end
      else
        @reduction_state = :PACKETS
      end

      case @version
      when 4
        return handle_mode4()
      when 5, 6
        return handle_mode5()
      else
        raise "PreidentifiedProtocol unsupported version: #{@version}"
      end
    end

    def handle_mode5
      if @file and @extra and @extra[:filename]
        filename = @extra[:filename]
      else
        filename = @packet_log_reader.filename
      end

      # If this is the first time through or the filename has changed
      if !@packet_log_reader.filename or @packet_log_reader.filename != filename
        @packet_log_reader.open(filename, string_io: StringIO.new(@data, 'rb'), file_header: @file)
      end
      packet = @packet_log_reader.read()
      if packet
        # Set the data returned in read_packet()
        @read_target_name = packet.target_name
        @read_packet_name = packet.packet_name
        @read_received_time = packet.received_time
        @read_stored = packet.stored
        return packet.buffer, packet.extra
      else
        return :STOP
      end
    end

    def handle_mode4
      # Read and remove flags
      return :STOP if @data.length < 1

      flags = @data[0].unpack('C')[0] # byte
      @data.replace(@data[1..-1])
      @read_stored = false
      @read_stored = true if (flags & COSMOS4_STORED_FLAG_MASK) != 0
      extra = nil
      if (flags & COSMOS4_EXTRA_FLAG_MASK) != 0
        @reduction_state = :NEED_EXTRA
      else
        @reduction_state = :FLAGS_REMOVED
      end

      if @reduction_state == :NEED_EXTRA
        # Read and remove extra
        extra = read_length_field_followed_by_string(4)
        return :STOP if extra == :STOP

        extra = JSON.parse(extra, :allow_nan => true, :create_additions => true)
        @reduction_state = :FLAGS_REMOVED
      end

      if @reduction_state == :FLAGS_REMOVED
        # Read and remove packet received time
        return :STOP if @data.length < 8

        time_seconds = @data[0..3].unpack('N')[0] # UINT32
        time_microseconds = @data[4..7].unpack('N')[0] # UINT32
        @read_received_time = Time.at(time_seconds, time_microseconds).sys
        @data.replace(@data[8..-1])
        @reduction_state = :TIME_REMOVED
      end

      puts "4@reduction_state #{@reduction_state} data length #{@data.length} @data #{@data.simple_formatted}"
      if @reduction_state == :TIME_REMOVED
        # Read and remove the target name
        @read_target_name = read_length_field_followed_by_string(1)
        return :STOP if @read_target_name == :STOP

        @reduction_state = :TARGET_NAME_REMOVED
      end

      puts "5@reduction_state #{@reduction_state} data length #{@data.length} @data #{@data.simple_formatted}"
      if @reduction_state == :TARGET_NAME_REMOVED
        # Read and remove the packet name
        @read_packet_name = read_length_field_followed_by_string(1)
        return :STOP if @read_packet_name == :STOP

        @reduction_state = :PACKET_NAME_REMOVED
      end

      puts "6@reduction_state #{@reduction_state} data length #{@data.length} @data #{@data.simple_formatted}"
      if @reduction_state == :PACKET_NAME_REMOVED
        # Read packet data and return
        packet_data = read_length_field_followed_by_string(4)
        return :STOP if packet_data == :STOP

        @reduction_state = :PACKETS
        return packet_data, extra
      end

      raise "Error should never reach end of method #{@reduction_state}"
    end
  end
end
