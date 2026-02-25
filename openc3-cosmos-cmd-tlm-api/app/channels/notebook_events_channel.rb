# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

class NotebookEventsChannel < ApplicationCable::Channel
  @@broadcasters = {}

  def subscribed
    subscription_key = "notebook_events_#{uuid}"
    stream_from subscription_key
    @@broadcasters[subscription_key] = NotebookEventsApi.new(subscription_key, params['history_count'], scope: scope)
  end

  def unsubscribed
    subscription_key = "notebook_events_#{uuid}"
    if @@broadcasters[subscription_key]
      stop_stream_from subscription_key
      @@broadcasters[subscription_key].kill
      @@broadcasters[subscription_key] = nil
      @@broadcasters.delete(subscription_key)
    end
  end
end
