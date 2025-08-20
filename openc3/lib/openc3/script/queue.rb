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

require 'openc3/script/extract'

module OpenC3
  module Script
    include Extract

    private

    # Gets all queues
    #
    # @return The result of the method call.
    def queue_all(scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/queues", scope: scope)
      # Non-existent just returns nil
      return nil if response.nil? || response.status != 200
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    # Gets a queue by name
    #
    # @param name [String] The queue name
    # @return The result of the method call.
    def queue_get(name, scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/queues/#{name}", scope: scope)
      # Non-existent just returns nil
      return nil if response.nil? || response.status != 200
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    # Create a new queue
    #
    # @param name [String] The queue name
    # @return The result of the method call.
    def queue_create(name, scope: $openc3_scope)
      response = $api_server.request('post', "/openc3-api/queues/#{name}", scope: scope)
      if response.nil?
        raise "Failed to create queue due to #{response.status}"
      elsif response.status != 201
        raise "Failed to create queue due to #{response.status}"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    # Hold a queue
    #
    # @param name [String] The queue name
    # @return The result of the method call.
    def queue_hold(name, scope: $openc3_scope)
      response = $api_server.request('post', "/openc3-api/queues/#{name}/hold", scope: scope)
      if response.nil? || response.status != 200
        raise "Failed to hold queue"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    # Release a queue
    #
    # @param name [String] The queue name
    # @return The result of the method call.
    def queue_release(name, scope: $openc3_scope)
      response = $api_server.request('post', "/openc3-api/queues/#{name}/release", scope: scope)
      if response.nil? || response.status != 200
        raise "Failed to release queue"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end
    alias release_queue queue_release

    # Disable a queue
    #
    # @param name [String] The queue name
    # @return The result of the method call.
    def queue_disable(name, scope: $openc3_scope)
      response = $api_server.request('post', "/openc3-api/queues/#{name}/disable", scope: scope)
      if response.nil? || response.status != 200
        raise "Failed to disable queue"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    # Delete a queue
    #
    # @param name [String] The queue name
    # @return The result of the method call.
    def queue_destroy(name, scope: $openc3_scope)
      response = $api_server.request('delete', "/openc3-api/queues/#{name}", scope: scope)
      if response.nil? || response.status != 200
        raise "Failed to destroy queue"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end
    alias queue_delete queue_destroy

    # Push a command to a queue
    #
    # @param name [String] The queue name
    # @param command [String] The command to add to the queue
    # @return The result of the method call.
    def queue_push(name, command, scope: $openc3_scope)
      data = { command: command }
      response = $api_server.request('post', "/openc3-api/queues/#{name}/push", data: data, json: true, scope: scope)
      if response.nil? || response.status != 200
        raise "Failed to push command to queue"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    # Pop a command from a queue
    #
    # @param name [String] The queue name
    # @return The result of the method call.
    def queue_pop(name, scope: $openc3_scope)
      response = $api_server.request('post', "/openc3-api/queues/#{name}/pop", scope: scope)
      if response.nil? || response.status != 200
        raise "Failed to pop command from queue"
      end
      result = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      if result['command']
        return result['command']
      else
        return nil
      end
    end
  end
end