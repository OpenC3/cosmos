# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import contextlib
import json
import os
import shutil
import sys
import time
import traceback
from datetime import datetime, timezone


working_dir = os.getcwd()

# Read the one-line credentials JSON the parent wrote to stdin right after spawn,
# and apply the API credentials to os.environ BEFORE importing openc3. openc3
# freezes OPENC3_API_* as module constants at import and ApiServerProxy() picks its
# auth strategy at construction (which runs when openc3.script is imported);
# applying the credentials afterward leaves the API client with no token and every
# API call fails with "AuthError: Token is nil". Applying them in-process after
# exec still keeps the secrets out of /proc/<pid>/environ. run_suite_analysis.py
# does the same. signing_key is stashed and applied after the imports below.
try:
    stdin_creds = json.loads(sys.stdin.readline())
    signing_key = stdin_creds["signing_key"]
    if not isinstance(signing_key, str) or not signing_key:
        raise ValueError("no signing_key")
except Exception:
    raise RuntimeError("run_script: missing or malformed stdin credentials") from None
auth = stdin_creds.get("auth")
if isinstance(auth, dict):
    if auth.get("token"):
        os.environ["OPENC3_API_TOKEN"] = auth["token"]
    elif auth.get("user") or auth.get("password"):
        # Leave OPENC3_API_USER unset for a null username: an empty string is not
        # None, so ApiServerProxy.generate_auth would pick Keycloak over Core auth.
        if auth.get("user"):
            os.environ["OPENC3_API_USER"] = auth["user"]
        if auth.get("password"):
            os.environ["OPENC3_API_PASSWORD"] = auth["password"]
            # Core authenticates as the service; OpenC3Authentication sets its service
            # flag by comparing OPENC3_API_PASSWORD to OPENC3_SERVICE_PASSWORD, so
            # restore it (runtime-only, so not exposed via /proc/<pid>/environ).
            os.environ["OPENC3_SERVICE_PASSWORD"] = auth["password"]

from openc3.environment import OPENC3_CONFIG_BUCKET  # noqa: E402
from openc3.models.script_status_model import ScriptStatusModel  # noqa: E402
from openc3.script import get_overrides  # noqa: E402
from openc3.utilities.bucket import Bucket  # noqa: E402
from openc3.utilities.extract import convert_to_value  # noqa: E402
from openc3.utilities.logger import Logger  # noqa: E402
from openc3.utilities.running_script import (  # noqa: E402
    RunningScript,
    running_script_anycable_publish,
)
from openc3.utilities.script_message_signing import NonceCache, accept  # noqa: E402
from openc3.utilities.store import EphemeralStore, Store  # noqa: E402
from openc3.utilities.store_queued import EphemeralStoreQueued, StoreQueued  # noqa: E402


def run_script_log(script_id, message, color="BLACK", message_log=True):
    line_to_write = (
        # Can't use isoformat because it appends "+00:00" instead of "Z"
        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ") + " (SCRIPTRUNNER): " + message
    )
    if message_log:
        RunningScript.message_log().write(line_to_write + "\n", True)
    running_script_anycable_publish(
        f"running-script-channel:{script_id}",
        {"type": "output", "line": line_to_write, "color": color},
    )


start_time = time.time()
# Load the bucket client code to ensure we authenticate outside ENV vars
Bucket.get_client()
# Preload Store and remove Redis secrets from ENV
Store.instance()
EphemeralStore.instance()

# Clear ENV vars for security purposes so user script code can't read them.
# Use pop with default to avoid KeyError if vars don't exist (e.g. Enterprise/Keycloak).
# OPENC3_API_PASSWORD / OPENC3_SERVICE_PASSWORD were applied from the stdin
# credentials above; openc3.environment captured them as constants at import and the
# API client has already authenticated, so they are no longer needed in os.environ.
for key in [
    "OPENC3_API_PASSWORD",
    "OPENC3_SERVICE_PASSWORD",
    "OPENC3_BUCKET_USERNAME",
    "OPENC3_BUCKET_PASSWORD",
    "OPENC3_REDIS_USERNAME",
    "OPENC3_REDIS_PASSWORD",
    "OPENC3_TSDB_USERNAME",
    "OPENC3_TSDB_PASSWORD",
    # This actually contains the password via redis://openc3:XXXXXXXX@openc3-redis:6379
    "ANYCABLE_REDIS_URL",
    "KC_DB_USERNAME",
    "KC_DB_PASSWORD",
    "KEYCLOAK_ADMIN",
    "KEYCLOAK_ADMIN_PASSWORD",
]:
    os.environ.pop(key, None)

RunningScript.signing_key = signing_key
seen_nonces = NonceCache()

script_id = sys.argv[1]
scope = sys.argv[2]
script_status = ScriptStatusModel.get_model(name=script_id, scope=scope)
if script_status is None:
    raise RuntimeError(f"Unknown script ID {script_id} for scope {scope}")
if script_status.state != "spawning":
    raise RuntimeError(f"Script in unexpected state: {script_status.state}")

startup_time = time.time() - start_time
path = os.path.join(OPENC3_CONFIG_BUCKET, scope, "targets", script_status.filename)

running_script = None
try:
    # Ensure usage of Logger in scripts will show Script Runner as the source
    Logger.microservice_name = "Script Runner"
    running_script = RunningScript(script_status)
    run_script_log(
        script_id,
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
        run_script_log(script_id, message, "YELLOW")

    # Subscribe to the pub sub channel for this script BEFORE starting the thread
    # to avoid a race condition where the thread crashes (e.g. SyntaxError) and
    # publishes "shutdown" before the main thread subscribes, losing the message.
    redis = Store.instance().build_redis()
    p = redis.pubsub(ignore_subscribe_messages=True)
    p.subscribe(f"script-api:cmd-running-script-channel:{script_id}")

    # Start the script in another thread
    running_script.run()

    # Notify frontend of number of running scripts in this scope
    running = ScriptStatusModel.all(scope=scope, type="running")
    running_script_anycable_publish(
        "all-scripts-channel",
        {
            "type": "start",
            "filename": script_status.filename,
            "active_scripts": len(running),
            "scope": scope,
        },
    )

    for msg in p.listen():
        accepted, parsed_cmd = accept(signing_key, msg["data"], seen_nonces)
        if not accepted:
            run_script_log(script_id, "WARNING: dropped unverified control message", "YELLOW")
            continue
        if parsed_cmd != "shutdown" or (isinstance(parsed_cmd, dict) and not parsed_cmd.get("method")):
            run_script_log(script_id, f"Script {path} received command: {json.dumps(parsed_cmd)}")
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
                            | "check_box"
                            | "prompt"
                            | "prompt_for_hazardous"
                            | "prompt_for_critical_cmd"
                            | "metadata_input"
                            | "open_file_dialog"
                            | "open_files_dialog"
                            | "open_bucket_dialog"
                        ):
                            if running_script.prompt_id is not None:
                                if "prompt_id" in parsed_cmd and running_script.prompt_id == parsed_cmd["prompt_id"]:
                                    if "password" in parsed_cmd:
                                        running_script.user_input = str(parsed_cmd["password"])
                                    elif "multiple" in parsed_cmd:
                                        running_script.user_input = json.loads(parsed_cmd["multiple"])
                                        run_script_log(
                                            script_id,
                                            f"Multiple input: {running_script.user_input}",
                                        )
                                    elif parsed_cmd["method"] == "open_bucket_dialog":
                                        running_script.user_input = parsed_cmd["answer"]
                                        run_script_log(
                                            script_id,
                                            f"Bucket file: {running_script.user_input}",
                                        )
                                    elif "open_file" in parsed_cmd["method"]:
                                        running_script.user_input = parsed_cmd["answer"]
                                        run_script_log(
                                            script_id,
                                            f"File(s): {running_script.user_input}",
                                        )
                                    else:
                                        running_script.user_input = str(parsed_cmd["answer"])
                                        if parsed_cmd["method"] == "ask":
                                            running_script.user_input = convert_to_value(running_script.user_input)
                                        run_script_log(
                                            script_id,
                                            f"User input: {running_script.user_input}",
                                        )
                                    running_script.do_continue()
                                else:
                                    prompt_id = "None"
                                    if "prompt_id" in parsed_cmd:
                                        prompt_id = parsed_cmd["prompt_id"]
                                    run_script_log(
                                        script_id,
                                        f"INFO: Received answer for prompt {prompt_id} when looking for {running_script.prompt_id}.",
                                    )
                            else:
                                prompt_id = "None"
                                if "prompt_id" in parsed_cmd:
                                    prompt_id = parsed_cmd["prompt_id"]
                                run_script_log(
                                    script_id,
                                    f"INFO: Unexpectedly received answer for unknown prompt {prompt_id}.",
                                )
                        case "backtrace":
                            running_script_anycable_publish(
                                f"running-script-channel:{script_id}",
                                {
                                    "type": "script",
                                    "method": "backtrace",
                                    "args": running_script.current_backtrace,
                                },
                            )
                        case "debug":
                            run_script_log(script_id, f"DEBUG: {parsed_cmd['args']}")  # Log what we were passed
                            running_script.debug(parsed_cmd["args"])  # debug() logs the output of the command
                        case "executewhilepaused":
                            run_script_log(
                                script_id,
                                f"INFO: executewhilepaused: {parsed_cmd['args']}",
                            )  # Log what we were passed
                            running_script.execute_while_paused(*parsed_cmd["args"])
                        case _:
                            run_script_log(
                                script_id,
                                f"ERROR: Script method not handled: {parsed_cmd['method']}",
                                "RED",
                            )
                else:
                    run_script_log(
                        script_id,
                        f"ERROR: Script command not handled: {json.dumps(parsed_cmd)}",
                        "RED",
                    )
except Exception:
    tb = traceback.format_exc()
    run_script_log(script_id, tb, "RED")
    script_status.state = "crashed"
    if script_status.errors is None:
        script_status.errors = []
    script_status.errors.append(tb)
finally:
    try:
        # Dump all queued redis messages
        StoreQueued.instance().shutdown()

        # Ensure script is marked as complete with an end time
        if not script_status.is_complete():
            script_status.state = "completed"
        script_status.end_time = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        script_status.update()

        running = ScriptStatusModel.all(scope=scope, type="running")

        # Inform script channel it is complete (include suite report if available to avoid race condition)
        complete_msg = {"type": "complete", "state": script_status.state}
        if running_script and running_script.suite_report:
            complete_msg["report"] = running_script.suite_report
        running_script_anycable_publish(
            f"running-script-channel:{script_id}",
            complete_msg,
        )

        # Inform frontend of number of running scripts in this scope
        running_script_anycable_publish(
            "all-scripts-channel",
            {
                "type": "complete",
                "filename": script_status.filename,
                "active_scripts": len(running),
                "scope": scope,
            },
        )

        # Flush the queued replay-stream writes before the process exits. The
        # complete (and any crash) events above are published after the
        # StoreQueued.shutdown above, so without this their replay-stream writes
        # could be lost and a late-subscribing client would never see the script
        # finish.
        # best-effort; the live broadcast already went out
        with contextlib.suppress(Exception):
            EphemeralStoreQueued.instance().shutdown()
    finally:
        if running_script:
            running_script.stop_message_log()
        shutil.rmtree(working_dir)
