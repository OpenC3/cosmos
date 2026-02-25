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

require_relative "messages_thread"

class MessagesApi
  def initialize(
    subscription_key,
    history_count = 0,
    start_offset: nil,
    start_time: nil,
    end_time: nil,
    types: nil,
    level: nil,
    scope:
  )
    @thread =
      MessagesThread.new(
        subscription_key,
        history_count,
        start_offset: start_offset,
        start_time: start_time,
        end_time: end_time,
        types: types,
        level: level,
        scope: scope
      )
    @thread.start
  end

  def kill
    @thread.stop
  end
end
