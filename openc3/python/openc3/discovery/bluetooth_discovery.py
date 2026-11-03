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


KEYS = ("local_name", "service_uuid", "service_data_uuid", "manufacturer_id", "manufacturer_data_start")


class BluetoothDiscovery(Discovery):
    """Lists the addresses of Bluetooth LE devices advertising nearby.

    Each parameter is a matcher of |-separated conditions that must all hold:
    local_name=<glob> (case sensitive), service_uuid=<uuid>,
    service_data_uuid=<uuid>, manufacturer_id=<id> or
    manufacturer_data_start=<hex bytes> (the start of the data of the matcher's
    manufacturer_id, or of any manufacturer), e.g.
    local_name=Govee*|manufacturer_id=34818 or
    manufacturer_id=76|manufacturer_data_start=0215BB70. A device is listed if any matcher
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
            if key not in KEYS:
                raise ValueError(f"Unknown Bluetooth matcher condition '{key}' in '{text}'")
            if key == "manufacturer_id":
                conditions[key] = int(value, 0)
            elif key == "manufacturer_data_start":
                try:
                    conditions[key] = bytes.fromhex(value.strip()).hex()
                except ValueError as error:
                    raise ValueError(f"manufacturer_data_start must be hex bytes in '{text}'") from error
            else:
                conditions[key] = value.strip()
        return conditions

    @staticmethod
    def _matches(device, matcher):
        for key, expected in matcher.items():
            if key == "local_name":
                if not device["name"] or not fnmatch(device["name"], expected):
                    return False
            elif key == "service_uuid":
                if expected.lower() not in device["service_uuids"]:
                    return False
            elif key == "service_data_uuid":
                if expected.lower() not in device["service_data_uuids"]:
                    return False
            elif key == "manufacturer_id":
                if str(expected) not in device["manufacturer_data"]:
                    return False
            else:
                manufacturer_id = matcher.get("manufacturer_id")
                data = device["manufacturer_data"]
                candidates = [data.get(str(manufacturer_id), "")] if manufacturer_id is not None else data.values()
                if not any(value.startswith(expected) for value in candidates):
                    return False
        return True

    def scan(self):
        try:
            from bleak import BleakScanner
        except ImportError as error:
            raise RuntimeError("The bleak Python package is not installed on the host") from error

        found = asyncio.run(BleakScanner.discover(timeout=self.SCAN_SECONDS, return_adv=True))
        devices = []
        for address, (device, advertisement) in sorted(found.items()):
            name = advertisement.local_name or device.name
            devices.append(
                {
                    "value": address,
                    "text": f"{name} ({address})" if name else address,
                    "name": name,
                    "service_uuids": [uuid.lower() for uuid in advertisement.service_uuids or []],
                    "service_data_uuids": [uuid.lower() for uuid in (advertisement.service_data or {})],
                    # Hex data by manufacturer ID, as strings for JSON
                    "manufacturer_data": {
                        str(manufacturer_id): bytes(data).hex()
                        for manufacturer_id, data in sorted((advertisement.manufacturer_data or {}).items())
                    },
                }
            )
        return devices

    def match(self, device):
        return not self.matchers or any(self._matches(device, matcher) for matcher in self.matchers)
