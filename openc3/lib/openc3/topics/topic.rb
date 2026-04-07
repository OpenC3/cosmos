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

require 'openc3/utilities/store'

module OpenC3
  class Topic
    # Delegate all unknown class methods to EphemeralStore shard 0 (system-level topics)
    def self.method_missing(message, *args, **kwargs, &block)
      EphemeralStore.public_send(message, *args, **kwargs, &block)
    end

    def self.clear_topics(topics, maxlen = 0, shard: 0)
      store = EphemeralStore.instance(shard: shard)
      topics.each { |topic| store.xtrim(topic, maxlen) }
    end

    def self.get_cnt(topic, shard: 0)
      _, packet = EphemeralStore.instance(shard: shard).get_newest_message(topic)
      packet ? packet["received_count"].to_i : 0
    end

    # Shard-aware topic methods for target-specific streams.
    # These explicitly route to the correct EphemeralStore shard.

    def self.write_topic(topic, msg_hash, id = '*', maxlen = nil, approximate = 'true', shard: 0)
      EphemeralStore.instance(shard: shard).write_topic(topic, msg_hash, id, maxlen, approximate)
    end

    def self.read_topics(topics, offsets = nil, timeout_ms = 1000, count = nil, shard: 0, &block)
      EphemeralStore.instance(shard: shard).read_topics(topics, offsets, timeout_ms, count, &block)
    end

    def self.get_newest_message(topic, shard: 0)
      EphemeralStore.instance(shard: shard).get_newest_message(topic)
    end

    def self.get_oldest_message(topic, shard: 0)
      EphemeralStore.instance(shard: shard).get_oldest_message(topic)
    end

    def self.get_last_offset(topic, shard: 0)
      EphemeralStore.instance(shard: shard).get_last_offset(topic)
    end

    def self.update_topic_offsets(topics, shard: 0)
      EphemeralStore.instance(shard: shard).update_topic_offsets(topics)
    end

    def self.trim_topic(topic, minid, approximate = true, limit: 0, shard: 0)
      EphemeralStore.instance(shard: shard).trim_topic(topic, minid, approximate, limit: limit)
    end

    def self.del(topic, shard: 0)
      EphemeralStore.instance(shard: shard).del(topic)
    end

    # Group topics by shard. Each topic's target name is extracted and looked up.
    # Topics matching target_pattern are sharded; others go to shard 0.
    # @param topics [Array<String>] List of topic strings
    # @param target_pattern [String] Substring to identify target-specific topics (e.g. 'CMD}TARGET__', '__TELEMETRY__')
    # @param scope [String] Scope name for shard lookup
    # @return [Hash] { shard => [topic, ...] }
    def self.group_topics_by_shard(topics, target_pattern:, scope:)
      groups = {}
      topics.each do |topic|
        if topic.include?(target_pattern)
          target_name = topic.match(/__\{?([^}_]+)\}?__/)[1] rescue nil
          # Handle CMD}TARGET__ pattern where target is after TARGET__
          target_name = topic.split('TARGET__')[1] if target_pattern.include?('TARGET__') && target_name.nil?
          shard = Store.shard_for_target(target_name, scope: scope)
        else
          shard = 0
        end
        groups[shard] ||= []
        groups[shard] << topic
      end
      groups
    end

    # Check if all shard groups resolve to shard 0 (single-shard fast path).
    def self.all_on_shard_zero?(shard_groups)
      shard_groups.length <= 1 && (shard_groups.empty? || shard_groups.key?(0))
    end

    # Build the ACK topic from a command/router topic and write the ack.
    def self.write_ack(topic, result, msg_id, shard: 0)
      ack_topic = topic.split("__")
      ack_topic[1] = 'ACK' + ack_topic[1]
      ack_topic = ack_topic.join("__")
      Topic.write_topic(ack_topic, { 'result' => result, 'id' => msg_id }, '*', 100, shard: shard)
    end
  end
end
