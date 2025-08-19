# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/topics/topic'

module OpenC3
  class QueueTopic < Topic
    PRIMARY_KEY = "openc3_queue"

    def self.write_notification(notification, scope:)
      Topic.write_topic("#{scope}__#{PRIMARY_KEY}", notification, '*', 1000)
    end

    # # Write a queue event notification
    # #
    # # @param scope [String] The scope
    # # @param name [String] Queue entry name
    # # @param kind [String] The event kind (created, updated, deleted, enabled, disabled, started, completed, failed)
    # # @param data [Hash] Queue entry data
    # def self.write_event(scope:, name:, kind:, data:)
    #   notification = {
    #     'kind' => kind,
    #     'type' => 'queue',
    #     'data' => JSON.generate(data)
    #   }
    #   write_notification(notification, scope: scope)
    # end

    # # Write a queue status change notification
    # #
    # # @param scope [String] The scope
    # # @param name [String] Queue entry name
    # # @param status [String] The new status
    # # @param data [Hash] Queue entry data
    # def self.write_status(scope:, name:, status:, data:)
    #   notification = {
    #     'kind' => status,
    #     'type' => 'queue',
    #     'data' => JSON.generate(data)
    #   }
    #   write_notification(notification, scope: scope)
    # end

    # # Write a queue error notification
    # #
    # # @param scope [String] The scope
    # # @param name [String] Queue entry name
    # # @param error [String] Error message
    # # @param data [Hash] Queue entry data
    # def self.write_error(scope:, name:, error:, data:)
    #   notification = {
    #     'kind' => 'error',
    #     'type' => 'queue',
    #     'data' => JSON.generate(data.merge('error' => error))
    #   }
    #   write_notification(notification, scope: scope)
    # end
  end
end