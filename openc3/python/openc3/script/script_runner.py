# Copyright 2024 OpenC3, Inc.
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

import json
from openc3.utilities.extract import *
import openc3.script
from openc3.environment import OPENC3_SCOPE


def _script_response_error(response, message, scope=OPENC3_SCOPE):
    if response:
        raise RuntimeError(f"{message} ({response.status_code}): {response.text}")
    else:
        raise RuntimeError(f"{message}: No Response")


def script_list(scope=OPENC3_SCOPE):
    endpoint = "/script-api/scripts"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("get", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Script list request failed", scope=scope)
    else:
        scripts = json.loads(response.text)
        # Remove the '*' from the script names
        return [script.rstrip("*") for script in scripts]


def script_syntax_check(script, scope=OPENC3_SCOPE):
    endpoint = "/script-api/scripts/temp.py/syntax"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, json=False, data=script, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Script syntax check request failed", scope=scope)
    else:
        result = json.loads(response.text)
        if result.get("title") == "Syntax Check Successful":
            result["success"] = True
        else:
            result["success"] = False
        return result


def script_body(filename, scope=OPENC3_SCOPE):
    endpoint = f"/script-api/scripts/{filename}"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("get", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to get {filename}", scope=scope)
    else:
        result = json.loads(response.text)
        return result.get("contents")


def script_run(filename, disconnect=False, environment=None, scope=OPENC3_SCOPE):
    if disconnect:
        endpoint = f"/script-api/scripts/{filename}/run/disconnect"
    else:
        endpoint = f"/script-api/scripts/{filename}/run"

    # Encode the environment hash into an array of key values
    if environment and not len(environment) == 0:
        env_data = []
        for key, value in environment.items():
            env_data.append({"key": key, "value": value})
    else:
        env_data = []
    # NOTE: json: true causes json_api_object to JSON generate and set the Content-Type to json
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
        "post", endpoint, json=True, data={"environment": env_data}, scope=scope
    )
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to run {filename}", scope=scope)
    else:
        script_id = int(response.text)
        return script_id


def script_delete(filename, scope=OPENC3_SCOPE):
    endpoint = f"/script-api/scripts/{filename}/delete"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to delete {filename}", scope=scope)
    else:
        return True


def script_lock(filename, scope=OPENC3_SCOPE):
    endpoint = f"/script-api/scripts/{filename}/lock"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to lock {filename}", scope=scope)
    else:
        return True


def script_unlock(filename, scope=OPENC3_SCOPE):
    endpoint = f"/script-api/scripts/{filename}/unlock"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to unlock {filename}", scope=scope)
    else:
        return True


def script_instrumented(script, scope=OPENC3_SCOPE):
    endpoint = "/script-api/scripts/temp.py/instrumented"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, json=False, data=script, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Script instrumented request failed", scope=scope)
    else:
        result = json.loads(response.text)
        if result.get("title") == "Instrumented Script":
            parsed = json.loads(result.get("description"))
            return "\n".join(parsed)
        else:
            raise result


def script_create(filename, script, breakpoints=[], scope=OPENC3_SCOPE):
    endpoint = f"/script-api/scripts/{filename}"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
        "post",
        endpoint,
        json=True,
        data={"text": script, "breakpoints": breakpoints},
        scope=scope,
    )
    if not response or response.status_code != 200:
        _script_response_error(response, "Script create request failed", scope=scope)
    else:
        return json.loads(response.text)


def script_delete_all_breakpoints(scope=OPENC3_SCOPE):
    endpoint = "/script-api/breakpoints/delete/all"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("delete", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Script delete all breakpoints failed", scope=scope)
    else:
        return True


def running_script_list(scope=OPENC3_SCOPE):
    endpoint = "/script-api/running-script"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("get", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Running script list request failed", scope=scope)
    else:
        return json.loads(response.text)


def running_script_get(id, scope=OPENC3_SCOPE):
    endpoint = f"/script-api/running-script/{id}"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("get", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Running script show request failed", scope=scope)
    else:
        return json.loads(response.text)


def _running_script_action(id, action_name, scope=OPENC3_SCOPE):
    endpoint = f"/script-api/running-script/{id}/{action_name}"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Running script {action_name} request failed", scope=scope)
    else:
        return True


def running_script_stop(id, scope=OPENC3_SCOPE):
    _running_script_action(id, "stop", scope=scope)


def running_script_pause(id, scope=OPENC3_SCOPE):
    _running_script_action(id, "pause", scope=scope)


def running_script_retry(id, scope=OPENC3_SCOPE):
    _running_script_action(id, "retry", scope=scope)


def running_script_go(id, scope=OPENC3_SCOPE):
    _running_script_action(id, "go", scope=scope)


def running_script_step(id, scope=OPENC3_SCOPE):
    _running_script_action(id, "step", scope=scope)


def running_script_delete(id, scope=OPENC3_SCOPE):
    _running_script_action(id, "delete", scope=scope)


def running_script_backtrace(id, scope=OPENC3_SCOPE):
    _running_script_action(id, "backtrace", scope=scope)


def running_script_debug(id, debug_code, scope=OPENC3_SCOPE):
    endpoint = f"/script-api/running-script/{id}/debug"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
        "post", endpoint, json=True, data={"args": debug_code}, scope=scope
    )
    if not response or response.status_code != 200:
        _script_response_error(response, "Running script debug request failed", scope=scope)
    else:
        return True


def running_script_prompt(id, method_name, answer, prompt_id, password=None, scope=OPENC3_SCOPE):
    endpoint = f"/script-api/running-script/{id}/prompt"
    if password:
        response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
            "post",
            endpoint,
            json=True,
            data={
                "method": method_name,
                "answer": answer,
                "prompt_id": prompt_id,
                "password": password,
            },
            scope=scope,
        )
    else:
        response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
            "post",
            endpoint,
            json=True,
            data={"method": method_name, "answer": answer, "prompt_id": prompt_id},
            scope=scope,
        )
    if not response or response.status_code != 200:
        _script_response_error(response, "Running script prompt request failed", scope=scope)
    else:
        return True


def completed_script_list(scope=OPENC3_SCOPE):
    endpoint = "/script-api/completed-scripts"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("get", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Completed script list request failed", scope=scope)
    else:
        return json.loads(response.text)
