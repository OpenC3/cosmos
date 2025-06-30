# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require 'openc3/packets/packet'

module OpenC3
  module CmdLog
    def _build_cmd_output_string(method_name, target_name, cmd_name, cmd_params, packet)
      output_string = "#{method_name}(\""
      output_string << (target_name + ' ' + cmd_name)
      if cmd_params.nil? or cmd_params.empty?
        output_string << '")'
      else
        params = []
        cmd_params.each do |key, value|
          next if Packet::RESERVED_ITEM_NAMES.include?(key)

          item = packet['items'].find { |find_item| find_item['name'] == key.to_s }
          begin
            item_type = item['data_type'].intern
          rescue
            item_type = nil
          end

          if (item and item['obfuscate'])
            params << "#{key} *****"
          else
            if value.is_a?(String)
              value = value.dup
              if item_type == :BLOCK or item_type == :STRING
                if !value.is_printable?
                  value = "0x" + value.simple_formatted
                else
                  value = value.inspect
                end
              else
                value = value.convert_to_value.to_s
              end
              if value.length > 256
                value = value[0..255] + "...'"
              end
              value.tr!('"', "'")
            elsif value.is_a?(Array)
              value = "[#{value.join(", ")}]"
            end
            params << "#{key} #{value}"
          end
        end
        params = params.join(", ")
        output_string << (' with ' + params + '")')
      end
      return output_string
    end
  end
end