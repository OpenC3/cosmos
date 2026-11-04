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

import sys
from fnmatch import fnmatch
from pathlib import Path

from openc3.discovery.discovery import Discovery


class UsbDiscovery(Discovery):
    """Lists the USB devices on the host (except hubs), such as cameras, software
    defined radios, debug probes and test instruments, which aren't serial ports
    or HID devices. The value is the device's serial number, or its location
    (bus-port path, e.g. 1-2.3) when it has none.

    Each parameter is a matcher made of conditions joined with |. A condition is
    a hex VID:PID like 0BDA:2838 (the PID can be omitted or *), vid=hex,
    pid=hex, class=hex (the device class or the class of any of its interfaces,
    optionally with /subclass and /protocol, e.g. class=FE/03 for USB test and
    measurement devices or class=0E for cameras), or manufacturer=glob,
    product=glob or serial=glob (case-insensitive). Requires the pyusb package
    and libusb, which the libusb-package package provides."""

    CONDITION_KEYS = ("vid", "pid", "class", "manufacturer", "product", "serial")
    HUB_CLASS = 0x09
    # Linux sysfs, which has the device strings without needing access to the device
    SYSFS_DEVICES = Path("/sys/bus/usb/devices")

    def __init__(self, *matchers):
        super().__init__(*matchers)
        self.matchers = [self._parse_matcher(matcher) for matcher in matchers if matcher]

    @classmethod
    def _parse_matcher(cls, text):
        conditions = []
        for item in text.split("|"):
            item = item.strip()
            key, separator, value = item.partition("=")
            try:
                if not separator:
                    # VID:PID shorthand
                    vid, _, pid = item.partition(":")
                    conditions.append(("vid", int(vid, 16)))
                    if pid not in ("", "*"):
                        conditions.append(("pid", int(pid, 16)))
                    continue
                key = key.strip().lower()
                value = value.strip()
                if key in ("vid", "pid"):
                    conditions.append((key, int(value, 16)))
                elif key == "class":
                    parts = tuple(int(part, 16) for part in value.split("/"))
                    if not 1 <= len(parts) <= 3:
                        raise ValueError
                    conditions.append((key, parts))
                elif key in cls.CONDITION_KEYS:
                    conditions.append((key, value.lower()))
                else:
                    raise ValueError
            except ValueError as error:
                raise ValueError(
                    f"USB matcher '{text}' must be a hex VID:PID or conditions like vid=054C, pid=0CE6, "
                    f"class=FE/03, manufacturer=glob, product=glob or serial=glob joined with |"
                ) from error
        return conditions

    @staticmethod
    def _condition_matches(device, key, expected):
        if key in ("vid", "pid"):
            return device.get(key) == expected
        if key == "class":
            classes = [device.get("class") or []] + list(device.get("interfaces") or [])
            return any(list(usb_class[: len(expected)]) == list(expected) for usb_class in classes)
        value = device.get("serial_number" if key == "serial" else key)
        return value is not None and fnmatch(str(value).lower(), expected)

    def match(self, device):
        if not self.matchers:
            return True
        return any(
            all(self._condition_matches(device, key, expected) for key, expected in matcher)
            for matcher in self.matchers
        )

    def scan(self):
        try:
            import usb.core
        except ImportError as error:
            raise RuntimeError("The pyusb Python package is not installed on the host") from error

        devices = []
        seen = set()
        for usb_device in usb.core.find(find_all=True, backend=self._backend()):
            if usb_device.bDeviceClass == self.HUB_CLASS:
                continue
            port_numbers = getattr(usb_device, "port_numbers", None) or ()
            location = f"{usb_device.bus}-{'.'.join(str(port) for port in port_numbers)}" if port_numbers else None
            strings = self._strings(usb_device, location)
            vid = usb_device.idVendor
            pid = usb_device.idProduct
            value = strings["serial_number"] or location or f"{usb_device.bus}:{usb_device.address}"
            if value in seen:
                continue
            seen.add(value)
            name = " ".join(part for part in (strings["manufacturer"], strings["product"]) if part)
            text = f"{name or 'USB device'} ({vid:04X}:{pid:04X})"
            devices.append(
                {
                    "value": value,
                    "text": text,
                    "vid": vid,
                    "pid": pid,
                    "class": [usb_device.bDeviceClass, usb_device.bDeviceSubClass, usb_device.bDeviceProtocol],
                    "interfaces": self._interfaces(usb_device),
                    "manufacturer": strings["manufacturer"],
                    "product": strings["product"],
                    "serial_number": strings["serial_number"],
                    "location": location,
                }
            )
        return devices

    @staticmethod
    def _backend():
        # libusb-package bundles libusb for every platform, otherwise pyusb finds
        # libusb installed on the host
        try:
            import libusb_package
        except ImportError:
            return None
        return libusb_package.get_libusb1_backend()

    @staticmethod
    def _interfaces(usb_device):
        interfaces = []
        try:
            for configuration in usb_device:
                for interface in configuration:
                    usb_class = [interface.bInterfaceClass, interface.bInterfaceSubClass, interface.bInterfaceProtocol]
                    if usb_class not in interfaces:
                        interfaces.append(usb_class)
        except Exception:
            # Some platforms can't read the configuration of a device without a driver
            pass
        return interfaces

    def _strings(self, usb_device, location):
        strings = {"manufacturer": None, "product": None, "serial_number": None}
        files = {"manufacturer": "manufacturer", "product": "product", "serial_number": "serial"}
        indexes = {
            "manufacturer": usb_device.iManufacturer,
            "product": usb_device.iProduct,
            "serial_number": usb_device.iSerialNumber,
        }
        sysfs = self.SYSFS_DEVICES / location if sys.platform.startswith("linux") and location else None
        for key in strings:
            value = None
            if sysfs:
                try:
                    value = (sysfs / files[key]).read_text(errors="replace").strip()
                except OSError:
                    value = None
            if not value and indexes[key]:
                value = self._get_string(usb_device, indexes[key])
            strings[key] = value or None
        return strings

    @staticmethod
    def _get_string(usb_device, index):
        try:
            import usb.util

            return (usb.util.get_string(usb_device, index) or "").strip()
        except Exception:
            # Reading strings needs access to the device, which e.g. Windows only
            # gives devices using the WinUSB driver
            return None
