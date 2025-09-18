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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963

require 'openc3/api/interface_api'
require 'openc3/models/queue_model'
require 'openc3/models/target_model'
require 'openc3/topics/command_topic'
require 'openc3/topics/command_decom_topic'
require 'openc3/topics/decom_interface_topic'
require 'openc3/topics/interface_topic'
require 'openc3/script/extract'
require 'openc3/utilities/cmd_log'

module OpenC3
  module Api
    include OpenC3::CmdLog
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
                       'build_cmd',
                       'build_command', # DEPRECATED
                       'enable_cmd',
                       'disable_cmd',
                       'send_raw',
                       'get_all_cmds',
                       'get_all_commands', # DEPRECATED
                       'get_all_cmd_names',
                       'get_all_command_names', # DEPRECATED
                       'get_cmd',
                       'get_command', # DEPRECATED
                       'get_param',
                       'get_parameter', # DEPRECATED
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
      _cmd_implementation('cmd', *args, range_check: true, hazardous_check: true, raw: false, **kwargs)
    end
    def cmd_raw(*args, **kwargs)
      _cmd_implementation('cmd_raw', *args, range_check: true, hazardous_check: true, raw: true, **kwargs)
    end

    # Send a command packet to a target without performing any value range
    # checks on the parameters. Useful for testing to allow sending command
    # parameters outside the allowable range as defined in the configuration.
    def cmd_no_range_check(*args, **kwargs)
      _cmd_implementation('cmd_no_range_check', *args, range_check: false, hazardous_check: true, raw: false, **kwargs)
    end
    def cmd_raw_no_range_check(*args, **kwargs)
      _cmd_implementation('cmd_raw_no_range_check', *args, range_check: false, hazardous_check: true, raw: true, **kwargs)
    end

    # Send a command packet to a target without performing any hazardous checks
    # both on the command itself and its parameters. Useful in scripts to
    # prevent popping up warnings to the user.
    def cmd_no_hazardous_check(*args, **kwargs)
      _cmd_implementation('cmd_no_hazardous_check', *args, range_check: true, hazardous_check: false, raw: false, **kwargs)
    end
    def cmd_raw_no_hazardous_check(*args, **kwargs)
      _cmd_implementation('cmd_raw_no_hazardous_check', *args, range_check: true, hazardous_check: false, raw: true, **kwargs)
    end

    # Send a command packet to a target without performing any value range
    # checks or hazardous checks both on the command itself and its parameters.
    def cmd_no_checks(*args, **kwargs)
      _cmd_implementation('cmd_no_checks', *args, range_check: false, hazardous_check: false, raw: false, **kwargs)
    end
    def cmd_raw_no_checks(*args, **kwargs)
      _cmd_implementation('cmd_raw_no_checks', *args, range_check: false, hazardous_check: false, raw: true, **kwargs)
    end

    # Build a command binary
    #
    # @since 5.8.0
    def build_cmd(*args, range_check: true, raw: false, manual: false, timeout: 5, scope: $openc3_scope, token: $openc3_token, **kwargs)
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
      authorize(permission: 'cmd_info', target_name: target_name, manual: manual, scope: scope, token: token)
      DecomInterfaceTopic.build_cmd(target_name, cmd_name, cmd_params, range_check, raw, timeout: timeout, scope: scope)
    end
    # build_command is DEPRECATED
    alias build_command build_cmd

    # Helper method for disable_cmd / enable_cmd
    def _get_and_set_cmd(method, *args, manual:, scope:, token:)
      target_name, command_name = _extract_target_command_names(method, *args)
      authorize(permission: 'admin', target_name: target_name, packet_name: command_name, manual: manual, scope: scope, token: token)
      command = yield TargetModel.packet(target_name, command_name, type: :CMD, scope: scope)
      TargetModel.set_packet(target_name, command_name, command, type: :CMD, scope: scope)
    end

    # @since 5.15.1
    def enable_cmd(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      _get_and_set_cmd('enable_cmd', *args, manual: manual, scope: scope, token: token) do |command|
        command['disabled'] = false
        command
      end
    end

    # @since 5.15.1
    def disable_cmd(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      _get_and_set_cmd('disable_cmd', *args, manual: manual, scope: scope, token: token) do |command|
        command['disabled'] = true
        command
      end
    end

    # Send a raw binary string to the specified interface.
    #
    # @param interface_name [String] The interface to send the raw binary
    # @param data [String] The raw binary data
    def send_raw(interface_name, data, manual: false, scope: $openc3_scope, token: $openc3_token)
      interface_name = interface_name.upcase
      interface = get_interface(interface_name, scope: scope, token: token)
      # Verify we have command authority on all the targets mapped to this interface
      interface['cmd_target_names'].each do |target_name|
        authorize(permission: 'cmd_raw', interface_name: interface_name, target_name: target_name, manual: manual, scope: scope, token: token)
      end
      InterfaceTopic.write_raw(interface_name, data, scope: scope)
    end

    # Returns the raw buffer from the most recent specified command packet.
    #
    # @param target_name [String] Target name of the command
    # @param command_name [String] Packet name of the command
    # @return [Hash] command hash with last command buffer
    def get_cmd_buffer(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, command_name = _extract_target_command_names('get_cmd_buffer', *args)
      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, manual: manual, scope: scope, token: token)
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
    def get_all_cmds(target_name, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name = target_name.upcase
      authorize(permission: 'cmd_info', target_name: target_name, manual: manual, scope: scope, token: token)
      TargetModel.packets(target_name, type: :CMD, scope: scope)
    end
    # get_all_commands is DEPRECATED
    alias get_all_commands get_all_cmds

    # Returns an array of all the command packet names
    #
    # @since 5.0.6
    # @param target_name [String] Name of the target
    # @return [Array<String>] Array of all command packet names
    def get_all_cmd_names(target_name, hidden: false, manual: false, scope: $openc3_scope, token: $openc3_token)
      begin
        packets = get_all_cmds(target_name, scope: scope, token: token)
      rescue RuntimeError
        packets = []
      end
      names = []
      packets.each do |packet|
        if hidden
          names << packet['packet_name']
        else
          names << packet['packet_name'] unless packet['hidden']
        end
      end
      return names
    end
    # get_all_command_names is DEPRECATED
    alias get_all_command_names get_all_cmd_names

    # Returns a hash of the given command
    #
    # @since 5.0.0
    # @return [Hash] Command as a hash
    def get_cmd(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, command_name = _extract_target_command_names('get_cmd', *args)
      authorize(permission: 'cmd_info', target_name: target_name, manual: manual, scope: scope, token: token)
      TargetModel.packet(target_name, command_name, type: :CMD, scope: scope)
    end
    # get_command is DEPRECATED
    alias get_command get_cmd

    # Returns a hash of the given command parameter
    #
    # @since 5.0.0
    # @param target_name [String] Name of the target
    # @param command_name [String] Name of the packet
    # @param parameter_name [String] Name of the parameter
    # @return [Hash] Command parameter as a hash
    def get_param(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, command_name, parameter_name = _extract_target_command_parameter_names('get_param', *args)
      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, manual: manual, scope: scope, token: token)
      TargetModel.packet_item(target_name, command_name, parameter_name, type: :CMD, scope: scope)
    end
    # get_parameter is DEPRECATED
    alias get_parameter get_param

    # Returns whether the specified command is hazardous
    #
    # Accepts two different calling styles:
    #   get_cmd_hazardous("TGT CMD with PARAM1 val, PARAM2 val")
    #   get_cmd_hazardous('TGT','CMD',{'PARAM1'=>val,'PARAM2'=>val})
    #
    # @param args [String|Array<String>] See the description for calling style
    # @return [Boolean] Whether the command is hazardous
    def get_cmd_hazardous(*args, manual: false, scope: $openc3_scope, token: $openc3_token, **kwargs)
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

      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, manual: manual, scope: scope, token: token)
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
    # Supports the following call syntax:
    #   get_cmd_value("TGT PKT ITEM", type: :RAW)
    #   get_cmd_value("TGT", "PKT", "ITEM", type: :RAW)
    #   get_cmd_value("TGT", "PKT", "ITEM", :RAW) # DEPRECATED
    def get_cmd_value(*args, type: :CONVERTED, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name = nil
      command_name = nil
      parameter_name = nil
      case args.length
      when 1
        target_name, command_name, parameter_name = args[0].upcase.split
      when 3
        target_name = args[0].upcase
        command_name = args[1].upcase
        parameter_name = args[2].upcase
      when 4
        target_name = args[0].upcase
        command_name = args[1].upcase
        parameter_name = args[2].upcase
        type = args[3].upcase
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to get_cmd_value()"
      end
      if target_name.nil? or command_name.nil? or parameter_name.nil?
        raise "ERROR: Target name, command name and parameter name required. Usage: get_cmd_value(\"TGT CMD PARAM\") or #{method_name}(\"TGT\", \"CMD\", \"PARAM\")"
      end
      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, manual: manual, scope: scope, token: token)
      CommandDecomTopic.get_cmd_item(target_name, command_name, parameter_name, type: type, scope: scope)
    end

    # Returns the time the most recent command was sent
    #
    # @param target_name [String] Target name of the command. If not given then
    #    the most recent time from all commands will be returned
    # @param command_name [String] Packet name of the command. If not given then
    #    then most recent time from the given target will be returned.
    # @return [Array<Target Name, Command Name, Time Seconds, Time Microseconds>]
    def get_cmd_time(target_name = nil, command_name = nil, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'cmd_info', target_name: target_name, packet_name: command_name, manual: manual, scope: scope, token: token)
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
    def get_cmd_cnt(*args, manual: false, scope: $openc3_scope, token: $openc3_token)
      target_name, command_name = _extract_target_command_names('get_cmd_cnt', *args)
      authorize(permission: 'system', target_name: target_name, packet_name: command_name, manual: manual, scope: scope, token: token)
      TargetModel.packet(target_name, command_name, type: :CMD, scope: scope)
      return TargetModel.get_command_count(target_name, command_name, scope: scope)
    end

    # Get the transmit counts for command packets
    #
    # @param target_commands [Array<Array<String, String>>] Array of arrays containing target_name, packet_name
    # @return [Numeric] Transmit count for the command
    def get_cmd_cnts(target_commands, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      unless target_commands.is_a?(Array) and target_commands[0].is_a?(Array)
        raise "get_cmd_cnts takes an array of arrays containing target, packet_name, e.g. [['INST', 'COLLECT'], ['INST', 'ABORT']]"
      end
      return TargetModel.get_command_counts(target_commands, scope: scope)
    end

    ###########################################################################
    # PRIVATE implementation details
    ###########################################################################

    def _extract_target_command_names(method_name, *args)
      target_name = nil
      command_name = nil
      case args.length
      when 1
        target_name, command_name = args[0].upcase.split
      when 2
        target_name = args[0].upcase
        command_name = args[1].upcase
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to #{method_name}()"
      end
      if target_name.nil? or command_name.nil?
        raise "ERROR: Target name and command name required. Usage: #{method_name}(\"TGT CMD\") or #{method_name}(\"TGT\", \"CMD\")"
      end
      return [target_name, command_name]
    end

    def _extract_target_command_parameter_names(method_name, *args)
      target_name = nil
      command_name = nil
      parameter_name = nil
      case args.length
      when 1
        target_name, command_name, parameter_name = args[0].upcase.split
      when 3
        target_name = args[0].upcase
        command_name = args[1].upcase
        parameter_name = args[2].upcase
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to #{method_name}()"
      end
      if target_name.nil? or command_name.nil? or parameter_name.nil?
        raise "ERROR: Target name, command name and parameter name required. Usage: #{method_name}(\"TGT CMD PARAM\") or #{method_name}(\"TGT\", \"CMD\", \"PARAM\")"
      end
      return [target_name, command_name, parameter_name]
    end

    # NOTE: When adding new keywords to this method, make sure to update script/commands.rb
    def _cmd_implementation(method_name, *args, range_check:, hazardous_check:, raw:, timeout: nil, log_message: nil, manual: false, validate: true, queue: nil,
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
      user = authorize(permission: 'cmd', target_name: target_name, packet_name: cmd_name, manual: manual, scope: scope, token: token)
      if user.nil?
        user = {}
        user['username'] = ENV['OPENC3_MICROSERVICE_NAME']

        # Get the caller stack trace to determine the point in the code where the command was called
        # This code works but ultimately we didn't want to overload 'username' and take a performance hit
        # caller.each do |frame|
        #   # Look for the following line in the stack trace which indicates custom code
        #   # /tmp/d20240827-62-8e57pf/targets/INST/lib/example_limits_response.rb:31:in `call'
        #   if frame.include?("/targets/#{target_name}")
        #     user = {}
        #     # username is the name of the custom code file
        #     user['username'] = frame.split("/targets/")[-1].split(':')[0]
        #     break
        #   end
        # end
      end

      packet = TargetModel.packet(target_name, cmd_name, type: :CMD, scope: scope)
      if packet['disabled']
        error = DisabledError.new
        error.target_name = target_name
        error.cmd_name = cmd_name
        raise error
      end
      if log_message.nil? # This means the default was used, no argument was passed
        log_message = true # Default is true
        # If the packet has the DISABLE_MESSAGES keyword then no messages by default
        log_message = false if packet["messages_disabled"]
        # Check if any of the parameters have DISABLE_MESSAGES
        cmd_params.each do |key, value|
          item = packet['items'].find { |find_item| find_item['name'] == key.to_s }
          if item && item['states'] && item['states'][value] && item['states'][value]["messages_disabled"]
            log_message = false
          end
        end
      end
      cmd_string = _build_cmd_output_string(method_name, target_name, cmd_name, cmd_params, packet)
      username = user && user['username'] ? user['username'] : 'anonymous'
      command = {
        'target_name' => target_name,
        'cmd_name' => cmd_name,
        'cmd_params' => cmd_params,
        'range_check' => range_check.to_s,
        'hazardous_check' => hazardous_check.to_s,
        'raw' => raw.to_s,
        'cmd_string' => cmd_string,
        'username' => username,
        'validate' => validate.to_s,
        'manual' => manual.to_s,
        'log_message' => log_message.to_s,
        'obfuscated_items' => packet['obfuscated_items'].to_s
      }
      # Users have to explicitly opt into a default queue by setting the OPENC3_DEFAULT_QUEUE
      # At which point ALL commands will go to that queue unless they specifically opt out with queue: false
      if ENV['OPENC3_DEFAULT_QUEUE'] && queue.nil?
        queue = ENV['OPENC3_DEFAULT_QUEUE']
      end
      if queue
        # Pull the command out of the script string, e.g. cmd("INST ABORT")
        queued = cmd_string.split('("')[1].split('")')[0]
        QueueModel.queue_command(queue, command: queued, username: username, scope: scope)
      else
        CommandTopic.send_command(command, timeout: timeout, scope: scope)
      end
      return command
    end
  end
end
