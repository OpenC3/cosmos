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

from datetime import datetime, timezone
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.conversions.unix_time_formatted_conversion import (
    UnixTimeFormattedConversion,
)
from openc3.packets.packet import Packet


class TestUnixTimeFormattedConversion(unittest.TestCase):
    def test_initializes_converted_type_and_converted_bit_size(self):
        gc = UnixTimeFormattedConversion("TIME")
        self.assertEqual(gc.converted_type, "STRING")
        self.assertEqual(gc.converted_bit_size, 0)

    def test_returns_the_formatted_packet_time_based_on_seconds(self):
        gc = UnixTimeFormattedConversion("TIME")
        packet = Packet("TGT", "PKT")
        packet.append_item("TIME", 32, "UINT")
        time = datetime(2020, 1, 31, 12, 15, 30, tzinfo=timezone.utc).timestamp()
        packet.write("TIME", time)
        self.assertEqual(
            gc.call(None, packet, packet.buffer), "2020/01/31 12:15:30.000"
        )

    def test_returns_the_formatted_packet_time_based_on_seconds_and_microseconds(self):
        gc = UnixTimeFormattedConversion("TIME", "TIME_US")
        packet = Packet("TGT", "PKT")
        packet.append_item("TIME", 32, "UINT")
        time = datetime(2020, 1, 31, 12, 15, 30, tzinfo=timezone.utc).timestamp()
        packet.write("TIME", time)
        packet.append_item("TIME_US", 32, "UINT")
        packet.write("TIME_US", 500000)
        self.assertEqual(
            gc.call(None, packet, packet.buffer), "2020/01/31 12:15:30.500"
        )

    def test_complains_if_the_seconds_item_doesnt_exist(self):
        gc = UnixTimeFormattedConversion("TIME")
        packet = Packet("TGT", "PKT")
        with self.assertRaisesRegex(
            AttributeError, "Packet item 'TGT PKT TIME' does not exist"
        ):
            gc.call(None, packet, packet.buffer)

    def test_complains_if_the_microseconds_item_doesnt_exist(self):
        gc = UnixTimeFormattedConversion("TIME", "TIME_US")
        packet = Packet("TGT", "PKT")
        packet.append_item("TIME", 32, "UINT")
        with self.assertRaisesRegex(
            AttributeError, "Packet item 'TGT PKT TIME_US' does not exist"
        ):
            gc.call(None, packet, packet.buffer)

    def test_returns_the_seconds_conversion(self):
        gc = UnixTimeFormattedConversion("TIME")
        self.assertEqual(str(gc), "UnixTimeFormattedConversion TIME")

    def test_returns_the_microseconds_conversion(self):
        gc = UnixTimeFormattedConversion("TIME", "TIME_US")
        self.assertEqual(str(gc), "UnixTimeFormattedConversion TIME TIME_US")
