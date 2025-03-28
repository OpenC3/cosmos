# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

class CalendarEventsChannel < ApplicationCable::Channel
  @@broadcasters = {}

  def subscribed
    stream_from uuid
    @@broadcasters[uuid] = CalendarEventsApi.new(uuid, self, params['history_count'], scope: scope)
  end

  def unsubscribed
    if @@broadcasters[uuid]
      stop_stream_from uuid
      @@broadcasters[uuid].kill
      @@broadcasters[uuid] = nil
      @@broadcasters.delete(uuid)
    end
  end
end
