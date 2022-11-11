# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

module OpenC3
  class Accessor
    def read_item(item, buffer)
      raise "Must be defined by subclass"
    end

    def write_item(item, value, buffer)
      raise "Must be defined by subclass"
    end

    def self.read_items(items, buffer)
      result = {}
      items.each do |item|
        result[item.name] = read_item(item, buffer)
      end
      return result
    end

    def self.write_items(items, values, buffer)
      items.each_with_index do |item, index|
        write_item(item, values[index], buffer)
      end
      return buffer
    end

    def self.convert_to_type(value, item)
      data_type = item.data_type
      if (data_type == :STRING) || (data_type == :BLOCK)
        #######################################
        # Handle :STRING and :BLOCK data types
        #######################################
        value = value.to_s

      elsif (data_type == :INT) || (data_type == :UINT)
        ###################################
        # Handle :INT data type
        ###################################
        value = Integer(value)

      elsif data_type == :FLOAT
        ##########################
        # Handle :FLOAT data type
        ##########################
        value = Float(value)

      else
        ############################
        # Handle Unknown data types
        ############################

        raise(ArgumentError, "data_type #{data_type} is not recognized")
      end
      return value
    end
  end
end