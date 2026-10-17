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

from openc3.discovery.discovery import Discovery


class HidDiscovery(Discovery):
    """Lists the serial numbers of USB HID devices on the host, optionally limited
    to a vendor ID and product ID (decimal or 0x hex), e.g. 0x054C 0x0CE6 for a
    PS5 DualSense controller"""

    def __init__(self, vendor_id=None, product_id=None):
        super().__init__(vendor_id, product_id)
        self.vendor_id = self._parse_id(vendor_id)
        self.product_id = self._parse_id(product_id)

    @staticmethod
    def _parse_id(value):
        if value is None or str(value).upper() in ("", "NIL", "NONE"):
            return 0
        return int(str(value), 0)

    def discover(self):
        try:
            import hid
        except ImportError as error:
            raise RuntimeError("The hidapi Python package is not installed on the host") from error

        results = []
        seen = set()
        # hid.enumerate treats 0 as a wildcard for both IDs
        for device in hid.enumerate(self.vendor_id, self.product_id):
            serial_number = device.get("serial_number")
            # Composite devices report one entry per HID interface so dedupe by serial number
            if not serial_number or serial_number in seen:
                continue
            seen.add(serial_number)
            product = device.get("product_string") or f"{device['vendor_id']:04X}:{device['product_id']:04X}"
            results.append({"value": serial_number, "text": f"{product} ({serial_number})"})
        return results
