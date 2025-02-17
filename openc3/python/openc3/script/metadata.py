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

import time
import json
import typing

from openc3.utilities.extract import *
import openc3.script
from openc3.environment import OPENC3_SCOPE


def metadata_all(limit: int = 100, scope: str = OPENC3_SCOPE):
    """Gets all the metadata

    Args:
        limit (int) Optional, defaults to 100
        scope (str) Optional, defaults to env.OPENC3_SCOPE

    Return:
        The json result of the method call
    """
    response = openc3.script.API_SERVER.request("get", "/openc3-api/metadata", query={"limit": limit}, scope=scope)
    # Non-existent just returns None
    if not response or response.status_code != 200:
        return None
    return json.loads(response.text)


def metadata_get(start: typing.Optional[int] = None, scope: str = OPENC3_SCOPE):
    """Gets metadata, default is latest if start is None

    Args:
        start (int) Metadata time value as integer seconds from epoch, Optional, defaults to "latest"
        scope (str) Optional, defaults to env.OPENC3_SCOPE

    Return:
        The json result of the method call
    """
    start_str = f"{start}" if start else "latest"
    response = openc3.script.API_SERVER.request("get", f"/openc3-api/metadata/{start_str}", scope=scope)

    # Non-existent just returns None
    if not response or response.status_code != 200:
        return None
    return json.loads(response.text)


def metadata_set(
    metadata: dict, start: typing.Optional[int] = None, color: typing.Optional[str] = None, scope: str = OPENC3_SCOPE
):
    """Create a new metadata entry at the given start time or now if no start given

    Args:
        metadata (dict) A dict of metadata
        start (int) Metadata time value as integer seconds from epoch
        color (str) Events color to show on Calendar tool, if None will be blue
        scope (str) Optional, defaults to env.OPENC3_SCOPE

    Return:
        The json result of the method call
    """
    if not isinstance(metadata, dict):
        raise TypeError(f"metadata must be a dict: {metadata} is a {metadata.__class__.__name__}")

    data = {"color": color if color else "#003784", "metadata": metadata}
    if start:
        data["start"] = time.asctime(time.gmtime(start))
    response = openc3.script.API_SERVER.request("post", "/openc3-api/metadata", data=data, json=True, scope=scope)
    if not response:
        raise RuntimeError(f"Failed to set metadata due to {response.status_code}")
    elif response.status_code == 409:
        raise RuntimeError("Metadata overlaps existing metadata. Did you metadata_set within 1s of another?")
    elif response.status_code != 201:
        raise RuntimeError(f"Failed to set metadata due to {response.status_code}")
    return json.loads(response.text)


def metadata_update(
    metadata: dict, start: typing.Optional[int] = None, color: typing.Optional[str] = None, scope: str = OPENC3_SCOPE
):
    """Updates existing metadata. If no start is given, updates latest metadata.

    Args:
        metadata (Dict[str, Any]) A dict of metadata
        start (int) Metadata time value as integer seconds from epoch
        color (str) Events color to show on Calendar tool, if None will be blue
        scope (str) Optional, defaults to env.OPENC3_SCOPE

    Return:
        The json result of the method call
    """
    if not isinstance(metadata, dict):
        raise TypeError(f"metadata must be a Hash: {metadata} is a {metadata.__class__.__name__}")

    if start is None:  # No start so grab latest
        existing = metadata_get()
        start = existing["start"]
        if not color:
            color = existing["color"]
        metadata = existing["metadata"] | metadata
    else:
        if not color:
            color = "#003784"

    data = {"color": color, "metadata": metadata, "start": time.asctime(time.gmtime(start))}
    response = openc3.script.API_SERVER.request(
        "put", f"/openc3-api/metadata/{start}", data=data, json=True, scope=scope
    )
    if not response or response.status_code != 200:
        raise RuntimeError("Failed to update metadata")

    return json.loads(response.text)


# Requests the metadata from the user for a target
def metadata_input(*args, **kwargs):
    raise RuntimeError("can only be used in Script Runner")
