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

require 'openc3'
require 'json'
require 'openc3/config/config_parser'

module OpenC3
  class JsonPacket
    attr_accessor :cmd_or_tlm
    attr_accessor :target_name
    attr_accessor :packet_name
    attr_accessor :packet_time
    attr_accessor :stored
    attr_accessor :json_hash

    def initialize(cmd_or_tlm, target_name, packet_name, time_nsec_from_epoch, stored, json_data, key_map = nil)
      @cmd_or_tlm = cmd_or_tlm.intern
      @target_name = target_name
      @packet_name = packet_name
      @packet_time = ::Time.from_nsec_from_epoch(time_nsec_from_epoch)
      @stored = ConfigParser.handle_true_false(stored)
      @json_hash = json_data
      @json_hash = JSON.parse(json_data, :allow_nan => true, :create_additions => true) if String === json_data
      if key_map
        uncompressed = {}
        @json_hash.each do |key, value|
          uncompressed_key = key_map[key]
          uncompressed_key = key unless uncompressed_key
          uncompressed[uncompressed_key] = value
        end
        @json_hash = uncompressed
      end
    end

    # Read an item in the packet by name
    #
    # @param name [String] Name of the item to read - Should already by upcase
    # @param value_type (see #read_item)
    def read(name, value_type = :CONVERTED, reduced_type = nil)
      if reduced_type
        raise "Reduced types only support RAW or CONVERTED value types: #{value_type} unsupported" if value_type == :WITH_UNITS or value_type == :FORMATTED
        if value_type == :CONVERTED
          case reduced_type
          when :AVG
            value = @json_hash["#{name}__CA"]
            return value if value
          when :STDDEV
            value = @json_hash["#{name}__CS"]
            return value if value
          when :MIN
            value = @json_hash["#{name}__CN"]
            return value if value
          when :MAX
            value = @json_hash["#{name}__CX"]
            return value if value
          end
        end
        case reduced_type
        when :AVG
          value = @json_hash["#{name}__A"]
          return value if value
        when :STDDEV
          value = @json_hash["#{name}__S"]
          return value if value
        when :MIN
          value = @json_hash["#{name}__N"]
          return value if value
        when :MAX
          value = @json_hash["#{name}__X"]
          return value if value
        end
      end
      if value_type == :WITH_UNITS
        value = @json_hash["#{name}__U"]
        return value if value
      end
      if value_type == :WITH_UNITS or value_type == :FORMATTED
        value = @json_hash["#{name}__F"]
        return value if value

        value = @json_hash["#{name}__C"]
        return value.to_s if value

        value = @json_hash[name]
        return value.to_s if value

        return nil
      end
      if value_type == :CONVERTED
        value = @json_hash["#{name}__C"]
        return value if value
      end
      value = @json_hash[name]
      return value if value
    end

    def read_with_limits_state(name, value_type = :CONVERTED, reduced_type = nil)
      value = read(name, value_type, reduced_type)
      limits_state = @json_hash["#{name}__L"]
      limits_state.intern if limits_state
      return [value, limits_state]
    end

    # Read all items in the packet into an array of arrays
    #   [[item name, item value], ...]
    #
    # @param value_type (see #read_item)
    def read_all(value_type = :CONVERTED, reduced_type = nil, names = nil)
      result = {}
      names = read_all_names() unless names
      names.each do |name|
        result[name] = read(name, value_type, reduced_type)
      end
      return result
    end

    # Read all items in the packet into an array of arrays
    #   [[item name, item value], [item limits state], ...]
    #
    # @param value_type (see #read_all)
    def read_all_with_limits_states(value_type = :CONVERTED, reduced_type = nil, names = nil)
      result = {}
      names = read_all_names() unless names
      names.each do |name|
        result[name] = read_with_limits_state(name, value_type, reduced_type)
      end
      return result
    end

    # Read all the names of items in the packet
    # Note: This is not very efficient, ideally only call once for discovery purposes
    def read_all_names(value_type = nil, reduced_type = nil)
      result = {}
      if value_type
        case value_type
        when :RAW
          postfix = ''
        when :CONVERTED
          postfix = 'C'
        when :FORMATTED
          postfix = 'F'
        when :WITH_UNITS
          postfix = 'U'
        end
        case reduced_type
        when :MIN
          postfix << 'N'
        when :MAX
          postfix << 'X'
        when :AVG
          postfix << 'A'
        when :STDDEV
          postfix << 'S'
        else
          postfix = nil if value_type == :RAW
        end
        @json_hash.each do |key, value|
          key_split = key.split("__")
          result[key_split[0]] = true if key_split[1] == postfix
        end
      else
        @json_hash.each { |key, value| result[key.split("__")[0]] = true }
      end
      return result.keys
    end

    # Create a string that shows the name and value of each item in the packet
    #
    # @param value_type (see #read_item)
    # @param indent (see Structure#formatted)
    def formatted(value_type = :CONVERTED, reduced_type = nil, names = nil, indent = 0)
      names = read_all_names() unless names
      indent_string = ' ' * indent
      string = ''
      names.each do |name|
        value = read(name, value_type, reduced_type)
        if String === value and value =~ File::NON_ASCII_PRINTABLE
          string << "#{indent_string}#{name}:\n"
          string << value.formatted(1, 16, ' ', indent + 2)
        else
          string << "#{indent_string}#{name}: #{value}\n"
        end
      end
      return string
    end
  end
end
