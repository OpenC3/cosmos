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

require 'openc3/topics/command_topic'
require 'openc3/topics/telemetry_topic'
require 'openc3/system/system'

module OpenC3
  module InterfaceDecomCommon
    def handle_inject_tlm(inject_tlm_json)
      inject_tlm_hash = JSON.parse(inject_tlm_json, allow_nan: true, create_additions: true)
      target_name = inject_tlm_hash['target_name']
      packet_name = inject_tlm_hash['packet_name']
      item_hash = inject_tlm_hash['item_hash']
      type = inject_tlm_hash['type'].to_s.intern
      packet = System.telemetry.packet(target_name, packet_name)
      if item_hash
        item_hash.each do |name, value|
          packet.write(name.to_s, value, type)
        end
      end
      packet.received_count += 1
      packet.received_time = Time.now.sys
      TelemetryTopic.write_packet(packet, scope: @scope)
    end

    def handle_build_cmd(build_cmd_json)
      build_cmd_hash = JSON.parse(build_cmd_json, allow_nan: true, create_additions: true)
      target_name = build_cmd_hash['target_name']
      cmd_name = build_cmd_hash['cmd_name']
      cmd_params = build_cmd_hash['cmd_params']
      range_check = build_cmd_hash['range_check']
      raw = build_cmd_hash['raw']
      begin
        command = System.commands.build_cmd(target_name, cmd_name, cmd_params, range_check, raw)
        CommandTopic.write_built_cmd(command, scope: @scope)
      # If there is an error due to parameter out of range, etc, we rescue it so we can
      # write the BUILTCOMMAND topic and allow the TelemetryDecomTopic.build_cmd to return
      rescue => error
        topic = "#{@scope}__BUILTCOMMAND__{#{target_name}}__#{cmd_name}"
        msg_hash = {
          result: 'ERROR',
          message: error.message
        }
        Topic.write_topic(topic, msg_hash)
      end
    end
  end
end
