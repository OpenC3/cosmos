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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963

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
      packet.received_time = Time.now.sys
      packet.received_count = TargetModel.increment_telemetry_count(packet.target_name, packet.packet_name, 1, scope: @scope)
      TelemetryTopic.write_packet(packet, scope: @scope)
    # If the inject_tlm parameters are bad we rescue so
    # interface_microservice and decom_microservice can continue
    rescue => e
      @logger.error "inject_tlm error due to #{e.message}"
    end

    def handle_build_cmd(build_cmd_json, msg_id)
      build_cmd_hash = JSON.parse(build_cmd_json, allow_nan: true, create_additions: true)
      target_name = build_cmd_hash['target_name']
      cmd_name = build_cmd_hash['cmd_name']
      cmd_params = build_cmd_hash['cmd_params']
      range_check = build_cmd_hash['range_check']
      raw = build_cmd_hash['raw']
      ack_topic = "{#{@scope}__ACKCMD}TARGET__#{target_name}"
      begin
        command = System.commands.build_cmd(target_name, cmd_name, cmd_params, range_check, raw)
        msg_hash = {
          id: msg_id,
          result: 'SUCCESS',
          time: command.packet_time.to_nsec_from_epoch,
          received_time: command.received_time.to_nsec_from_epoch,
          target_name: command.target_name,
          packet_name: command.packet_name,
          received_count: command.received_count,
          buffer: command.buffer(false)
        }
      # If there is an error due to parameter out of range, etc, we rescue it so we can
      # write the ACKCMD}TARGET topic and allow the TelemetryDecomTopic.build_cmd to return
      rescue => error
        msg_hash = {
          id: msg_id,
          result: 'ERROR',
          message: error.message
        }
      end
      Topic.write_topic(ack_topic, msg_hash)
    end

    def handle_get_tlm_buffer(get_tlm_buffer_json, msg_id)
      get_tlm_buffer_hash = JSON.parse(get_tlm_buffer_json, allow_nan: true, create_additions: true)
      target_name = get_tlm_buffer_hash['target_name']
      packet_name = get_tlm_buffer_hash['packet_name']
      ack_topic = "{#{@scope}__ACKCMD}TARGET__#{target_name}"
      begin
        packet = System.telemetry.packet(target_name, packet_name)
        msg_hash = {
          id: msg_id,
          result: 'SUCCESS',
          time: packet.packet_time.to_nsec_from_epoch,
          received_time: packet.received_time.to_nsec_from_epoch,
          target_name: packet.target_name,
          packet_name: packet.packet_name,
          received_count: packet.received_count,
          stored: packet.stored.to_s,
          buffer: packet.buffer(false)
        }
        msg_hash[:extra] = JSON.generate(packet.extra.as_json, allow_nan: true) if packet.extra

      # If there is an error due to parameter out of range, etc, we rescue it so we can
      # write the ACKCMD}TARGET topic and allow the source to return
      rescue => error
        msg_hash = {
          id: msg_id,
          result: 'ERROR',
          message: error.message
        }
      end
      Topic.write_topic(ack_topic, msg_hash)
    end
  end
end
