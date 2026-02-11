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

class TimelineEventsChannel < ApplicationCable::Channel
  @@broadcasters = {}

  def subscribed
    subscription_key = "timeline_events_#{uuid}"
    stream_from subscription_key
    @@broadcasters[subscription_key] = TimelineEventsApi.new(subscription_key, params['history_count'], scope: scope)
  end

  def unsubscribed
    subscription_key = "timeline_events_#{uuid}"
    if @@broadcasters[subscription_key]
      stop_stream_from subscription_key
      @@broadcasters[subscription_key].kill
      @@broadcasters[subscription_key] = nil
      @@broadcasters.delete(subscription_key)
    end
  end
end
