# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/topics/topic'

module OpenC3
  class SystemEventsTopic < Topic
    PRIMARY_KEY = "OPENC3__SYSTEM__EVENTS".freeze

    # Collect all unique target shards from TargetModel data on shard 0.
    def self._active_shards
      shards = Set.new([0])
      # Iterate all scopes to find all target shards
      Store.scan_each(match: '*__openc3_targets', type: 'hash') do |key|
        Store.hgetall(key).each do |_name, json|
          parsed = JSON.parse(json, allow_nan: true, create_additions: true)
          shards << (parsed['shard'] || 0).to_i
        end
      end
      shards
    end

    def self.update_topic_offsets()
      Topic.update_topic_offsets([PRIMARY_KEY])
    end

    def self.write(type, event)
      event['type'] = type
      msg = {event: JSON.generate(event, allow_nan: true)}
      # Write to all active shards so every interface microservice can read system events inline
      _active_shards.each do |shard|
        Topic.write_topic(PRIMARY_KEY, msg, '*', 1000, shard: shard)
      end
    end

    def self.read()
      Topic.read_topics([PRIMARY_KEY]) do |_topic, _msg_id, msg_hash, _redis|
        yield JSON.parse(msg_hash['event'])
      end
    end
  end
end
