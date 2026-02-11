# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/topics/topic'

module OpenC3
  class QueueTopic < Topic
    PRIMARY_KEY = "openc3_queue"

    def self.write_notification(notification, scope:)
      Topic.write_topic("#{scope}__#{PRIMARY_KEY}", notification, '*', 1000)
    end
  end
end
