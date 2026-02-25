# Copyright 2023 OpenC3, Inc.
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

from openc3.conversions.received_count_conversion import ReceivedCountConversion
from openc3.packets.packet import Packet
from test.test_helper import *


class TestReceivedCountConversion(unittest.TestCase):
    def test_initializes_converted_type_and_converted_bit_size(self):
        gc = ReceivedCountConversion()
        self.assertEqual(gc.converted_type, "UINT")
        self.assertEqual(gc.converted_bit_size, 32)

    def test_calls_the_code_to_eval_and_return_the_result(self):
        gc = ReceivedCountConversion()
        packet = Packet("TGT", "PKT")
        packet.received_count = 100
        self.assertEqual(gc.call(None, packet, None), 100)

    def test_returns_the_class(self):
        self.assertEqual(str(ReceivedCountConversion()), "ReceivedCountConversion")
