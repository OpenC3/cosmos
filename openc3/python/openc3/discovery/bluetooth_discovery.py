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

import asyncio
from fnmatch import fnmatch

from openc3.discovery.discovery import Discovery


class BluetoothDiscovery(Discovery):
    """Lists the addresses of Bluetooth LE devices advertising nearby.

    Each parameter is a matcher of |-separated conditions that must all hold:
    local_name=<glob> (case sensitive), service_uuid=<uuid>,
    service_data_uuid=<uuid> or manufacturer_id=<id>, e.g.
    local_name=Govee*|manufacturer_id=34818. A device is listed if any matcher
    matches, or every device is listed without matchers. On macOS the address is
    the CoreBluetooth UUID of the device. Requires the bleak package."""

    SCAN_SECONDS = 5.0

    def __init__(self, *matchers):
        super().__init__(*matchers)
        self.matchers = [self._parse_matcher(matcher) for matcher in matchers if matcher]

    @staticmethod
    def _parse_matcher(text):
        conditions = {}
        for item in text.split("|"):
            key, _, value = item.partition("=")
            key = key.strip().lower()
            if key not in ("local_name", "service_uuid", "service_data_uuid", "manufacturer_id"):
                raise ValueError(f"Unknown Bluetooth matcher condition '{key}' in '{text}'")
            conditions[key] = int(value, 0) if key == "manufacturer_id" else value.strip()
        return conditions

    @staticmethod
    def _matches(name, advertisement, matcher):
        for key, expected in matcher.items():
            if key == "local_name":
                if not name or not fnmatch(name, expected):
                    return False
            elif key == "service_uuid":
                if expected.lower() not in [uuid.lower() for uuid in advertisement.service_uuids or []]:
                    return False
            elif key == "service_data_uuid":
                if expected.lower() not in [uuid.lower() for uuid in (advertisement.service_data or {})]:
                    return False
            elif expected not in (advertisement.manufacturer_data or {}):
                return False
        return True

    def discover(self):
        try:
            from bleak import BleakScanner
        except ImportError as error:
            raise RuntimeError("The bleak Python package is not installed on the host") from error

        devices = asyncio.run(BleakScanner.discover(timeout=self.SCAN_SECONDS, return_adv=True))
        results = []
        for address, (device, advertisement) in sorted(devices.items()):
            name = advertisement.local_name or device.name
            if self.matchers and not any(self._matches(name, advertisement, matcher) for matcher in self.matchers):
                continue
            results.append({"value": address, "text": f"{name} ({address})" if name else address})
        return results
