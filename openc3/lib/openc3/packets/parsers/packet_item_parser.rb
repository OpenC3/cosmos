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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/packets/packet_item'

module OpenC3
  # Parses a packet item definition and creates a new PacketItem
  class PacketItemParser
    # This number is a little arbitrary but there are definitely issues at
    # 1 million and you really shouldn't be doing anything this big anyway
    BIG_ARRAY_SIZE = 100_000

    # @param parser [ConfigParser] Configuration parser
    # @param packet [Packet] The packet the item should be added to
    # @param cmd_or_tlm [String] Whether this is a command or telemetry packet
    # @param warnings [Array<String>] Array of warning strings from PacketConfig
    def self.parse(parser, packet_config, packet, cmd_or_tlm, warnings)
      parser = PacketItemParser.new(parser, packet_config, warnings)
      parser.verify_parameters(cmd_or_tlm)
      parser.create_packet_item(packet, cmd_or_tlm)
    end

    # @param parser [ConfigParser] Configuration parser
    # @param warnings [Array<String>] Array of warning strings from PacketConfig
    def initialize(parser, packet_config, warnings)
      @parser = parser
      @packet_config = packet_config
      @warnings = warnings
      @usage = get_usage()
    end

    def verify_parameters(cmd_or_tlm)
      if @parser.keyword.include?('ITEM') && cmd_or_tlm == PacketConfig::COMMAND
        raise @parser.error("ITEM types are only valid with TELEMETRY", @usage)
      elsif @parser.keyword.include?('PARAMETER') && cmd_or_tlm == PacketConfig::TELEMETRY
        raise @parser.error("PARAMETER types are only valid with COMMAND", @usage)
      end

      # The usage is formatted with brackets <XXX> around each option so
      # count the number of open brackets to determine the number of options
      max_options = @usage.count("<")
      if @parser.keyword.include?('STRUCTURE')
        @parser.verify_num_parameters(max_options, max_options, @usage)
      else
        # The last two options (description and endianness) are optional
        @parser.verify_num_parameters(max_options - 2, max_options, @usage)
      end
      @parser.verify_parameter_naming(1) # Item name is the 1st parameter
    end

    def create_packet_item(packet, cmd_or_tlm)
      item_name = @parser.parameters[0].upcase
      if packet.items[item_name]
        msg = "#{packet.target_name} #{packet.packet_name} #{item_name} redefined."
        Logger.instance.warn msg
        @warnings << msg
      end
      if @parser.keyword.include?("STRUCTURE")
        item = PacketItem.new(item_name,
                              get_bit_offset(),
                              get_bit_size(true),
                              :BLOCK,
                              :BIG_ENDIAN,
                              nil,
                              :ERROR) # overflow
      else
        item = PacketItem.new(item_name,
                              get_bit_offset(),
                              get_bit_size(),
                              get_data_type(),
                              get_endianness(packet),
                              get_array_size(),
                              :ERROR) # overflow
        if cmd_or_tlm == PacketConfig::COMMAND
          item.range = get_range()
          item.default = get_default()
        end
        item.id_value = get_id_value(item)
        item.description = get_description()
      end
      if append?
        item = packet.append(item)
      else
        item = packet.define(item)
      end
      if @parser.keyword.include?("STRUCTURE")
        structure = lookup_packet(get_cmd_or_tlm(), get_target_name(), get_packet_name())
        packet.structurize_item(item, structure)
      end
      item
    end

    private

    def append?
      @parser.keyword.include?("APPEND")
    end

    def get_data_type
      index = append? ? 2 : 3
      @parser.parameters[index].upcase.to_sym
    end

    def get_bit_offset
      return 0 if append?
      Integer(@parser.parameters[1])
    rescue => e
      raise @parser.error(e, @usage)
    end

    def get_bit_size(check_structure = false)
      index = append? ? 1 : 2
      bit_size = @parser.parameters[index]
      if not check_structure or bit_size.to_s.upcase != 'DEFINED'
        return Integer(bit_size)
      else
        structure = lookup_packet(get_cmd_or_tlm(), get_target_name(), get_packet_name())
        return structure.defined_length_bits
      end
    rescue => e
      raise @parser.error(e, @usage)
    end

    def get_array_size
      return nil unless @parser.keyword.include?('ARRAY')

      index = append? ? 3 : 4
      array_bit_size = Integer(@parser.parameters[index])
      items = array_bit_size / get_bit_size()
      if items >= BIG_ARRAY_SIZE
        warning = "Performance Issue!\n"\
                  "In #{@parser.filename}:#{@parser.line_number} your definition of:\n"\
                  "#{@parser.line}\n"\
                  "creates an array with #{items} elements. Consider creating a BLOCK if this is binary data."
        Logger.warn(warning)
        @warnings << warning
      end
      array_bit_size
    rescue => e
      raise @parser.error(e, @usage)
    end

    def get_endianness(packet)
      params = @parser.parameters
      max_options = @usage.count("<")
      if params[max_options - 1]
        endianness = params[max_options - 1].to_s.upcase.intern
        if endianness != :BIG_ENDIAN and endianness != :LITTLE_ENDIAN
          raise @parser.error("Invalid endianness #{endianness}. Must be BIG_ENDIAN or LITTLE_ENDIAN.", @usage)
        end
      else
        endianness = packet.default_endianness
      end
      endianness
    end

    def get_range
      return nil if @parser.keyword.include?('ARRAY')

      data_type = get_data_type()
      return nil unless data_type == :INT or data_type == :UINT or data_type == :FLOAT

      index = append? ? 3 : 4
      return nil if @parser.parameters[index] == 'nil'
      min = ConfigParser.handle_defined_constants(
        @parser.parameters[index].convert_to_value, get_data_type(), get_bit_size()
      )
      max = ConfigParser.handle_defined_constants(
        @parser.parameters[index + 1].convert_to_value, get_data_type(), get_bit_size()
      )
      min..max
    end

    def get_cmd_or_tlm
      index = append? ? 2 : 3
      cmd_or_tlm = @parser.parameters[index].to_s.upcase.intern
      raise ArgumentError, "Unknown type: #{cmd_or_tlm}" unless %i(CMD TLM COMMAND TELEMETRY).include?(cmd_or_tlm)
      cmd_or_tlm
    end

    def get_target_name
      index = append? ? 3 : 4
      @parser.parameters[index].to_s.upcase
    end

    def get_packet_name
      index = append? ? 4 : 5
      @parser.parameters[index].to_s.upcase
    end

    def lookup_packet(cmd_or_tlm, target_name, packet_name)
      if cmd_or_tlm == :CMD or cmd_or_tlm == :COMMAND
        return @packet_config.commands[target_name][packet_name]
      else
        return @packet_config.telemetry[target_name][packet_name]
      end
    end

    def convert_string_value(index)
      # If the default value is 0x<data> (no quotes), it is treated as
      # binary data.  Otherwise, the default value is considered to be a string.
      if @parser.parameters[index].upcase.start_with?("0X") and
        !@parser.line.include?("\"#{@parser.parameters[index]}\"") and
        !@parser.line.include?("\'#{@parser.parameters[index]}\'")
        return @parser.parameters[index].hex_to_byte_string
      else
        return @parser.parameters[index]
      end
    end

    def get_default
      return [] if @parser.keyword.include?('ARRAY')

      index = append? ? 3 : 4
      data_type = get_data_type()
      if data_type == :BOOL
        value = @parser.parameters[index].to_s.upcase
        if value == "TRUE" or value == "FALSE"
          return ConfigParser.handle_true_false(@parser.parameters[index])
        else
          raise @parser.error("Default for BOOL data type must be TRUE or FALSE")
        end
      end
      if data_type == :ARRAY
        value = @parser.parameters[index].to_s
        begin
          value = JSON.parse(value, allow_nan: true)
        rescue Exception
          raise @parser.error("Unparsable value for ARRAY: #{value}")
        end
        if Array === value
          return value
        else
          raise @parser.error("Default for ARRAY data type must be an Array")
        end
      end
      if data_type == :OBJECT
        value = @parser.parameters[index].to_s
        begin
          value = JSON.parse(value, allow_nan: true)
        rescue Exception
          raise @parser.error("Unparsable value for OBJECT: #{value}")
        end
        if Hash === value
          return value
        else
          raise @parser.error("Default for OBJECT data type must be a Hash")
        end
      end
      if data_type == :ANY
        value = @parser.parameters[index].to_s
        if value.length > 0
          begin
            return JSON.parse(value, allow_nan: true)
          rescue Exception
            return value
          end
        else
          return ""
        end
      end
      if data_type == :STRING or data_type == :BLOCK
        return convert_string_value(index)
      else
        if data_type != :DERIVED
          return ConfigParser.handle_defined_constants(
            @parser.parameters[index + 2].convert_to_value, data_type, get_bit_size()
          )
        else
          return @parser.parameters[index + 2].convert_to_value
        end
      end
    end

    def get_id_value(item)
      return nil unless @parser.keyword.include?('ID_')
      data_type = get_data_type
      if data_type == :DERIVED
        raise @parser.error("DERIVED data type not allowed for Identifier")
      end
      # For PARAMETERS the default value is the ID value
      if @parser.keyword.include?("PARAMETER")
        return item.default
      end

      index = append? ? 3 : 4
      if data_type == :BOOL
        value = @parser.parameters[index].to_s.upcase
        if value == "TRUE" or value == "FALSE"
          return ConfigParser.handle_true_false(@parser.parameters[index])
        else
          raise @parser.error("ID Value for BOOL data type must be TRUE or FALSE")
        end
      end
      if data_type == :ARRAY
        value = @parser.parameters[index].to_s
        begin
          value = JSON.parse(value, allow_nan: true)
        rescue Exception
          raise @parser.error("Unparsable value for ARRAY: #{value}")
        end
        if Array === value
          return value
        else
          raise @parser.error("ID Value for ARRAY data type must be an Array")
        end
      end
      if data_type == :OBJECT
        value = @parser.parameters[index].to_s
        begin
          value = JSON.parse(value, allow_nan: true)
        rescue Exception
          raise @parser.error("Unparsable value for OBJECT: #{value}")
        end
        if Hash === value
          return value
        else
          raise @parser.error("ID Value for OBJECT data type must be a Hash")
        end
      end
      if data_type == :ANY
        value = @parser.parameters[index].to_s
        if value.length > 0
          begin
            return JSON.parse(value, allow_nan: true)
          rescue Exception
            return value
          end
        else
          return ""
        end
      end
      if data_type == :STRING or data_type == :BLOCK
        return convert_string_value(index)
      else
        return ConfigParser.handle_defined_constants(
          @parser.parameters[index].convert_to_value, data_type, get_bit_size()
        )
      end
    end

    def get_description
      max_options = @usage.count("<")
      @parser.parameters[max_options - 2] if @parser.parameters[max_options - 2]
    end

    # There are many different usages of the ITEM and PARAMETER keywords so
    # parse the keyword and parameters to generate the correct usage information.
    def get_usage
      usage = "#{@parser.keyword} <ITEM NAME> "
      usage << "<BIT OFFSET> " unless @parser.keyword.include?("APPEND")
      usage << bit_size_usage()
      if not @parser.keyword.include?("STRUCTURE")
        usage << type_usage()
        usage << "<TOTAL ARRAY BIT SIZE> " if @parser.keyword.include?("ARRAY")
        usage << id_usage()
        usage << "<DESCRIPTION (Optional)> <ENDIANNESS (Optional)>"
      else
        usage << "<CMD or TLM> <Target Name> <Packet Name>"
      end
      usage
    end

    def bit_size_usage
      if @parser.keyword.include?("ARRAY")
        "<ARRAY ITEM BIT SIZE> "
      else
        "<BIT SIZE> "
      end
    end

    def type_usage
      keyword = @parser.keyword
      # Item type usage is simple so just return it
      return "<TYPE: INT/UINT/FLOAT/STRING/BLOCK/DERIVED/BOOL/ARRAY/OBJECT/ANY> " if keyword.include?("ITEM")

      # Build up the parameter type usage based on the keyword
      usage = "<TYPE: "
      # ARRAY types don't have min or max or default values
      if keyword.include?("ARRAY")
        usage << "INT/UINT/FLOAT/STRING/BLOCK/BOOL/OBJECT/ANY> "
      else
        begin
          data_type = get_data_type()
        rescue
          # If the data type could not be determined set something
          data_type = :INT
        end
        if data_type == :INT || data_type == :UINT || data_type == :FLOAT || data_type == :DERIVED
          usage << "INT/UINT/FLOAT/DERIVED> <MIN VALUE> <MAX VALUE> "
        else
          usage << "STRING/BLOCK/BOOL/ARRAY/OBJECT/ANY> "
        end
        # ID Values do not have default values
        unless keyword.include?("ID")
          usage << "<DEFAULT_VALUE> "
        end
      end
      usage
    end

    def id_usage
      return '' unless @parser.keyword.include?("ID")

      if @parser.keyword.include?("PARAMETER")
        "<DEFAULT AND ID VALUE> "
      else
        "<ID VALUE> "
      end
    end
  end
end
