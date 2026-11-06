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

"""Runs a Discovery class and prints its results as JSON on stdout.

Used by openc3-cosmos-app on the host to answer discovery requests from COSMOS:

    python -m openc3.discovery.discovery_runner <discovery filename or module> [args...]

The discovery class is given either as a filename (openc3/discovery/hid_discovery.py)
or a module (openc3.discovery.hid_discovery) and is named after its file (HidDiscovery).

Prints a single JSON object, either {"results": [{"value": ..., "text": ...}, ...]}
or {"error": "..."} (with a non-zero exit code).
"""

import contextlib
import json
import sys

from openc3.top_level import get_class_from_module
from openc3.utilities.string import filename_to_class_name, filename_to_module


def normalize_results(results):
    """Convert discover() output into a list of {"value": str, "text": str}"""
    normalized = []
    for result in results or []:
        if isinstance(result, dict):
            value = str(result["value"])
            text = str(result.get("text") or value)
        else:
            value = str(result)
            text = value
        normalized.append({"value": value, "text": text})
    return normalized


def load_discovery_class(name):
    """Load a discovery class from a filename or module name"""
    if name.endswith(".py") or "/" in name:
        return get_class_from_module(filename_to_module(name), filename_to_class_name(name))
    return get_class_from_module(name, filename_to_class_name(name.split(".")[-1]))


def run_discovery(name, *args):
    return normalize_results(load_discovery_class(name)(*args).discover())


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 1:
        print(json.dumps({"error": "Usage: discovery_runner <discovery filename or module> [args...]"}))
        return 1
    try:
        # Keep stdout clean for the JSON response if the discovery class prints
        with contextlib.redirect_stdout(sys.stderr):
            results = run_discovery(argv[0], *argv[1:])
    except Exception as error:
        print(json.dumps({"error": f"{error.__class__.__name__}: {error}"}))
        return 1
    print(json.dumps({"results": results}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
