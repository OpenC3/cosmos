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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

module OpenC3
  module Script
    private

    # Group Methods
    def autonomic_group_list(scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/group"
        response = $api_server.request('get', endpoint, scope: scope)
        if response.nil? || response.status != 200
          raise "Unexpected response to autonomic_group_list: #{response.inspect}"
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_group_list failed due to #{error.formatted}"
      end
    end

    def autonomic_group_create(name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/group"
        response = $api_server.request('post', endpoint, data: { name: name }, json: true, scope: scope)
        if response.nil? || response.status != 201
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_group_create error: #{parsed['message']}"
          else
            raise "autonomic_group_create failed"
          end
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_group_create failed due to #{error.formatted}"
      end
    end

    def autonomic_group_show(name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/group/#{name}"
        response = $api_server.request('get', endpoint, scope: scope)
        if response.nil? || response.status != 200
          raise "Unexpected response to autonomic_group_show: #{response.inspect}"
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_group_show failed due to #{error.formatted}"
      end
    end

    def autonomic_group_destroy(name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/group/#{name}"
        response = $api_server.request('delete', endpoint, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_group_destroy error: #{parsed['error']}"
          else
            raise "autonomic_group_destroy failed"
          end
        end
        return
      rescue => error
        raise "autonomic_group_destroy failed due to #{error.formatted}"
      end
    end

    # Trigger Methods
    def autonomic_trigger_list(group: 'DEFAULT', scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/#{group}/trigger"
        response = $api_server.request('get', endpoint, scope: scope)
        if response.nil? || response.status != 200
          raise "Unexpected response to autonomic_trigger_list: #{response.inspect}"
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_trigger_list failed due to #{error.formatted}"
      end
    end

    def autonomic_trigger_create(left:, operator:, right:, group: 'DEFAULT', scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/#{group}/trigger"
        config = {
          'group' => group,
          'left' => left,
          'operator' => operator,
          'right' => right
        }
        response = $api_server.request('post', endpoint, data: config, json: true, scope: scope)
        if response.nil? || response.status != 201
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_trigger_create error: #{parsed['error']}"
          else
            raise "autonomic_trigger_create failed"
          end
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_trigger_create failed due to #{error.formatted}"
      end
    end

    def autonomic_trigger_show(name, group: 'DEFAULT', scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/#{group}/trigger/#{name}"
        response = $api_server.request('get', endpoint, scope: scope)
        if response.nil? || response.status != 200
          raise "Unexpected response to autonomic_trigger_show: #{response.inspect}"
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_trigger_show failed due to #{error.formatted}"
      end
    end

    def autonomic_trigger_enable(name, group: 'DEFAULT', scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/#{group}/trigger/#{name}/enable"
        response = $api_server.request('post', endpoint, json: true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_trigger_enable error: #{parsed['error']}"
          else
            raise "autonomic_trigger_enable failed"
          end
        end
        return
      rescue => error
        raise "autonomic_trigger_enable failed due to #{error.formatted}"
      end
    end

    def autonomic_trigger_disable(name, group: 'DEFAULT', scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/#{group}/trigger/#{name}/disable"
        response = $api_server.request('post', endpoint, json: true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_trigger_disable error: #{parsed['error']}"
          else
            raise "autonomic_trigger_disable failed"
          end
        end
        return
      rescue => error
        raise "autonomic_trigger_disable failed due to #{error.formatted}"
      end
    end

    def autonomic_trigger_update(name, group: 'DEFAULT', left: nil, operator: nil, right: nil, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/#{group}/trigger/#{name}"
        config = {}
        config['left'] = left if left
        config['operator'] = operator if operator
        config['right'] = right if right
        response = $api_server.request('put', endpoint, data: config, json: true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_trigger_update error: #{parsed['error']}"
          else
            raise "autonomic_trigger_update failed"
          end
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_trigger_update failed due to #{error.formatted}"
      end
    end

    def autonomic_trigger_destroy(name, group: 'DEFAULT', scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/#{group}/trigger/#{name}"
        response = $api_server.request('delete', endpoint, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_trigger_destroy error: #{parsed['error']}"
          else
            raise "autonomic_trigger_destroy failed"
          end
        end
        return
      rescue => error
        raise "autonomic_trigger_destroy failed due to #{error.formatted}"
      end
    end

    # Reaction Methods
    def autonomic_reaction_list(scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/reaction"
        response = $api_server.request('get', endpoint, scope: scope)
        if response.nil? || response.status != 200
          raise "Unexpected response to autonomic_reaction_list: #{response.inspect}"
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_reaction_list failed due to #{error.formatted}"
      end
    end

    def autonomic_reaction_create(triggers:, actions:, trigger_level: 'EDGE', snooze: 0, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/reaction"
        config = {
          'triggers' => triggers,
          'actions' => actions,
          'trigger_level' => trigger_level,
          'snooze' => snooze,
        }
        response = $api_server.request('post', endpoint, data: config, json: true, scope: scope)
        if response.nil? || response.status != 201
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_reaction_create error: #{parsed['error']}"
          else
            raise "autonomic_reaction_create failed"
          end
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_reaction_create failed due to #{error.formatted}"
      end
    end

    def autonomic_reaction_show(name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/reaction/#{name}"
        response = $api_server.request('get', endpoint, scope: scope)
        if response.nil? || response.status != 200
          raise "Unexpected response to autonomic_reaction_show: #{response.inspect}"
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_reaction_show failed due to #{error.formatted}"
      end
    end

    def autonomic_reaction_enable(name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/reaction/#{name}/enable"
        response = $api_server.request('post', endpoint, json: true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_reaction_enable error: #{parsed['error']}"
          else
            raise "autonomic_reaction_enable failed"
          end
        end
        return
      rescue => error
        raise "autonomic_reaction_enable failed due to #{error.formatted}"
      end
    end

    def autonomic_reaction_disable(name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/reaction/#{name}/disable"
        response = $api_server.request('post', endpoint, json: true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_reaction_disable error: #{parsed['error']}"
          else
            raise "autonomic_reaction_disable failed"
          end
        end
        return
      rescue => error
        raise "autonomic_reaction_disable failed due to #{error.formatted}"
      end
    end

    def autonomic_reaction_execute(name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/reaction/#{name}/execute"
        response = $api_server.request('post', endpoint, json: true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_reaction_execute error: #{parsed['error']}"
          else
            raise "autonomic_reaction_execute failed"
          end
        end
        return
      rescue => error
        raise "autonomic_reaction_execute failed due to #{error.formatted}"
      end
    end

    def autonomic_reaction_update(name, triggers: nil, actions: nil, trigger_level: nil, snooze: nil, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/reaction/#{name}"
        config = {}
        config['triggers'] = triggers if triggers
        config['actions'] = actions if actions
        config['trigger_level'] = trigger_level if trigger_level
        config['snooze'] = snooze if snooze
        response = $api_server.request('put', endpoint, data: config, json: true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_reaction_update error: #{parsed['error']}"
          else
            raise "autonomic_reaction_update failed"
          end
        end
        return JSON.parse(response.body)
      rescue => error
        raise "autonomic_reaction_update failed due to #{error.formatted}"
      end
    end

    def autonomic_reaction_destroy(name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/autonomic/reaction/#{name}"
        response = $api_server.request('delete', endpoint, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response.body)
            raise "autonomic_reaction_destroy error: #{parsed['error']}"
          else
            raise "autonomic_reaction_destroy failed"
          end
        end
        return
      rescue => error
        raise "autonomic_reaction_destroy failed due to #{error.formatted}"
      end
    end
  end
end
