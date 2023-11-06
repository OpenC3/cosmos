# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from datetime import datetime
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.conversions.received_time_formatted_conversion import (
    ReceivedTimeFormattedConversion,
)
from openc3.packets.packet import Packet
from openc3.utilities.time import openc3_timezone


class TestReceivedTimeFormattedConversion(unittest.TestCase):
    def test_initializes_converted_type_and_converted_bit_size(self):
        gc = ReceivedTimeFormattedConversion()
        self.assertEqual(gc.converted_type, "STRING")
        self.assertEqual(gc.converted_bit_size, 0)

    def test_returns_the_formatted_packet_time(self):
        gc = ReceivedTimeFormattedConversion()
        packet = Packet("TGT", "PKT")
        packet.received_time = datetime(
            2020, 1, 31, 12, 15, 30, tzinfo=openc3_timezone()
        )
        self.assertEqual(gc.call(None, packet, None), "2020/01/31 12:15:30.000")

    def test_returns_a_string_if_packet_time_isnt_set(self):
        gc = ReceivedTimeFormattedConversion()
        packet = Packet("TGT", "PKT")
        self.assertEqual(gc.call(None, packet, None), "No Packet Received Time")

    def test_returns_the_class(self):
        self.assertEqual(
            str(ReceivedTimeFormattedConversion()), "ReceivedTimeFormattedConversion"
        )
