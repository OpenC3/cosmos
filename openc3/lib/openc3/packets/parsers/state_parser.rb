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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/packets/packet_item'

module OpenC3
  class StateParser
    # @param parser [ConfigParser] Configuration parser
    # @param packet [Packet] The current packet
    # @param cmd_or_tlm [String] Whether this is a command or telemetry packet
    # @param item [PacketItem] The packet item to create states on
    # @param warnings [Array<String>] Array of string warnings which will be
    #   appended with any warnings found when parsing the limits
    def self.parse(parser, packet, cmd_or_tlm, item, warnings)
      raise parser.error("Items with LIMITS can't define STATE") if item.limits.values
      raise parser.error("Items with UNITS can't define STATE") if item.units

      parser = StateParser.new(parser)
      parser.verify_parameters(cmd_or_tlm)
      parser.create_state(packet, cmd_or_tlm, item, warnings)
    end

    # @param parser [ConfigParser] Configuration parser
    def initialize(parser)
      @parser = parser
    end

    # @param cmd_or_tlm [String] Whether this is a command or telemetry packet
    def verify_parameters(cmd_or_tlm)
      @usage = "STATE <STATE NAME> <STATE VALUE> "
      if cmd_or_tlm == PacketConfig::COMMAND
        @usage << "<HAZARDOUS / DISABLE_MESSAGES (Optional)> <Hazardous Description (Optional)>"
        @parser.verify_num_parameters(2, 4, @usage)
      else
        @usage << "<COLOR: GREEN/YELLOW/RED (Optional)>"
        @parser.verify_num_parameters(2, 3, @usage)
      end
    end

    # @param packet [Packet] The current packet
    # @param cmd_or_tlm [String] Whether this is a command or telemetry packet
    # @param item [PacketItem] The packet item to create states on
    # @param warnings [Array<String>] Array of string warnings which will be
    #   appended with any warnings found when parsing the limits
    def create_state(packet, cmd_or_tlm, item, warnings)
      item.states ||= {}

      state_name = get_state_name()
      check_for_duplicate_states(item, warnings)
      item.states[state_name] = get_state_value(item.data_type)
      parse_additional_parameters(packet, cmd_or_tlm, item)
    end

    private

    def get_state_name
      @parser.parameters[0].upcase
    end

    def get_state_value(data_type)
      if data_type == :STRING || data_type == :BLOCK
        @parser.parameters[1]
      else
        value = @parser.parameters[1].convert_to_value
        # Check if the value is a string, which indicates an error in parsing
        # except for 'ANY' which is a valid state value
        if value.is_a?(String) and value != "ANY"
          raise @parser.error("Invalid state value #{value} for data type #{data_type}.", @usage)
        end
        return value
      end
    end

    def check_for_duplicate_states(item, warnings)
      if item.states[get_state_name()]
        msg = "Duplicate state defined on line #{@parser.line_number}: #{@parser.line}"
        Logger.instance.warn(msg)
        warnings << msg
      end
    end

    def parse_additional_parameters(packet, cmd_or_tlm, item)
      return unless @parser.parameters.length > 2

      if cmd_or_tlm == PacketConfig::COMMAND
        get_hazardous_or_disable_messages(item)
      else
        get_state_colors(item)
        packet.update_limits_items_cache(item)
      end
    end

    def get_hazardous_or_disable_messages(item)
      case @parser.parameters[2].upcase
      when 'HAZARDOUS'
        item.hazardous ||= {}
        if @parser.parameters[3]
          item.hazardous[get_state_name()] = @parser.parameters[3]
        else
          item.hazardous[get_state_name()] = ""
        end
      when 'DISABLE_MESSAGES'
        item.messages_disabled ||= {}
        item.messages_disabled[get_state_name()] = true
      else
        raise @parser.error("HAZARDOUS or DISABLE_MESSAGES expected as third parameter for this line.", @usage)
      end
    end

    def get_state_colors(item)
      color = @parser.parameters[2].upcase.to_sym
      unless PacketItem::STATE_COLORS.include? color
        raise @parser.error("Invalid state color #{color}. Must be one of #{PacketItem::STATE_COLORS.join(' ')}.", @usage)
      end

      item.limits.enabled = true
      item.state_colors ||= {}
      item.state_colors[get_state_name()] = color
    end
  end
end
