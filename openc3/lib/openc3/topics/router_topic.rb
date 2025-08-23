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

require 'openc3/topics/topic'

module OpenC3
  class RouterTopic < Topic
    # Generate a list of topics for this router. This includes the router itself
    # and all the targets which are assigned to this router.
    def self.topics(router, scope:)
      topics = []
      topics << "{#{scope}__CMD}ROUTER__#{router.name}"
      router.tlm_target_names.each do |target_name|
        System.telemetry.packets(target_name).each do |packet_name, packet|
          topics << "#{scope}__TELEMETRY__{#{packet.target_name}}__#{packet.packet_name}"
        end
      end
      topics
    end

    def self.receive_telemetry(router, scope:)
      while true
        Topic.read_topics(RouterTopic.topics(router, scope: scope)) do |topic, msg_id, msg_hash, redis|
          result = yield topic, msg_id, msg_hash, redis
          if result and /CMD}ROUTER/.match?(topic)
            ack_topic = topic.split("__")
            ack_topic[1] = 'ACK' + ack_topic[1]
            ack_topic = ack_topic.join("__")
            Topic.write_topic(ack_topic, { 'result' => result }, msg_id, 100)
          end
        end
      end
    end

    def self.route_command(packet, target_names, scope:)
      if packet.identified?
        topic = "{#{scope}__CMD}TARGET__#{packet.target_name}"
        Topic.write_topic(topic, { 'target_name' => packet.target_name, 'cmd_name' => packet.packet_name, 'cmd_buffer' => packet.buffer(false) }, '*', 100)
      elsif target_names.length == 1
        topic = "{#{scope}__CMD}TARGET__#{target_names[0]}"
        Topic.write_topic(topic, { 'target_name' => packet.target_name ? packet.target_name : 'UNKNOWN', 'cmd_name' => 'UNKNOWN', 'cmd_buffer' => packet.buffer(false) }, '*', 100)
      else
        raise "No route for command: #{packet.target_name ? packet.target_name : 'UNKNOWN'} #{packet.packet_name ? packet.packet_name : 'UNKNOWN'}"
      end
    end

    def self.connect_router(router_name, *router_params, scope:)
      if router_params && !router_params.empty?
        Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'connect' => 'true', 'params' => JSON.generate(router_params) }, '*', 100)
      else
        Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'connect' => 'true' }, '*', 100)
      end
    end

    def self.disconnect_router(router_name, scope:)
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'disconnect' => 'true' }, '*', 100)
    end

    def self.start_raw_logging(router_name, scope:)
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'log_stream' => 'true' }, '*', 100)
    end

    def self.stop_raw_logging(router_name, scope:)
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'log_stream' => 'false' }, '*', 100)
    end

    def self.shutdown(router, scope:)
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router.name}", { 'shutdown' => 'true' }, '*', 100)
    end

    def self.router_cmd(router_name, cmd_name, *cmd_params, scope:)
      data = {}
      data['cmd_name'] = cmd_name
      data['cmd_params'] = cmd_params
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'router_cmd' => JSON.generate(data, allow_nan: true) }, '*', 100)
    end

    def self.protocol_cmd(router_name, cmd_name, *cmd_params, read_write: :READ_WRITE, index: -1, scope:)
      data = {}
      data['cmd_name'] = cmd_name
      data['cmd_params'] = cmd_params
      data['read_write'] = read_write.to_s.upcase
      data['index'] = index
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'protocol_cmd' => JSON.generate(data, allow_nan: true) }, '*', 100)
    end

    def self.router_target_enable(router_name, target_name, cmd_only: false, tlm_only: false, scope:)
      data = {}
      data['target_name'] = target_name.to_s.upcase
      data['cmd_only'] = cmd_only
      data['tlm_only'] = tlm_only
      data['action'] = 'enable'
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'target_control' => JSON.generate(data, allow_nan: true) }, '*', 100)
    end

    def self.router_target_disable(router_name, target_name, cmd_only: false, tlm_only: false, scope:)
      data = {}
      data['target_name'] = target_name.to_s.upcase
      data['cmd_only'] = cmd_only
      data['tlm_only'] = tlm_only
      data['action'] = 'disable'
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'target_control' => JSON.generate(data, allow_nan: true) }, '*', 100)
    end

    def self.router_details(router_name, scope:)
      router_name = router_name.upcase

      timeout = COMMAND_ACK_TIMEOUT_S unless timeout
      ack_topic = "{#{scope}__ACKCMD}ROUTER__#{router_name}"
      Topic.update_topic_offsets([ack_topic])

      cmd_id = Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'router_details' => 'true' }, '*', 100)
      time = Time.now
      while (Time.now - time) < timeout
        Topic.read_topics([ack_topic]) do |_topic, _msg_id, msg_hash, _redis|
          if msg_hash["id"] == cmd_id
            return JSON.parse(msg_hash["result"], :allow_nan => true, :create_additions => true)
          end
        end
      end
      raise "Timeout of #{timeout}s waiting for cmd ack"
    end
  end
end
