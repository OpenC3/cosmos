# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require_relative 'topics_thread'

class ConfigEventsApi
  def initialize(subscription_key, history_count = 0, start_offset = nil, scope:)
    topics = ["#{scope}__CONFIG"]
    start_offsets = [start_offset] if start_offset and start_offset != 'undefined'
    @thread = TopicsThread.new(topics, subscription_key, history_count, offsets: start_offsets, transmit_msg_id: true)
    @thread.start
  end

  def kill
    @thread.stop
  end
end
