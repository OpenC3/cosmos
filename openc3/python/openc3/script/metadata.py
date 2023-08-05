#!/usr/bin/env python3
#!/usr/bin/env python3

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
from openc3.utilities.extract import *
import openc3.script
from openc3.environment import OPENC3_SCOPE


# Gets all the metadata
#
# @return The result of the method call.
def metadata_all(limit=100, scope=OPENC3_SCOPE):
    response = openc3.script.API_SERVER.request(
        "get", "/openc3-api/metadata", query={"limit": limit}, scope=scope
    )
    # Non-existant just returns None
    if not response or response.status_code != 200:
        return None
    return json.loads(response.text)


# Gets metadata, default is latest if start is None
#
# @return The result of the method call.
def metadata_get(start=None, scope=OPENC3_SCOPE):
    if start:
        response = openc3.script.API_SERVER.request(
            "get", f"/openc3-api/metadata/{start}", scope=scope
        )
    else:
        response = openc3.script.API_SERVER.request(
            "get", "/openc3-api/metadata/latest", scope=scope
        )

    # Non-existant just returns None
    if not response or response.status_code != 200:
        return None
    return json.loads(response.text)


# Create a new metadata entry at the given start time or now if no start given
#
# @param metadata [Hash<Symbol, Variable>] A hash of metadata
# @param start [Integer] Metadata time value as integer seconds from epoch
# @param color [String] Events color to show on Calendar tool, if None will be blue
# @return The result of the method call.
def metadata_set(metadata, start=None, color=None, scope=OPENC3_SCOPE):
    if type(metadata) != dict:
        raise RuntimeError(
            f"metadata must be a Hash: {metadata} is a {metadata.__class__.__name__}"
        )

    if not color:
        color = "#003784"
    data = {"color": color, "metadata": metadata}
    if start:
        data["start"] = time.asctime(time.gmtime(start))
    response = openc3.script.API_SERVER.request(
        "post", "/openc3-api/metadata", data=data, json=True, scope=scope
    )
    if not response:
        raise RuntimeError(f"Failed to set metadata due to {response.status_code}")
    elif response.status_code == 409:
        raise RuntimeError(
            "Metadata overlaps existing metadata. Did you metadata_set within 1s of another?"
        )
    elif response.status_code != 201:
        raise RuntimeError(f"Failed to set metadata due to {response.status_code}")
    return json.loads(response.text)


# Updates existing metadata. If no start is given, updates latest metadata.
#
# @param metadata [Hash<Symbol, Variable>] A hash of metadata
# @param start [Integer] Metadata time value as integer seconds from epoch
# @param color [String] Events color to show on Calendar tool, if None will be blue
# @return The result of the method call.
def metadata_update(metadata, start=None, color=None, scope=OPENC3_SCOPE):
    if type(metadata) != dict:
        raise RuntimeError(
            f"metadata must be a Hash: {metadata} is a {metadata.__class__.__name__}"
        )

    if not start:  # No start so grab latest
        existing = metadata_get()
        start = existing["start"]
        if not color:
            color = existing["color"]
        metadata = existing["metadata"] | metadata
    else:
        if not color:
            color = "#003784"

    data = {"color": color, "metadata": metadata}
    data["start"] = time.asctime(time.gmtime(start))
    response = openc3.script.API_SERVER.request(
        "put", f"/openc3-api/metadata/{start}", data=data, json=True, scope=scope
    )
    if not response or response.status_code != 200:
        raise RuntimeError("Failed to update metadata")

    return json.loads(response.text)


# Requests the metadata from the user for a target
def metadata_input(*args, **kwargs):
    raise RuntimeError("can only be used in Script Runner")
