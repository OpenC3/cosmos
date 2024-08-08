# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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

require 'openc3/conversions/conversion'

module OpenC3
  class ObjectReadConversion < Conversion
    def initialize(cmd_or_tlm, target_name, packet_name)
      super()
      @cmd_or_tlm = cmd_or_tlm.to_s.upcase.intern
      raise ArgumentError, "Unknown type: #{cmd_or_tlm}" unless %i(CMD TLM).include?(@cmd_or_tlm)
      @target_name = target_name.to_s.upcase
      @packet_name = packet_name.to_s.upcase
      @converted_type = :OBJECT
      @converted_bit_size = 0
    end

    # Perform the conversion on the value.
    #
    # @param value [String] The BLOCK data to make into a packet
    # @param packet [Packet] Unused
    # @param buffer [String] The packet buffer
    # @return The converted value
    def call(value, _packet, buffer)
      if @cmd_or_tlm == :CMD
        fill_packet = System.commands.packet(@target_name, @packet_name)
      else
        fill_packet = System.telemetry.packet(@target_name, @packet_name)
      end
      fill_packet.buffer = value
      return fill_packet.read_all(:CONVERTED, buffer, true).to_h
    end

    # @return [String] The conversion class
    def to_s
      "#{self.class.to_s.split('::')[-1]} #{@cmd_or_tlm} #{@target_name} #{@packet_name}"
    end

    # @param read_or_write [String] Not used
    # @return [String] Config fragment for this conversion
    def to_config(read_or_write)
      "    READ_CONVERSION #{self.class.name.class_name_to_filename} #{@cmd_or_tlm} #{@target_name} #{@packet_name}\n"
    end

    def as_json(*a)
      result = super(*a)
      result['cmd_or_tlm'] = @cmd_or_tlm
      result['target_name'] = @target_name
      result['packet_name'] = @packet_name
      return result
    end
  end
end
