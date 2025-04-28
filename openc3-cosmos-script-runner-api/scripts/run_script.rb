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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

start_time = Time.now
require 'openc3'
require 'openc3/config/config_parser'
require 'openc3/utilities/store'
require 'openc3/utilities/bucket'
require 'json'
require '../app/models/script'
require '../app/models/running_script'

# Load the bucket client code to ensure we authenticate outside ENV vars
OpenC3::Bucket.getClient()
# Clear the ENV vars for security purposes
ENV['OPENC3_BUCKET_USERNAME'] = nil
ENV['OPENC3_BUCKET_PASSWORD'] = nil

# Preload Store and remove Redis secrets from ENV
OpenC3::Store.instance
OpenC3::EphemeralStore.instance
ENV['OPENC3_REDIS_USERNAME'] = nil
ENV['OPENC3_REDIS_PASSWORD'] = nil

id = ARGV[0]
scope = ARGV[1]
script_status = OpenC3::ScriptStatusModel.get_model(name: id, scope: scope)
raise "Unknown script id #{id} for scope #{scope}" unless script_status
raise "Script in unexpected state: #{script_status.state}" unless script_status.state == 'spawning'

startup_time = Time.now - start_time
path = File.join(ENV['OPENC3_CONFIG_BUCKET'], scope, 'targets', script_status.filename)

def run_script_log(id, message, color = 'BLACK', message_log = true)
  line_to_write = Time.now.sys.formatted + " (SCRIPTRUNNER): " + message
  RunningScript.message_log.write(line_to_write + "\n", true) if message_log
  running_script_anycable_publish("running-script-channel:#{id}", { type: :output, line: line_to_write, color: color })
end

begin
  # Ensure usage of Logger in scripts will show Script Runner as the source
  OpenC3::Logger.microservice_name = "Script Runner"
  running_script = RunningScript.new(script_status)
  run_script_log(id, "Script #{path} spawned in #{startup_time} seconds <ruby #{RUBY_VERSION}>", 'BLACK')

  # Log any overrides if present
  overrides = get_overrides()
  unless overrides.empty?
    message = "The following overrides were present:"
    overrides.each do |o|
      message << "\n#{o['target_name']} #{o['packet_name']} #{o['item_name']} = #{o['value']}, type: :#{o['value_type']}"
    end
    run_script_log(id, message, 'YELLOW')
  end

  # Start the script in another thread
  if script_status.suite_runner
    script_status.suite_runner = JSON.parse(script_status.suite_runner, :allow_nan => true, :create_additions => true) # Convert to hash
    running_script.parse_options(script_status.suite_runner['options'])
    if script_status.suite_runner['script']
      running_script.run_text("OpenC3::SuiteRunner.start(#{script_status.suite_runner['suite']}, #{script_status.suite_runner['group']}, '#{script_status.suite_runner['script']}')", initial_filename: "SCRIPTRUNNER")
    elsif script_status.suite_runner['group']
      running_script.run_text("OpenC3::SuiteRunner.#{script_status.suite_runner['method']}(#{script_status.suite_runner['suite']}, #{script_status.suite_runner['group']})", initial_filename: "SCRIPTRUNNER")
    else
      running_script.run_text("OpenC3::SuiteRunner.#{script_status.suite_runner['method']}(#{script_status.suite_runner['suite']})", initial_filename: "SCRIPTRUNNER")
    end
  else
    running_script.run
  end

  # Notify frontend of number of running scripts in this scope
  running = OpenC3::ScriptStatusModel.all(scope: scope, type: "running")
  running_script_anycable_publish("all-scripts-channel", { type: :start, filename: script_status.filename, active_scripts: running.length, scope: scope })

  # Subscribe to the pub sub channel for this script
  # Note: SCRIPT_API = 'script-api' in running_script.rb
  redis = OpenC3::Store.instance.build_redis
  redis.subscribe([SCRIPT_API, "cmd-running-script-channel:#{id}"].compact.join(":")) do |on|
    on.message do |_channel, msg|
      parsed_cmd = JSON.parse(msg, :allow_nan => true, :create_additions => true)
      run_script_log(id, "Script #{path} received command: #{msg}") unless parsed_cmd == "shutdown" or parsed_cmd["method"]
      case parsed_cmd
      when "go"
        running_script.go
      when "pause"
        running_script.pause
      when "retry"
        running_script.retry_needed
      when "step"
        running_script.step
      when "stop"
        running_script.stop
        redis.unsubscribe
      when "shutdown"
        redis.unsubscribe
      else
        if parsed_cmd["method"]
          case parsed_cmd["method"]
          # This list matches the list in running_script.rb:44
          when "ask", "ask_string", "message_box", "vertical_message_box", "combo_box", "prompt", "prompt_for_hazardous",
            "prompt_for_critical_cmd", "metadata_input", "open_file_dialog", "open_files_dialog"
            unless running_script.prompt_id.nil?
              if running_script.prompt_id == parsed_cmd["prompt_id"]
                if parsed_cmd["password"]
                  running_script.user_input = parsed_cmd["password"].to_s
                elsif parsed_cmd["multiple"]
                  running_script.user_input = JSON.parse(parsed_cmd["multiple"])
                  run_script_log(id, "Multiple input: #{running_script.user_input}")
                elsif parsed_cmd["method"].include?('open_file')
                  running_script.user_input = parsed_cmd["answer"]
                  run_script_log(id, "File(s): #{running_script.user_input}")
                else
                  running_script.user_input = OpenC3::ConfigParser.handle_true_false(parsed_cmd["answer"].to_s)
                  if parsed_cmd["method"] == 'ask'
                    running_script.user_input = running_script.user_input.convert_to_value
                  end
                  run_script_log(id, "User input: #{running_script.user_input}")
                end
                running_script.continue
              else
                run_script_log(id, "INFO: Received answer for prompt #{parsed_cmd["prompt_id"]} when looking for #{running_script.prompt_id}.")
              end
            else
              run_script_log(id, "INFO: Unexpectedly received answer for unknown prompt #{parsed_cmd["prompt_id"]}.")
            end
          when "backtrace"
            running_script_anycable_publish("running-script-channel:#{id}", { type: :script, method: :backtrace, args: running_script.current_backtrace })
          when "debug"
            run_script_log(id, "DEBUG: #{parsed_cmd["args"]}") # Log what we were passed
            running_script.debug(parsed_cmd["args"]) # debug() logs the output of the command
          else
            run_script_log(id, "ERROR: Script method not handled: #{parsed_cmd["method"]}", 'RED')
          end
        else
          run_script_log(id, "ERROR: Script command not handled: #{msg}", 'RED')
        end
      end
    end
  end
rescue Exception => e
  run_script_log(id, e.formatted, 'RED')
  script_status.state = 'crashed'
  script_status.errors ||= []
  script_status.errors << e.formatted
  script_status.update
ensure
  begin
    # Dump all queued redis messages
    OpenC3::StoreQueued.instance.shutdown

    # Ensure the script is marked as complete with an end time
    unless script_status.is_complete?()
      script_status.state = 'completed'
    end
    script_status.end_time = Time.now.utc.iso8601
    script_status.update

    running = OpenC3::ScriptStatusModel.all(scope: scope, type: "running")

    # Inform script channel it is complete
    running_script_anycable_publish("running-script-channel:#{id}", { type: :complete, state: script_status.state })

    # Inform frontend of number of running scripts in this scope
    running_script_anycable_publish("all-scripts-channel", { type: :complete, filename: script_status.filename, active_scripts: running.length, scope: scope })
  ensure
    running_script.stop_message_log if running_script
  end
end
