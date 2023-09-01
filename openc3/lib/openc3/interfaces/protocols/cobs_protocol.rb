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

# This file implements the COBS protocol as here:
# https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing
# http://www.stuartcheshire.org/papers/COBSforToN.pdf

# COBS is a framing protocol and is therefore expected to be used for packet deliniation

module OpenC3

  # Usage in plugin.txt:
  #
  # INTERFACE ...
  #   PROTOCOL READ_WRITE CobsProtocol

  class CobsProtocol < TerminatedProtocol

    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def initialize(allow_empty_data = nil)

      strip_read_termination = true
      discard_leading_bytes = 0
      sync_pattern = nil
      fill_fields = false # Handled in write_data below

      super(
        "", # Write termination handled in write_data below
        "00",
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

      result_data = ''
      while data.length > 1
        # Read the offset to the next zero byte
        # Note: This may be off the end of the data. If so, the packet is over
        zero_offset = data[0].unpack('C')[0]
        if zero_offset == 0xFF # No zeros in this segment
          result_data << data[1..254]
          data = data[255..-1]
        elsif zero_offset <= 1 # End of data or 1 zero
          result_data << "\x00"
          data = data[1..-1]
        else # Mid range zero or end of packet
          result_data << data[1..(zero_offset - 1)]
          data = data[zero_offset..-1]
          result_data << "\x00" if data.length >= 1
        end
      end

      return result_data, extra
    end

    def write_data(data, extra = nil)
      # Intentionally not calling super()

      need_insert = false
      result_data = ''
      while data.length > 0
        index = data.index("\x00")
        if (index and index > 253) or (index.nil? and data.length >= 254)
          result_data << "\xFF"
          result_data << data[0..253]
          data = data[254..-1]
          need_insert = false
        else # index <= 253 or (index.nil? and data.length < 254)
          if index
            result_data << [index + 1].pack('C')
            if index >= 1
              result_data << data[0..(index - 1)]
            end
            data = data[(index + 1)..-1]
            need_insert = true
          else
            result_data << [data.length + 1].pack('C')
            result_data << data
            data = ''
            need_insert = false
          end
        end
      end

      # Handle a zero at the end of the packet
      result_data << "\x01" if need_insert

      # Terminate message with 0x00
      result_data << "\x00"

      return result_data, extra
    end
  end

end
