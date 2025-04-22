# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

class RunningScriptController < ApplicationController
  def index
    return unless authorization('script_view')
    render json: OpenC3::ScriptStatusModel.all(scope: params[:scope], type: 'running')
  end

  def show
    return unless authorization('script_view')
    running_script = OpenC3::ScriptStatusModel.get(name: params[:id], scope: params[:scope])
    if running_script
      render json: running_script
    else
      head :not_found
    end
  end

  def stop
    running_script = OpenC3::ScriptStatusModel.get(name: params[:id], scope: params[:scope])
    if running_script
      target_name = running_script['name'].split('/')[0]
      return unless authorization('script_run', target_name: target_name)
      running_script_publish("cmd-running-script-channel:#{params[:id]}", "stop")
      OpenC3::Logger.info("Script stopped: #{running_script}", scope: params[:scope], user: username())
      head :ok
    else
      head :not_found
    end
  end

  def delete
    running_script = OpenC3::ScriptStatusModel.get_model(name: params[:id], scope: params[:scope])
    if running_script
      target_name = running_script.name.split('/')[0]
      pid = running_script.pid.to_i
      return unless authorization('script_run', target_name: target_name)
      running_script_publish("cmd-running-script-channel:#{params[:id]}", "stop")

      # Give the process 1 second to stop from stop message
      stopped = false
      start_time = Time.now
      while Time.now - start_time < 1.0
        begin
          Process.getpgid(pid.to_i)
          sleep 0.1
        rescue Errno::ESRCH
          stopped = true
          break
        end
      end

      # If the process is still running
      # Send a SIGINT and give it one more second
      if not stopped
        Process.kill("SIGINT", pid)
        start_time = Time.now
        while Time.now - start_time < 1.0
          begin
            Process.getpgid(pid.to_i)
            sleep 0.1
          rescue Errno::ESRCH
            stopped = true
            break
          end
        end
      end

      # If the process is still running send a hard kill signal
      if not stopped
        Process.kill("SIGKILL", pid)

        # Also need to cleanup the status model in this case because the process will not die and cleanup
        running_script.state = "killed"
        running_script.update
      end

      OpenC3::Logger.info("Script deleted: #{running_script.name}", scope: params[:scope], user: username())
      head :ok
    else
      head :not_found
    end
  end

  def pause
    running_script = OpenC3::ScriptStatusModel.get(name: params[:id], scope: params[:scope])
    if running_script
      target_name = running_script['name'].split('/')[0]
      return unless authorization('script_run', target_name: target_name)
      running_script_publish("cmd-running-script-channel:#{params[:id]}", "pause")
      OpenC3::Logger.info("Script paused: #{running_script}", scope: params[:scope], user: username())
      head :ok
    else
      head :not_found
    end
  end

  def retry
    running_script = OpenC3::ScriptStatusModel.get(name: params[:id], scope: params[:scope])
    if running_script
      target_name = running_script['name'].split('/')[0]
      return unless authorization('script_run', target_name: target_name)
      running_script_publish("cmd-running-script-channel:#{params[:id]}", "retry")
      OpenC3::Logger.info("Script retried: #{running_script}", scope: params[:scope], user: username())
      head :ok
    else
      head :not_found
    end
  end

  def go
    running_script = OpenC3::ScriptStatusModel.get(name: params[:id], scope: params[:scope])
    if running_script
      target_name = running_script['name'].split('/')[0]
      return unless authorization('script_run', target_name: target_name)
      running_script_publish("cmd-running-script-channel:#{params[:id]}", "go")
      OpenC3::Logger.info("Script resumed: #{running_script}", scope: params[:scope], user: username())
      head :ok
    else
      head :not_found
    end
  end

  def step
    running_script = OpenC3::ScriptStatusModel.get(name: params[:id], scope: params[:scope])
    if running_script
      target_name = running_script['name'].split('/')[0]
      return unless authorization('script_run', target_name: target_name)
      running_script_publish("cmd-running-script-channel:#{params[:id]}", "step")
      OpenC3::Logger.info("Script stepped: #{running_script}", scope: params[:scope], user: username())
      head :ok
    else
      head :not_found
    end
  end

  def prompt
    running_script = OpenC3::ScriptStatusModel.get(name: params[:id], scope: params[:scope])
    if running_script
      target_name = running_script['name'].split('/')[0]
      return unless authorization('script_run', target_name: target_name)
      if params[:password]
        # TODO: ActionCable is logging this ... probably shouldn't
        running_script_publish("cmd-running-script-channel:#{params[:id]}", { method: params[:method], password: params[:password], prompt_id: params[:prompt_id] })
      elsif params[:multiple]
        running_script_publish("cmd-running-script-channel:#{params[:id]}", { method: params[:method], multiple: JSON.generate(params[:answer]), prompt_id: params[:prompt_id] })
      else
        running_script_publish("cmd-running-script-channel:#{params[:id]}", { method: params[:method], answer: params[:answer], prompt_id: params[:prompt_id] })
      end
      OpenC3::Logger.info("Script prompt action #{params[:method]}: #{running_script}", scope: params[:scope], user: username())
      head :ok
    else
      head :not_found
    end
  end

  def method
    running_script = OpenC3::ScriptStatusModel.get(name: params[:id], scope: params[:scope])
    if running_script
      target_name = running_script['name'].split('/')[0]
      return unless authorization('script_run', target_name: target_name)
      running_script_publish("cmd-running-script-channel:#{params[:id]}", { method: params[:method], args: params[:args], prompt_id: params[:prompt_id] })
      OpenC3::Logger.info("Script method action #{params[:method]}: #{running_script}", scope: params[:scope], user: username())
      head :ok
    else
      head :not_found
    end
  end
end
