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

require 'openc3/packets/binary_accessor'
require 'openc3/interfaces/protocols/burst_protocol'
require 'openc3/config/config_parser'

module OpenC3
  # Protocol which delineates packets using a length field at a fixed
  # location in each packet.
  class LengthProtocol < BurstProtocol
    # @param length_bit_offset [Integer] The bit offset of the length field
    # @param length_bit_size [Integer] The size in bits of the length field
    # @param length_value_offset [Integer] The offset to apply to the length
    #   value once it has been read from the packet. The value in the length
    #   field itself plus the length value offset MUST equal the total bytes
    #   including any discarded bytes.
    #   For example: if your length field really means "length - 1" this value should be 1.
    # @param length_bytes_per_count [Integer] The number of bytes per each
    #   length field 'count'. This is used if the units of the length field is
    #   something other than bytes, for example words.
    # @param length_endianness [String] The endianness of the length field.
    #   Must be either BIG_ENDIAN or LITTLE_ENDIAN.
    # @param discard_leading_bytes (see BurstProtocol#initialize)
    # @param sync_pattern (see BurstProtocol#initialize)
    # @param max_length [Integer] The maximum allowed value of the length field
    # @param fill_length_and_sync_pattern [Boolean] Fill the length field and sync
    #    pattern when writing packets
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(
      length_bit_offset = 0,
      length_bit_size = 16,
      length_value_offset = 0,
      length_bytes_per_count = 1,
      length_endianness = 'BIG_ENDIAN',
      discard_leading_bytes = 0,
      sync_pattern = nil,
      max_length = nil,
      fill_length_and_sync_pattern = false,
      allow_empty_data = nil
    )
      super(discard_leading_bytes, sync_pattern, fill_length_and_sync_pattern, allow_empty_data)

      # Save length field attributes
      @length_bit_offset = Integer(length_bit_offset)
      @length_bit_size = Integer(length_bit_size)
      @length_value_offset = Integer(length_value_offset)
      @length_bytes_per_count = Integer(length_bytes_per_count)

      # Save endianness
      if length_endianness.to_s.upcase == 'LITTLE_ENDIAN'
        @length_endianness = :LITTLE_ENDIAN
      else
        @length_endianness = :BIG_ENDIAN
      end

      # Derive number of bytes required to contain entire length field
      if @length_endianness == :BIG_ENDIAN or ((@length_bit_offset % 8) == 0)
        length_bits_needed = @length_bit_offset + @length_bit_size
        length_bits_needed += 8 if (length_bits_needed % 8) != 0
        @length_bytes_needed = ((length_bits_needed - 1) / 8) + 1
      else
        @length_bytes_needed = (length_bit_offset / 8) + 1
      end

      # Save max length setting
      @max_length = ConfigParser.handle_nil(max_length)
      @max_length = Integer(@max_length) if @max_length
    end

    # Called to perform modifications on a command packet before it is send
    #
    # @param packet [Packet] Original packet
    # @return [Packet] Potentially modified packet
    def write_packet(packet)
      if @fill_fields
        # If the start of the length field is past what we discard, then the
        # length field is inside the packet
        if @length_bit_offset >= (@discard_leading_bytes * 8)
          length = calculate_length(packet.buffer(false).length + @discard_leading_bytes)
          # Subtract off the discarded bytes since they haven't been added yet
          # Adding bytes happens in the write_data method
          offset = @length_bit_offset - (@discard_leading_bytes * 8)
          # Directly write the packet buffer and fill in the length
          BinaryAccessor.write(length, offset, @length_bit_size, :UINT,
                               packet.buffer(false), @length_endianness, :ERROR)
        end
      end
      return super(packet) # Allow burst_protocol to set the sync if needed
    end

    # Called to perform modifications on write data before making it into a packet
    #
    # @param data [String] Raw packet data
    # @return [String] Potentially modified packet data
    def write_data(data, extra = nil)
      data, extra = super(data, extra)
      if @fill_fields
        # If the start of the length field is before what we discard, then the
        # length field is outside the packet
        if @length_bit_offset < (@discard_leading_bytes * 8)
          BinaryAccessor.write(calculate_length(data.length), @length_bit_offset, @length_bit_size, :UINT,
                               data, @length_endianness, :ERROR)
        end
      end
      return data, extra
    end

    def write_details
      result = super()
      result['length_bit_offset'] = @length_bit_offset
      result['length_bit_size'] = @length_bit_size
      result['length_value_offset'] = @length_value_offset
      result['length_bytes_per_count'] = @length_bytes_per_count
      result['length_endianness'] = @length_endianness
      result['length_bytes_needed'] = @length_bytes_needed
      result['max_length'] = @max_length
      return result
    end

    def read_details
      result = super()
      result['length_bit_offset'] = @length_bit_offset
      result['length_bit_size'] = @length_bit_size
      result['length_value_offset'] = @length_value_offset
      result['length_bytes_per_count'] = @length_bytes_per_count
      result['length_endianness'] = @length_endianness
      result['length_bytes_needed'] = @length_bytes_needed
      result['max_length'] = @max_length
      return result
    end

    # protected

    def calculate_length(buffer_length)
      length = (buffer_length / @length_bytes_per_count) - @length_value_offset
      if @max_length && length > @max_length
        raise "Calculated length #{length} larger than max_length #{@max_length}"
      end

      length
    end

    def reduce_to_single_packet
      # Make sure we have at least enough data to reach the length field
      return :STOP if @data.length < @length_bytes_needed

      # Determine the packet's length
      length = BinaryAccessor.read(@length_bit_offset,
                                   @length_bit_size,
                                   :UINT,
                                   @data,
                                   @length_endianness)
      raise "Length value received larger than max_length: #{length} > #{@max_length}" if @max_length and length > @max_length

      packet_length = (length * @length_bytes_per_count) + @length_value_offset
      # Ensure the calculated packet length is long enough to support the location of the length field
      # without overlap into the next packet
      if (packet_length * 8) < (@length_bit_offset + @length_bit_size)
        raise "Calculated packet length of #{packet_length * 8} bits < (offset:#{@length_bit_offset} + size:#{@length_bit_size})"
      end

      # Make sure we have enough data for the packet
      return :STOP if @data.length < packet_length

      # Reduce to packet data and setup current_data for next packet
      packet_data = @data[0..(packet_length - 1)]
      @data.replace(@data[packet_length..-1])

      return packet_data, @extra
    end
  end
end
