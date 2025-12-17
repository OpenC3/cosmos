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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/interfaces/protocols/terminated_protocol'
require 'openc3/config/config_parser'

# This file implements the SLIP protocol as documented in RFC 1055
# https://datatracker.ietf.org/doc/html/rfc1055

# SLIP is a framing protocol and is therefore expected to be used for packet deliniation

module OpenC3

  # Usage in plugin.txt:
  #
  # INTERFACE ...
  #   PROTOCOL READ_WRITE SlipProtocol

  class SlipProtocol < TerminatedProtocol

    # Note: Characters are expected to be given as integers
    # @param start_char   [Integer/nil] Character to place at the start of frames (Defaults to nil)
    # @param read_strip_characters [true/false] Strip off start_char and end_char from reads
    # @param read_enable_escaping [true/false] Whether to enable or disable character escaping on reads
    # @param write_enable_escaping [true/false] Whether to enable or disable character escaping on writes
    # @param end_char     [Integer] Character to place at the end of frames (Defaults to 0xC0)
    # @param esc_char     [Integer] Escape character (Defaults to 0xDB)
    # @param esc_end_char [Integer] Character to Escape End character (Defaults to 0xDC)
    # @param esc_esc_char [Integer] Character to Escape Escape character (Defaults to 0xDD)
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(
      start_char = nil,
      read_strip_characters = true,
      read_enable_escaping = true,
      write_enable_escaping = true,
      end_char = 0xC0,
      esc_char = 0xDB,
      esc_end_char = 0xDC,
      esc_esc_char = 0xDD,
      allow_empty_data = nil)

      @start_char = ConfigParser.handle_nil(start_char)
      @start_char = [Integer(start_char)].pack('C') if @start_char
      @end_char = [Integer(end_char)].pack('C')
      @esc_char = [Integer(esc_char)].pack('C')
      @esc_end_char = [Integer(esc_end_char)].pack('C')
      @esc_esc_char = [Integer(esc_esc_char)].pack('C')
      @replace_end = @esc_char + @esc_end_char
      @replace_esc = @esc_char + @esc_esc_char
      @read_strip_characters = ConfigParser.handle_true_false(read_strip_characters)
      raise "read_strip_characters must be true or false" if @read_strip_characters != true and @read_strip_characters != false
      @read_enable_escaping = ConfigParser.handle_true_false(read_enable_escaping)
      raise "read_enable_escaping must be true or false" if @read_enable_escaping != true and @read_enable_escaping != false
      @write_enable_escaping = ConfigParser.handle_true_false(write_enable_escaping)
      raise "write_enable_escaping must be true or false" if @write_enable_escaping != true and @write_enable_escaping != false

      strip_read_termination = false
      discard_leading_bytes = 0
      if @start_char
        sync_pattern = sprintf("%0X", Integer(start_char))
      else
        sync_pattern = nil
      end
      fill_fields = false # Handled in write_data below

      super(
        "", # Write termination handled in write_data below
        sprintf("%0X", Integer(end_char)), # Expects Hex Character String
        strip_read_termination,
        discard_leading_bytes,
        sync_pattern,
        fill_fields,
        allow_empty_data
      )
    end

    def read_data(data, extra = nil)
      data, extra = super(data, extra)
      return data, extra if data.length <= 0 or Symbol === data

      if @read_strip_characters
        if @start_char
          data = data[1..-1]
        end
        data = data[0..-2]
      end

      if @read_enable_escaping
        data = data.gsub(@replace_end, @end_char).gsub(@replace_esc, @esc_char)
      end

      return data, extra
    end

    def write_data(data, extra = nil)
      # Intentionally not calling super()

      if @write_enable_escaping
        data = data.gsub(@esc_char, @replace_esc).gsub(@end_char, @replace_end)
      end

      if @start_char
        data = @start_char + data
      end

      data << @end_char

      return data, extra
    end

    def reduce_to_single_packet
      return :STOP if @data.length <= 0
      if @start_char
        index = @data[1..-1].index(@read_termination_characters)
        index = index + 1 if index
      else
        index = @data.index(@read_termination_characters)
      end

      # Reduce to packet data and setup current_data for next packet
      if index
        if index > 0
          packet_data = @data[0..(index + @read_termination_characters.length - 1)]
        else # @data begins with the termination characters
          packet_data = @data[0..(@read_termination_characters.length - 1)]
        end
        @data.replace(@data[(index + @read_termination_characters.length)..-1])
        return packet_data, @extra
      else
        return :STOP
      end
    end

    def write_details
      result = super()
      result['start_char'] = @start_char.inspect
      result['end_char'] = @end_char.inspect
      result['esc_char'] = @esc_char.inspect
      result['esc_end_char'] = @esc_end_char.inspect
      result['esc_esc_char'] = @esc_esc_char.inspect
      result['write_enable_escaping'] = @write_enable_escaping
      return result
    end

    def read_details
      result = super()
      result['start_char'] = @start_char.inspect
      result['end_char'] = @end_char.inspect
      result['esc_char'] = @esc_char.inspect
      result['esc_end_char'] = @esc_end_char.inspect
      result['esc_esc_char'] = @esc_esc_char.inspect
      result['read_strip_characters'] = @read_strip_characters
      result['read_enable_escaping'] = @read_enable_escaping
      return result
    end
  end

end
