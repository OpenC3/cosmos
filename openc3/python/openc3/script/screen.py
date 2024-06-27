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
import json
from openc3.utilities.extract import *
import openc3.script
from openc3.environment import OPENC3_SCOPE


def get_screen_list(scope: str = OPENC3_SCOPE):
    """Gets a list of screens

    Args:
        scope (str) Optional, defaults to env.OPENC3_SCOPE

    Return:
        The json result of the method call
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
        raise RuntimeError(f"get_screen_list failed due to {repr(error)}") from error


def get_screen_definition(target_name: str, screen_name: str, scope: str = OPENC3_SCOPE):
    """Gets a screen definition

    Args:
        target_name (str) the target name
        screen_name (str) the screen name
        scope (str) Optional, defaults to env.OPENC3_SCOPE

    Return:
        The json result of the method call
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
        raise RuntimeError(f"get_screen_definition failed due to {repr(error)}") from error


def create_screen(target_name: str, screen_name: str, definition: str, scope: str = OPENC3_SCOPE):
    """Create a screen definition

    Args:
        target_name (str) the target name
        screen_name (str) the screen name
        definition (str) the screen definition
        scope (str) Optional, defaults to env.OPENC3_SCOPE

    Return:
        The json result of the method call
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
        raise RuntimeError(f"create_screen failed due to {repr(error)}") from error


def delete_screen(target_name: str, screen_name: str, scope: str = OPENC3_SCOPE):
    """Create a screen definition

    Args:
        target_name (str) the target name
        screen_name (str) the screen name
        scope (str) Optional, defaults to env.OPENC3_SCOPE

    Return:
        The json result of the method call
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
        raise RuntimeError(f"delete_screen failed due to {repr(error)}") from error


def display_screen(target_name, screen_name, x=None, y=None, scope=OPENC3_SCOPE):
    # Noop outside of ScriptRunner
    pass


def clear_screen(target_name, screen_name):
    # Noop outside of ScriptRunner
    pass


def clear_all_screens():
    # Noop outside of ScriptRunner
    pass


def local_screen(screen_name, definition, x=None, y=None):
    # Noop outside of ScriptRunner
    pass
