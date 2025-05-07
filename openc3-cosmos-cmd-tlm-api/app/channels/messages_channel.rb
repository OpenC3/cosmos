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

class MessagesChannel < ApplicationCable::Channel
  @@broadcasters = {}

  def subscribed
    subscription_key = "messages_#{uuid}"
    stream_from subscription_key

    @@broadcasters[subscription_key] = MessagesApi.new(
      subscription_key,
      params["history_count"],
      start_offset: params["start_offset"],
      start_time: params["start_time"],
      end_time: params["end_time"],
      types: params["types"],
      level: params["level"],
      scope: scope
    )
  end

  def unsubscribed
    subscription_key = "messages_#{uuid}"
    if @@broadcasters[subscription_key]
      stop_stream_from subscription_key
      @@broadcasters[subscription_key].kill
      @@broadcasters[subscription_key] = nil
      @@broadcasters.delete(subscription_key)
    end
  end
end
