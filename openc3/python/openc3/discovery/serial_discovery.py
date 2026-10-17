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

from serial.tools import list_ports

from openc3.discovery.discovery import Discovery


class SerialDiscovery(Discovery):
    """Lists the serial ports available on the host"""

    # Ports that exist on every Mac but are never connected to hardware
    IGNORED_DEVICES = ["/dev/cu.debug-console", "/dev/cu.Bluetooth-Incoming-Port"]

    def discover(self):
        results = []
        for port in sorted(list_ports.comports(), key=lambda port: port.device):
            if port.device in self.IGNORED_DEVICES:
                continue
            text = port.device
            if port.description and port.description != "n/a" and port.description != port.device:
                text = f"{port.device} - {port.description}"
            results.append({"value": port.device, "text": text})
        return results
