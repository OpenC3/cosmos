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
  class InterfaceTopic < Topic
    COMMAND_ACK_TIMEOUT_S = 30

    # Look up db_shard from Interface
    def self._db_shard_for_interface(interface_name, scope:)
      json = Store.hget("#{scope}__openc3_interfaces", interface_name)
      json ? (JSON.parse(json, allow_nan: true, create_additions: true)['db_shard'] || 0).to_i : 0
    end

    # Generate a list of topics for this interface. This includes the interface itself
    # and all the targets which are assigned to this interface.
    def self.topics(interface, scope:)
      topics = []
      topics << "{#{scope}__CMD}INTERFACE__#{interface.name}"
      interface.cmd_target_names.each do |target_name|
        topics << "{#{scope}__CMD}TARGET__#{target_name}"
      end
      topics << "OPENC3__SYSTEM__EVENTS" # Add System Events
      topics
    end

    def self.receive_commands(interface, scope:, db_shard: 0)
      db_shard = db_shard.to_i
      interface_cmd_topic = "{#{scope}__CMD}INTERFACE__#{interface.name}"
      system_events_topic = "OPENC3__SYSTEM__EVENTS"

      target_topics = []
      interface.cmd_target_names.each do |target_name|
        target_topics << "{#{scope}__CMD}TARGET__#{target_name}"
      end

      # Group target command topics by db_shard; include interface cmd and system events on db_shard
      db_shard_groups = Topic.group_topics_by_db_shard(target_topics, target_pattern: 'CMD}TARGET__', scope: scope)
      db_shard_groups[db_shard] ||= []
      db_shard_groups[db_shard] << interface_cmd_topic
      db_shard_groups[db_shard] << system_events_topic

      all_same_db_shard = Topic.all_same_db_shard?(db_shard_groups)

      while true
        if all_same_db_shard
          # Fast path: everything on one db_shard, single read
          db_shard = db_shard_groups.keys.first || 0
          Topic.read_topics(db_shard_groups[db_shard], db_shard: db_shard) do |topic, msg_id, msg_hash, redis|
            result = yield topic, msg_id, msg_hash, redis
            Topic.write_ack(topic, result, msg_id, db_shard: db_shard) if result
          end
        else
          timeout_per_db_shard = [1000 / [db_shard_groups.length, 1].max, 100].max
          db_shard_groups.each do |db_shard, topics|
            Topic.read_topics(topics, nil, timeout_per_db_shard, db_shard: db_shard) do |topic, msg_id, msg_hash, redis|
              result = yield topic, msg_id, msg_hash, redis
              Topic.write_ack(topic, result, msg_id, db_shard: db_shard) if result
            end
          end
        end
      end
    end

    def self.write_raw(interface_name, data, timeout: nil, scope:)
      interface_name = interface_name.upcase
      db_shard = _db_shard_for_interface(interface_name, scope: scope)

      timeout = COMMAND_ACK_TIMEOUT_S unless timeout
      ack_topic = "{#{scope}__ACKCMD}INTERFACE__#{interface_name}"
      Topic.update_topic_offsets([ack_topic], db_shard: db_shard)

      cmd_id = Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'raw' => data }, '*', 100, db_shard: db_shard)
      time = Time.now
      while (Time.now - time) < timeout
        Topic.read_topics([ack_topic], db_shard: db_shard) do |_topic, _msg_id, msg_hash, _redis|
          if msg_hash["id"] == cmd_id
            if msg_hash["result"] == "SUCCESS"
              return
            else
              raise msg_hash["result"]
            end
          end
        end
      end
      raise "Timeout of #{timeout}s waiting for cmd ack"
    end

    def self.connect_interface(interface_name, *interface_params, scope:)
      db_shard = _db_shard_for_interface(interface_name, scope: scope)
      if interface_params && !interface_params.empty?
        Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'connect' => 'true', 'params' => JSON.generate(interface_params, allow_nan: true) }, '*', 100, db_shard: db_shard)
      else
        Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'connect' => 'true' }, '*', 100, db_shard: db_shard)
      end
    end

    def self.disconnect_interface(interface_name, scope:)
      db_shard = _db_shard_for_interface(interface_name, scope: scope)
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'disconnect' => 'true' }, '*', 100, db_shard: db_shard)
    end

    def self.start_raw_logging(interface_name, scope:)
      db_shard = _db_shard_for_interface(interface_name, scope: scope)
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'log_stream' => 'true' }, '*', 100, db_shard: db_shard)
    end

    def self.stop_raw_logging(interface_name, scope:)
      db_shard = _db_shard_for_interface(interface_name, scope: scope)
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'log_stream' => 'false' }, '*', 100, db_shard: db_shard)
    end

    def self.shutdown(interface, scope:)
      db_shard = _db_shard_for_interface(interface.name, scope: scope)
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface.name}", { 'shutdown' => 'true' }, '*', 100, db_shard: db_shard)
    end

    def self.interface_cmd(interface_name, cmd_name, *cmd_params, scope:)
      db_shard = _db_shard_for_interface(interface_name, scope: scope)
      data = {}
      data['cmd_name'] = cmd_name
      data['cmd_params'] = cmd_params
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'interface_cmd' => JSON.generate(data, allow_nan: true) }, '*', 100, db_shard: db_shard)
    end

    def self.protocol_cmd(interface_name, cmd_name, *cmd_params, read_write: :READ_WRITE, index: -1, scope:)
      db_shard = _db_shard_for_interface(interface_name, scope: scope)
      data = {}
      data['cmd_name'] = cmd_name
      data['cmd_params'] = cmd_params
      data['read_write'] = read_write.to_s.upcase
      data['index'] = index
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'protocol_cmd' => JSON.generate(data, allow_nan: true) }, '*', 100, db_shard: db_shard)
    end

    def self.inject_tlm(interface_name, target_name, packet_name, item_hash = nil, type: :CONVERTED, scope:)
      db_shard = _db_shard_for_interface(interface_name, scope: scope)
      data = {}
      data['target_name'] = target_name.to_s.upcase
      data['packet_name'] = packet_name.to_s.upcase
      data['item_hash'] = item_hash
      data['type'] = type
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'inject_tlm' => JSON.generate(data, allow_nan: true) }, '*', 100, db_shard: db_shard)
    end

    def self.interface_target_enable(interface_name, target_name, cmd_only: false, tlm_only: false, scope:)
      db_shard = _db_shard_for_interface(interface_name, scope: scope)
      data = {}
      data['target_name'] = target_name.to_s.upcase
      data['cmd_only'] = cmd_only
      data['tlm_only'] = tlm_only
      data['action'] = 'enable'
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'target_control' => JSON.generate(data, allow_nan: true) }, '*', 100, db_shard: db_shard)
    end

    def self.interface_target_disable(interface_name, target_name, cmd_only: false, tlm_only: false, scope:)
      db_shard = _db_shard_for_interface(interface_name, scope: scope)
      data = {}
      data['target_name'] = target_name.to_s.upcase
      data['cmd_only'] = cmd_only
      data['tlm_only'] = tlm_only
      data['action'] = 'disable'
      Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'target_control' => JSON.generate(data, allow_nan: true) }, '*', 100, db_shard: db_shard)
    end

    def self.interface_details(interface_name, timeout: nil, scope:)
      interface_name = interface_name.upcase
      db_shard = _db_shard_for_interface(interface_name, scope: scope)

      timeout = COMMAND_ACK_TIMEOUT_S unless timeout
      ack_topic = "{#{scope}__ACKCMD}INTERFACE__#{interface_name}"
      Topic.update_topic_offsets([ack_topic], db_shard: db_shard)

      cmd_id = Topic.write_topic("{#{scope}__CMD}INTERFACE__#{interface_name}", { 'interface_details' => 'true' }, '*', 100, db_shard: db_shard)
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
