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
    # Delegate all unknown class methods to delegate to the EphemeralStore
    def self.method_missing(message, *args, **kwargs, &block)
      EphemeralStore.public_send(message, *args, **kwargs, &block)
    end

    def self.clear_topics(topics, maxlen = 0)
      topics.each { |topic| EphemeralStore.xtrim(topic, maxlen) }
    end

    def self.get_cnt(topic)
      _, packet = EphemeralStore.get_newest_message(topic)
      packet ? packet["received_count"].to_i : 0
    end
  end
end
