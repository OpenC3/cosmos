# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.io.json_rpc import JsonRpcRequest


class TestJsonRpc(unittest.TestCase):
    def test_encodes_non_utf8_params(self):
        json_rpc_request = JsonRpcRequest(0, "cmd", {"DATA": b"\x61\x62"})  # ASCII ab
        request = json_rpc_request.to_hash()
        self.assertEqual(list(request.keys()), ["jsonrpc", "method", "params", "id"])
        self.assertEqual(request["jsonrpc"], "2.0")
        self.assertEqual(request["method"], "cmd")
        self.assertEqual(request["params"], [{"DATA": "ab"}])  # ASCII
        self.assertEqual(request["id"], 0)

        json_rpc_request = JsonRpcRequest(0, "cmd", {"DATA": b"\xc3\xb1"})  # UTF-8
        request = json_rpc_request.to_hash()
        self.assertEqual(request["params"], [{"DATA": "ñ"}])

        json_rpc_request = JsonRpcRequest(0, "cmd", {"DATA": b"\xc3\x28"})
        request = json_rpc_request.to_hash()
        self.assertEqual(
            request["params"], [{"DATA": {"json_class": "String", "raw": [195, 40]}}]
        )

        json_rpc_request = JsonRpcRequest(0, "cmd", {"DATA": b"\xe2\x28\xa1"})
        request = json_rpc_request.to_hash()
        self.assertEqual(
            request["params"],
            [{"DATA": {"json_class": "String", "raw": [226, 40, 161]}}],
        )

        json_rpc_request = JsonRpcRequest(0, "cmd", {"DATA": b"\xf0\x28\x8c\x28"})
        request = json_rpc_request.to_hash()
        self.assertEqual(
            request["params"],
            [{"DATA": {"json_class": "String", "raw": [240, 40, 140, 40]}}],
        )

    def test_preserves_unicode_characters_as_readable_text(self):
        """Ensure Unicode characters like µA (micro-Ampères) are preserved as readable strings.

        This is a regression test for the issue where valid UTF-8 Unicode characters
        were incorrectly encoded as raw byte arrays instead of being preserved as text.
        See: https://github.com/OpenC3/cosmos/pull/2535
        """
        # Test micro sign µ (U+00B5) - common in units like "µA" for micro-Ampères
        micro_amperes = "0.5 µA".encode("utf-8")
        json_rpc_request = JsonRpcRequest(0, "cmd", {"UNITS": micro_amperes})
        request = json_rpc_request.to_hash()
        self.assertEqual(request["params"], [{"UNITS": "0.5 µA"}])

        # Test degree symbol ° (U+00B0) - common in temperature units
        degree_celsius = "25 °C".encode("utf-8")
        json_rpc_request = JsonRpcRequest(0, "cmd", {"TEMP": degree_celsius})
        request = json_rpc_request.to_hash()
        self.assertEqual(request["params"], [{"TEMP": "25 °C"}])

        # Test accented characters like in "Ampères"
        amperes = "Ampères".encode("utf-8")
        json_rpc_request = JsonRpcRequest(0, "cmd", {"LABEL": amperes})
        request = json_rpc_request.to_hash()
        self.assertEqual(request["params"], [{"LABEL": "Ampères"}])

    def test_encodes_binary_data_as_raw_object(self):
        """Ensure true binary data (invalid UTF-8) is encoded as json_class raw object.

        Binary data from hex strings like 0xDEADBEEF should be encoded as raw byte
        arrays to support round-trip serialization through JSON.
        """
        # Binary data that is NOT valid UTF-8
        binary_data = bytes([0xDE, 0xAD, 0xBE, 0xEF])
        json_rpc_request = JsonRpcRequest(0, "cmd", {"DATA": binary_data})
        request = json_rpc_request.to_hash()
        self.assertEqual(
            request["params"],
            [{"DATA": {"json_class": "String", "raw": [222, 173, 190, 239]}}],
        )

    def test_distinguishes_binary_from_unicode_text(self):
        """Ensure we correctly distinguish binary data from valid UTF-8 Unicode text.

        Both binary data and Unicode text may contain bytes > 127, but only valid
        UTF-8 sequences should be preserved as text strings.
        """
        # Binary data: invalid UTF-8, should be encoded as raw
        binary = bytes([0xDE, 0xAD, 0xBE, 0xEF])
        json_rpc_request = JsonRpcRequest(0, "cmd", {"BIN": binary, "TXT": "Test µ".encode("utf-8")})
        request = json_rpc_request.to_hash()

        # Binary should be raw object
        self.assertIsInstance(request["params"][0]["BIN"], dict)
        self.assertEqual(request["params"][0]["BIN"]["json_class"], "String")

        # Unicode text should be preserved as string
        self.assertIsInstance(request["params"][0]["TXT"], str)
        self.assertEqual(request["params"][0]["TXT"], "Test µ")
