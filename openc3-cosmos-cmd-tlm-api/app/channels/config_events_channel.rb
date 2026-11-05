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

class ConfigEventsChannel < ApplicationCable::Channel
  include ApplicationCable::BroadcasterChannel
  broadcaster_prefix 'config_events'

  private

  def create_broadcaster
    ConfigEventsApi.new(subscription_key, params['history_count'], scope: scope)
  end
end
