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

class MessagesChannel < ApplicationCable::Channel
  include ApplicationCable::BroadcasterChannel
  broadcaster_prefix 'messages'

  private

  def create_broadcaster
    MessagesApi.new(
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
end
