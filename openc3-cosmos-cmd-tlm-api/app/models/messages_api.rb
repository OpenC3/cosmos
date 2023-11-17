# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

require_relative "messages_thread"

class MessagesApi
  def initialize(
    uuid,
    channel,
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
        channel,
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
