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
from openc3.interfaces.stream_interface import StreamInterface
from openc3.interfaces.protocols.burst_protocol import BurstProtocol
from openc3.interfaces.protocols.length_protocol import LengthProtocol


class TestStreamInterface(unittest.TestCase):
    def test_adds_burst_protocol(self):
        i = StreamInterface("burst")
        self.assertEqual(i.name, "StreamInterface")
        self.assertEqual(i.read_protocols[0], i.write_protocols[0])
        self.assertIsInstance(i.read_protocols[0], BurstProtocol)

    def test_adds_length_protocol_with_params(self):
        i = StreamInterface("length", [1, 2])
        self.assertEqual(i.name, "StreamInterface")
        self.assertEqual(i.read_protocols[0], i.write_protocols[0])
        self.assertIsInstance(i.read_protocols[0], LengthProtocol)
        self.assertEqual(i.read_protocols[0].length_bit_offset, 1)
        self.assertEqual(i.read_protocols[0].length_bit_size, 2)
        self.assertEqual(i.read_protocols[0].length_value_offset, 0)
        self.assertEqual(i.read_protocols[0].length_bytes_per_count, 1)
