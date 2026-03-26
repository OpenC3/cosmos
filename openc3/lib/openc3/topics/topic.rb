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
  end
end
