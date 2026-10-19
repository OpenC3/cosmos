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
from openc3.discovery.discovery_runner import main, normalize_results
from openc3.discovery.hid_discovery import HidDiscovery
from openc3.discovery.serial_discovery import SerialDiscovery
from openc3.discovery.zeroconf_discovery import ZeroconfDiscovery


class TestDiscoveryRunner(unittest.TestCase):
    def run_main(self, argv):
        output = io.StringIO()
        with redirect_stdout(output):
            code = main(argv)
        return code, json.loads(output.getvalue())

    def test_normalize_results(self):
        self.assertEqual(
            normalize_results(["COM1", {"value": 2}, {"value": "a", "text": "A"}]),
            [{"value": "COM1", "text": "COM1"}, {"value": "2", "text": "2"}, {"value": "a", "text": "A"}],
        )
        self.assertEqual(normalize_results(None), [])

    def test_main_prints_results(self):
        with patch.object(SerialDiscovery, "discover", return_value=["COM3"]):
            code, output = self.run_main(["openc3/discovery/serial_discovery.py"])
        self.assertEqual(code, 0)
        self.assertEqual(output, {"results": [{"value": "COM3", "text": "COM3"}]})

    def test_main_accepts_a_module_name(self):
        with patch.object(SerialDiscovery, "discover", return_value=["COM4"]):
            code, output = self.run_main(["openc3.discovery.serial_discovery"])
        self.assertEqual(code, 0)
        self.assertEqual(output, {"results": [{"value": "COM4", "text": "COM4"}]})

    def test_main_keeps_stdout_clean(self):
        def noisy(_self):
            print("debug output")
            return ["COM3"]

        with patch.object(SerialDiscovery, "discover", noisy), patch("sys.stderr", io.StringIO()):
            code, output = self.run_main(["openc3/discovery/serial_discovery.py"])
        self.assertEqual(code, 0)
        self.assertEqual(output["results"][0]["value"], "COM3")

    def test_main_reports_errors(self):
        code, output = self.run_main(["openc3/discovery/does_not_exist.py"])
        self.assertEqual(code, 1)
        self.assertIn("ModuleNotFoundError", output["error"])
        code, output = self.run_main([])
        self.assertEqual(code, 1)
        self.assertIn("Usage", output["error"])


class TestSerialDiscovery(unittest.TestCase):
    def test_lists_ports_skipping_ignored(self):
        ports = [
            Mock(device="/dev/ttyUSB1", description="n/a"),
            Mock(device="/dev/cu.debug-console", description="debug"),
            Mock(device="/dev/ttyUSB0", description="FT232R USB UART"),
        ]
        with patch("openc3.discovery.serial_discovery.list_ports.comports", return_value=ports):
            results = SerialDiscovery().discover()
        self.assertEqual(
            results,
            [
                {"value": "/dev/ttyUSB0", "text": "/dev/ttyUSB0 - FT232R USB UART"},
                {"value": "/dev/ttyUSB1", "text": "/dev/ttyUSB1"},
            ],
        )

    def test_filters_by_usb_id(self):
        ports = [
            Mock(device="/dev/ttyUSB0", description="CP2102", vid=0x10C4, pid=0xEA60),
            Mock(device="/dev/ttyUSB1", description="FT232R", vid=0x0403, pid=0x6001),
            Mock(device="/dev/ttyS0", description="n/a", vid=None, pid=None),
        ]
        with patch("openc3.discovery.serial_discovery.list_ports.comports", return_value=ports):
            results = SerialDiscovery("10C4:EA60").discover()
        self.assertEqual(results, [{"value": "/dev/ttyUSB0", "text": "/dev/ttyUSB0 - CP2102"}])
        with patch("openc3.discovery.serial_discovery.list_ports.comports", return_value=ports):
            results = SerialDiscovery("0403:*", "10C4").discover()
        self.assertEqual([result["value"] for result in results], ["/dev/ttyUSB0", "/dev/ttyUSB1"])
        with self.assertRaisesRegex(ValueError, "VID:PID"):
            SerialDiscovery("USB")


class TestZeroconfDiscovery(unittest.TestCase):
    def fake_zeroconf(self, services):
        """A zeroconf module whose browser finds services: {name: (type, properties, addresses)}"""
        module = types.ModuleType("zeroconf")
        module.IPVersion = types.SimpleNamespace(V4Only="v4")

        class FakeZeroconf:
            closed = False

            def get_service_info(self, service_type, name, timeout):
                found_type, properties, addresses = services[name]
                info = Mock(properties=properties)
                info.parsed_addresses = Mock(return_value=addresses)
                return info

            def close(self):
                FakeZeroconf.closed = True

        class FakeBrowser:
            def __init__(self, zeroconf, service_types, handlers):
                for name, (service_type, _, _) in services.items():
                    if service_type in service_types:
                        handlers[0](zeroconf, service_type, name, None)

            def cancel(self):
                pass

        module.Zeroconf = FakeZeroconf
        module.ServiceBrowser = FakeBrowser
        return module

    def test_lists_matching_addresses(self):
        services = {
            "shellyplus1-a1._http._tcp.local.": ("_http._tcp.local.", {b"gen": b"2"}, ["192.168.1.50"]),
            "printer._http._tcp.local.": ("_http._tcp.local.", {}, ["192.168.1.60"]),
            "Hue Bridge._hue._tcp.local.": ("_hue._tcp.local.", {}, ["192.168.1.70", "192.168.1.71"]),
            "ignored._ipp._tcp.local.": ("_ipp._tcp.local.", {}, ["192.168.1.80"]),
        }
        module = self.fake_zeroconf(services)
        discovery = ZeroconfDiscovery("_http._tcp.local.|name=shelly*|gen=2", "_hue._tcp.local")
        with patch.dict(sys.modules, {"zeroconf": module}), patch("time.sleep"):
            results = discovery.discover()
        self.assertEqual(
            results,
            [
                {"value": "192.168.1.70", "text": "Hue Bridge (192.168.1.70)"},
                {"value": "192.168.1.50", "text": "shellyplus1-a1 (192.168.1.50)"},
            ],
        )
        self.assertTrue(module.Zeroconf.closed)

    def test_no_matchers_or_package(self):
        self.assertEqual(ZeroconfDiscovery().discover(), [])
        with patch.dict(sys.modules, {"zeroconf": None}), self.assertRaisesRegex(RuntimeError, "zeroconf"):
            ZeroconfDiscovery("_hue._tcp.local.").discover()


class TestBluetoothDiscovery(unittest.TestCase):
    def test_lists_matching_devices(self):
        def advertisement(name, uuids=(), data=None, manufacturer=None):
            return Mock(
                local_name=name,
                service_uuids=list(uuids),
                service_data=data or {},
                manufacturer_data=manufacturer or {},
            )

        devices = {
            "AA:01": (types.SimpleNamespace(name=None), advertisement("Govee_H6159", manufacturer={34818: b"x"})),
            "AA:02": (
                types.SimpleNamespace(name=None),
                advertisement("Other", uuids=["0000FE95-0000-1000-8000-00805F9B34FB"]),
            ),
            "AA:03": (types.SimpleNamespace(name=None), advertisement("Nope")),
        }

        async def scan(timeout, return_adv):
            return devices

        bleak = types.ModuleType("bleak")
        bleak.BleakScanner = Mock(discover=scan)
        discovery = BluetoothDiscovery(
            "local_name=Govee*|manufacturer_id=34818", "service_uuid=0000fe95-0000-1000-8000-00805f9b34fb"
        )
        with patch.dict(sys.modules, {"bleak": bleak}):
            results = discovery.discover()
        self.assertEqual(
            results,
            [{"value": "AA:01", "text": "Govee_H6159 (AA:01)"}, {"value": "AA:02", "text": "Other (AA:02)"}],
        )

    def test_bad_matcher(self):
        with self.assertRaisesRegex(ValueError, "Unknown Bluetooth matcher"):
            BluetoothDiscovery("color=red")


class TestHidDiscovery(unittest.TestCase):
    def test_lists_unique_serial_numbers(self):
        hid = types.ModuleType("hid")
        hid.enumerate = Mock(
            return_value=[
                {"vendor_id": 0x054C, "product_id": 0x0CE6, "serial_number": "abc", "product_string": "DualSense"},
                {"vendor_id": 0x054C, "product_id": 0x0CE6, "serial_number": "abc", "product_string": "DualSense"},
                {"vendor_id": 0x054C, "product_id": 0x0CE6, "serial_number": "", "product_string": "DualSense"},
                {"vendor_id": 0x054C, "product_id": 0x0CE6, "serial_number": "def", "product_string": None},
            ]
        )
        with patch.dict(sys.modules, {"hid": hid}):
            results = HidDiscovery("0x054C", "0x0CE6").discover()
        hid.enumerate.assert_called_once_with(0x054C, 0x0CE6)
        self.assertEqual(
            results,
            [{"value": "abc", "text": "DualSense (abc)"}, {"value": "def", "text": "054C:0CE6 (def)"}],
        )

    def test_ids_default_to_wildcard(self):
        self.assertEqual(HidDiscovery().vendor_id, 0)
        self.assertEqual(HidDiscovery("nil", "1234").product_id, 1234)

    def test_missing_hidapi(self):
        with patch.dict(sys.modules, {"hid": None}), self.assertRaisesRegex(RuntimeError, "hidapi"):
            HidDiscovery().discover()
