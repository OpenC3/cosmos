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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

module OpenC3
  module Script
    private

    def critical_cmd_status(uuid, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/criticalcmd/status/#{uuid}"
        response = $api_server.request('get', endpoint, scope: scope)
        if response.nil? || response.status != 200
          raise "Unexpected response to critical_cmd_status: #{response.inspect}"
        end
        result = JSON.parse(response.body)
        return result['status']
      rescue => error
        raise "critical_cmd_status failed due to #{error.formatted}"
      end
    end

    def critical_cmd_approve(uuid, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/criticalcmd/approve/#{uuid}"
        response = $api_server.request('post', endpoint, :json => true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "critical_cmd_approve error: #{parsed['error']}"
          else
            raise "critical_cmd_approve failed"
          end
        end
        return
      rescue => error
        raise "critical_cmd_approve failed due to #{error.formatted}"
      end
    end

    def critical_cmd_reject(uuid, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/criticalcmd/reject/#{uuid}"
        response = $api_server.request('post', endpoint, :json => true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "critical_cmd_reject error: #{parsed['error']}"
          else
            raise "critical_cmd_reject failed"
          end
        end
        return
      rescue => error
        raise "critical_cmd_reject failed due to #{error.formatted}"
      end
    end

    def critical_cmd_can_approve(uuid, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/criticalcmd/canapprove/#{uuid}"
        response = $api_server.request('get', endpoint, scope: scope)
        if response.nil? || response.status != 200
          raise "Unexpected response to critical_cmd_can_approve: #{response.inspect}"
        end
        result = JSON.parse(response.body)
        if result['status'] == 'ok'
          return true
        else
          return false
        end
      rescue => error
        raise "critical_cmd_can_approve failed due to #{error.formatted}"
      end
    end
  end
end
