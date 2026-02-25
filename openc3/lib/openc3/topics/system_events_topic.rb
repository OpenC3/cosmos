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

    def self.update_topic_offsets()
      Topic.update_topic_offsets([PRIMARY_KEY])
    end

    def self.write(type, event)
      event['type'] = type
      Topic.write_topic(PRIMARY_KEY, {event: JSON.generate(event, allow_nan: true)}, '*', 1000)
    end

    def self.read()
      Topic.read_topics([PRIMARY_KEY]) do |_topic, _msg_id, msg_hash, _redis|
        yield JSON.parse(msg_hash['event'])
      end
    end
  end
end
