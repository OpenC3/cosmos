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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/packets/packet'
require 'openc3/script/extract'

module OpenC3
  module Script
    include Extract

    private

    # Format the command like it appears in a script
    def _cmd_string(target_name, cmd_name, cmd_params, raw, scope)
      output_string = $disconnect ? 'DISCONNECT: ' : ''
      if raw
        output_string += 'cmd_raw("'
      else
        output_string += 'cmd("'
      end
      output_string += target_name + ' ' + cmd_name
      if cmd_params.nil? or cmd_params.empty?
        output_string << '")'
      else
        params = []
        # TODO: On the client side, decide if obfuscation is needed
        packet = TargetModel.packet(target_name, cmd_name, type: :CMD, scope: scope)
        cmd_params.each do |key, value|
          next if Packet::RESERVED_ITEM_NAMES.include?(key)

          item = packet['items'].find { |find_item| find_item['name'] == key.to_s }

          if item['obfuscate']
            params << "#{key} *****"
          else
            if value.is_a?(String)
              if !value.is_printable?
                value = "BINARY"
              elsif value.length > 256
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
        output_string += ' with ' + params + '")'
      end
      output_string
    end

    # Log any warnings about disabling checks and log the command itself
    # NOTE: This is a helper method and should not be called directly
    def _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous, scope)
      if no_range
        puts "WARN: Command #{target_name} #{cmd_name} being sent ignoring range checks"
      end
      if no_hazardous
        puts "WARN: Command #{target_name} #{cmd_name} being sent ignoring hazardous warnings"
      end
      puts _cmd_string(target_name, cmd_name, cmd_params, raw, scope)
    end

    def _cmd_disconnect(cmd, raw, no_range, no_hazardous, *args, scope: $openc3_scope)
      case args.length
      when 1
        target_name, cmd_name, cmd_params = extract_fields_from_cmd_text(args[0])
      when 2, 3
        target_name = args[0]
        cmd_name    = args[1]
        if args.length == 2
          cmd_params = {}
        else
          cmd_params = args[2]
        end
      else
        # Invalid number of arguments
        raise "ERROR: Invalid number of arguments (#{args.length}) passed to #{cmd}()"
      end

      # Get the command and validate the parameters
      command = $api_server.get_cmd(target_name, cmd_name, scope: scope)
      cmd_params.each do |param_name, _param_value|
        param = command['items'].find { |item| item['name'] == param_name }
        unless param
          raise "Packet item '#{target_name} #{cmd_name} #{param_name}' does not exist"
        end
      end
      _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous, scope)
   end

    # Send the command and log the results
    # This method signature has to include the keyword params present in cmd_api.rb _cmd_implementation()
    # except for range_check, hazardous_check, and raw as they are part of the cmd name
    # manual is always false since this is called from script and that is the default
    # NOTE: This is a helper method and should not be called directly
    def _cmd(cmd, cmd_no_hazardous, *args, timeout: nil, log_message: nil, validate: true, scope: $openc3_scope, token: $openc3_token, **kwargs)
      extract_string_kwargs_to_args(args, kwargs)
      raw = cmd.include?('raw')
      no_range = cmd.include?('no_range') || cmd.include?('no_checks')
      no_hazardous = cmd.include?('no_hazardous') || cmd.include?('no_checks')

      if $disconnect
        _cmd_disconnect(cmd, raw, no_range, no_hazardous, *args, scope: scope)
      else
        begin
          begin
            target_name, cmd_name, cmd_params = $api_server.method_missing(cmd, *args, timeout: timeout, log_message: log_message, validate: validate, scope: scope, token: token)
            if log_message.nil? or log_message
              _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous, scope)
            end
          rescue HazardousError => e
            # This opens a prompt at which point they can cancel and stop the script
            # or say Yes and send the command. Thus we don't care about the return value.
            prompt_for_hazardous(e.target_name, e.cmd_name, e.hazardous_description)
            target_name, cmd_name, cmd_params = $api_server.method_missing(cmd_no_hazardous, *args, timeout: timeout, log_message: log_message, validate: validate, scope: scope, token: token)
            if log_message.nil? or log_message
              _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous, scope)
            end
          end
        rescue CriticalCmdError => e
          # This should not return until the critical command has been approved
          prompt_for_critical_cmd(e.uuid, e.username, e.target_name, e.cmd_name, e.cmd_params, e.cmd_string)
          if log_message.nil? or log_message
            _log_cmd(e.target_name, e.cmd_name, e.cmd_params, raw, no_range, no_hazardous, scope)
          end
        end
      end
    end

    # The following methods send a command to the specified target. The equivalent
    # 'raw' version does not perform command parameter conversions
    #
    # Usage:
    #   cmd(target_name, cmd_name, cmd_params = {})
    # or
    #   cmd('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    def cmd(*args, **kwargs)
      _cmd('cmd', 'cmd_no_hazardous_check', *args, **kwargs)
    end
    def cmd_raw(*args, **kwargs)
      _cmd('cmd_raw', 'cmd_raw_no_hazardous_check', *args, **kwargs)
    end

    # Send a command to the specified target without range checking parameters
    def cmd_no_range_check(*args, **kwargs)
      _cmd('cmd_no_range_check', 'cmd_no_checks', *args, **kwargs)
    end
    def cmd_raw_no_range_check(*args, **kwargs)
      _cmd('cmd_raw_no_range_check', 'cmd_raw_no_checks', *args, **kwargs)
    end

    # Send a command to the specified target without hazardous checks
    def cmd_no_hazardous_check(*args, **kwargs)
      _cmd('cmd_no_hazardous_check', nil, *args, **kwargs)
    end
    def cmd_raw_no_hazardous_check(*args, **kwargs)
      _cmd('cmd_raw_no_hazardous_check', nil, *args, **kwargs)
    end

    # Send a command to the specified target without range checking or hazardous checks
    def cmd_no_checks(*args, **kwargs)
      _cmd('cmd_no_checks', nil, *args, **kwargs)
    end
    def cmd_raw_no_checks(*args, **kwargs)
      _cmd('cmd_raw_no_checks', nil, *args, **kwargs)
    end

    # Builds a command binary
    #
    # Accepts two different calling styles:
    #   build_cmd("TGT CMD with PARAM1 val, PARAM2 val")
    #   build_cmd('TGT','CMD',{'PARAM1'=>val,'PARAM2'=>val})
    def build_cmd(*args, range_check: true, raw: false, scope: $openc3_scope, **kwargs)
      extract_string_kwargs_to_args(args, kwargs)
      $api_server.build_cmd(*args)
    end
    # build_command is DEPRECATED
    alias build_command build_cmd

    # Returns whether the specified command is hazardous
    #
    # Accepts two different calling styles:
    #   get_cmd_hazardous("TGT CMD with PARAM1 val, PARAM2 val")
    #   get_cmd_hazardous('TGT','CMD',{'PARAM1'=>val,'PARAM2'=>val})
    def get_cmd_hazardous(*args, **kwargs)
      extract_string_kwargs_to_args(args, kwargs)
      $api_server.get_cmd_hazardous(*args)
    end

    # Returns the time the most recent command was sent
    def get_cmd_time(target_name = nil, command_name = nil, scope: $openc3_scope)
      results = $api_server.get_cmd_time(target_name, command_name, scope: scope)
      if Array === results
        if results[2] and results[3]
          results[2] = Time.at(results[2], results[3]).sys
        end
        results.delete_at(3)
      end
      results
    end
  end
end
