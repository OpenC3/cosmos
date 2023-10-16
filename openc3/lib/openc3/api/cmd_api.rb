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

require 'openc3/models/target_model'
require 'openc3/topics/command_topic'
require 'openc3/topics/command_decom_topic'
require 'openc3/topics/decom_interface_topic'
require 'openc3/topics/interface_topic'
require 'openc3/script/extract'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
                       'cmd',
                       'cmd_no_range_check',
                       'cmd_no_hazardous_check',
                       'cmd_no_checks',
                       'cmd_raw',
                       'cmd_raw_no_range_check',
                       'cmd_raw_no_hazardous_check',
                       'cmd_raw_no_checks',
                       'build_command',
                       'send_raw',
                       'get_all_commands',
                       'get_all_command_names',
                       'get_command',
                       'get_parameter',
                       'get_cmd_buffer',
                       'get_cmd_hazardous',
                       'get_cmd_value',
                       'get_cmd_time',
                       'get_cmd_cnt',
                       'get_cmd_cnts',
                     ])

    # The following methods send a command packet to a target. The 'raw' version of the equivalent
    # command methods do not perform command parameter conversions.
    #
    # Accepts two different calling styles:
    #   cmd("TGT CMD with PARAM1 val, PARAM2 val")
    #   cmd('TGT','CMD','PARAM1'=>val,'PARAM2'=>val)
    #
    # Favor the first syntax where possible as it is more succinct.
    def cmd(*args, **kwargs)
      cmd_implementation('cmd', *args, range_check: true, hazardous_check: true, raw: false, **kwargs)
    end
    def cmd_raw(*args, **kwargs)
      cmd_implementation('cmd_raw', *args, range_check: true, hazardous_check: true, raw: true, **kwargs)
    end

    # Send a command packet to a target without performing any value range
    # checks on the parameters. Useful for testing to allow sending command
    # parameters outside the allowable range as defined in the configuration.
    def cmd_no_range_check(*args, **kwargs)
      cmd_implementation('cmd_no_range_check', *args, range_check: false, hazardous_check: true, raw: false, **kwargs)
    end
    def cmd_raw_no_range_check(*args, **kwargs)
      cmd_implementation('cmd_raw_no_range_check', *args, range_check: false, hazardous_check: true, raw: true, **kwargs)
    end

    # Send a command packet to a target without performing any hazardous checks
    # both on the command itself and its parameters. Useful in scripts to
    # prevent popping up warnings to the user.
    def cmd_no_hazardous_check(*args, **kwargs)
      cmd_implementation('cmd_no_hazardous_check', *args, range_check: true, hazardous_check: false, raw: false, **kwargs)
    end
    def cmd_raw_no_hazardous_check(*args, **kwargs)
      cmd_implementation('cmd_raw_no_hazardous_check', *args, range_check: true, hazardous_check: false, raw: true, **kwargs)
    end

    # Send a command packet to a target without performing any value range
    # checks or hazardous checks both on the command itself and its parameters.
    def cmd_no_checks(*args, **kwargs)
      cmd_implementation('cmd_no_checks', *args, range_check: false, hazardous_check: false, raw: false, **kwargs)
    end
    def cmd_raw_no_checks(*args, **kwargs)
      cmd_implementation('cmd_raw_no_checks', *args, range_check: false, hazardous_check: false, raw: true, **kwargs)
    end

    # Build a command binary
    #
    # @since 5.8.0
    def build_command(*args, range_check: true, raw: false, scope: $openc3_scope, token: $openc3_token, **kwargs)
      extract_string_kwargs_to_args(args, kwargs)
      case args.length
      when 1
        target_name, cmd_name, cmd_params = extract_fields_from_cmd_text(args[0], scope: scope)
      when 2, 3
        target_name  = args[0]
        cmd_name     = args[1]
        if args.length == 2
          cmd_params = {}
        else
          cmd_params = args[2]
        end
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to build_command()"
      end
      target_name = target_name.upcase
      cmd_name = cmd_name.upcase
      cmd_params = cmd_params.transform_keys(&:upcase)
      authorize(permission: 'cmd_info', target_name: target_name, scope: scope, token: token)
      DecomInterfaceTopic.build_cmd(target_name, cmd_name, cmd_params, range_check, raw, scope: scope)
    end

    # Send a raw binary string to the specified interface.
    #
    # @param interface_name [String] The interface to send the raw binary
    # @param data [String] The raw binary data
    def send_raw(interface_name, data, scope: $openc3_scope, token: $openc3_token)
      interface_name = interface_name.upcase
      authorize(permission: 'cmd_raw', interface_name: interface_name, scope: scope, token: token)
      get_interface(interface_name, scope: scope, token: token) # Check to make sure the interface exists
      InterfaceTopic.write_raw(interface_name, data, scope: scope)
    end

    # Returns the raw buffer from the most recent specified command packet.
    #
    # @param target_name [String] Target name of the command
    # @param command_name [String] Packet name of the command
    # @return [Hash] command hash with last command buffer
    def get_cmd_buffer(target_name, command_name, scope: $openc3_scope, token: $openc3_token)
      target_name = target_name.upcase
      command_name = command_name.upcase
      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, scope: scope, token: token)
      TargetModel.packet(target_name, command_name, type: :CMD, scope: scope)
      topic = "#{scope}__COMMAND__{#{target_name}}__#{command_name}"
      msg_id, msg_hash = Topic.get_newest_message(topic)
      if msg_id
        msg_hash['buffer'] = msg_hash['buffer'].b
        return msg_hash
      end
      return nil
    end

    # Returns an array of all the commands as a hash
    #
    # @since 5.0.0
    # @param target_name [String] Name of the target
    # @return [Array<Hash>] Array of all commands as a hash
    def get_all_commands(target_name, scope: $openc3_scope, token: $openc3_token)
      target_name = target_name.upcase
      authorize(permission: 'cmd_info', target_name: target_name, scope: scope, token: token)
      TargetModel.packets(target_name, type: :CMD, scope: scope)
    end

    # Returns an array of all the command packet names
    #
    # @since 5.0.6
    # @param target_name [String] Name of the target
    # @return [Array<String>] Array of all command packet names
    def get_all_command_names(target_name, scope: $openc3_scope, token: $openc3_token)
      target_name = target_name.upcase
      authorize(permission: 'cmd_info', target_name: target_name, scope: scope, token: token)
      TargetModel.packet_names(target_name, type: :CMD, scope: scope)
    end

    # Returns a hash of the given command
    #
    # @since 5.0.0
    # @param target_name [String] Name of the target
    # @param command_name [String] Name of the packet
    # @return [Hash] Command as a hash
    def get_command(target_name, command_name, scope: $openc3_scope, token: $openc3_token)
      target_name = target_name.upcase
      command_name = command_name.upcase
      authorize(permission: 'cmd_info', target_name: target_name, scope: scope, token: token)
      TargetModel.packet(target_name, command_name, type: :CMD, scope: scope)
    end

    # Returns a hash of the given command parameter
    #
    # @since 5.0.0
    # @param target_name [String] Name of the target
    # @param command_name [String] Name of the packet
    # @param parameter_name [String] Name of the parameter
    # @return [Hash] Command parameter as a hash
    def get_parameter(target_name, command_name, parameter_name, scope: $openc3_scope, token: $openc3_token)
      target_name = target_name.upcase
      command_name = command_name.upcase
      parameter_name = parameter_name.upcase
      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, scope: scope, token: token)
      TargetModel.packet_item(target_name, command_name, parameter_name, type: :CMD, scope: scope)
    end

    # Returns whether the specified command is hazardous
    #
    # Accepts two different calling styles:
    #   get_cmd_hazardous("TGT CMD with PARAM1 val, PARAM2 val")
    #   get_cmd_hazardous('TGT','CMD',{'PARAM1'=>val,'PARAM2'=>val})
    #
    # @param args [String|Array<String>] See the description for calling style
    # @return [Boolean] Whether the command is hazardous
    def get_cmd_hazardous(*args, scope: $openc3_scope, token: $openc3_token, **kwargs)
      extract_string_kwargs_to_args(args, kwargs)
      case args.length
      when 1
        target_name, command_name, parameters = extract_fields_from_cmd_text(args[0], scope: scope)
      when 2, 3
        target_name = args[0]
        command_name = args[1]
        if args.length == 2
          parameters = {}
        else
          parameters = args[2]
        end
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to get_cmd_hazardous()"
      end
      target_name = target_name.upcase
      command_name = command_name.upcase
      parameters = parameters.transform_keys(&:upcase)

      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, scope: scope, token: token)
      packet = TargetModel.packet(target_name, command_name, type: :CMD, scope: scope)
      return true if packet['hazardous']

      packet['items'].each do |item|
        next unless parameters.keys.include?(item['name']) && item['states']

        # States are an array of the name followed by a hash of 'value' and sometimes 'hazardous'
        item['states'].each do |name, hash|
          parameter_name = parameters[item['name']]
          # Remove quotes from string parameters
          parameter_name = parameter_name.gsub('"', '').gsub("'", '') if parameter_name.is_a?(String)
          # To be hazardous the state must be marked hazardous
          # Check if either the state name or value matches the param passed
          if hash['hazardous'] && (name == parameter_name || hash['value'] == parameter_name)
            return true
          end
        end
      end

      false
    end

    # Returns a value from the specified command
    #
    # @param target_name [String] Target name of the command
    # @param command_name [String] Packet name of the command
    # @param parameter_name [String] Parameter name in the command
    # @param value_type [Symbol] How the values should be converted. Must be
    #   one of {Packet::VALUE_TYPES}
    # @return [Varies] value
    def get_cmd_value(target_name, command_name, parameter_name, value_type = :CONVERTED, scope: $openc3_scope, token: $openc3_token)
      target_name = target_name.upcase
      command_name = command_name.upcase
      parameter_name = parameter_name.upcase
      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, scope: scope, token: token)
      CommandDecomTopic.get_cmd_item(target_name, command_name, parameter_name, type: value_type, scope: scope)
    end

    # Returns the time the most recent command was sent
    #
    # @param target_name [String] Target name of the command. If not given then
    #    the most recent time from all commands will be returned
    # @param command_name [String] Packet name of the command. If not given then
    #    then most recent time from the given target will be returned.
    # @return [Array<Target Name, Command Name, Time Seconds, Time Microseconds>]
    def get_cmd_time(target_name = nil, command_name = nil, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, scope: scope, token: token)
      if target_name and command_name
        target_name = target_name.upcase
        command_name = command_name.upcase
        time = CommandDecomTopic.get_cmd_item(target_name, command_name, 'RECEIVED_TIMESECONDS', type: :CONVERTED, scope: scope)
        return [target_name, command_name, time.to_i, ((time.to_f - time.to_i) * 1_000_000).to_i]
      else
        if target_name.nil?
          targets = TargetModel.names(scope: scope)
        else
          target_name = target_name.upcase
          targets = [target_name]
        end
        time = 0
        command_name = nil
        targets.each do |cur_target|
          TargetModel.packets(cur_target, type: :CMD, scope: scope).each do |packet|
            cur_time = CommandDecomTopic.get_cmd_item(cur_target, packet["packet_name"], 'RECEIVED_TIMESECONDS', type: :CONVERTED, scope: scope)
            next unless cur_time

            if cur_time > time
              time = cur_time
              command_name = packet["packet_name"]
              target_name = cur_target
            end
          end
        end
        target_name = nil unless command_name
        return [target_name, command_name, time.to_i, ((time.to_f - time.to_i) * 1_000_000).to_i]
      end
    end

    # Get the transmit count for a command packet
    #
    # @param target_name [String] Target name of the command
    # @param command_name [String] Packet name of the command
    # @return [Numeric] Transmit count for the command
    def get_cmd_cnt(target_name, command_name, scope: $openc3_scope, token: $openc3_token)
      target_name = target_name.upcase
      command_name = command_name.upcase
      authorize(permission: 'system', target_name: target_name, packet_name: command_name, scope: scope, token: token)
      TargetModel.packet(target_name, command_name, type: :CMD, scope: scope)
      Topic.get_cnt("#{scope}__COMMAND__{#{target_name}}__#{command_name}")
    end

    # Get the transmit counts for command packets
    #
    # @param target_commands [Array<Array<String, String>>] Array of arrays containing target_name, packet_name
    # @return [Numeric] Transmit count for the command
    def get_cmd_cnts(target_commands, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      unless target_commands.is_a?(Array) and target_commands[0].is_a?(Array)
        raise "get_cmd_cnts takes an array of arrays containing target, packet_name, e.g. [['INST', 'COLLECT'], ['INST', 'ABORT']]"
      end
      counts = []
      target_commands.each do |target_name, command_name|
        target_name = target_name.upcase
        command_name = command_name.upcase
        counts << Topic.get_cnt("#{scope}__COMMAND__{#{target_name}}__#{command_name}")
      end
      counts
    end

    ###########################################################################
    # PRIVATE implementation details
    ###########################################################################

    def cmd_implementation(method_name, *args, range_check:, hazardous_check:, raw:, timeout: nil, log_message: nil,
                           scope: $openc3_scope, token: $openc3_token, **kwargs)
      extract_string_kwargs_to_args(args, kwargs)
      unless [nil, true, false].include?(log_message)
        raise "Invalid log_message parameter: #{log_message}. Must be true or false."
      end
      unless timeout.nil?
        begin
          Float(timeout)
        rescue ArgumentError, TypeError
          raise "Invalid timeout parameter: #{timeout}. Must be numeric."
        end
      end

      case args.length
      when 1
        target_name, cmd_name, cmd_params = extract_fields_from_cmd_text(args[0], scope: scope)
      when 2, 3
        target_name  = args[0]
        cmd_name     = args[1]
        if args.length == 2
          cmd_params = {}
        else
          cmd_params = args[2]
        end
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to #{method_name}()"
      end
      target_name = target_name.upcase
      cmd_name = cmd_name.upcase
      cmd_params = cmd_params.transform_keys(&:upcase)
      authorize(permission: 'cmd', target_name: target_name, packet_name: cmd_name, scope: scope, token: token)
      packet = TargetModel.packet(target_name, cmd_name, type: :CMD, scope: scope)

      command = {
        'target_name' => target_name,
        'cmd_name' => cmd_name,
        'cmd_params' => cmd_params,
        'range_check' => range_check.to_s,
        'hazardous_check' => hazardous_check.to_s,
        'raw' => raw.to_s
      }
      if log_message.nil? # This means the default was used, no argument was passed
        log_message = true # Default is true
        # If the packet has the DISABLE_MESSAGES keyword then no messages by default
        log_message = false if packet["messages_disabled"]
        # Check if any of the parameters have DISABLE_MESSAGES
        cmd_params.each do |key, value|
          item = packet['items'].find { |item| item['name'] == key.to_s }
          if item && item['states'] && item['states'][value] && item['states'][value]["messages_disabled"]
            log_message = false
          end
        end
      end
      if log_message
        Logger.info(build_cmd_output_string(method_name, target_name, cmd_name, cmd_params, packet), scope: scope)
      end
      CommandTopic.send_command(command, timeout: timeout, scope: scope)
    end

    def build_cmd_output_string(method_name, target_name, cmd_name, cmd_params, packet)
      output_string = "#{method_name}(\""
      output_string << target_name + ' ' + cmd_name
      if cmd_params.nil? or cmd_params.empty?
        output_string << '")'
      else
        params = []
        cmd_params.each do |key, value|
          next if Packet::RESERVED_ITEM_NAMES.include?(key)

          item = packet['items'].find { |item| item['name'] == key.to_s }

          begin
            item_type = item['data_type'].intern
          rescue
            item_type = nil
          end

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
        params = params.join(", ")
        output_string << ' with ' + params + '")'
      end
      return output_string
    end
  end
end
