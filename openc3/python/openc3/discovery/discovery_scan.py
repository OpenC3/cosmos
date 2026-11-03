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

"""Scans the host for hardware and checks it against discovery matchers.

Used by openc3-app on the host to answer hardware discovery requests from
COSMOS, which proposes plugins for the devices found:

    python -m openc3.discovery.discovery_scan < request.json

The request is a JSON object with the matchers of the plugins to check, each a
discovery class and the parameters that must discover the device (see
PluginModel.discovery_matchers), and optionally the classes to scan:

    {"matchers": [{"id": "1", "class": "openc3.discovery.hid_discovery", "params": ["0x054C", "0x0CE6"]}],
     "classes": ["openc3.discovery.hid_discovery"]}

Each class scans once, in parallel, and every matcher is checked against its
devices. Without "classes" every scannable class is scanned, so devices no
matcher recognizes are listed too. Prints a single JSON object:

    {"devices": [{"class": ..., "value": ..., "text": ..., "details": {...}, "matches": ["1"]}],
     "errors": {"<class>": "..."}, "skipped": {"<matcher id>": "..."}}

Only the discovery classes shipped with COSMOS are run, never code from a
plugin, since matchers come from plugins that aren't installed.
"""

import contextlib
import importlib
import json
import sys
from concurrent.futures import ThreadPoolExecutor

from openc3.discovery.discovery_runner import load_discovery_class


# The discovery classes that can scan for hardware, as discovery class keys
SCAN_CLASSES = [
    "openc3.discovery.serial_discovery",
    "openc3.discovery.hid_discovery",
    "openc3.discovery.zeroconf_discovery",
    "openc3.discovery.bluetooth_discovery",
]


def class_key(name):
    """The module form of a discovery class given as a filename or module, as
    PluginModel.discovery_class_key does"""
    return str(name).removesuffix(".py").replace("/", ".")


def scan_class(name, matchers):
    """Scan for one class's devices and check them against its matchers.
    Returns (devices, skipped matcher reasons)."""
    discovery_class = load_discovery_class(name)
    skipped = {}
    checks = []
    for matcher in matchers:
        try:
            checks.append((matcher["id"], discovery_class(*matcher.get("params", []))))
        except Exception as error:
            skipped[matcher["id"]] = f"{error.__class__.__name__}: {error}"

    devices = []
    seen = set()
    for device in discovery_class().scan():
        if device["value"] in seen:
            continue
        seen.add(device["value"])
        details = {key: value for key, value in device.items() if key not in ("value", "text")}
        devices.append(
            {
                "class": name,
                "value": str(device["value"]),
                "text": str(device.get("text") or device["value"]),
                "details": details,
                "matches": [matcher_id for matcher_id, check in checks if check.match(device)],
            }
        )
    return devices, skipped


def scan(request):
    matchers_by_class = {}
    skipped = {}
    for matcher in request.get("matchers") or []:
        name = class_key(matcher.get("class"))
        if name not in SCAN_CLASSES:
            skipped[matcher["id"]] = f"{matcher.get('class')} is not a discovery class COSMOS can scan with"
            continue
        matchers_by_class.setdefault(name, []).append(matcher)

    classes = [class_key(name) for name in request.get("classes") or SCAN_CLASSES]
    classes = [name for name in SCAN_CLASSES if name in classes]
    devices = []
    errors = {}
    for name in classes:
        # A class that can't load reports it when scanning
        with contextlib.suppress(Exception):
            for module in load_discovery_class(name).MAIN_THREAD_IMPORTS:
                # A missing package is reported by the class's scan()
                with contextlib.suppress(ImportError):
                    importlib.import_module(module)
    with ThreadPoolExecutor(max_workers=len(classes) or 1) as executor:
        futures = {name: executor.submit(scan_class, name, matchers_by_class.get(name, [])) for name in classes}
        for name, future in futures.items():
            try:
                class_devices, class_skipped = future.result()
            except Exception as error:
                errors[name] = f"{error.__class__.__name__}: {error}"
                continue
            devices.extend(class_devices)
            skipped.update(class_skipped)
    # Matchers of classes that weren't scanned didn't get a chance to match
    for name, matchers in matchers_by_class.items():
        if name not in classes:
            for matcher in matchers:
                skipped[matcher["id"]] = f"{name} was not scanned"
    return {"devices": devices, "errors": errors, "skipped": skipped}


def main(stdin=None):
    try:
        request = json.load(stdin or sys.stdin)
        # Keep stdout clean for the JSON response if a discovery class prints
        with contextlib.redirect_stdout(sys.stderr):
            response = scan(request)
    except Exception as error:
        print(json.dumps({"error": f"{error.__class__.__name__}: {error}"}))
        return 1
    # default=str keeps odd attribute types (e.g. bytes) from failing the response
    print(json.dumps(response, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
