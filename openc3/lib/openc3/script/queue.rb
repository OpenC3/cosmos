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

    # Helper method that makes the request and parses the response
    def _make_request(action:, verb:, uri:, scope:)
      response = $api_server.request(verb, uri, scope: scope)
      if response.nil?
        raise "Failed to #{action} queue. No response from server."
      elsif response.status != 200 and response.status != 201
        result = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
        raise "Failed to #{action} queue due to #{result['message']}"
      end
      return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end

    def queue_all(scope: $openc3_scope)
      return _make_request(action: 'index', verb: 'get', uri: "/openc3-api/queues", scope: scope)
    end

    def queue_get(name, scope: $openc3_scope)
      return _make_request(action: 'get', verb: 'get', uri: "/openc3-api/queues/#{name}", scope: scope)
    end

    def queue_list(name, scope: $openc3_scope)
      return _make_request(action: 'list', verb: 'get', uri: "/openc3-api/queues/#{name}/list", scope: scope)
    end

    def queue_create(name, scope: $openc3_scope)
      return _make_request(action: 'create', verb: 'post', uri: "/openc3-api/queues/#{name}", scope: scope)
    end

    def queue_hold(name, scope: $openc3_scope)
      return _make_request(action: 'hold', verb: 'post', uri: "/openc3-api/queues/#{name}/hold", scope: scope)
    end

    def queue_release(name, scope: $openc3_scope)
      return _make_request(action: 'release', verb: 'post', uri: "/openc3-api/queues/#{name}/release", scope: scope)
    end

    def queue_disable(name, scope: $openc3_scope)
      return _make_request(action: 'disable', verb: 'post', uri: "/openc3-api/queues/#{name}/disable", scope: scope)
    end

    def queue_delete(name, scope: $openc3_scope)
      return _make_request(action: 'delete', verb: 'delete', uri: "/openc3-api/queues/#{name}", scope: scope)
    end
    alias queue_destroy queue_delete
  end
end
