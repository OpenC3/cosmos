# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require_relative 'topics_thread'

class NotebookEventsApi
  def initialize(subscription_key, history_count = 0, scope:)
    topics = ["#{scope}__openc3_notebook"] # MUST be equal to `NotebookTopic::PRIMARY_KEY`
    @thread = TopicsThread.new(topics, subscription_key, history_count)
    @thread.start
  end

  def kill
    @thread.stop
  end
end
