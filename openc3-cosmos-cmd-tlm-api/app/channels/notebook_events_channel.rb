# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

class NotebookEventsChannel < ApplicationCable::Channel
  include ApplicationCable::BroadcasterChannel
  broadcaster_prefix 'notebook_events'

  private

  def create_broadcaster
    NotebookEventsApi.new(subscription_key, params['history_count'], scope: scope)
  end
end
