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

import os
import time
import json
import sys
from datetime import datetime
from openc3.utilities.bucket import Bucket
from openc3.utilities.store import Store, EphemeralStore
from openc3.environment import *
import traceback

start_time = time.time()

from running_script import RunningScript

# # Load the bucket client code to ensure we authenticate outside ENV vars
Bucket.getClient()

del os.environ["OPENC3_BUCKET_USERNAME"]
del os.environ["OPENC3_BUCKET_PASSWORD"]
os.unsetenv("OPENC3_BUCKET_USERNAME")
os.unsetenv("OPENC3_BUCKET_PASSWORD")

# # Preload Store and remove Redis secrets from ENV
Store.instance()
EphemeralStore.instance()

del os.environ["OPENC3_REDIS_USERNAME"]
del os.environ["OPENC3_REDIS_PASSWORD"]
os.unsetenv("OPENC3_REDIS_USERNAME")
os.unsetenv("OPENC3_REDIS_PASSWORD")

id = sys.argv[1]
script_data = Store.get(f"running-script:{id}")
if script_data:
    script = json.loads(script_data)
else:
    raise RuntimeError(f"RunningScript with id {id} not found")
scope = script["scope"]
name = script["name"]
disconnect = script["disconnect"]
startup_time = time.time() - start_time
path = os.path.join(OPENC3_CONFIG_BUCKET, scope, "targets", name)


def run_script_log(id, message, color="BLACK", message_log=True):
    line_to_write = datetime.now().isoformat(" ") + " (SCRIPTRUNNER): " + message
    if message_log:
        RunningScript.message_log().write(line_to_write + "\n", True)
    Store.publish(
        f"script-api:running-script-channel:{id}",
        json.dumps({"type": "output", "line": line_to_write, "color": color}),
    )


running_script = None
try:
    running_script = RunningScript(id, scope, name, disconnect)
    run_script_log(
        id,
        f"Script {path} spawned in {startup_time} seconds <python {sys.version}>",
        "BLACK",
    )

    # TODO
    # overrides = get_overrides()
    # unless overrides.empty?
    #   message = "The following overrides were present:"
    #   overrides.each do |o|
    #     message << "\n#{o['target_name']} #{o['packet_name']} #{o['item_name']} = #{o['value']}, type: :#{o['value_type']}"
    #   end
    #   run_script_log(id, message, 'YELLOW')
    # end

    # TODO
    # if script['suite_runner']
    #   script['suite_runner'] = JSON.parse(script['suite_runner'], :allow_nan => true, :create_additions => true) # Convert to hash
    #   running_script.parse_options(script['suite_runner']['options'])
    #   if script['suite_runner']['script']
    #     running_script.run_text("OpenC3::SuiteRunner.start(#{script['suite_runner']['suite']}, #{script['suite_runner']['group']}, '#{script['suite_runner']['script']}')")
    #   elsif script['suite_runner']['group']
    #     running_script.run_text("OpenC3::SuiteRunner.#{script['suite_runner']['method']}(#{script['suite_runner']['suite']}, #{script['suite_runner']['group']})")
    #   else
    #     running_script.run_text("OpenC3::SuiteRunner.#{script['suite_runner']['method']}(#{script['suite_runner']['suite']})")
    #   end
    # else
    running_script.run()

    # Subscribe to the ActionCable generated topic which is namedspaced with channel_prefix
    # (defined in cable.yml) and then the channel stream. This isn't typically how you see these
    # topics used in the Rails ActionCable documentation but this is what is happening under the
    # scenes in ActionCable. Throughout the rest of the code we use ActionCable to broadcast
    #   e.g. ActionCable.server.broadcast("running-script-channel:#{@id}", ...)
    redis = Store.instance().build_redis()
    p = redis.pubsub(ignore_subscribe_messages=True)
    p.subscribe(f"script-api:cmd-running-script-channel:{id}")
    for msg in p.listen():
        parsed_cmd = json.loads(msg["data"])
        if not parsed_cmd == "shutdown" or (
            type(parsed_cmd) is dict and parsed_cmd["method"]
        ):
            run_script_log(id, f"Script {path} received command: {msg['data']}")
        match parsed_cmd:
            case "go":
                running_script.do_go()
            case "pause":
                running_script.do_pause()
            case "retry":
                running_script.do_retry_needed()
            case "step":
                running_script.do_step()
            case "stop":
                running_script.do_stop()
                p.unsubscribe()
            case "shutdown":
                p.unsubscribe()
            case _:
                if type(parsed_cmd) is dict and parsed_cmd["method"]:
                    match parsed_cmd["method"]:
                        # This list matches the list in running_script.py:102
                        case "ask" | "ask_string" | "message_box" | "vertical_message_box" | "combo_box" | "prompt" | "prompt_for_hazardous" | "metadata_input" | "open_file_dialog" | "open_files_dialog":
                            if not running_script.prompt_id == None:
                                if running_script.prompt_id == parsed_cmd["prompt_id"]:
                                    if parsed_cmd["password"]:
                                        running_script.user_input = str(
                                            parsed_cmd["password"]
                                        )
                                    elif parsed_cmd["multiple"]:
                                        running_script.user_input = json.loads(
                                            parsed_cmd["multiple"]
                                        )
                                        run_script_log(
                                            id,
                                            f"Multiple input: {running_script.user_input}",
                                        )
                                    elif "open_file" in parsed_cmd["method"]:
                                        running_script.user_input = parsed_cmd["answer"]
                                        run_script_log(
                                            id, f"File(s): {running_script.user_input}"
                                        )
                                    else:
                                        # TODO convert_to_value for true/false/integers etc.
                                        running_script.user_input = str(
                                            parsed_cmd["answer"]
                                        )
                                        # if parsed_cmd["method"] == 'ask':
                                        #   running_script.user_input = running_script.user_input.convert_to_value
                                        run_script_log(
                                            id,
                                            f"User input: {running_script.user_input}",
                                        )
                                    running_script.do_continue()
                                else:
                                    run_script_log(
                                        id,
                                        f"INFO: Received answer for prompt {parsed_cmd['prompt_id']} when looking for {running_script.prompt_id}.",
                                    )
                            else:
                                run_script_log(
                                    id,
                                    f"INFO: Unexpectedly received answer for unknown prompt {parsed_cmd['prompt_id']}.",
                                )
                        case "backtrace":
                            Store.publish(
                                f"script-api:running-script-channel:{id}",
                                json.dumps(
                                    {
                                        "type": "script",
                                        "method": "backtrace",
                                        "args": running_script.current_backtrace,
                                    }
                                ),
                            )
                        case "debug":
                            run_script_log(
                                id, f"DEBUG: {parsed_cmd['args']}"
                            )  # Log what we were passed
                            running_script.debug(
                                parsed_cmd["args"]
                            )  # debug() logs the output of the command
                        case _:
                            run_script_log(
                                id,
                                f"ERROR: Script method not handled: {parsed_cmd['method']}",
                                "RED",
                            )
                else:
                    run_script_log(
                        id, f"ERROR: Script command not handled: {msg['data']}", "RED"
                    )
except Exception as err:
    tb = traceback.format_exc()
    run_script_log(id, tb, "RED")
finally:
    try:
        # Remove running script from redis
        script = Store.get(f"running-script:{id}")
        if script:
            Store.delete(f"running-script:{id}")
        running = Store.smembers("running-scripts")
        for item in running:
            parsed = json.loads(item)
            if str(parsed["id"]) == str(id):
                Store.srem("running-scripts", item)
                break
        time.sleep(
            0.2
        )  # Allow the message queue to be emptied before signaling complete
        Store.publish(
            f"script-api:running-script-channel:{id}", json.dumps({"type": "complete"})
        )
    finally:
        if running_script:
            running_script.stop_message_log()
