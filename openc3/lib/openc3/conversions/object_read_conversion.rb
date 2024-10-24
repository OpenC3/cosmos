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

require 'openc3/config/config_parser'
require 'openc3/conversions/conversion'

module OpenC3
  class ObjectReadConversion < Conversion
    def initialize(cmd_or_tlm, target_name, packet_name)
      super()
      cmd_or_tlm = ConfigParser.handle_nil(cmd_or_tlm)
      if cmd_or_tlm
        @cmd_or_tlm = cmd_or_tlm.to_s.upcase.intern
        raise ArgumentError, "Unknown type: #{cmd_or_tlm}" unless %i(CMD TLM COMMAND TELEMETRY).include?(@cmd_or_tlm)
      else
        # Unknown - Will need to search
        @cmd_or_tlm = nil
      end
      @target_name = target_name.to_s.upcase
      @packet_name = packet_name.to_s.upcase
      @converted_type = :OBJECT
      @converted_bit_size = 0
      @params = [@cmd_or_tlm, @target_name, @packet_name]
    end

    def lookup_packet
      if @cmd_or_tlm
        if @cmd_or_tlm == :CMD or @cmd_or_tlm == :COMMAND
          return System.commands.packet(@target_name, @packet_name)
        else
          return System.telemetry.packet(@target_name, @packet_name)
        end
      else
        # Always searches commands first
        begin
          return System.commands.packet(@target_name, @packet_name)
        rescue
          return System.telemetry.packet(@target_name, @packet_name)
        end
      end
    end

    # Perform the conversion on the value.
    #
    # @param value [String] The BLOCK data to make into a packet
    # @param packet [Packet] Unused
    # @param buffer [String] The packet buffer
    # @return The converted value
    def call(value, _packet, buffer)
      fill_packet = lookup_packet()
      fill_packet.buffer = value
      return fill_packet.read_all(:CONVERTED, buffer, true).to_h
    end

    # @return [String] The conversion class
    def to_s
      "#{self.class.to_s.split('::')[-1]} #{@cmd_or_tlm ? @cmd_or_tlm : "nil"} #{@target_name} #{@packet_name}"
    end

    # @param read_or_write [String] Not used
    # @return [String] Config fragment for this conversion
    def to_config(read_or_write)
      "    #{read_or_write}_CONVERSION #{self.class.name.class_name_to_filename} #{@cmd_or_tlm ? @cmd_or_tlm : "nil"} #{@target_name} #{@packet_name}\n"
    end
  end
end
