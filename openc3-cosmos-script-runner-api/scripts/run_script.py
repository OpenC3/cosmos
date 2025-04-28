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
from openc3.utilities.store_queued import StoreQueued
from openc3.utilities.extract import convert_to_value
from openc3.utilities.logger import Logger
from openc3.environment import OPENC3_CONFIG_BUCKET
from running_script import RunningScript, running_script_anycable_publish
from openc3.models.script_status_model import ScriptStatusModel

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
scope = sys.argv[2]
script_status = ScriptStatusModel.get_model(name = id, scope = scope)
if script_status is None:
    raise RuntimeError(f"Unknown script id {id} for scope {scope}")
if script_status.state != "spawning":
    raise RuntimeError(f"Script in unexpected state: {script_status.state}")

startup_time = time.time() - start_time
path = os.path.join(OPENC3_CONFIG_BUCKET, scope, "targets", script_status.filename)

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
    running_script = RunningScript(script_status)
    run_script_log(
        id,
        f"Script {path} spawned in {startup_time} seconds <python {sys.version}>",
        "BLACK",
    )

    # Log any overrides if present
    overrides = get_overrides()
    if len(overrides) > 0:
        message = "The following overrides were present:"
        for o in overrides:
            message = (
                message
                + f"\n{o['target_name']} {o['packet_name']} {o['item_name']} = {o['value']}, type: :{o['value_type']}"
            )
        run_script_log(id, message, "YELLOW")

    # Start the script in another thread
    if script_status.suite_runner is not None:
        script_status.suite_runner = json.loads(script_status.suite_runner)  # Convert to hash
        running_script.parse_options(script_status.suite_runner["options"])
        if "script" in script_status.suite_runner:
            running_script.run_text(
                f"from openc3.script.suite_runner import SuiteRunner\nSuiteRunner.start({script_status.suite_runner['suite']}, {script_status.suite_runner['group']}, '{script_status.suite_runner['script']}')",
                initial_filename="SCRIPTRUNNER",
            )
        elif "group" in script_status.suite_runner:
            running_script.run_text(
                f"from openc3.script.suite_runner import SuiteRunner\nSuiteRunner.{script_status.suite_runner['method']}({script_status.suite_runner['suite']}, {script_status.suite_runner['group']})",
                initial_filename="SCRIPTRUNNER",
            )
        else:
            running_script.run_text(
                f"from openc3.script.suite_runner import SuiteRunner\nSuiteRunner.{script_status.suite_runner['method']}({script_status.suite_runner['suite']})",
                initial_filename="SCRIPTRUNNER",
            )
    else:
        running_script.run()

    # Notify frontend of number of running scripts in this scope
    running = ScriptStatusModel.all(scope = scope, type = "running")
    running_script_anycable_publish(
        "all-scripts-channel",
        {
            "type": "start",
            "filename": script_status.filename,
            "active_scripts": len(running),
            "scope": scope,
        },
    )

    # Subscribe to the pub sub channel for this script
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
    script_status.state = "crashed"
    if script_status.errors is None:
        script_status.errors = []
    script_status.errors.append(tb)
    script_status.update()
finally:
    try:
        # Dump all queued redis messages
        StoreQueued.instance().shutdown()

        # Ensure script is marked as complete with an end time
        if not script_status.is_complete():
            script_status.state = "completed"
        script_status.end_time = datetime.now(timezone.utc).isoformat(timespec="seconds").replace('+00:00', 'Z')
        script_status.update()

        running = ScriptStatusModel.all(scope = scope, type = "running")

        # Inform script channel it is complete
        running_script_anycable_publish(
            f"running-script-channel:{id}", {"type": "complete", "state": script_status.state}
        )

        # Inform frontend of number of running scripts in this scope
        running_script_anycable_publish(
            "all-scripts-channel",
            {"type": "complete", "filename": script_status.filename, "active_scripts": len(running), "scope": scope},
        )
    finally:
        if running_script:
            running_script.stop_message_log()
