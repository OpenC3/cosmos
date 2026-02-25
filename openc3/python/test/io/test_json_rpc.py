# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *

from openc3.io.json_rpc import JsonRpcRequest
from test.test_helper import *


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
        self.assertEqual(request["params"], [{"DATA": {"json_class": "String", "raw": [195, 40]}}])

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
        micro_amperes = "0.5 µA".encode()
        json_rpc_request = JsonRpcRequest(0, "cmd", {"UNITS": micro_amperes})
        request = json_rpc_request.to_hash()
        self.assertEqual(request["params"], [{"UNITS": "0.5 µA"}])

        # Test degree symbol ° (U+00B0) - common in temperature units
        degree_celsius = "25 °C".encode()
        json_rpc_request = JsonRpcRequest(0, "cmd", {"TEMP": degree_celsius})
        request = json_rpc_request.to_hash()
        self.assertEqual(request["params"], [{"TEMP": "25 °C"}])

        # Test accented characters like in "Ampères"
        amperes = "Ampères".encode()
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
        json_rpc_request = JsonRpcRequest(0, "cmd", {"BIN": binary, "TXT": "Test µ".encode()})
        request = json_rpc_request.to_hash()

        # Binary should be raw object
        self.assertIsInstance(request["params"][0]["BIN"], dict)
        self.assertEqual(request["params"][0]["BIN"]["json_class"], "String")

        # Unicode text should be preserved as string
        self.assertIsInstance(request["params"][0]["TXT"], str)
        self.assertEqual(request["params"][0]["TXT"], "Test µ")

    def test_treats_2_byte_valid_utf8_binary_as_binary(self):
        """Ensure 2-byte binary data that happens to be valid UTF-8 is treated as binary.

        This is a regression test for the issue where 0xDEAD (2 bytes) was being
        interpreted as valid UTF-8 text instead of binary data.
        \\xDE\\xAD happens to be a valid 2-byte UTF-8 sequence (decodes to U+07AD, Thaana script)
        but should be treated as binary since Thaana characters are not expected in command data.
        """
        # 2-byte binary that happens to be valid UTF-8
        binary_data = bytes([0xDE, 0xAD])  # This is valid UTF-8 (U+07AD)
        json_rpc_request = JsonRpcRequest(0, "cmd", {"DATA": binary_data})
        request = json_rpc_request.to_hash()

        # Should be encoded as raw binary, not as text
        self.assertIsInstance(request["params"][0]["DATA"], dict)
        self.assertEqual(request["params"][0]["DATA"]["json_class"], "String")
        self.assertEqual(request["params"][0]["DATA"]["raw"], [222, 173])

    def test_treats_c1_control_characters_as_binary(self):
        """Ensure bytes that decode to C1 control characters (U+0080-U+009F) are treated as binary."""
        # U+0080 is encoded as \\xC2\\x80 in UTF-8
        c1_control = bytes([0xC2, 0x80])
        json_rpc_request = JsonRpcRequest(0, "cmd", {"DATA": c1_control})
        request = json_rpc_request.to_hash()

        # Should be encoded as raw binary
        self.assertIsInstance(request["params"][0]["DATA"], dict)
        self.assertEqual(request["params"][0]["DATA"]["json_class"], "String")
