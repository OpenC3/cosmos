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
    """

    def __init__(self, *args):
        self.args = args

    def discover(self):
        """Return a list of discovered values. Each entry is either a value string
        or a dict with a 'value' key and an optional 'text' description."""
        raise NotImplementedError(f"{self.__class__.__name__} must implement discover()")
