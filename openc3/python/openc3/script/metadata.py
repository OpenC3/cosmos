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
import time
import warnings
from typing import Any, NoReturn

import openc3.script
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.extract import *


# The metadata methods are deprecated. Define a telemetry packet for metadata
# and set it with inject_tlm instead. See https://docs.openc3.com/docs/guides/metadata


# DEPRECATED
def metadata_all(limit: int = 100, scope: str = OPENC3_SCOPE) -> list[dict[str, Any]] | None:
    """Return the most recent metadata entries.

    Deprecated: use Data Extractor or Telemetry Grapher on a metadata packet
    (since 7.5.0). See https://docs.openc3.com/docs/guides/metadata

    Args:
        limit: Maximum number of entries to return.
        scope: COSMOS scope.

    Returns:
        The metadata entries, or None if the request fails.
    """
    warnings.warn(
        "metadata_all is deprecated, use Data Extractor or Telemetry Grapher on a metadata packet. See https://docs.openc3.com/docs/guides/metadata",
        FutureWarning,
        stacklevel=2,
    )
    response = openc3.script.API_SERVER.request("get", "/openc3-api/metadata", query={"limit": limit}, scope=scope)
    # Non-existent just returns None
    if not response or response.status_code != 200:
        return None
    return json.loads(response.text)


# DEPRECATED
def metadata_get(start: int | None = None, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Return a metadata entry.

    Deprecated: use `tlm` or `get_tlm_packet` on a metadata packet (since
    7.5.0). See https://docs.openc3.com/docs/guides/metadata

    Args:
        start: Start time of the entry in epoch seconds. Defaults to the
            latest entry.
        scope: COSMOS scope.

    Returns:
        The metadata entry, or None if not found.
    """
    warnings.warn(
        "metadata_get is deprecated, use tlm or get_tlm_packet on a metadata packet. See https://docs.openc3.com/docs/guides/metadata",
        FutureWarning,
        stacklevel=2,
    )
    return _metadata_get(start, scope=scope)


def _metadata_get(start: int | None = None, scope: str = OPENC3_SCOPE):
    start_str = f"{start}" if start else "latest"
    response = openc3.script.API_SERVER.request("get", f"/openc3-api/metadata/{start_str}", scope=scope)

    # Non-existent just returns None
    if not response or response.status_code != 200:
        return None
    return json.loads(response.text)


# DEPRECATED
def metadata_set(
    metadata: dict[str, Any],
    start: int | None = None,
    color: str | None = None,
    scope: str = OPENC3_SCOPE,
) -> dict[str, Any]:
    """Create a new metadata entry.

    Deprecated: use `inject_tlm` on a metadata packet (since 7.5.0). See
    https://docs.openc3.com/docs/guides/metadata

    Args:
        metadata: Metadata key/value pairs.
        start: Start time of the entry in epoch seconds. Defaults to now.
        color: Color of the entry in the Calendar tool. Defaults to blue
            ("#003784").
        scope: COSMOS scope.

    Returns:
        The created metadata entry.

    Raises:
        TypeError: If metadata is not a dict.
        RuntimeError: If the entry overlaps an existing entry or the request
            fails.
    """
    warnings.warn(
        "metadata_set is deprecated, use inject_tlm on a metadata packet. See https://docs.openc3.com/docs/guides/metadata",
        FutureWarning,
        stacklevel=2,
    )
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


# DEPRECATED
def metadata_update(
    metadata: dict[str, Any],
    start: int | None = None,
    color: str | None = None,
    scope: str = OPENC3_SCOPE,
) -> dict[str, Any]:
    """Update an existing metadata entry.

    Deprecated: use `inject_tlm` with only the changed items (since 7.5.0).
    See https://docs.openc3.com/docs/guides/metadata

    When start is None the latest entry is updated and the given metadata is
    merged into its existing metadata. Otherwise the entry's metadata is
    replaced.

    Args:
        metadata: Metadata key/value pairs.
        start: Start time of the entry in epoch seconds. Defaults to the
            latest entry.
        color: Color of the entry in the Calendar tool. Defaults to the
            latest entry's color when start is None, otherwise blue
            ("#003784").
        scope: COSMOS scope.

    Returns:
        The updated metadata entry.

    Raises:
        TypeError: If metadata is not a dict.
        RuntimeError: If the request fails.
    """
    warnings.warn(
        "metadata_update is deprecated, use inject_tlm with only the changed items. See https://docs.openc3.com/docs/guides/metadata",
        FutureWarning,
        stacklevel=2,
    )
    if not isinstance(metadata, dict):
        raise TypeError(f"metadata must be a Hash: {metadata} is a {metadata.__class__.__name__}")

    if start is None:  # No start so grab latest
        existing = _metadata_get(scope=scope)
        start = existing["start"]
        if not color:
            color = existing["color"]
        metadata = existing["metadata"] | metadata
    else:
        if not color:
            color = "#003784"

    data = {
        "color": color,
        "metadata": metadata,
        "start": time.asctime(time.gmtime(start)),
    }
    response = openc3.script.API_SERVER.request(
        "put", f"/openc3-api/metadata/{start}", data=data, json=True, scope=scope
    )
    if not response or response.status_code != 200:
        raise RuntimeError("Failed to update metadata")

    return json.loads(response.text)


# DEPRECATED
def metadata_input(*args: Any, **kwargs: Any) -> NoReturn:
    """Prompt the user for metadata in Script Runner.

    Deprecated: use the user input methods followed by `inject_tlm` (since
    7.5.0). See https://docs.openc3.com/docs/guides/metadata

    Args:
        *args: Ignored.
        **kwargs: Ignored.

    Raises:
        RuntimeError: Always, as this is only available in Script Runner.
    """
    warnings.warn(
        "metadata_input is deprecated, use the user input methods followed by inject_tlm. See https://docs.openc3.com/docs/guides/metadata",
        FutureWarning,
        stacklevel=2,
    )
    raise RuntimeError("can only be used in Script Runner")
