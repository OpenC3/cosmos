# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/topics/topic'

module OpenC3
  class RouterTopic < Topic
    COMMAND_ACK_TIMEOUT_S = 30

    # Look up db_shard from RouterModel
    def self._db_shard_for_router(router_name, scope:)
      json = Store.hget("#{scope}__openc3_routers", router_name)
      json ? (JSON.parse(json, allow_nan: true, create_additions: true)['db_shard'] || 0).to_i : 0
    end

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

    def self.receive_telemetry(router, scope:, db_shard: 0)
      db_shard = db_shard.to_i
      router_cmd_topic = "{#{scope}__CMD}ROUTER__#{router.name}"

      target_topics = []
      router.tlm_target_names.each do |target_name|
        System.telemetry.packets(target_name).each do |packet_name, packet|
          target_topics << "#{scope}__TELEMETRY__{#{packet.target_name}}__#{packet.packet_name}"
        end
      end

      # Group telemetry topics by db_shard; include router cmd topic on db_shard
      db_shard_groups = Topic.group_topics_by_db_shard(target_topics, target_pattern: '__TELEMETRY__', scope: scope)
      db_shard_groups[db_shard] ||= []
      db_shard_groups[db_shard] << router_cmd_topic

      all_same_db_shard = Topic.all_same_db_shard?(db_shard_groups)

      while true
        if all_same_db_shard
          # Fast path: everything on one db_shard, single read
          db_shard = db_shard_groups.keys.first || 0
          Topic.read_topics(db_shard_groups[db_shard], db_shard: db_shard) do |topic, msg_id, msg_hash, redis|
            result = yield topic, msg_id, msg_hash, redis
            Topic.write_ack(topic, result, msg_id, db_shard: db_shard) if result and /CMD}ROUTER/.match?(topic)
          end
        else
          timeout_per_db_shard = [1000 / [db_shard_groups.length, 1].max, 100].max
          db_shard_groups.each do |db_shard, topics|
            Topic.read_topics(topics, nil, timeout_per_db_shard, db_shard: db_shard) do |topic, msg_id, msg_hash, redis|
              result = yield topic, msg_id, msg_hash, redis
              Topic.write_ack(topic, result, msg_id, db_shard: db_shard) if result and /CMD}ROUTER/.match?(topic)
            end
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
      db_shard = _db_shard_for_router(router_name, scope: scope)
      if router_params && !router_params.empty?
        Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'connect' => 'true', 'params' => JSON.generate(router_params, allow_nan: true) }, '*', 100, db_shard: db_shard)
      else
        Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'connect' => 'true' }, '*', 100, db_shard: db_shard)
      end
    end

    def self.disconnect_router(router_name, scope:)
      db_shard = _db_shard_for_router(router_name, scope: scope)
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'disconnect' => 'true' }, '*', 100, db_shard: db_shard)
    end

    def self.start_raw_logging(router_name, scope:)
      db_shard = _db_shard_for_router(router_name, scope: scope)
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'log_stream' => 'true' }, '*', 100, db_shard: db_shard)
    end

    def self.stop_raw_logging(router_name, scope:)
      db_shard = _db_shard_for_router(router_name, scope: scope)
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'log_stream' => 'false' }, '*', 100, db_shard: db_shard)
    end

    def self.shutdown(router, scope:)
      db_shard = _db_shard_for_router(router.name, scope: scope)
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router.name}", { 'shutdown' => 'true' }, '*', 100, db_shard: db_shard)
    end

    def self.router_cmd(router_name, cmd_name, *cmd_params, scope:)
      db_shard = _db_shard_for_router(router_name, scope: scope)
      data = {}
      data['cmd_name'] = cmd_name
      data['cmd_params'] = cmd_params
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'router_cmd' => JSON.generate(data, allow_nan: true) }, '*', 100, db_shard: db_shard)
    end

    def self.protocol_cmd(router_name, cmd_name, *cmd_params, read_write: :READ_WRITE, index: -1, scope:)
      db_shard = _db_shard_for_router(router_name, scope: scope)
      data = {}
      data['cmd_name'] = cmd_name
      data['cmd_params'] = cmd_params
      data['read_write'] = read_write.to_s.upcase
      data['index'] = index
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'protocol_cmd' => JSON.generate(data, allow_nan: true) }, '*', 100, db_shard: db_shard)
    end

    def self.router_target_enable(router_name, target_name, cmd_only: false, tlm_only: false, scope:)
      db_shard = _db_shard_for_router(router_name, scope: scope)
      data = {}
      data['target_name'] = target_name.to_s.upcase
      data['cmd_only'] = cmd_only
      data['tlm_only'] = tlm_only
      data['action'] = 'enable'
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'target_control' => JSON.generate(data, allow_nan: true) }, '*', 100, db_shard: db_shard)
    end

    def self.router_target_disable(router_name, target_name, cmd_only: false, tlm_only: false, scope:)
      db_shard = _db_shard_for_router(router_name, scope: scope)
      data = {}
      data['target_name'] = target_name.to_s.upcase
      data['cmd_only'] = cmd_only
      data['tlm_only'] = tlm_only
      data['action'] = 'disable'
      Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'target_control' => JSON.generate(data, allow_nan: true) }, '*', 100, db_shard: db_shard)
    end

    def self.router_details(router_name, timeout: nil, scope:)
      router_name = router_name.upcase
      db_shard = _db_shard_for_router(router_name, scope: scope)

      timeout = COMMAND_ACK_TIMEOUT_S unless timeout
      ack_topic = "{#{scope}__ACKCMD}ROUTER__#{router_name}"
      Topic.update_topic_offsets([ack_topic], db_shard: db_shard)

      cmd_id = Topic.write_topic("{#{scope}__CMD}ROUTER__#{router_name}", { 'router_details' => 'true' }, '*', 100, db_shard: db_shard)
      time = Time.now
      while (Time.now - time) < timeout
        Topic.read_topics([ack_topic], db_shard: db_shard) do |_topic, _msg_id, msg_hash, _redis|
          if msg_hash["id"] == cmd_id
            return JSON.parse(msg_hash["result"], :allow_nan => true, :create_additions => true)
          end
        end
      end
      raise "Timeout of #{timeout}s waiting for cmd ack"
    end
  end
end
