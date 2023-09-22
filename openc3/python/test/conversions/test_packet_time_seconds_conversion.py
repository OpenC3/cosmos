#!/usr/bin/env python3

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
from openc3.conversions.generic_conversion import GenericConversion
from openc3.conversions.packet_time_seconds_conversion import (
    PacketTimeSecondsConversion,
)
from openc3.packets.packet import Packet


class TestPacketTimeSecondsConversion(unittest.TestCase):
    def test_initializes_converted_type_and_converted_bit_size(self):
        gc = PacketTimeSecondsConversion()
        self.assertEqual(gc.converted_type, "FLOAT")
        self.assertEqual(gc.converted_bit_size, 64)

    def test_returns_the_formatted_packet_time(self):
        gc = PacketTimeSecondsConversion()
        packet = Packet("TGT", "PKT")
        time = datetime(2020, 1, 31, 12, 15, 30, tzinfo=timezone.utc)
        packet.received_time = time
        self.assertEqual(gc.call(None, packet, None), time.timestamp())

    def test_returns_0_0_if_packet_time_isnt_set(self):
        gc = PacketTimeSecondsConversion()
        packet = Packet("TGT", "PKT")
        self.assertEqual(gc.call(None, packet, None), 0.0)

    def test_returns_the_class(self):
        self.assertEqual(
            str(PacketTimeSecondsConversion()), "PacketTimeSecondsConversion"
        )
