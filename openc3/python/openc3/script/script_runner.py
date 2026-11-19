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

import json
from typing import Any, NoReturn

import openc3.script
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.extract import *


def _script_response_error(response: Any, message: str, scope: str = OPENC3_SCOPE) -> NoReturn:
    # NOTE: check identity not truthiness - requests.Response is falsy for any
    # non-2xx status (Response.__bool__ returns self.ok), which would otherwise
    # report an error response (e.g. 404) as "No Response" and discard the body.
    if response is not None:
        raise RuntimeError(f"{message} ({response.status_code}): {response.text}")
    else:
        raise RuntimeError(f"{message}: No Response")


def script_list(scope: str = OPENC3_SCOPE) -> list[str]:
    """List the script files in a scope.

    Args:
        scope: COSMOS scope.

    Returns:
        The script file names (target relative paths). Names of scripts with
        unsaved modifications are returned without the trailing '*'.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = "/script-api/scripts"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("get", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Script list request failed", scope=scope)
    else:
        scripts = json.loads(response.text)
        # Remove the '*' from the script names
        return [script.rstrip("*") for script in scripts]


def script_syntax_check(script: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Check the syntax of Python script text.

    Args:
        script: The script text to check.
        scope: COSMOS scope.

    Returns:
        The Script Runner API result with a "success" key added which is True
        when the syntax check passed.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = "/script-api/scripts/temp.py/syntax"
    # Explicitly set the headers to text/plain so the request.body is set correctly
    headers = {"Content-Type": "text/plain"}
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
        "post", endpoint, json=False, data=script, headers=headers, scope=scope
    )
    if not response or response.status_code != 200:
        _script_response_error(response, "Script syntax check request failed", scope=scope)
    else:
        result = json.loads(response.text)
        if result.get("title") == "Syntax Check Successful":
            result["success"] = True
        else:
            result["success"] = False
        return result


def script_body(filename: str, scope: str = OPENC3_SCOPE) -> str | None:
    """Get the contents of a script file.

    Args:
        filename: Script file name including the target, e.g. "INST/procedures/test.py".
        scope: COSMOS scope.

    Returns:
        The script file contents, or None if the response has no contents.

    Raises:
        RuntimeError: If the request to the Script Runner API fails, e.g. the file does not exist.
    """
    endpoint = f"/script-api/scripts/{filename}"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("get", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to get {filename}", scope=scope)
    else:
        result = json.loads(response.text)
        return result.get("contents")


def script_run(
    filename: str,
    disconnect: bool = False,
    environment: dict[str, Any] | None = None,
    suite_runner: dict[str, Any] | None = None,
    scope: str = OPENC3_SCOPE,
) -> int:
    """Start running a script file in Script Runner.

    Args:
        filename: Script file name including the target, e.g. "INST/procedures/test.py".
        disconnect: Run the script in disconnect mode.
        environment: Environment variables to set for the script as name / value pairs.
        suite_runner: Suite runner options for a suite file, e.g.
            {"suite": "MySuite", "group": "MyGroup", "script": "script_1"}.
        scope: COSMOS scope.

    Returns:
        The ID of the started running script.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    if disconnect:
        endpoint = f"/script-api/scripts/{filename}/run/disconnect"
    else:
        endpoint = f"/script-api/scripts/{filename}/run"

    # Encode the environment hash into an array of key values
    if environment and len(environment) != 0:
        env_data = []
        for key, value in environment.items():
            env_data.append({"key": key, "value": value})
    else:
        env_data = []
    data = {"environment": env_data}
    if suite_runner:
        # TODO 7.0: Should suiteRunner be snake case?
        data["suiteRunner"] = suite_runner

    # NOTE: json: true causes json_api_object to JSON generate and set the Content-Type to json
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, json=True, data=data, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to run {filename}", scope=scope)
    else:
        script_id = int(response.text)
        return script_id


def script_delete(filename: str, scope: str = OPENC3_SCOPE) -> bool:
    """Delete a script file.

    Args:
        filename: Script file name including the target, e.g. "INST/procedures/test.py".
        scope: COSMOS scope.

    Returns:
        True when the script was deleted.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = f"/script-api/scripts/{filename}/delete"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to delete {filename}", scope=scope)
    else:
        return True


def script_lock(filename: str, scope: str = OPENC3_SCOPE) -> bool:
    """Lock a script file for editing by the current user.

    Args:
        filename: Script file name including the target, e.g. "INST/procedures/test.py".
        scope: COSMOS scope.

    Returns:
        True when the script was locked.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = f"/script-api/scripts/{filename}/lock"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to lock {filename}", scope=scope)
    else:
        return True


def script_unlock(filename: str, scope: str = OPENC3_SCOPE) -> bool:
    """Unlock a script file.

    Args:
        filename: Script file name including the target, e.g. "INST/procedures/test.py".
        scope: COSMOS scope.

    Returns:
        True when the script was unlocked.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = f"/script-api/scripts/{filename}/unlock"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Failed to unlock {filename}", scope=scope)
    else:
        return True


def script_instrumented(script: str, scope: str = OPENC3_SCOPE) -> str:
    """Get the instrumented version of Python script text.

    The instrumented script is what Script Runner executes to track the
    current line.

    Args:
        script: The script text to instrument.
        scope: COSMOS scope.

    Returns:
        The instrumented script text.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = "/script-api/scripts/temp.py/instrumented"
    # Explicitly set the headers to text/plain so the request.body is set correctly
    headers = {"Content-Type": "text/plain"}
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
        "post", endpoint, json=False, data=script, headers=headers, scope=scope
    )
    if not response or response.status_code != 200:
        _script_response_error(response, "Script instrumented request failed", scope=scope)
    else:
        result = json.loads(response.text)
        if result.get("title") == "Instrumented Script":
            parsed = json.loads(result.get("description"))
            return "\n".join(parsed)
        else:
            raise result


def script_create(
    filename: str, script: str, breakpoints: list[int] | None = None, scope: str = OPENC3_SCOPE
) -> dict[str, Any]:
    """Create or overwrite a script file.

    Args:
        filename: Script file name including the target, e.g. "INST/procedures/test.py".
        script: The script text.
        breakpoints: Line numbers to set breakpoints on.
        scope: COSMOS scope.

    Returns:
        The Script Runner API result. For a suite file it includes the parsed
        "suites", "error" and "success" keys.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    if breakpoints is None:
        breakpoints = []
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


def script_delete_all_breakpoints(scope: str = OPENC3_SCOPE) -> bool:
    """Delete all script breakpoints in a scope.

    Args:
        scope: COSMOS scope.

    Returns:
        True when the breakpoints were deleted.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = "/script-api/breakpoints/delete/all"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("delete", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Script delete all breakpoints failed", scope=scope)
    else:
        return True


def running_script_list(limit: int = 10, offset: int = 0, scope: str = OPENC3_SCOPE) -> list[Any]:
    """List the currently running scripts, most recent first.

    Args:
        limit: Maximum number of scripts to return.
        offset: Number of scripts to skip, for paging.
        scope: COSMOS scope.

    Returns:
        The running script status records.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = "/script-api/running-script"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
        "get", endpoint, query={"limit": limit, "offset": offset}, scope=scope
    )
    if not response or response.status_code != 200:
        _script_response_error(response, "Running script list request failed", scope=scope)
    else:
        return json.loads(response.text)["items"]


def script_get(id: int | str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Get the status of a running or completed script.

    Args:
        id: Running script ID.
        scope: COSMOS scope.

    Returns:
        The script status record.

    Raises:
        RuntimeError: If the request to the Script Runner API fails, e.g. the ID does not exist.
    """
    endpoint = f"/script-api/running-script/{id}"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("get", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, "Running script show request failed", scope=scope)
    else:
        return json.loads(response.text)


running_script_get = script_get  # Alias for compatibility


def _running_script_action(id: int | str, action_name: str, scope: str = OPENC3_SCOPE):
    endpoint = f"/script-api/running-script/{id}/{action_name}"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request("post", endpoint, scope=scope)
    if not response or response.status_code != 200:
        _script_response_error(response, f"Running script {action_name} request failed", scope=scope)
    else:
        return True


def running_script_stop(id: int | str, scope: str = OPENC3_SCOPE) -> None:
    """Stop a running script.

    Args:
        id: Running script ID.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    _running_script_action(id, "stop", scope=scope)


def running_script_pause(id: int | str, scope: str = OPENC3_SCOPE) -> None:
    """Pause a running script.

    Args:
        id: Running script ID.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    _running_script_action(id, "pause", scope=scope)


def running_script_retry(id: int | str, scope: str = OPENC3_SCOPE) -> None:
    """Retry the current line of a running script which is paused on an error.

    Args:
        id: Running script ID.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    _running_script_action(id, "retry", scope=scope)


def running_script_go(id: int | str, scope: str = OPENC3_SCOPE) -> None:
    """Continue a paused running script.

    Args:
        id: Running script ID.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    _running_script_action(id, "go", scope=scope)


def running_script_step(id: int | str, scope: str = OPENC3_SCOPE) -> None:
    """Execute the next line of a running script and pause.

    Args:
        id: Running script ID.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    _running_script_action(id, "step", scope=scope)


def running_script_delete(id: int | str, scope: str = OPENC3_SCOPE) -> None:
    """Delete a running script from the running script list.

    Args:
        id: Running script ID.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    _running_script_action(id, "delete", scope=scope)


def running_script_backtrace(id: int | str, scope: str = OPENC3_SCOPE) -> None:
    """Request the backtrace of a running script.

    Args:
        id: Running script ID.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    _running_script_action(id, "backtrace", scope=scope)


def running_script_debug(id: int | str, debug_code: str, scope: str = OPENC3_SCOPE) -> bool:
    """Execute debug code in the context of a running script.

    Args:
        id: Running script ID.
        debug_code: The code to execute.
        scope: COSMOS scope.

    Returns:
        True when the request was accepted.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = f"/script-api/running-script/{id}/debug"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
        "post", endpoint, json=True, data={"args": debug_code}, scope=scope
    )
    if not response or response.status_code != 200:
        _script_response_error(response, "Running script debug request failed", scope=scope)
    else:
        return True


def running_script_prompt(
    id: int | str,
    method_name: str,
    answer: Any,
    prompt_id: str,
    password: str | None = None,
    scope: str = OPENC3_SCOPE,
) -> bool:
    """Answer a prompt (e.g. ask or message_box) displayed by a running script.

    Args:
        id: Running script ID.
        method_name: Name of the prompting method, e.g. "ask".
        answer: The answer to the prompt.
        prompt_id: ID of the prompt being answered.
        password: Password, for prompts which require one.
        scope: COSMOS scope.

    Returns:
        True when the answer was accepted.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
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


def running_script_execute_while_paused(
    id: int | str,
    filename: str,
    line_no: int,
    end_line_no: int | None = None,
    scope: str = OPENC3_SCOPE,
) -> bool:
    """Execute a line, or range of lines, of a script while the running script is paused.

    Args:
        id: Running script ID.
        filename: Script file name containing the lines to execute.
        line_no: First line number to execute.
        end_line_no: Last line number to execute. Only line_no is executed if None.
        scope: COSMOS scope.

    Returns:
        True when the request was accepted.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = f"/script-api/running-script/{id}/executewhilepaused"
    if end_line_no is not None:
        response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
            "post",
            endpoint,
            json=True,
            data={
                "args": [filename, line_no, end_line_no],
            },
            scope=scope,
        )
    else:
        response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
            "post",
            endpoint,
            json=True,
            data={"args": [filename, line_no]},
            scope=scope,
        )
    if not response or response.status_code != 200:
        _script_response_error(response, "Running script executewhilepaused request failed", scope=scope)
    else:
        return True


def completed_script_list(limit: int = 10, offset: int = 0, scope: str = OPENC3_SCOPE) -> list[Any]:
    """List the completed scripts, most recent first.

    Args:
        limit: Maximum number of scripts to return.
        offset: Number of scripts to skip, for paging.
        scope: COSMOS scope.

    Returns:
        The completed script status records.

    Raises:
        RuntimeError: If the request to the Script Runner API fails.
    """
    endpoint = "/script-api/completed-scripts"
    response = openc3.script.SCRIPT_RUNNER_API_SERVER.request(
        "get", endpoint, query={"limit": limit, "offset": offset}, scope=scope
    )
    if not response or response.status_code != 200:
        _script_response_error(response, "Completed script list request failed", scope=scope)
    else:
        return json.loads(response.text)["items"]
