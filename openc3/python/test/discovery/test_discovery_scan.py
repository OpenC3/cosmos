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

import io
import json
import sys
import types
import unittest
from contextlib import redirect_stdout
from unittest.mock import Mock, patch

from openc3.discovery.bluetooth_discovery import BluetoothDiscovery
from openc3.discovery.discovery import Discovery
from openc3.discovery.discovery_scan import SCAN_CLASSES, main, scan
from openc3.discovery.hid_discovery import HidDiscovery
from openc3.discovery.serial_discovery import SerialDiscovery
from openc3.discovery.zeroconf_discovery import ZeroconfDiscovery


SERIAL = "openc3.discovery.serial_discovery"
HID = "openc3.discovery.hid_discovery"
ZEROCONF = "openc3.discovery.zeroconf_discovery"
BLUETOOTH = "openc3.discovery.bluetooth_discovery"
USB = "openc3.discovery.usb_discovery"
SSDP = "openc3.discovery.ssdp_discovery"
NEIGHBOR = "openc3.discovery.neighbor_discovery"

SERIAL_DEVICES = [
    {"value": "/dev/ttyUSB0", "text": "/dev/ttyUSB0 - CP2102", "vid": 0x10C4, "pid": 0xEA60},
    {"value": "/dev/ttyACM0", "text": "/dev/ttyACM0 - Arduino Uno", "vid": 0x2341, "pid": 0x0043},
    {"value": "/dev/ttyS0", "text": "/dev/ttyS0", "vid": None, "pid": None},
]
HID_DEVICES = [
    {"value": "abc", "text": "DualSense (abc)", "vid": 0x054C, "pid": 0x0CE6},
    {"value": "def", "text": "Keyboard (def)", "vid": 0x05AC, "pid": 0x0250},
]


class TestDiscoveryBase(unittest.TestCase):
    def test_discover_is_scan_then_match(self):
        class Even(Discovery):
            def scan(self):
                return [{"value": str(n), "text": f"#{n}", "n": n} for n in (1, 2, 2, 3, 4)]

            def match(self, device):
                return device["n"] % 2 == 0

        # Matching devices, once each, with only value and text
        self.assertEqual(Even().discover(), [{"value": "2", "text": "#2"}, {"value": "4", "text": "#4"}])

    def test_scan_is_optional(self):
        with self.assertRaisesRegex(NotImplementedError, "does not implement scan"):
            Discovery().scan()
        self.assertTrue(Discovery().match({"value": "x"}))


class TestScanAndMatch(unittest.TestCase):
    def test_serial(self):
        ports = [
            Mock(
                device="/dev/ttyUSB0",
                description="CP2102",
                vid=0x10C4,
                pid=0xEA60,
                serial_number="0001",
                manufacturer="Silicon Labs",
                product="CP2102",
            ),
            Mock(device="/dev/cu.debug-console", description="debug", vid=None, pid=None),
        ]
        with patch("openc3.discovery.serial_discovery.list_ports.comports", return_value=ports):
            devices = SerialDiscovery().scan()
        self.assertEqual(
            devices,
            [
                {
                    "value": "/dev/ttyUSB0",
                    "text": "/dev/ttyUSB0 - CP2102",
                    "vid": 0x10C4,
                    "pid": 0xEA60,
                    "serial_number": "0001",
                    "manufacturer": "Silicon Labs",
                    "product": "CP2102",
                }
            ],
        )
        self.assertTrue(SerialDiscovery("10C4:EA60").match(devices[0]))
        self.assertTrue(SerialDiscovery("10C4").match(devices[0]))
        self.assertFalse(SerialDiscovery("0403:6001").match(devices[0]))
        self.assertTrue(SerialDiscovery().match(devices[0]))

    def test_hid(self):
        hid = types.ModuleType("hid")
        hid.enumerate = Mock(
            return_value=[
                {
                    "vendor_id": 0x054C,
                    "product_id": 0x0CE6,
                    "serial_number": "abc",
                    "product_string": "DualSense",
                    "manufacturer_string": "Sony",
                }
            ]
        )
        with patch.dict(sys.modules, {"hid": hid}):
            devices = HidDiscovery().scan()
        hid.enumerate.assert_called_once_with(0, 0)
        self.assertEqual(
            devices,
            [
                {
                    "value": "abc",
                    "text": "DualSense (abc)",
                    "vid": 0x054C,
                    "pid": 0x0CE6,
                    "manufacturer": "Sony",
                    "product": "DualSense",
                }
            ],
        )
        self.assertTrue(HidDiscovery("0x054C", "0x0CE6").match(devices[0]))
        self.assertTrue(HidDiscovery("0x054C").match(devices[0]))
        self.assertFalse(HidDiscovery("0x054C", "0x05C4").match(devices[0]))

    def test_zeroconf_scans_every_service_type_without_parameters(self):
        services = {
            "Hue Bridge._hue._tcp.local.": ("_hue._tcp.local.", {b"bridgeid": b"001788"}, ["192.168.1.70"]),
            "printer._ipp._tcp.local.": ("_ipp._tcp.local.", {}, ["192.168.1.80"]),
            "v6only._ipp._tcp.local.": ("_ipp._tcp.local.", {}, []),
        }
        module = types.ModuleType("zeroconf")
        module.IPVersion = types.SimpleNamespace(V4Only="v4")
        browsed = []

        class FakeZeroconf:
            def get_service_info(self, service_type, name, timeout):
                _, properties, addresses = services[name]
                info = Mock(properties=properties)
                info.parsed_addresses = Mock(return_value=addresses)
                return info

            def close(self):
                pass

        class FakeBrowser:
            def __init__(self, zeroconf, service_types, handlers):
                browsed.extend(service_types)
                for name, (service_type, _, _) in services.items():
                    if service_type in service_types:
                        handlers[0](zeroconf, service_type, name, None)

            def cancel(self):
                pass

        module.Zeroconf = FakeZeroconf
        module.ServiceBrowser = FakeBrowser
        module.ZeroconfServiceTypes = Mock(find=Mock(return_value=("_ipp._tcp.local.", "_hue._tcp.local.")))
        with patch.dict(sys.modules, {"zeroconf": module}), patch("time.sleep"):
            devices = ZeroconfDiscovery().scan()
        self.assertEqual(browsed, ["_hue._tcp.local.", "_ipp._tcp.local."])
        self.assertEqual(
            devices,
            [
                {
                    "value": "192.168.1.70",
                    "text": "Hue Bridge (192.168.1.70)",
                    "type": "_hue._tcp.local.",
                    "name": "Hue Bridge._hue._tcp.local.",
                    "properties": {"bridgeid": "001788"},
                },
                {
                    "value": "192.168.1.80",
                    "text": "printer (192.168.1.80)",
                    "type": "_ipp._tcp.local.",
                    "name": "printer._ipp._tcp.local.",
                    "properties": {},
                },
            ],
        )
        self.assertTrue(ZeroconfDiscovery("_hue._tcp.local.|bridgeid=0017*").match(devices[0]))
        self.assertFalse(ZeroconfDiscovery("_hue._tcp.local.").match(devices[1]))
        # discover() still finds nothing without parameters
        self.assertEqual(ZeroconfDiscovery().discover(), [])

    def test_bluetooth(self):
        found = {
            "AA:01": (
                types.SimpleNamespace(name="Fallback"),
                Mock(
                    local_name="Govee_H6159",
                    service_uuids=["0000FE95-0000-1000-8000-00805F9B34FB"],
                    service_data={"0000FCD2-0000-1000-8000-00805F9B34FB": b"x"},
                    manufacturer_data={34818: b"\x01\x02\x03", 76: b"\x02\x15\xbb\x70"},
                ),
            ),
        }

        async def discover(timeout, return_adv, **kwargs):
            return found

        bleak = types.ModuleType("bleak")
        bleak.BleakScanner = Mock(discover=discover)
        with patch.dict(sys.modules, {"bleak": bleak}):
            devices = BluetoothDiscovery().scan()
        self.assertEqual(
            devices,
            [
                {
                    "value": "AA:01",
                    "text": "Govee_H6159 (AA:01)",
                    "name": "Govee_H6159",
                    "service_uuids": ["0000fe95-0000-1000-8000-00805f9b34fb"],
                    "service_data_uuids": ["0000fcd2-0000-1000-8000-00805f9b34fb"],
                    "manufacturer_data": {"76": "0215bb70", "34818": "010203"},
                }
            ],
        )
        self.assertTrue(BluetoothDiscovery("local_name=Govee*|manufacturer_id=34818").match(devices[0]))
        self.assertTrue(BluetoothDiscovery("service_data_uuid=0000FCD2-0000-1000-8000-00805F9B34FB").match(devices[0]))
        self.assertFalse(BluetoothDiscovery("local_name=Govee*|manufacturer_id=1").match(devices[0]))
        # The start of a manufacturer's data, like Home Assistant's manufacturer_data_start
        self.assertTrue(BluetoothDiscovery("manufacturer_id=76|manufacturer_data_start=0215BB").match(devices[0]))
        self.assertFalse(BluetoothDiscovery("manufacturer_id=76|manufacturer_data_start=0215CC").match(devices[0]))
        self.assertFalse(BluetoothDiscovery("manufacturer_id=34818|manufacturer_data_start=0215").match(devices[0]))
        self.assertTrue(BluetoothDiscovery("manufacturer_data_start=0102").match(devices[0]))
        with self.assertRaisesRegex(ValueError, "hex bytes"):
            BluetoothDiscovery("manufacturer_data_start=xyz")


class TestDiscoveryScan(unittest.TestCase):
    def setUp(self):
        patcher = patch.multiple(
            "openc3.discovery.serial_discovery.SerialDiscovery", scan=Mock(return_value=SERIAL_DEVICES)
        )
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher = patch.multiple("openc3.discovery.hid_discovery.HidDiscovery", scan=Mock(return_value=HID_DEVICES))
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_checks_every_matcher_against_one_scan(self):
        response = scan(
            {
                "matchers": [
                    {"id": "uno", "class": "openc3/discovery/serial_discovery.py", "params": ["2341:*"]},
                    {"id": "cp210x", "class": SERIAL, "params": ["10C4:EA60", "1A86:7523"]},
                    {"id": "dualsense", "class": HID, "params": ["0x054C", "0x0CE6"]},
                    {"id": "edge", "class": HID, "params": ["0x054C", "0x0DF2"]},
                ],
                "classes": [SERIAL, HID],
            }
        )
        self.assertEqual(response["errors"], {})
        self.assertEqual(response["skipped"], {})
        matches = {(device["class"], device["value"]): device["matches"] for device in response["devices"]}
        self.assertEqual(
            matches,
            {
                (SERIAL, "/dev/ttyUSB0"): ["cp210x"],
                (SERIAL, "/dev/ttyACM0"): ["uno"],
                # Unrecognized devices are listed too
                (SERIAL, "/dev/ttyS0"): [],
                (HID, "abc"): ["dualsense"],
                (HID, "def"): [],
            },
        )
        # Which of a matcher's alternative parameters matched
        params = {device["value"]: device["matched_params"] for device in response["devices"]}
        self.assertEqual(params["/dev/ttyUSB0"], {"cp210x": [0]})
        self.assertEqual(params["/dev/ttyACM0"], {})
        dualsense = next(device for device in response["devices"] if device["value"] == "abc")
        # HID parameters together describe one device
        self.assertEqual(dualsense["matched_params"], {})
        self.assertEqual(dualsense["text"], "DualSense (abc)")
        self.assertEqual(dualsense["details"], {"vid": 0x054C, "pid": 0x0CE6})

    def test_only_runs_classes_shipped_with_cosmos(self):
        response = scan(
            {
                "matchers": [
                    {"id": "plugin", "class": "my_plugin/lib/my_discovery.py", "params": ["x"]},
                    {"id": "bad", "class": SERIAL, "params": ["not-an-id"]},
                    {"id": "unscanned", "class": HID, "params": ["0x054C"]},
                ],
                "classes": [SERIAL],
            }
        )
        self.assertIn("not a discovery class COSMOS can scan", response["skipped"]["plugin"])
        self.assertIn("VID:PID", response["skipped"]["bad"])
        self.assertIn("was not scanned", response["skipped"]["unscanned"])
        self.assertEqual({device["class"] for device in response["devices"]}, {SERIAL})

    def test_class_errors_dont_stop_the_others(self):
        with patch("openc3.discovery.hid_discovery.HidDiscovery.scan", side_effect=RuntimeError("hidapi missing")):
            response = scan({"matchers": [], "classes": [SERIAL, HID]})
        self.assertEqual(response["errors"], {HID: "RuntimeError: hidapi missing"})
        self.assertEqual(len(response["devices"]), 3)

    def test_scans_every_class_by_default(self):
        scanned = []

        def fake_scan(name):
            def scan(self):
                scanned.append(name)
                return []

            return scan

        with (
            patch("openc3.discovery.zeroconf_discovery.ZeroconfDiscovery.scan", fake_scan(ZEROCONF)),
            patch("openc3.discovery.bluetooth_discovery.BluetoothDiscovery.scan", fake_scan(BLUETOOTH)),
            patch("openc3.discovery.usb_discovery.UsbDiscovery.scan", fake_scan(USB)),
            patch("openc3.discovery.ssdp_discovery.SsdpDiscovery.scan", fake_scan(SSDP)),
            patch("openc3.discovery.neighbor_discovery.NeighborDiscovery.scan", fake_scan(NEIGHBOR)),
        ):
            response = scan({})
        self.assertEqual(sorted(scanned), sorted([ZEROCONF, BLUETOOTH, USB, SSDP, NEIGHBOR]))
        self.assertEqual({device["class"] for device in response["devices"]}, {SERIAL, HID})
        self.assertEqual(SCAN_CLASSES, [SERIAL, HID, ZEROCONF, BLUETOOTH, USB, SSDP, NEIGHBOR])

    def test_a_value_found_more_than_once_is_one_device(self):
        # A host advertising two mDNS services matches through either of them
        services = [
            {
                "value": "192.168.1.5",
                "text": "printer (192.168.1.5)",
                "type": "_ipp._tcp.local.",
                "name": "p",
                "properties": {},
            },
            {
                "value": "192.168.1.5",
                "text": "hue (192.168.1.5)",
                "type": "_hue._tcp.local.",
                "name": "h",
                "properties": {},
            },
        ]
        with patch("openc3.discovery.zeroconf_discovery.ZeroconfDiscovery.scan", Mock(return_value=services)):
            response = scan(
                {
                    "matchers": [
                        {"id": "ipp", "class": ZEROCONF, "params": ["_ipp._tcp.local."]},
                        {"id": "hue", "class": ZEROCONF, "params": ["_hue._tcp.local."]},
                    ],
                    "classes": [ZEROCONF],
                }
            )
        self.assertEqual(len(response["devices"]), 1)
        self.assertEqual(response["devices"][0]["text"], "printer (192.168.1.5)")
        self.assertEqual(response["devices"][0]["matches"], ["ipp", "hue"])

    def test_reports_the_parameters_that_matched(self):
        lamp = {"value": "AA:01", "text": "Govee_H607C", "name": "Govee_H607C", "service_uuids": []}
        lamp.update(service_data_uuids=[], manufacturer_data={"34883": "00"})
        with patch("openc3.discovery.bluetooth_discovery.BluetoothDiscovery.scan", Mock(return_value=[lamp])):
            response = scan(
                {
                    "matchers": [
                        {
                            "id": "govee",
                            "class": BLUETOOTH,
                            "params": [
                                "manufacturer_id=60552|service_uuid=0000ec88",
                                "local_name=Govee*",
                                "local_name=GV*",
                            ],
                        }
                    ],
                    "classes": [BLUETOOTH],
                }
            )
        # Only the broad name pattern matched
        self.assertEqual(response["devices"][0]["matches"], ["govee"])
        self.assertEqual(response["devices"][0]["matched_params"], {"govee": [1]})

    def test_main(self):
        output = io.StringIO()
        request = {"matchers": [{"id": 1, "class": HID, "params": ["0x054C"]}], "classes": [HID]}
        with redirect_stdout(output):
            code = main(io.StringIO(json.dumps(request)))
        self.assertEqual(code, 0)
        response = json.loads(output.getvalue())
        self.assertEqual([device["matches"] for device in response["devices"]], [[1], []])

        output = io.StringIO()
        with redirect_stdout(output):
            code = main(io.StringIO("not json"))
        self.assertEqual(code, 1)
        self.assertIn("JSONDecodeError", json.loads(output.getvalue())["error"])
