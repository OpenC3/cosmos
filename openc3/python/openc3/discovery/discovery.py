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


class Discovery:
    """Base class for discovering hardware available on the host computer.

    Discovery classes run on the host (via openc3-app and the COSMOS bridge), not
    inside COSMOS, so they can see local devices such as serial ports and USB HID
    devices. They are referenced from plugin.txt by filename, for example
    VARIABLE_DISCOVERY openc3/discovery/serial_discovery.py, and any additional
    parameters are passed to the constructor as strings.

    Discovery classes either implement discover(), or scan() and match() so
    hardware discovery (discovery_scan.py) can scan for devices once and check
    them against many sets of parameters.
    """

    # Python modules scan() uses that must first be imported on the main thread,
    # since discovery_scan.py scans with each class in its own thread
    MAIN_THREAD_IMPORTS = []

    def __init__(self, *args):
        self.args = args

    def scan(self):
        """Return the devices this class can see, limited by the parameters where
        that makes scanning faster. Each is a dict with a 'value' (what goes into
        the plugin variable), a 'text' description, and any other attributes
        match() checks, which must be JSON serializable."""
        raise NotImplementedError(f"{self.__class__.__name__} does not implement scan()")

    def match(self, device):
        """Whether a device from scan() is one these parameters discover"""
        return True

    def discover(self):
        """Return a list of discovered values. Each entry is either a value string
        or a dict with a 'value' key and an optional 'text' description."""
        results = []
        seen = set()
        for device in self.scan():
            if device["value"] in seen or not self.match(device):
                continue
            seen.add(device["value"])
            results.append({"value": device["value"], "text": device["text"]})
        return results
