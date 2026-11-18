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
import os
import traceback

import openc3.script
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.extract import *


def get_screen_list(scope: str = OPENC3_SCOPE) -> dict[str, list[str]]:
    """Return the names of all screens grouped by target.

    Args:
        scope: COSMOS scope.

    Returns:
        Upper case screen names keyed by target name.

    Raises:
        RuntimeError: If the request fails.
    """
    try:
        endpoint = "/openc3-api/screens"
        # Pass the name of the ENV variable name where we pull the actual bucket name
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if not response or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to get_screen_list: {response}")
        screen_list = {}
        filenames = json.loads(response.text)
        for filename in filenames:
            # TARGET/screens/filename.txt
            split_filename = filename.split("/")
            target_name = split_filename[0]
            screen_name = os.path.splitext(os.path.basename(filename))[0].upper()
            if not screen_list.get(target_name):
                screen_list[target_name] = []
            screen_list[target_name].append(screen_name)
        return screen_list
    except Exception as error:
        raise RuntimeError(f"get_screen_list failed due to {traceback.format_exc()}") from error


def get_screen_definition(target_name: str, screen_name: str, scope: str = OPENC3_SCOPE) -> str:
    """Return the text of a screen definition.

    Args:
        target_name: Target name.
        screen_name: Screen name.
        scope: COSMOS scope.

    Returns:
        The screen definition text.

    Raises:
        RuntimeError: If the screen is not found or the request fails.
    """
    try:
        endpoint = f"/openc3-api/screen/{target_name.upper()}/{screen_name.upper()}"
        response = openc3.script.API_SERVER.request(
            "get",
            endpoint,
            headers={
                "Accept": "text/plain",
            },
            scope=scope,
        )
        if not response or response.status_code != 200:
            raise RuntimeError(f"Screen definition not found: {target_name} {screen_name}")

        return response.text
    except Exception as error:
        raise RuntimeError(f"get_screen_definition failed due to {traceback.format_exc()}") from error


def create_screen(target_name: str, screen_name: str, definition: str, scope: str = OPENC3_SCOPE) -> str:
    """Create or overwrite a screen definition.

    Args:
        target_name: Target name.
        screen_name: Screen name.
        definition: Screen definition text.
        scope: COSMOS scope.

    Returns:
        The raw JSON response body describing the saved screen.

    Raises:
        RuntimeError: If the request fails.
    """
    try:
        endpoint = "/openc3-api/screen"
        data = {"target": target_name, "screen": screen_name, "text": definition}
        response = openc3.script.API_SERVER.request("post", endpoint, data=data, json=True, scope=scope)
        if not response or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"create_screen error: {parsed['error']}")
            else:
                raise RuntimeError("create_screen failed")
        return response.text
    except Exception as error:
        raise RuntimeError(f"create_screen failed due to {traceback.format_exc()}") from error


def delete_screen(target_name: str, screen_name: str, scope: str = OPENC3_SCOPE) -> str:
    """Delete a screen definition.

    Args:
        target_name: Target name.
        screen_name: Screen name.
        scope: COSMOS scope.

    Returns:
        The raw response body, normally empty.

    Raises:
        RuntimeError: If the request fails.
    """
    try:
        endpoint = f"/openc3-api/screen/{target_name.upper()}/{screen_name.upper()}"
        response = openc3.script.API_SERVER.request("delete", endpoint, scope=scope)
        if not response or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"delete_screen error: {parsed['error']}")
            else:
                raise RuntimeError("delete_screen failed")

        return response.text
    except Exception as error:
        raise RuntimeError(f"delete_screen failed due to {traceback.format_exc()}") from error


def display_screen(
    target_name: str, screen_name: str, x: int | None = None, y: int | None = None, scope: str = OPENC3_SCOPE
) -> None:
    """Open a screen in Script Runner.

    Does nothing outside of Script Runner.

    Args:
        target_name: Target name.
        screen_name: Screen name.
        x: Horizontal position of the screen in pixels.
        y: Vertical position of the screen in pixels.
        scope: COSMOS scope.
    """
    # Noop outside of ScriptRunner
    pass


def clear_screen(target_name: str, screen_name: str) -> None:
    """Close a screen opened in Script Runner.

    Does nothing outside of Script Runner.

    Args:
        target_name: Target name.
        screen_name: Screen name.
    """
    # Noop outside of ScriptRunner
    pass


def clear_all_screens() -> None:
    """Close all screens opened in Script Runner.

    Does nothing outside of Script Runner.
    """
    # Noop outside of ScriptRunner
    pass


def local_screen(screen_name: str, definition: str, x: int | None = None, y: int | None = None) -> None:
    """Open a screen in Script Runner from a definition given in the script.

    Does nothing outside of Script Runner.

    Args:
        screen_name: Screen name.
        definition: Screen definition text.
        x: Horizontal position of the screen in pixels.
        y: Vertical position of the screen in pixels.
    """
    # Noop outside of ScriptRunner
    pass


def open_tab(url: str) -> None:
    """Open a URL in a new browser tab from Script Runner.

    Does nothing outside of Script Runner.

    Args:
        url: URL to open.
    """
    # Noop outside of ScriptRunner
    pass
