# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

module OpenC3
  module Script
    private

    def _script_response_error(response, message, scope: $openc3_scope)
      if response
        raise "#{message} (#{response.code}): #{response.body}"
      else
        raise "#{message}: No Response"
      end
    end

    def script_list(scope: $openc3_scope)
      endpoint = "/script-api/scripts"
      response = $script_runner_api_server.request('get', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Script list request failed", scope: scope)
      else
        return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      end
    end

    def script_syntax_check(script, scope: $openc3_scope)
      endpoint = "/script-api/scripts/syntax"
      response = $script_runner_api_server.request('post', endpoint, :data => script, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Script syntax check request failed", scope: scope)
      else
        result = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
        if result['title'] == "Syntax Check Successful"
          return true
        else
          raise result.inspect
        end
      end
    end

    def script_body(filename, scope: $openc3_scope)
      endpoint = "/script-api/scripts/#{filename}"
      response = $script_runner_api_server.request('get', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Failed to get #{filename}", scope: scope)
      else
        script = response.body
        return script
      end
    end

    def script_run(filename, disconnect: false, scope: $openc3_scope)
      if disconnect
        endpoint = "/script-api/scripts/#{filename}/run/disconnect"
      else
        endpoint = "/script-api/scripts/#{filename}/run"
      end
      response = $script_runner_api_server.request('post', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Failed to run #{filename}", scope: scope)
      else
        script_id = Integer(response.body)
        return script_id
      end
    end

    def script_delete(filename, scope: $openc3_scope)
      endpoint = "/script-api/scripts/#{filename}/delete"
      response = $script_runner_api_server.request('post', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Failed to delete #{filename}", scope: scope)
      else
        return true
      end
    end

    def script_lock(filename, scope: $openc3_scope)
      endpoint = "/script-api/scripts/#{filename}/lock"
      response = $script_runner_api_server.request('post', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Failed to lock #{filename}", scope: scope)
      else
        return true
      end
    end

    def script_unlock(filename, scope: $openc3_scope)
      endpoint = "/script-api/scripts/#{filename}/unlock"
      response = $script_runner_api_server.request('post', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Failed to unlock #{filename}", scope: scope)
      else
        return true
      end
    end

    def script_instrumented(filename, script, scope: $openc3_scope)
      endpoint = "/script-api/scripts/#{filename}/instrumented"
      response = $script_runner_api_server.request('post', endpoint, :data => script, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Script instrumented request failed", scope: scope)
      else
        result = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
        if result['title'] == "Instrumented Script"
          parsed = JSON.parse(result['description'], :allow_nan => true, :create_additions => true)
          return parsed.join("\n")
        else
          raise result.inspect
        end
      end
    end

    def script_create(filename, script, breakpoints = [], scope: $openc3_scope)
      endpoint = "/script-api/scripts/#{filename}"
      response = $script_runner_api_server.request('post', endpoint, :data => {text: script, breakpoints: breakpoints}, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Script create request failed", scope: scope)
      else
        return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      end
    end

    def script_delete_all_breakpoints(scope: $openc3_scope)
      endpoint = "/script-api/breakpoints/delete/all"
      response = $script_runner_api_server.request('delete', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Script delete all breakpoints failed", scope: scope)
      else
        return true
      end
    end

    def running_script_list(scope: $openc3_scope)
      endpoint = "/script-api/running-script"
      response = $script_runner_api_server.request('get', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Running script list request failed", scope: scope)
      else
        return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      end
    end

    def running_script_get(id, scope: $openc3_scope)
      endpoint = "/script-api/running-script/#{id}"
      response = $script_runner_api_server.request('get', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Running script show request failed", scope: scope)
      else
        return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      end
    end

    def _running_script_action(id, action_name, scope: $openc3_scope)
      endpoint = "/script-api/running-script/#{id}/#{action_name}"
      response = $script_runner_api_server.request('post', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Running script #{action_name} request failed", scope: scope)
      else
        return true
      end
    end

    def running_script_stop(id, scope: $openc3_scope)
      _running_script_action(id, 'stop', scope: scope)
    end

    def running_script_pause(id, scope: $openc3_scope)
      _running_script_action(id, 'pause', scope: scope)
    end

    def running_script_retry(id, scope: $openc3_scope)
      _running_script_action(id, 'retry', scope: scope)
    end

    def running_script_go(id, scope: $openc3_scope)
      _running_script_action(id, 'go', scope: scope)
    end

    def running_script_step(id, scope: $openc3_scope)
      _running_script_action(id, 'step', scope: scope)
    end

    def running_script_delete(id, scope: $openc3_scope)
      _running_script_action(id, 'delete', scope: scope)
    end

    def running_script_backtrace(id, scope: $openc3_scope)
      _running_script_action(id, 'backtrace', scope: scope)
    end

    def running_script_debug(id, debug_code, scope: $openc3_scope)
      endpoint = "/script-api/running-script/#{id}/debug"
      response = $script_runner_api_server.request('post', endpoint, data: {'args' => debug_code}, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Running script debug request failed", scope: scope)
      else
        return true
      end
    end

    def running_script_prompt(id, method_name, answer, prompt_id, password: nil, scope: $openc3_scope)
      endpoint = "/script-api/running-script/#{id}/prompt"
      if password
        response = $script_runner_api_server.request('post', endpoint, data: {'method' => method_name, 'answer' => answer, 'prompt_id' => prompt_id, 'password' => password}, scope: scope)
      else
        response = $script_runner_api_server.request('post', endpoint, data: {'method' => method_name, 'answer' => answer, 'prompt_id' => prompt_id}, scope: scope)
      end
      if response.nil? || response.code != 200
        _script_response_error(response, "Running script prompt request failed", scope: scope)
      else
        return true
      end
    end

    def completed_script_list(scope: $openc3_scope)
      endpoint = "/script-api/completed-scripts"
      response = $script_runner_api_server.request('get', endpoint, scope: scope)
      if response.nil? || response.code != 200
        _script_response_error(response, "Completed script list request failed", scope: scope)
      else
        return JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      end
    end

  end
end
