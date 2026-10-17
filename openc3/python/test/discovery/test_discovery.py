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

from openc3.discovery.discovery_runner import main, normalize_results
from openc3.discovery.hid_discovery import HidDiscovery
from openc3.discovery.serial_discovery import SerialDiscovery


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
