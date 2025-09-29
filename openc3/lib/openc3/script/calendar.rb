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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'date'

module OpenC3
  module Script

    private

    def list_timelines(scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/timeline", scope: scope)
      return _cal_handle_response(response, 'Failed to list timelines')
    end

    def create_timeline(name, color: nil, scope: $openc3_scope)
      data = {}
      data['name'] = name
      data['color'] = color if color
      response = $api_server.request('post', "/openc3-api/timeline", data: data, json: true, scope: scope)
      return _cal_handle_response(response, 'Failed to create timeline')
    end

    def get_timeline(name, scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/timeline/#{name}", scope: scope)
      return _cal_handle_response(response, 'Failed to get timeline')
    end

    def set_timeline_color(name, color, scope: $openc3_scope)
      post_data = {}
      post_data['color'] = color
      response = $api_server.request('post', "/openc3-api/timeline/#{name}/color", data: post_data, json: true, scope: scope)
      return _cal_handle_response(response, 'Failed to set timeline color')
    end

    def delete_timeline(name, force: false, scope: $openc3_scope)
      url = "/openc3-api/timeline/#{name}"
      if force
        url += "?force=true"
      end
      response = $api_server.request('delete', url, scope: scope)
      return _cal_handle_response(response, 'Failed to delete timeline')
    end

    def create_timeline_activity(name, kind:, start:, stop:, data: {}, scope: $openc3_scope)
      kind = kind.to_s.downcase()
      kinds = %w(command script reserve)
      unless kinds.include?(kind)
        raise "Unknown kind: #{kind}. Must be one of #{kinds.join(', ')}."
      end
      post_data = {}
      post_data['start'] = start.to_datetime.iso8601
      post_data['stop'] = stop.to_datetime.iso8601
      post_data['kind'] = kind
      post_data['data'] = data
      response = $api_server.request('post', "/openc3-api/timeline/#{name}/activities", data: post_data, json: true, scope: scope)
      return _cal_handle_response(response, 'Failed to create timeline activity')
    end

    def get_timeline_activity(name, start, uuid, scope: $openc3_scope)
      response = $api_server.request('get', "/openc3-api/timeline/#{name}/activity/#{start}/#{uuid}", scope: scope)
      return _cal_handle_response(response, 'Failed to get timeline activity')
    end

    def get_timeline_activities(name, start: nil, stop: nil, limit: nil, scope: $openc3_scope)
      url = "/openc3-api/timeline/#{name}/activities"
      if start and stop
        url += "?start=#{start}&stop=#{stop}"
      end
      if limit
        url += "?limit=#{limit}"
      end
      response = $api_server.request('get', url, scope: scope)
      return _cal_handle_response(response, 'Failed to get timeline activities')
    end

    def delete_timeline_activity(name, start, uuid, scope: $openc3_scope)
      response = $api_server.request('delete', "/openc3-api/timeline/#{name}/activity/#{start}/#{uuid}", scope: scope)
      return _cal_handle_response(response, 'Failed to delete timeline activity')
    end

    # Helper method to handle the response
    def _cal_handle_response(response, error_message)
      return nil if response.nil?
      if response.status >= 400
        result = JSON.parse(response.body, allow_nan: true, create_additions: true)
        raise "#{error_message} due to #{result['message']}"
      end
      return JSON.parse(response.body, allow_nan: true, create_additions: true)
    end
  end
end
