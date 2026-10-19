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
    """Lists the serial ports available on the host, optionally limited to USB
    devices with the given hex VID:PID parameters, e.g. 10C4:EA60. The PID can
    be omitted (or *) to match any product of a vendor."""

    # Ports that exist on every Mac but are never connected to hardware
    IGNORED_DEVICES = ["/dev/cu.debug-console", "/dev/cu.Bluetooth-Incoming-Port"]

    def __init__(self, *usb_ids):
        super().__init__(*usb_ids)
        self.usb_ids = set()
        for usb_id in usb_ids:
            vid, _, pid = usb_id.partition(":")
            try:
                self.usb_ids.add((int(vid, 16), None if pid in ("", "*") else int(pid, 16)))
            except ValueError as error:
                raise ValueError(f"USB ID '{usb_id}' must be VID:PID in hex, e.g. 10C4:EA60") from error

    def discover(self):
        results = []
        for port in sorted(list_ports.comports(), key=lambda port: port.device):
            if port.device in self.IGNORED_DEVICES:
                continue
            if self.usb_ids and (port.vid, port.pid) not in self.usb_ids and (port.vid, None) not in self.usb_ids:
                continue
            text = port.device
            if port.description and port.description != "n/a" and port.description != port.device:
                text = f"{port.device} - {port.description}"
            results.append({"value": port.device, "text": text})
        return results
