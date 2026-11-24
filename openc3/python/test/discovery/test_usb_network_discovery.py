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

import socket
import sys
import types
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from openc3.discovery.neighbor_discovery import NeighborDiscovery
from openc3.discovery.ssdp_discovery import SsdpDiscovery
from openc3.discovery.usb_discovery import UsbDiscovery


def fake_usb_device(vid, pid, bus, ports, strings, device_class=(0, 0, 0), interfaces=(), address=1):
    """A pyusb device: iterating gives configurations, which give interfaces"""
    indexes = {name: index for index, name in enumerate(("manufacturer", "product", "serial_number"), start=1)}
    configuration = [
        SimpleNamespace(bInterfaceClass=c, bInterfaceSubClass=s, bInterfaceProtocol=p) for c, s, p in interfaces
    ]

    class Device(SimpleNamespace):
        def __iter__(self):
            return iter([configuration])

    return Device(
        idVendor=vid,
        idProduct=pid,
        bus=bus,
        address=address,
        port_numbers=ports,
        bDeviceClass=device_class[0],
        bDeviceSubClass=device_class[1],
        bDeviceProtocol=device_class[2],
        iManufacturer=indexes["manufacturer"] if strings.get("manufacturer") else 0,
        iProduct=indexes["product"] if strings.get("product") else 0,
        iSerialNumber=indexes["serial_number"] if strings.get("serial_number") else 0,
        strings={indexes[key]: value for key, value in strings.items()},
    )


class TestUsbDiscovery(unittest.TestCase):
    def scan(self, devices, *matchers):
        usb = types.ModuleType("usb")
        usb.core = types.SimpleNamespace(find=Mock(return_value=devices))
        usb.util = types.SimpleNamespace(get_string=lambda device, index: device.strings[index])
        with (
            patch.dict(sys.modules, {"usb": usb, "usb.core": usb.core, "usb.util": usb.util, "libusb_package": None}),
            patch.object(sys, "platform", "darwin"),
        ):
            discovery = UsbDiscovery(*matchers)
            found = discovery.scan()
        return discovery, found

    def test_lists_devices_except_hubs(self):
        devices = [
            fake_usb_device(0x05E3, 0x0610, 1, (1,), {"product": "Hub"}, device_class=(9, 0, 1)),
            fake_usb_device(
                0x0BDA,
                0x2838,
                1,
                (2,),
                {"manufacturer": "Realtek", "product": "RTL2838UHIDIR", "serial_number": "00000001"},
            ),
            fake_usb_device(0x1366, 0x1051, 1, (3, 1), {"product": "J-Link"}, interfaces=[(0xFF, 0xFF, 0xFF)]),
        ]
        _, found = self.scan(devices)
        self.assertEqual([device["value"] for device in found], ["00000001", "1-3.1"])
        self.assertEqual(found[0]["text"], "Realtek RTL2838UHIDIR (0BDA:2838)")
        self.assertEqual(found[1]["text"], "J-Link (1366:1051)")
        self.assertEqual(found[1]["interfaces"], [[0xFF, 0xFF, 0xFF]])
        self.assertEqual(found[1]["location"], "1-3.1")

    def test_matches_ids_classes_and_strings(self):
        camera = {"vid": 0x046D, "pid": 0x085E, "class": [0xEF, 2, 1], "interfaces": [[0x0E, 1, 0], [0x0E, 2, 0]]}
        camera.update({"manufacturer": "Logitech", "product": "BRIO", "serial_number": "ABC"})
        scope = {"vid": 0x0957, "pid": 0x1796, "class": [0, 0, 0], "interfaces": [[0xFE, 3, 1]]}
        scope.update({"manufacturer": "Agilent", "product": "DSO-X 2024A", "serial_number": None})

        def matches(*matchers):
            discovery = UsbDiscovery(*matchers)
            return [device["product"] for device in (camera, scope) if discovery.match(device)]

        self.assertEqual(matches(), ["BRIO", "DSO-X 2024A"])
        self.assertEqual(matches("046D:085E"), ["BRIO"])
        self.assertEqual(matches("046D"), ["BRIO"])
        self.assertEqual(matches("046D:*|product=bri*"), ["BRIO"])
        self.assertEqual(matches("046D:*|product=c920*"), [])
        self.assertEqual(matches("class=0E"), ["BRIO"])
        self.assertEqual(matches("class=FE/03"), ["DSO-X 2024A"])
        self.assertEqual(matches("class=FE/03/02"), [])
        self.assertEqual(matches("class=EF/02"), ["BRIO"])
        self.assertEqual(matches("vid=0957|pid=1796"), ["DSO-X 2024A"])
        self.assertEqual(matches("serial=a*"), ["BRIO"])
        self.assertEqual(matches("serial=*"), ["BRIO"])

    def test_bad_matcher(self):
        for matcher in ("xyz", "class=", "color=red", "class=1/2/3/4"):
            with self.assertRaisesRegex(ValueError, "USB matcher"):
                UsbDiscovery(matcher)

    def test_unreadable_strings(self):
        device = fake_usb_device(0x2E8A, 0x0003, 2, (1,), {"product": "RP2 Boot"})

        def denied(*_args):
            raise ValueError(
                "The device has no langid (permission issue, no string descriptors supported or device error)"
            )

        usb = types.ModuleType("usb")
        usb.core = types.SimpleNamespace(find=Mock(return_value=[device]))
        usb.util = types.SimpleNamespace(get_string=denied)
        with patch.dict(sys.modules, {"usb": usb, "usb.core": usb.core, "usb.util": usb.util, "libusb_package": None}):
            found = UsbDiscovery().scan()
        self.assertEqual(found[0]["text"], "USB device (2E8A:0003)")
        self.assertEqual(found[0]["value"], "2-1")

    def test_missing_pyusb(self):
        with patch.dict(sys.modules, {"usb": None, "usb.core": None}), self.assertRaisesRegex(RuntimeError, "pyusb"):
            UsbDiscovery().scan()


DESCRIPTION = b"""<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:ZonePlayer:1</deviceType>
    <friendlyName>Living Room</friendlyName>
    <manufacturer>Sonos, Inc.</manufacturer>
    <modelName>Sonos Era 100</modelName>
    <deviceList>
      <device>
        <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
        <manufacturer>Sonos, Inc.</manufacturer>
        <modelName>Renderer</modelName>
      </device>
    </deviceList>
  </device>
</root>"""


class TestSsdpDiscovery(unittest.TestCase):
    def responses(self):
        def response(st, location):
            return (
                f"HTTP/1.1 200 OK\r\nST: {st}\r\nUSN: uuid:RINCON::{st}\r\nSERVER: Linux UPnP/1.0 Sonos/80\r\n"
                f"LOCATION: {location}\r\n\r\n"
            ).encode()

        return [
            (
                response("upnp:rootdevice", "http://192.168.1.26:1400/xml/device_description.xml"),
                ("192.168.1.26", 1900),
            ),
            (
                response(
                    "urn:schemas-upnp-org:device:ZonePlayer:1", "http://192.168.1.26:1400/xml/device_description.xml"
                ),
                ("192.168.1.26", 1900),
            ),
            # A device can only point at its own address
            (response("upnp:rootdevice", "http://10.0.0.1/evil.xml"), ("192.168.1.30", 1900)),
            (b"NOTIFY * HTTP/1.1\r\n\r\n", ("192.168.1.40", 1900)),
        ]

    def scan(self, *matchers, description=DESCRIPTION):
        sock = Mock()
        sock.recvfrom.side_effect = [*self.responses(), TimeoutError()]
        fetched = []

        class Response:
            def __init__(self, url):
                fetched.append(url)

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self, size):
                return description

        opener = Mock()
        opener.open.side_effect = lambda url, timeout: Response(url)
        with (
            patch("socket.socket", return_value=sock),
            patch("urllib.request.build_opener", return_value=opener),
        ):
            discovery = SsdpDiscovery(*matchers)
            found = discovery.scan()
        return discovery, found, fetched, sock

    def test_lists_devices_with_their_descriptions(self):
        _, found, fetched, sock = self.scan()
        self.assertIn(b"ST: ssdp:all", sock.sendto.call_args[0][0])
        self.assertEqual(fetched, ["http://192.168.1.26:1400/xml/device_description.xml"])
        self.assertEqual([device["value"] for device in found], ["192.168.1.26", "192.168.1.30"])
        sonos, other = found
        self.assertEqual(sonos["text"], "Living Room (192.168.1.26)")
        self.assertEqual(sonos["st"], ["upnp:rootdevice", "urn:schemas-upnp-org:device:ZonePlayer:1"])
        self.assertEqual([device["modelname"] for device in sonos["devices"]], ["Sonos Era 100", "Renderer"])
        self.assertEqual(other["text"], "Linux UPnP/1.0 Sonos/80 (192.168.1.30)")
        self.assertIsNone(other["location"])

    def test_matches_headers_and_one_device_description(self):
        discovery, found, _, _ = self.scan()
        sonos = found[0]

        def match(matcher):
            return SsdpDiscovery(matcher).match(sonos)

        self.assertTrue(match("st=urn:schemas-upnp-org:device:ZonePlayer:*"))
        self.assertTrue(match("manufacturer=sonos*|modelname=Sonos?Era*"))
        self.assertTrue(match("devicetype=*:MediaRenderer:1|modelname=renderer"))
        # Conditions on the description must hold for the same device
        self.assertFalse(match("devicetype=*:MediaRenderer:1|modelname=Sonos?Era*"))
        self.assertFalse(match("st=roku:ecp"))
        self.assertTrue(discovery.match(sonos))

    def test_rejects_unsafe_descriptions(self):
        bomb = b'<?xml version="1.0"?><!DOCTYPE lolz [<!ENTITY lol "lol">]><root><device><manufacturer>&lol;</manufacturer></device></root>'
        _, found, _, _ = self.scan(description=bomb)
        self.assertEqual(found[0]["devices"], [])
        self.assertEqual(found[0]["text"], "Linux UPnP/1.0 Sonos/80 (192.168.1.26)")

    def test_bad_matcher(self):
        for matcher in ("sonos", "color=red"):
            with self.assertRaisesRegex(ValueError, "SSDP matcher"):
                SsdpDiscovery(matcher)


MACOS_ARP = """? (192.168.1.1) at e4:38:83:9b:72:e8 on en0 ifscope [ethernet]
? (192.168.1.30) at 98:a3:16:ee:7c:c on en0 ifscope [ethernet]
? (192.168.1.40) at (incomplete) on en0 ifscope [ethernet]
? (192.168.1.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
? (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
"""

WINDOWS_ARP = """
Interface: 192.168.1.5 --- 0x4
  Internet Address      Physical Address      Type
  192.168.1.1           e4-38-83-9b-72-e8     dynamic
  192.168.1.30          98-a3-16-ee-7c-0c     dynamic
  224.0.0.22            01-00-5e-00-00-16     static
"""

LINUX_ARP = """IP address       HW type     Flags       HW address            Mask     Device
192.168.1.1      0x1         0x2         e4:38:83:9b:72:e8     *        eth0
192.168.1.40     0x1         0x0         00:00:00:00:00:00     *        eth0
192.168.1.30     0x1         0x2         98:a3:16:ee:7c:0c     *        eth0
"""


class TestNeighborDiscovery(unittest.TestCase):
    def test_parses_each_platform(self):
        expected = [("192.168.1.1", "E4:38:83:9B:72:E8"), ("192.168.1.30", "98:A3:16:EE:7C:0C")]
        for table in (
            NeighborDiscovery._parse_arp_output(MACOS_ARP),
            NeighborDiscovery._parse_arp_output(WINDOWS_ARP),
            NeighborDiscovery._parse_proc_arp(LINUX_ARP),
        ):
            discovery = NeighborDiscovery()
            with (
                patch.object(NeighborDiscovery, "_read_table", return_value=table),
                patch("socket.gethostbyaddr", side_effect=OSError),
            ):
                found = discovery.scan()
            self.assertEqual([(device["value"], device["mac"]) for device in found], expected)
        self.assertEqual(NeighborDiscovery._parse_arp_output(MACOS_ARP)[0][2], "en0")

    def test_names_and_matches(self):
        table = NeighborDiscovery._parse_arp_output(MACOS_ARP)

        def gethostbyaddr(ip):
            if ip == "192.168.1.30":
                return ("wled-ee7c0c.localdomain.", [], [ip])
            raise socket.herror

        with (
            patch.object(NeighborDiscovery, "_read_table", return_value=table),
            patch("socket.gethostbyaddr", side_effect=gethostbyaddr),
        ):
            found = NeighborDiscovery().scan()
        router, wled = found
        self.assertEqual(router["text"], "192.168.1.1 (E4:38:83:9B:72:E8)")
        self.assertEqual(wled["text"], "wled-ee7c0c.localdomain (192.168.1.30)")

        def matches(matcher):
            return [device["value"] for device in found if NeighborDiscovery(matcher).match(device)]

        self.assertEqual(matches("mac=98A316*"), ["192.168.1.30"])
        self.assertEqual(matches("mac=98:a3:16*"), ["192.168.1.30"])
        self.assertEqual(matches("hostname=wled-*"), ["192.168.1.30"])
        self.assertEqual(matches("hostname=*.localdomain|mac=E43883*"), [])
        self.assertEqual(matches("ip=192.168.1.1"), ["192.168.1.1"])

    def test_slow_hostnames_dont_hold_up_the_scan(self):
        discovery = NeighborDiscovery()
        discovery.HOSTNAME_TIMEOUT_S = 0.1
        release = __import__("threading").Event()

        def slow(ip):
            release.wait(5)
            raise OSError

        with patch("socket.gethostbyaddr", side_effect=slow):
            self.assertEqual(discovery._hostnames(["192.168.1.1"]), {})
        release.set()

    def test_unreadable_table(self):
        with (
            patch.object(sys, "platform", "darwin"),
            patch("subprocess.run", side_effect=FileNotFoundError("arp")),
            self.assertRaisesRegex(RuntimeError, "neighbor table"),
        ):
            NeighborDiscovery().scan()

    def test_bad_matcher(self):
        for matcher in ("98A316", "vendor=apple"):
            with self.assertRaisesRegex(ValueError, "Neighbor matcher"):
                NeighborDiscovery(matcher)
