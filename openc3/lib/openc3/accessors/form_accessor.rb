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

require 'openc3/accessors/accessor'
require 'uri'

module OpenC3
  class FormAccessor < Accessor
    def self.read_item(item, buffer)
      ary = URI.decode_www_form(buffer)
      value = nil
      ary.each do |key, ary_value|
        if key == item.key
          if value
            if not Array === value
              value_temp = []
              value_temp << value
              value = value_temp
            end
            value << ary_value
          else
            value = ary_value
          end
        end
      end
      return value
    end

    def self.write_item(item, value, buffer)
      ary = URI.decode_www_form(buffer)
      value = nil
      # Remove existing item from array
      ary.reject! {|key, ary_value| key == item.key}

      if Array === value
        value.each do |value_value|
          ary << [item.key, value_value]
        end
      else
        ary << [item.key, value]
      end

      buffer.replace(URI.encode_www_form(ary))
      return value
    end
  end
end
