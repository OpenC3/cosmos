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

    {"devices": [{"class": ..., "value": ..., "text": ..., "details": {...}, "matches": ["1"],
                  "matched_params": {"1": [0]}}],
     "errors": {"<class>": "..."}, "skipped": {"<matcher id>": "..."}}

A matcher's parameters are alternatives for most classes (the device matches
if any does), so matched_params lists the indexes of the ones that matched,
which tells COSMOS how specifically the device was recognized.

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
    "openc3.discovery.usb_discovery",
    "openc3.discovery.ssdp_discovery",
    "openc3.discovery.neighbor_discovery",
]


# Classes whose parameters together describe one device, rather than being
# alternatives that each match on their own
COMBINED_PARAM_CLASSES = {"openc3.discovery.hid_discovery"}


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
        params = matcher.get("params", [])
        try:
            if name in COMBINED_PARAM_CLASSES or len(params) <= 1:
                checks.append((matcher["id"], [(None, discovery_class(*params))]))
            else:
                # Each alternative separately, to know which matched
                checks.append((matcher["id"], [(index, discovery_class(param)) for index, param in enumerate(params)]))
        except Exception as error:
            skipped[matcher["id"]] = f"{error.__class__.__name__}: {error}"

    # A value can be found more than once, e.g. a host advertising several mDNS
    # services, so it's one device that matches if any of its records does
    devices = {}
    for record in discovery_class().scan():
        value = str(record["value"])
        device = devices.get(value)
        if device is None:
            details = {key: item for key, item in record.items() if key not in ("value", "text")}
            device = devices[value] = {
                "class": name,
                "value": value,
                "text": str(record.get("text") or value),
                "details": details,
                "matches": [],
                "matched_params": {},
            }
        for matcher_id, alternatives in checks:
            for index, check in alternatives:
                indexes = device["matched_params"].get(matcher_id, [])
                if (index is None and matcher_id in device["matches"]) or index in indexes or not check.match(record):
                    continue
                if matcher_id not in device["matches"]:
                    device["matches"].append(matcher_id)
                if index is not None:
                    device["matched_params"][matcher_id] = sorted([*indexes, index])
    return list(devices.values()), skipped


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
