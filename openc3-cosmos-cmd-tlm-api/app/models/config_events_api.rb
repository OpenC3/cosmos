# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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
