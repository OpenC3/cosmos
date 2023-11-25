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
