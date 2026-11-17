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
from typing import Any

from requests import Response

import openc3.script
from openc3.environment import OPENC3_SCOPE


def table_create_binary(definition: str, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Create a table binary file with default values from a table definition.

    Args:
        definition: Path to the table definition file in a target directory,
            e.g. "INST/tables/config/ConfigTables_def.txt".
        scope: COSMOS scope.

    Returns:
        {"filename": path} with the path of the created binary, or None if
        the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error.
    """
    data = {}
    data["definition"] = definition
    response = openc3.script.API_SERVER.request(
        "post", "/openc3-api/tables/generate", data=data, json=True, scope=scope
    )
    return _handle_response(response, "Failed to create binary")


# save=True (the default) writes the report into the target's storage next to the
# binary so it can be read back with get_target_file(). Pass save=False to get the
# contents in the return value without creating a file.
def table_create_report(
    filename: str, definition: str, table_name: str | None = None, save: bool = True, scope: str = OPENC3_SCOPE
) -> dict[str, Any] | None:
    """Create a CSV report of the contents of a table binary file.

    Args:
        filename: Path to the table binary file in a target directory.
        definition: Path to the table definition file in a target directory.
        table_name: Name of a single table to report. Defaults to all tables.
        save: Write the report to the target's storage next to the binary.
        scope: COSMOS scope.

    Returns:
        {"filename": path, "contents": csv} with the report path and
        contents, or None if the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error.
    """
    data = {}
    data["binary"] = filename
    data["definition"] = definition
    if table_name:
        data["table_name"] = table_name
    data["save"] = save
    response = openc3.script.API_SERVER.request("post", "/openc3-api/tables/report", data=data, json=True, scope=scope)
    return _handle_response(response, "Failed to create report")


# Helper method to handle the response
def _handle_response(response: Response | None, error_message: str):
    if response is None:
        return None
    if response.status_code >= 400:
        result = json.loads(response.text)
        raise RuntimeError(f"{error_message} due to {result['message']}")
    # Not sure why the response body is empty (on delete) but check for that
    if response.text is None or len(response.text) == 0:
        return None
    else:
        return json.loads(response.text)
