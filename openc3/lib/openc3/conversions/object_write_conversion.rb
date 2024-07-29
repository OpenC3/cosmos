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

require 'openc3/conversions/object_read_conversion'

module OpenC3
  class ObjectWriteConversion < ObjectReadConversion
    # Perform the conversion on the value.
    #
    # @param value [Object] Hash of packet key/value pairs
    # @param packet [Packet] Unused
    # @param buffer [String] The packet buffer
    # @return Raw BLOCK data
    def call(value, _packet, buffer)
      if @cmd_or_tlm == :CMD
        fill_packet = System.commands.packet(@target_name, @packet_name)
      else
        fill_packet = System.telemetry.packet(@target_name, @packet_name)
      end
      fill_packet.restore_defaults()
      value.each do |key, write_value|
        fill_packet.write(key, write_value)
      end
      return fill_packet.buffer
    end

    # @param read_or_write [String] Not used
    # @return [String] Config fragment for this conversion
    def to_config(read_or_write)
      "    WRITE_CONVERSION #{self.class.name.class_name_to_filename} #{@cmd_or_tlm} #{@target_name} #{@packet_name}\n"
    end
  end
end
