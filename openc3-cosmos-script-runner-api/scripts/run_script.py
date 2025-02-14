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

import os
import time
import json
import sys
import traceback
from datetime import datetime, timezone
from openc3.script import get_overrides
from openc3.utilities.bucket import Bucket
from openc3.utilities.store import Store, EphemeralStore
from openc3.utilities.extract import convert_to_value
from openc3.utilities.logger import Logger
from openc3.environment import OPENC3_CONFIG_BUCKET
from running_script import RunningScript, running_script_anycable_publish

start_time = time.time()

# Load the bucket client code to ensure we authenticate outside ENV vars
Bucket.getClient()

del os.environ["OPENC3_BUCKET_USERNAME"]
del os.environ["OPENC3_BUCKET_PASSWORD"]
os.unsetenv("OPENC3_BUCKET_USERNAME")
os.unsetenv("OPENC3_BUCKET_PASSWORD")

# Preload Store and remove Redis secrets from ENV
Store.instance()
EphemeralStore.instance()

del os.environ["OPENC3_REDIS_USERNAME"]
del os.environ["OPENC3_REDIS_PASSWORD"]
os.unsetenv("OPENC3_REDIS_USERNAME")
os.unsetenv("OPENC3_REDIS_PASSWORD")

id = sys.argv[1]
script_data = Store.get(f"running-script:{id}")
script = None
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
    line_to_write = (
        # Can't use isoformat because it appends "+00:00" instead of "Z"
        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        + " (SCRIPTRUNNER): "
        + message
    )
    if message_log:
        RunningScript.message_log().write(line_to_write + "\n", True)
    running_script_anycable_publish(
        f"running-script-channel:{id}",
        {"type": "output", "line": line_to_write, "color": color},
    )


running_script = None
try:
    # Ensure usage of Logger in scripts will show Script Runner as the source
    Logger.microservice_name = "Script Runner"
    running_script = RunningScript(id, scope, name, disconnect)
    run_script_log(
        id,
        f"Script {path} spawned in {startup_time} seconds <python {sys.version}>",
        "BLACK",
    )

    overrides = get_overrides()
    if len(overrides) > 0:
        message = "The following overrides were present:"
        for o in overrides:
            message = (
                message
                + f"\n{o['target_name']} {o['packet_name']} {o['item_name']} = {o['value']}, type: :{o['value_type']}"
            )
        run_script_log(id, message, "YELLOW")

    if "suite_runner" in script:
        script["suite_runner"] = json.loads(script["suite_runner"])  # Convert to hash
        running_script.parse_options(script["suite_runner"]["options"])
        if "script" in script["suite_runner"]:
            running_script.run_text(
                f"from openc3.script.suite_runner import SuiteRunner\nSuiteRunner.start({script['suite_runner']['suite']}, {script['suite_runner']['group']}, '{script['suite_runner']['script']}')",
                initial_filename="SCRIPTRUNNER",
            )
        elif "group" in script["suite_runner"]:
            running_script.run_text(
                f"from openc3.script.suite_runner import SuiteRunner\nSuiteRunner.{script['suite_runner']['method']}({script['suite_runner']['suite']}, {script['suite_runner']['group']})",
                initial_filename="SCRIPTRUNNER",
            )
        else:
            running_script.run_text(
                f"from openc3.script.suite_runner import SuiteRunner\nSuiteRunner.{script['suite_runner']['method']}({script['suite_runner']['suite']})",
                initial_filename="SCRIPTRUNNER",
            )
    else:
        running_script.run()

    running = Store.smembers("running-scripts")
    if running is None:
        running = []
    running_script_anycable_publish(
        "all-scripts-channel",
        {
            "type": "start",
            "filename": path,
            "active_scripts": len(running),
        },
    )

    # Subscribe to the ActionCable generated topic which is namedspaced with channel_prefix
    # (defined in cable.yml) and then the channel stream. This isn't typically how you see these
    # topics used in the Rails ActionCable documentation but this is what is happening under the
    # scenes in ActionCable. Throughout the rest of the code we use ActionCable to broadcast
    #   e.g. ActionCable.server.broadcast("running-script-channel:{@id}", ...)
    redis = Store.instance().build_redis()
    p = redis.pubsub(ignore_subscribe_messages=True)
    p.subscribe(f"script-api:cmd-running-script-channel:{id}")
    for msg in p.listen():
        parsed_cmd = json.loads(msg["data"])
        if not parsed_cmd == "shutdown" or (
            isinstance(parsed_cmd, dict) and parsed_cmd["method"]
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
                if isinstance(parsed_cmd, dict) and "method" in parsed_cmd:
                    match parsed_cmd["method"]:
                        # This list matches the list in running_script.py:113
                        case (
                            "ask"
                            | "ask_string"
                            | "message_box"
                            | "vertical_message_box"
                            | "combo_box"
                            | "prompt"
                            | "prompt_for_hazardous"
                            | "prompt_for_critical_cmd"
                            | "metadata_input"
                            | "open_file_dialog"
                            | "open_files_dialog"
                        ):
                            if running_script.prompt_id is not None:
                                if (
                                    "prompt_id" in parsed_cmd
                                    and running_script.prompt_id
                                    == parsed_cmd["prompt_id"]
                                ):
                                    if "password" in parsed_cmd:
                                        running_script.user_input = str(
                                            parsed_cmd["password"]
                                        )
                                    elif "multiple" in parsed_cmd:
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
                                        running_script.user_input = str(
                                            parsed_cmd["answer"]
                                        )
                                        if parsed_cmd["method"] == "ask":
                                            running_script.user_input = (
                                                convert_to_value(
                                                    running_script.user_input
                                                )
                                            )
                                        run_script_log(
                                            id,
                                            f"User input: {running_script.user_input}",
                                        )
                                    running_script.do_continue()
                                else:
                                    prompt_id = "None"
                                    if "prompt_id" in parsed_cmd:
                                        prompt_id = parsed_cmd["prompt_id"]
                                    run_script_log(
                                        id,
                                        f"INFO: Received answer for prompt {prompt_id} when looking for {running_script.prompt_id}.",
                                    )
                            else:
                                prompt_id = "None"
                                if "prompt_id" in parsed_cmd:
                                    prompt_id = parsed_cmd["prompt_id"]
                                run_script_log(
                                    id,
                                    f"INFO: Unexpectedly received answer for unknown prompt {prompt_id}.",
                                )
                        case "backtrace":
                            running_script_anycable_publish(
                                f"running-script-channel:{id}",
                                {
                                    "type": "script",
                                    "method": "backtrace",
                                    "args": running_script.current_backtrace,
                                },
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
except Exception:
    tb = traceback.format_exc()
    run_script_log(id, tb, "RED")
finally:
    try:
        # Remove running script from redis
        script = Store.get(f"running-script:{id}")
        if script:
            Store.delete(f"running-script:{id}")
        running = Store.smembers("running-scripts")
        active_scripts = len(running)
        for item in running:
            parsed = json.loads(item)
            if str(parsed["id"]) == str(id):
                Store.srem("running-scripts", item)
                active_scripts -= 1
                break
        time.sleep(
            0.2
        )  # Allow the message queue to be emptied before signaling complete
        running_script_anycable_publish(
            f"running-script-channel:{id}", {"type": "complete"}
        )
        running_script_anycable_publish(
            "all-scripts-channel",
            {"type": "complete", "active_scripts": active_scripts},
        )
    finally:
        if running_script:
            running_script.stop_message_log()
