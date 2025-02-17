# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.accessors.template_accessor import TemplateAccessor
from openc3.packets.packet import Packet
from collections import namedtuple


class TestTemplateAccessor(unittest.TestCase):
    def setUp(self):
        self.packet = Packet()
        self.packet.template = b"MEAS:VOLT (@<CHANNEL>); SOMETHING ELSE <MYVALUE>;"
        self.data = b"MEAS:VOLT (@2); SOMETHING ELSE 5.67;"

        self.packet2 = Packet()
        self.packet2.template = b"MEAS:VOLT <@(CHANNEL)>; SOMETHING ELSE (MYVALUE);"
        self.data2 = b"MEAS:VOLT <@2>; SOMETHING ELSE 5.67;"

    def test_should_escape_regexp_chars(self):
        packet = Packet()
        packet.template = b"VOLT <VOLTAGE>, ($1); VOLT? (+1)"
        data = b"VOLT 5, ($1); VOLT? (+1)"
        accessor = TemplateAccessor(packet)
        packet.buffer = data

        item1 = namedtuple("Item", ["name", "key", "data_type", "array_size"])
        item1.name = "VOLTAGE"
        item1.key = "VOLTAGE"
        item1.data_type = "FLOAT"
        item1.array_size = None
        value = accessor.read_item(item1, packet.buffer)
        self.assertEqual(value, 5.0)

    def test_should_allow_different_delimiters(self):
        packet = Packet()
        packet.template = b"VOLT (VOLTAGE), *1.0; VOLT? *1.0"
        data = b"VOLT 5, *1.0; VOLT? *1.0"
        accessor = TemplateAccessor(packet, "(", ")")
        packet.buffer = data

        item1 = namedtuple("Item", ["name", "key", "data_type", "array_size"])
        item1.name = "VOLTAGE"
        item1.key = "VOLTAGE"
        item1.data_type = "FLOAT"
        item1.array_size = None
        value = accessor.read_item(item1, packet.buffer_no_copy())
        self.assertEqual(value, 5.0)

    def test_should_read_values(self):
        accessor = TemplateAccessor(self.packet)
        self.packet.buffer = self.data

        item1 = namedtuple("Item", ["name", "key", "data_type", "array_size"])
        item1.name = "CHANNEL"
        item1.key = "CHANNEL"
        item1.data_type = "UINT"
        item1.array_size = None
        value = accessor.read_item(item1, self.packet.buffer_no_copy())
        self.assertEqual(value, 2)

        item2 = namedtuple("Item", ["name", "key", "data_type", "array_size"])
        item2.name = "MYVALUE"
        item2.key = "MYVALUE"
        item2.data_type = "FLOAT"
        item2.array_size = None
        value = accessor.read_item(item2, self.packet.buffer_no_copy())
        self.assertAlmostEqual(value, 5.67, places=2)

        values = accessor.read_items([item1, item2], self.packet.buffer_no_copy())
        self.assertEqual(values["CHANNEL"], 2)
        self.assertAlmostEqual(values["MYVALUE"], 5.67, places=2)

        accessor = TemplateAccessor(self.packet2, "(", ")")
        self.packet2.buffer = self.data2

        value = accessor.read_item(item1, self.packet2.buffer_no_copy())
        self.assertEqual(value, 2)

        value = accessor.read_item(item2, self.packet2.buffer_no_copy())
        self.assertAlmostEqual(value, 5.67, places=2)

        values = accessor.read_items([item1, item2], self.packet2.buffer_no_copy())
        self.assertEqual(values["CHANNEL"], 2)
        self.assertAlmostEqual(values["MYVALUE"], 5.67, places=2)

    def test_should_write_values(self):
        accessor = TemplateAccessor(self.packet)
        self.packet.restore_defaults()

        item1 = namedtuple("Item", ["name", "key", "data_type", "array_size"])
        item1.name = "CHANNEL"
        item1.key = "CHANNEL"
        item1.data_type = "UINT"
        item1.array_size = None
        value = accessor.write_item(item1, 3, self.packet.buffer_no_copy())
        self.assertEqual(value, 3)
        self.assertEqual(self.packet.buffer, b"MEAS:VOLT (@3); SOMETHING ELSE <MYVALUE>;")

        item2 = namedtuple("Item", ["name", "key", "data_type", "array_size"])
        item2.name = "MYVALUE"
        item2.key = "MYVALUE"
        item2.data_type = "FLOAT"
        item2.array_size = None
        value = accessor.write_item(item2, 1.234, self.packet.buffer_no_copy())
        self.assertAlmostEqual(value, 1.234, places=2)
        self.assertEqual(self.packet.buffer, b"MEAS:VOLT (@3); SOMETHING ELSE 1.234;")

        self.packet.restore_defaults()
        accessor.write_items([item1, item2], [4, 2.345], self.packet.buffer_no_copy())
        values = accessor.read_items([item1, item2], self.packet.buffer_no_copy())
        self.assertEqual(values["CHANNEL"], 4)
        self.assertAlmostEqual(values["MYVALUE"], 2.345, places=2)

        accessor = TemplateAccessor(self.packet2, "(", ")")
        self.packet2.restore_defaults()

        value = accessor.write_item(item1, 3, self.packet2.buffer_no_copy())
        self.assertEqual(value, 3)
        self.assertEqual(self.packet2.buffer, b"MEAS:VOLT <@3>; SOMETHING ELSE (MYVALUE);")

        value = accessor.write_item(item2, 1.234, self.packet2.buffer_no_copy())
        self.assertAlmostEqual(value, 1.234, places=2)
        self.assertEqual(self.packet2.buffer, b"MEAS:VOLT <@3>; SOMETHING ELSE 1.234;")

        self.packet2.restore_defaults()
        accessor.write_items([item1, item2], [4, 2.345], self.packet2.buffer_no_copy())
        values = accessor.read_items([item1, item2], self.packet2.buffer_no_copy())
        self.assertEqual(values["CHANNEL"], 4)
        self.assertAlmostEqual(values["MYVALUE"], 2.345, places=2)
