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

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.packets.packet import Packet
from openc3.packets.packet_item import PacketItem
from openc3.processors.processor import Processor
from openc3.conversions.generic_conversion import GenericConversion
from openc3.accessors.binary_accessor import BinaryAccessor
import fakeredis
from datetime import datetime


class TestPacket(unittest.TestCase):
    def test_sets_the_template(self):
        p = Packet("tgt", "pkt")
        p.template = b"\x00\x01\x02\x03"
        self.assertEqual(p.template, b"\x00\x01\x02\x03")

        p.template = None
        self.assertEqual(p.template, None)

    def test_complains_if_the_given_template_is_not_a_string(self):
        p = Packet("tgt", "pkt")
        with self.assertRaisesRegex(
            AttributeError, "template must be bytes but is a int"
        ):
            p.template = 1

    # def test_runs_processors_if_present(self):
    #     p = Packet("tgt", "pkt")
    #     p.processors['processor'] = double("call", :call : True)
    #     p.buffer = "\x00\x01\x02\x03"


@patch("redis.Redis", return_value=fakeredis.FakeStrictRedis(version=7))
class Buffer(unittest.TestCase):
    def test_sets_the_buffer(self, redis):
        p = Packet("tgt", "pkt")
        p.buffer = b"\x00\x01\x02\x03"
        self.assertEqual(p.buffer, b"\x00\x01\x02\x03")

    def test_complains_if_the_given_buffer_is_too_big(self, redis):
        for stdout in capture_io():
            p = Packet("tgt", "pkt")
            p.append_item("test1", 16, "UINT")

            p.buffer = b"\x00\x00\x00"
            self.assertIn(
                "TGT PKT received with actual packet length of 3 but defined length of 2",
                stdout.getvalue(),
            )

    def test_sets_the_target_name_to_an_uppermatch_string(self, redis):
        p = Packet("tgt", "pkt")
        self.assertEqual(p.target_name, "TGT")

    def test_sets_target_name_to_None(self, redis):
        p = Packet(None, "pkt")
        self.assertIsNone(p.target_name)

    def test_complains_about_non_string_target_names(self, redis):
        with self.assertRaisesRegex(
            AttributeError, "target_name must be a str but is a float"
        ):
            Packet(5.1, "pkt")

    def test_sets_the_packet_name_to_an_uppermatch_string(self, redis):
        p = Packet("tgt", "pkt")
        self.assertEqual(p.packet_name, "PKT")

    def test_sets_packet_name_to_None(self, redis):
        p = Packet("tgt", None)
        self.assertIsNone(p.packet_name)

    def test_complains_about_non_string_packet_names(self, redis):
        with self.assertRaisesRegex(
            AttributeError, "packet_name must be a str but is a float"
        ):
            Packet("tgt", 5.1)

    def test_sets_the_description_to_a_string(self, redis):
        p = Packet("tgt", "pkt", "BIG_ENDIAN", "This is a description")
        self.assertEqual(p.description, "This is a description")

    def test_sets_description_to_None(self, redis):
        p = Packet("tgt", "pkt")
        p.description = None
        self.assertIsNone(p.description)

    def test_complains_about_non_string_descriptions(self, redis):
        p = Packet("tgt", "pkt")
        with self.assertRaisesRegex(
            AttributeError, "description must be a str but is a float"
        ):
            p.description = 5.1

    def test_sets_the_received_time_fast_to_a_time(self, redis):
        p = Packet("tgt", "pkt")
        t = datetime.now()
        p.set_received_time_fast(t)
        self.assertEqual(p.received_time, t)

    def test_sets_the_received_time_to_a_time(self, redis):
        p = Packet("tgt", "pkt")
        t = datetime.now()
        p.received_time = t
        self.assertEqual(p.received_time, t)

    def test_sets_received_time_to_None(self, redis):
        p = Packet("tgt", "pkt")
        p.received_time = None
        self.assertIsNone(p.received_time)

    def test_complains_about_non_time_received_times(self, redis):
        p = Packet("tgt", "pkt")
        with self.assertRaisesRegex(
            AttributeError, "received_time must be a datetime but is a str"
        ):
            p.received_time = "1pm"

    def test_sets_the_received_count_to_a_fixnum(self, redis):
        p = Packet("tgt", "pkt")
        p.received_count = 10
        self.assertEqual(p.received_count, 10)

    def test_complains_about_none_received_count(self, redis):
        p = Packet("tgt", "pkt")
        with self.assertRaisesRegex(
            AttributeError, "received_count must be an int but is a NoneType"
        ):
            p.received_count = None

    def test_complains_about_non_fixnum_received_counts(self, redis):
        p = Packet("tgt", "pkt")
        with self.assertRaisesRegex(
            AttributeError, "received_count must be an int but is a str"
        ):
            p.received_count = "5"

    def test_sets_the_hazardous_description_to_a_string(self, redis):
        p = Packet("tgt", "pkt")
        p.hazardous_description = "This is a description"
        self.assertEqual(p.hazardous_description, "This is a description")

    def test_sets_hazardous_description_to_None(self, redis):
        p = Packet("tgt", "pkt")
        p.hazardous_description = None
        self.assertIsNone(p.hazardous_description)

    def test_complains_about_non_string_hazardous_descriptions(self, redis):
        p = Packet("tgt", "pkt")
        with self.assertRaisesRegex(
            AttributeError, "hazardous_description must be a str but is a float"
        ):
            p.hazardous_description = 5.1

    def test_sets_the_given_values_to_a_hash(self, redis):
        p = Packet("tgt", "pkt")
        gv = {}
        p.given_values = gv
        self.assertEqual(p.given_values, gv)

    def test_sets_given_values_to_None(self, redis):
        p = Packet("tgt", "pkt")
        p.given_values = None
        self.assertIsNone(p.given_values)

    def test_complains_about_non_hash_given_valuess(self, redis):
        p = Packet("tgt", "pkt")
        with self.assertRaisesRegex(
            AttributeError, "given_values must be a dict but is a list"
        ):
            p.given_values = []

    def test_allows_adding_items_to_the_meta_hash(self, redis):
        p = Packet("tgt", "pkt")
        p.meta["TYPE"] = "float32"
        self.assertEqual(p.meta["TYPE"], "float32")

    def test_sets_the_limits_change_callback_to_something_that_responds_to_call(
        self, redis
    ):
        p = Packet("tgt", "pkt")

        class Callback:
            def call(self):
                pass

        p.limits_change_callback = Callback()

    def test_sets_limits_change_callback_to_none(self, redis):
        p = Packet("tgt", "pkt")
        p.limits_change_callback = None

    def test_complains_about_non_call_limits_change_callbacks(self, redis):
        p = Packet("tgt", "pkt")
        with self.assertRaisesRegex(
            AttributeError, "limits_change_callback must implement call"
        ):
            p.limits_change_callback = ""

    def test_takes_a_format_string_read_conversion_write_conversion_and_id_value(
        self, redis
    ):
        p = Packet("tgt", "pkt")
        rc = GenericConversion("value / 2")
        wc = GenericConversion("value * 2")
        p.define_item(
            "item", 0, 32, "FLOAT", None, "BIG_ENDIAN", "ERROR", "%5.1f", rc, wc, 5
        )
        i = p.get_item("ITEM")
        self.assertEqual(i.format_string, "%5.1f")
        self.assertEqual(str(i.read_conversion), str(rc))
        self.assertEqual(str(i.write_conversion), str(wc))
        self.assertEqual(i.id_value, 5.0)

    def test_init_format_string_read_conversion_write_conversion_and_id_value_to_none(
        self, redis
    ):
        p = Packet("tgt", "pkt")
        p.define_item("item", 0, 32, "FLOAT")
        i = p.get_item("ITEM")
        self.assertIsNone(i.format_string)
        self.assertIsNone(i.read_conversion)
        self.assertIsNone(i.write_conversion)
        self.assertIsNone(i.id_value)

    def test_adds_a_packetitem_to_a_packet(self, redis):
        p = Packet("tgt", "pkt")
        rc = GenericConversion("value / 2")
        wc = GenericConversion("value * 2")
        pi = PacketItem("item1", 0, 32, "FLOAT", "BIG_ENDIAN", None, "ERROR")
        pi.format_string = "%5.1f"
        pi.read_conversion = rc
        pi.write_conversion = wc
        pi.state_colors = {"RED": 0}
        pi.id_value = 5
        p.define(pi)
        i = p.get_item("ITEM1")
        self.assertEqual(i.format_string, "%5.1f")
        self.assertEqual(str(i.read_conversion), str(rc))
        self.assertEqual(str(i.write_conversion), str(wc))
        self.assertEqual(i.id_value, 5.0)
        self.assertEqual(len(p.id_items), 1)
        self.assertEqual(p.id_items[0].name, "ITEM1")
        self.assertEqual(p.limits_items[0].name, "ITEM1")
        self.assertEqual(p.defined_length, 4)

    def test_allows_packetitems_to_be_defined_on_top_of_each_other(self, redis):
        p = Packet("tgt", "pkt")
        pi = PacketItem("item1", 0, 8, "UINT", "BIG_ENDIAN")
        p.define(pi)
        pi = PacketItem("item2", 0, 32, "UINT", "BIG_ENDIAN")
        p.define(pi)
        self.assertEqual(p.defined_length, 4)
        buffer = b"\x01\x02\x03\x04"
        self.assertEqual(p.read_item(p.get_item("item1"), "RAW", buffer), 1)
        self.assertEqual(p.read_item(p.get_item("item2"), "RAW", buffer), 0x1020304)

    def test_append_takes_a_format_string_read_conversion_write_conversion_and_id_value(
        self, redis
    ):
        p = Packet("tgt", "pkt")
        rc = GenericConversion("value / 2")
        wc = GenericConversion("value * 2")
        p.append_item(
            "item", 32, "FLOAT", None, "BIG_ENDIAN", "ERROR", "%5.1f", rc, wc, 5
        )
        i = p.get_item("ITEM")
        self.assertEqual(i.format_string, "%5.1f")
        self.assertEqual(str(i.read_conversion), str(rc))
        self.assertEqual(str(i.write_conversion), str(wc))
        self.assertEqual(i.id_value, 5.0)

    def test_append_inits_format_string_read_conversion_write_conversion_and_id_value_to_none(
        self, redis
    ):
        p = Packet("tgt", "pkt")
        p.append_item("item", 32, "FLOAT")
        i = p.get_item("ITEM")
        self.assertIsNone(i.format_string)
        self.assertIsNone(i.read_conversion)
        self.assertIsNone(i.write_conversion)
        self.assertIsNone(i.id_value)

    def test_adds_a_packetitem_to_the_end_of_a_packet(self, redis):
        p = Packet("tgt", "pkt")
        pi = PacketItem("item1", 0, 32, "FLOAT", "BIG_ENDIAN", None, "ERROR")
        pi.format_string = "%5.1f"
        pi.limits.values = {"DEFAULT": [0, 1, 2, 3]}
        pi.id_value = 5
        p.append(pi)
        i = p.get_item("ITEM1")
        self.assertEqual(i.format_string, "%5.1f")
        self.assertEqual(i.id_value, 5.0)
        self.assertEqual(len(p.id_items), 1)
        self.assertEqual(p.id_items[0].name, "ITEM1")
        self.assertEqual(p.limits_items[0].name, "ITEM1")
        self.assertEqual(p.defined_length, 4)

        pi = PacketItem("item2", 0, 32, "FLOAT", "BIG_ENDIAN", None, "ERROR")
        p.append(pi)
        i = p.get_item("ITEM2")
        self.assertEqual(i.bit_offset, 32)  # offset updated inside the PacketItem
        self.assertIsNone(i.format_string)
        self.assertIsNone(i.read_conversion)
        self.assertIsNone(i.write_conversion)
        self.assertIsNone(i.id_value)
        self.assertEqual(len(p.id_items), 1)
        self.assertEqual(p.defined_length, 8)

    def test_complains_if_an_item_doesnt_exist(self, redis):
        p = Packet("tgt", "pkt")
        with self.assertRaisesRegex(
            AttributeError, "Packet item 'TGT PKT TEST' does not exist"
        ):
            p.get_item("test")


class PacketReadReadItem(unittest.TestCase):
    def setUp(self):
        self.p = Packet("tgt", "pkt")

    def test_complains_about_unknown_value_type(self):
        self.p.append_item("item", 32, "UINT")
        i = self.p.get_item("ITEM")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type 'MINE', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.read("ITEM", "MINE", b"\x01\x02\x03\x04")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type 'MINE', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.read("ITEM", "MINE", b"\x01\x02\x03\x04")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type 'MINE', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.read_item(i, "MINE", b"\x01\x02\x03\x04")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type 'ABCDEFGHIJ...', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.read_item(i, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", b"\x01\x02\x03\x04")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type '.*', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.read("ITEM", b"\00")

    def test_reads_the_raw_value(self):
        self.p.append_item("item", 32, "UINT")
        i = self.p.get_item("ITEM")
        self.assertEqual(self.p.read("ITEM", "RAW", b"\x01\x02\x03\x04"), 0x01020304)
        self.assertEqual(self.p.read_item(i, "RAW", b"\x01\x02\x03\x04"), 0x01020304)
        self.assertEqual(self.p.read_item(i, "RAW", b"\x01\x02\x03\x04", 5), 5)

    def test_reads_the_converted_value(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        self.assertEqual(self.p.read("ITEM", "CONVERTED", b"\x02"), 2)
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x02"), 2)
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x02", 4), 4)
        i.read_conversion = GenericConversion("value / 2")
        self.assertEqual(self.p.read("ITEM", "CONVERTED", b"\x02"), 1)
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x02"), 1)
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x02", 4), 2)

    def test_clears_the_read_conversion_cache_on_clone(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        i.read_conversion = GenericConversion("value / 2")
        self.p.buffer = b"\x02"
        self.assertEqual(self.p.read("ITEM", "CONVERTED"), 1)
        self.assertEqual(self.p.read_item(i, "CONVERTED"), 1)
        cloned = self.p.clone()
        cloned.buffer = b"\x04"
        self.assertEqual(self.p.read("ITEM", "CONVERTED"), 1)
        self.assertEqual(self.p.read_item(i, "CONVERTED"), 1)
        self.assertEqual(cloned.read("ITEM", "CONVERTED"), 2)
        self.assertEqual(cloned.read_item(i, "CONVERTED"), 2)

    def test_prevents_the_read_conversion_cache_from_being_corrupted(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        i.read_conversion = GenericConversion("'A str'")
        i.units = "with units"
        value = self.p.read_item(i, "CONVERTED")
        self.assertEqual(value, "A str")
        value += "That got modified"
        value = self.p.read_item(i, "WITH_UNITS")
        self.assertEqual(value, "A str with units")
        value += "That got modified"
        self.assertEqual(self.p.read_item(i, "WITH_UNITS"), "A str with units")
        value = self.p.read_item(i, "WITH_UNITS")
        value += " more things"
        self.assertEqual(self.p.read_item(i, "WITH_UNITS"), "A str with units")

        self.p.buffer = "\x00"
        i.read_conversion = GenericConversion("['A', 'B', 'C']")
        value = self.p.read_item(i, "CONVERTED")
        self.assertEqual(value, ["A", "B", "C"])
        value = self.p.read_item(i, "WITH_UNITS")
        self.assertEqual(value, ["A with units", "B with units", "C with units"])
        self.assertEqual(
            self.p.read_item(i, "WITH_UNITS"),
            ["A with units", "B with units", "C with units"],
        )
        value = self.p.read_item(i, "WITH_UNITS")
        self.assertEqual(
            self.p.read_item(i, "WITH_UNITS"),
            ["A with units", "B with units", "C with units"],
        )

    def test_reads_the_converted_value_with_states(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        i.states = {"TRUE": 1, "FALSE": 2}
        self.assertEqual(self.p.read("ITEM", "CONVERTED", b"\x00"), 0)
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x00"), 0)
        self.assertEqual(self.p.read("ITEM", "CONVERTED", b"\x01"), "TRUE")
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x01"), "TRUE")
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x01", 2), "FALSE")
        i.read_conversion = GenericConversion("value / 2")
        self.assertEqual(self.p.read("ITEM", "CONVERTED", b"\x04"), "FALSE")
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x04"), "FALSE")
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x04", 2), "TRUE")

    def test_handles_an_any_state(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        i.states = {"TRUE": 1, "FALSE": 2, "ERROR": "ANY"}
        self.assertEqual(self.p.read("ITEM", "CONVERTED", b"\x00"), "ERROR")
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x00"), "ERROR")
        self.assertEqual(self.p.read("ITEM", "CONVERTED", b"\x01"), "TRUE")
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x01"), "TRUE")
        self.assertEqual(self.p.read("ITEM", "CONVERTED", b"\x02"), "FALSE")
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x02"), "FALSE")
        self.assertEqual(self.p.read("ITEM", "CONVERTED", b"\x03"), "ERROR")
        self.assertEqual(self.p.read_item(i, "CONVERTED", b"\x03"), "ERROR")

    def test_reads_the_formatted_value(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        self.assertEqual(self.p.read("ITEM", "FORMATTED", b"\x02"), "2")
        self.assertEqual(self.p.read_item(i, "FORMATTED", b"\x02"), "2")
        i.format_string = "0x%x"
        self.assertEqual(self.p.read("ITEM", "FORMATTED", b"\x02"), "0x2")
        self.assertEqual(self.p.read_item(i, "FORMATTED", b"\x02"), "0x2")
        self.assertEqual(self.p.read_item(i, "FORMATTED", b"\x02", 1), "0x1")
        i.states = {"TRUE": 1, "FALSE": 2}
        self.assertEqual(self.p.read("ITEM", "FORMATTED", b"\x01"), "TRUE")
        self.assertEqual(self.p.read_item(i, "FORMATTED", b"\x01"), "TRUE")
        self.assertEqual(self.p.read("ITEM", "FORMATTED", b"\x02"), "FALSE")
        self.assertEqual(self.p.read_item(i, "FORMATTED", b"\x02"), "FALSE")
        self.assertEqual(self.p.read("ITEM", "FORMATTED", b"\x04"), "0x4")
        self.assertEqual(self.p.read_item(i, "FORMATTED", b"\x04"), "0x4")
        i.read_conversion = GenericConversion("value / 2")
        self.assertEqual(self.p.read("ITEM", "FORMATTED", b"\x04"), "FALSE")
        self.assertEqual(self.p.read_item(i, "FORMATTED", b"\x04"), "FALSE")

    def test_reads_the_with_units_value(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        i.units = "V"
        self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x02"), "2 V")
        self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x02"), "2 V")
        i.format_string = "0x%x"
        self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x02"), "0x2 V")
        self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x02"), "0x2 V")
        i.states = {"TRUE": 1, "FALSE": 2}
        self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x01"), "TRUE")
        self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x01"), "TRUE")
        self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x02"), "FALSE")
        self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x02"), "FALSE")
        self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x04"), "0x4 V")
        self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x04"), "0x4 V")
        i.read_conversion = GenericConversion("value / 2")
        self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x04"), "FALSE")
        self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x04"), "FALSE")

    def test_reads_the_with_units_array_value(self):
        self.p.append_item("item", 8, "UINT", 16)
        i = self.p.get_item("ITEM")
        i.units = "V"
        self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x01\x02"), ["1 V", "2 V"])
        self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x01\x02"), ["1 V", "2 V"])
        i.format_string = "0x%x"
        self.assertEqual(
            self.p.read("ITEM", "WITH_UNITS", b"\x01\x02"), ["0x1 V", "0x2 V"]
        )
        self.assertEqual(
            self.p.read_item(i, "WITH_UNITS", b"\x01\x02"), ["0x1 V", "0x2 V"]
        )
        i.states = {"TRUE": 1, "FALSE": 2}
        self.assertEqual(
            self.p.read("ITEM", "WITH_UNITS", b"\x01\x02"), ["TRUE", "FALSE"]
        )
        self.assertEqual(
            self.p.read_item(i, "WITH_UNITS", b"\x01\x02"), ["TRUE", "FALSE"]
        )
        self.assertEqual(
            self.p.read("ITEM", "WITH_UNITS", b"\x00\x01"), ["0x0 V", "TRUE"]
        )
        self.assertEqual(
            self.p.read_item(i, "WITH_UNITS", b"\x00\x01"), ["0x0 V", "TRUE"]
        )
        self.assertEqual(
            self.p.read("ITEM", "WITH_UNITS", b"\x02\x03"), ["FALSE", "0x3 V"]
        )
        self.assertEqual(
            self.p.read_item(i, "WITH_UNITS", b"\x02\x03"), ["FALSE", "0x3 V"]
        )
        # Python doesn't support reading 1 byte when two are defined
        # self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x04"), ["0x4 V"])
        # self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x04"), ["0x4 V"])
        # self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x04"), ["0x4 V"])
        # self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x04"), ["0x4 V"])
        i.read_conversion = GenericConversion("value / 2")
        self.assertEqual(
            self.p.read("ITEM", "WITH_UNITS", b"\x02\x04"), ["TRUE", "FALSE"]
        )
        self.assertEqual(
            self.p.read_item(i, "WITH_UNITS", b"\x02\x04"), ["TRUE", "FALSE"]
        )
        # self.assertEqual(self.p.read("ITEM", "WITH_UNITS", b"\x08"), ["0x4 V"])
        # self.assertEqual(self.p.read_item(i, "WITH_UNITS", b"\x08"), ["0x4 V"])
        self.p.define_item("item2", 0, 0, "DERIVED")
        i = self.p.get_item("ITEM2")
        i.units = "V"
        i.read_conversion = GenericConversion("[1,2,3,4,5]")
        self.assertEqual(
            self.p.read("ITEM2", "FORMATTED", ""), ["1", "2", "3", "4", "5"]
        )
        self.assertEqual(
            self.p.read("ITEM2", "WITH_UNITS", ""), ["1 V", "2 V", "3 V", "4 V", "5 V"]
        )


class PacketReadDerived(unittest.TestCase):
    def setUp(self):
        self.p = Packet("tgt", "pkt")

    def test_returns_none_if_no_read_conversion_defined(self):
        self.p.append_item("item", 0, "DERIVED")
        i = self.p.get_item("ITEM")
        i.format_string = "0x%x"
        i.states = {"TRUE": 1, "FALSE": 0}
        i.units = "V"
        self.assertIsNone(self.p.read("ITEM", "RAW", ""))
        self.assertIsNone(self.p.read_item(i, "RAW", ""))

    def test_reads_the_raw_value(self):
        self.p.append_item("item", 0, "DERIVED")
        i = self.p.get_item("ITEM")
        i.format_string = "0x%x"
        i.states = {"TRUE": 1, "FALSE": 0}
        i.units = "V"
        i.read_conversion = GenericConversion("0")
        self.assertEqual(self.p.read("ITEM", "RAW", ""), 0)
        self.assertEqual(self.p.read_item(i, "RAW", ""), 0)
        i.read_conversion = GenericConversion("1")
        self.assertEqual(self.p.read("ITEM", "RAW", ""), 1)
        self.assertEqual(self.p.read_item(i, "RAW", ""), 1)

    def test_reads_the_converted_value(self):
        self.p.append_item("item", 0, "DERIVED")
        i = self.p.get_item("ITEM")
        i.format_string = "0x%x"
        i.states = {"TRUE": 1, "FALSE": 0}
        i.units = "V"
        i.read_conversion = GenericConversion("0")
        self.assertEqual(self.p.read("ITEM", "CONVERTED", ""), "FALSE")
        self.assertEqual(self.p.read_item(i, "CONVERTED", ""), "FALSE")
        i.read_conversion = GenericConversion("1")
        self.assertEqual(self.p.read("ITEM", "CONVERTED", ""), "TRUE")
        self.assertEqual(self.p.read_item(i, "CONVERTED", ""), "TRUE")

    def test_reads_the_formatted_value(self):
        self.p.append_item("item", 0, "DERIVED")
        i = self.p.get_item("ITEM")
        i.format_string = "0x%x"
        i.states = {"TRUE": 1, "FALSE": 0}
        i.units = "V"
        i.read_conversion = GenericConversion("3")
        self.assertEqual(self.p.read("ITEM", "FORMATTED", ""), "0x3")
        self.assertEqual(self.p.read_item(i, "FORMATTED", ""), "0x3")

    def test_reads_the_with_units_value(self):
        self.p.append_item("item", 0, "DERIVED")
        i = self.p.get_item("ITEM")
        i.format_string = "0x%x"
        i.states = {"TRUE": 1, "FALSE": 0}
        i.units = "V"
        i.read_conversion = GenericConversion("3")
        self.assertEqual(self.p.read("ITEM", "WITH_UNITS", ""), "0x3 V")
        self.assertEqual(self.p.read_item(i, "WITH_UNITS", ""), "0x3 V")


class PacketWrite(unittest.TestCase):
    def setUp(self):
        self.p = Packet("tgt", "pkt")
        self.buffer = bytearray(b"\x00\x00\x00\x00")

    def test_complains_about_unknown_value_type(self):
        self.p.append_item("item", 32, "UINT")
        i = self.p.get_item("ITEM")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type 'MINE', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.write("ITEM", 0, "MINE")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type 'MINE', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.write("ITEM", 0, "MINE")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type 'MINE', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.write_item(i, 0, "MINE")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type 'ABCDEFGHIJ...', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.write_item(i, 0, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        with self.assertRaisesRegex(
            AttributeError,
            "Unknown value type '.*', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'",
        ):
            self.p.write("ITEM", 0x01020304, "\x00")

    def test_writes_the_raw_value(self):
        self.p.append_item("item", 32, "UINT")
        i = self.p.get_item("ITEM")
        self.p.write("ITEM", 0x01020304, "RAW", self.buffer)
        self.assertEqual(self.buffer, b"\x01\x02\x03\x04")
        self.p.write_item(i, 0x05060708, "RAW", self.buffer)
        self.assertEqual(self.buffer, b"\x05\x06\x07\x08")

    def test_clears_the_read_cache(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        self.p.buffer = b"\x04"
        cache = self.p.read_conversion_cache
        i.read_conversion = GenericConversion("value / 2")
        self.assertIsNone(cache)
        self.assertEqual(self.p.read("ITEM"), 2)
        cache = self.p.read_conversion_cache
        self.assertEqual(cache[i.name], 2)
        self.p.write("ITEM", 0x08, "RAW")
        self.assertEqual(self.p.buffer, bytearray(b"\x08"))
        cache = self.p.read_conversion_cache
        self.assertIsNone(cache.get(i.name))
        self.assertEqual(self.p.read("ITEM"), 4)
        self.assertEqual(cache[i.name], 4)

    def test_writes_the_converted_value(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        self.p.write("ITEM", 1, "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x01\x00\x00\x00")
        self.p.write_item(i, 2, "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x02\x00\x00\x00")
        i.write_conversion = GenericConversion("value / 2")
        self.p.write("ITEM", 1, "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x00\x00\x00\x00")
        self.p.write_item(i, 2, "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x01\x00\x00\x00")

    def test_writes_the_converted_value_with_states(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        i.states = {"TRUE": 1, "FALSE": 2}
        self.p.write("ITEM", 3, "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x03\x00\x00\x00")
        self.p.write_item(i, 4, "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x04\x00\x00\x00")
        self.p.write("ITEM", "TRUE", "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x01\x00\x00\x00")
        self.p.write_item(i, "FALSE", "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x02\x00\x00\x00")
        with self.assertRaisesRegex(ValueError, "Unknown state BLAH for ITEM"):
            self.p.write_item(i, "BLAH", "CONVERTED", self.buffer)
        i.write_conversion = GenericConversion("value / 2")
        self.p.write("ITEM", 4, "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x02\x00\x00\x00")
        self.p.write("ITEM", "TRUE", "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x00\x00\x00\x00")
        self.p.write_item(i, "FALSE", "CONVERTED", self.buffer)
        self.assertEqual(self.buffer, b"\x01\x00\x00\x00")

    def test_complains_about_the_formatted_value_type(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        with self.assertRaisesRegex(
            AttributeError, "Invalid value type on write= FORMATTED"
        ):
            self.p.write("ITEM", 3, "FORMATTED", self.buffer)
        with self.assertRaisesRegex(
            AttributeError, "Invalid value type on write= FORMATTED"
        ):
            self.p.write_item(i, 3, "FORMATTED", self.buffer)

    def test_complains_about_the_with_units_value_type(self):
        self.p.append_item("item", 8, "UINT")
        i = self.p.get_item("ITEM")
        with self.assertRaisesRegex(
            AttributeError, "Invalid value type on write= WITH_UNITS"
        ):
            self.p.write("ITEM", 3, "WITH_UNITS", self.buffer)
        with self.assertRaisesRegex(
            AttributeError, "Invalid value type on write= WITH_UNITS"
        ):
            self.p.write_item(i, 3, "WITH_UNITS", self.buffer)


class PacketReadItems(unittest.TestCase):
    def test_reads_lists_of_items(self):
        p = Packet("tgt", "pkt")
        i1 = p.append_item("test1", 8, "UINT", 16)
        i2 = p.append_item("test2", 16, "UINT")
        i2.states = {"TRUE": 0x0304}
        i3 = p.append_item("test3", 32, "UINT")
        i3.read_conversion = GenericConversion("value / 2")
        i4 = p.define_item("test4", 0, 0, "DERIVED")
        i4.read_conversion = GenericConversion("packet.read('TEST1')")

        p.buffer = b"\x01\x02\x03\x04\x04\x06\x08\x0A"
        vals = p.read_items([i1, i2, i3, i4], "RAW")
        self.assertEqual(vals["TEST1"], [1, 2])
        self.assertEqual(vals["TEST2"], 0x0304)
        self.assertEqual(vals["TEST3"], 0x0406080A)
        self.assertEqual(vals["TEST4"], [1, 2])

        vals = p.read_items([i1, i2, i3, i4], "CONVERTED")
        self.assertEqual(vals["TEST1"], [1, 2])
        self.assertEqual(vals["TEST2"], "TRUE")
        self.assertEqual(vals["TEST3"], 0x02030405)
        self.assertEqual(vals["TEST4"], [1, 2])


class PacketWriteItems(unittest.TestCase):
    def test_writes_lists_of_items(self):
        p = Packet("tgt", "pkt")
        i1 = p.append_item("test1", 8, "UINT", 16)
        i2 = p.append_item("test2", 16, "UINT")
        i2.states = {"TRUE": 0x0304}
        i3 = p.append_item("test3", 32, "UINT")
        i3.read_conversion = GenericConversion("value / 2")
        i4 = p.define_item("test4", 0, 0, "DERIVED")
        i4.read_conversion = GenericConversion("packet.read('TEST1')")

        p.buffer = b"\x01\x02\x03\x04\x04\x06\x08\x0A"
        p.write_items([i1, i2, i3, i4], [[3, 4], 2, 1, None], "RAW")
        vals = p.read_items([i1, i2, i3, i4], "RAW")
        self.assertEqual(vals["TEST1"], [3, 4])
        self.assertEqual(vals["TEST2"], 0x0002)
        self.assertEqual(vals["TEST3"], 0x00000001)
        self.assertEqual(vals["TEST4"], [3, 4])

        p.write_items([i1, i2, i3], [[3, 4], 2, 1, None], "CONVERTED")
        vals = p.read_items([i1, i2, i3, i4], "RAW")
        self.assertEqual(vals["TEST1"], [3, 4])
        self.assertEqual(vals["TEST2"], 0x0002)
        self.assertEqual(vals["TEST3"], 0x00000001)
        self.assertEqual(vals["TEST4"], [3, 4])


class PacketReadAll(unittest.TestCase):
    def test_defaults_to_read_all_converted_items(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT", 16)
        p.append_item("test2", 16, "UINT")
        i = p.get_item("TEST2")
        i.states = {"TRUE": 0x0304}
        p.append_item("test3", 32, "UINT")
        i = p.get_item("TEST3")
        i.read_conversion = GenericConversion("value / 2")

        p.buffer = b"\x01\x02\x03\x04\x04\x06\x08\x0A"
        vals = p.read_all()
        self.assertEqual(vals[0][0], "TEST1")
        self.assertEqual(vals[1][0], "TEST2")
        self.assertEqual(vals[2][0], "TEST3")
        self.assertEqual(vals[0][1], [1, 2])
        self.assertEqual(vals[1][1], "TRUE")
        self.assertEqual(vals[2][1], 0x02030405)


class PacketReadAllWithLimitsStates(unittest.TestCase):
    def test_returns_an_array_of_items_with_their_limit_states(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT")
        i = p.get_item("TEST1")
        i.states = {"TRUE": 1, "FALSE": 0}
        i.state_colors = {"TRUE": "GREEN", "FALSE": "RED"}
        p.update_limits_items_cache(i)
        p.write("TEST1", 0)
        p.enable_limits("TEST1")
        p.append_item("test2", 16, "UINT")
        i = p.get_item("TEST2")
        i.limits.values = {"DEFAULT": [1, 2, 4, 5]}
        p.write("TEST2", 3)
        p.enable_limits("TEST2")
        p.update_limits_items_cache(i)
        p.check_limits()

        vals = p.read_all_with_limits_states()
        self.assertEqual(vals[0][0], "TEST1")
        self.assertEqual(vals[1][0], "TEST2")
        self.assertEqual(vals[0][1], "FALSE")
        self.assertEqual(vals[1][1], 3)
        self.assertEqual(vals[0][2], "RED")
        self.assertEqual(vals[1][2], "GREEN")


class PacketFormatted(unittest.TestCase):
    def test_prints_out_all_the_items(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT", 16)
        p.write("test1", [1, 2])
        p.append_item("test2", 16, "UINT")
        i = p.get_item("TEST2")
        i.states = {"TRUE": 0x0304}
        p.write("test2", 0x0304)
        p.append_item("test3", 32, "UINT")
        i = p.get_item("TEST3")
        i.read_conversion = GenericConversion("value / 2")
        p.write("test3", 0x0406080A)
        p.append_item("test4", 32, "BLOCK")
        i = p.get_item("TEST4")
        i.read_conversion = GenericConversion("str(value)")
        p.write("test4", b"Test")
        self.assertIn("TEST1: [1, 2]", p.formatted())
        self.assertIn("TEST2: TRUE", p.formatted())
        self.assertIn(f"TEST3: {0x02030405}", p.formatted())
        self.assertIn("TEST4: bytearray(b'Test')", p.formatted())
        # Test the data_type parameter
        self.assertIn("TEST1: [1, 2]", p.formatted("RAW"))
        self.assertIn(f"TEST2: {0x0304}", p.formatted("RAW"))
        self.assertIn(f"TEST3: {0x0406080A}", p.formatted("RAW"))
        self.assertIn("00000000: 54 65 73 74", p.formatted("RAW"))
        # Test the indent parameter
        self.assertIn("    TEST1: [1, 2]", p.formatted("CONVERTED", 4))
        # Test the buffer parameter
        buffer = b"\x02\x03\x04\x05\x00\x00\x00\x02\x44\x45\x41\x44"
        self.assertIn("TEST1: [2, 3]", p.formatted("CONVERTED", 0, buffer))
        self.assertIn(f"TEST2: {0x0405}", p.formatted("CONVERTED", 0, buffer))
        self.assertIn("TEST3: 1", p.formatted("CONVERTED", 0, buffer))
        self.assertIn("TEST4: b'DEAD'", p.formatted("CONVERTED", 0, buffer))
        # Test the ignored parameter
        string = p.formatted("CONVERTED", 0, p.buffer, ["TEST1", "TEST4"])
        self.assertNotIn("TEST1", string)
        self.assertIn("TEST2: TRUE", string)
        self.assertIn(f"TEST3: {0x02030405}", string)
        self.assertNotIn("TEST4", string)


class PacketCheckBitOffsets(unittest.TestCase):
    def test_complains_about_overlapping_items(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 8, "UINT")
        p.define_item("item2", 0, 8, "UINT")
        self.assertEqual(
            p.check_bit_offsets()[0],
            "Bit definition overlap at bit offset 0 for packet TGT1 PKT1 items ITEM2 and ITEM1",
        )

    def test_does_not_complain_with_non_overlapping_negative_offsets(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 8, "UINT")
        p.define_item("item2", 8, -16, "BLOCK")
        p.define_item("item3", -16, 16, "UINT")
        self.assertEqual(p.check_bit_offsets(), [])

    def test_complains_with_overlapping_negative_offsets(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 8, "UINT")
        p.define_item("item2", 8, -16, "BLOCK")
        p.define_item("item3", -17, 16, "UINT")
        self.assertEqual(
            p.check_bit_offsets()[0],
            "Bit definition overlap at bit offset -17 for packet TGT1 PKT1 items ITEM3 and ITEM2",
        )

    def test_complains_about_intersecting_items(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 32, "UINT")
        p.define_item("item2", 16, 32, "UINT")
        self.assertEqual(
            p.check_bit_offsets()[0],
            "Bit definition overlap at bit offset 16 for packet TGT1 PKT1 items ITEM2 and ITEM1",
        )

    def test_complains_about_array_overlapping_items(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 8, "UINT", 32)
        p.define_item("item2", 0, 8, "UINT", 32)
        self.assertEqual(
            p.check_bit_offsets()[0],
            "Bit definition overlap at bit offset 0 for packet TGT1 PKT1 items ITEM2 and ITEM1",
        )

    def test_does_not_complain_with_array_non_overlapping_negative_offsets(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 8, "UINT")
        p.define_item("item2", 8, 8, "INT", -16)
        p.define_item("item3", -16, 16, "UINT")
        self.assertEqual(p.check_bit_offsets(), [])

    def test_complains_with_array_overlapping_negative_offsets(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 8, "UINT")
        p.define_item("item2", 8, 8, "INT", -16)
        p.define_item("item3", -17, 16, "UINT")
        self.assertEqual(
            p.check_bit_offsets()[0],
            "Bit definition overlap at bit offset -17 for packet TGT1 PKT1 items ITEM3 and ITEM2",
        )

    def test_complains_about_array_intersecting_items(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 8, "UINT", 32)
        p.define_item("item2", 16, 8, "UINT", 32)
        self.assertEqual(
            p.check_bit_offsets()[0],
            "Bit definition overlap at bit offset 16 for packet TGT1 PKT1 items ITEM2 and ITEM1",
        )

    def test_does_not_complain_about_nonoverlapping_big_endian_bitfields(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 12, "UINT", None, "BIG_ENDIAN")
        p.define_item("item2", 12, 4, "UINT", None, "BIG_ENDIAN")
        p.define_item("item3", 16, 16, "UINT", None, "BIG_ENDIAN")
        self.assertEqual(p.check_bit_offsets(), [])

    def test_complains_about_overlapping_big_endian_bitfields(self):
        p = Packet("tgt1", "pkt1")
        p.define_item("item1", 0, 12, "UINT", None, "BIG_ENDIAN")
        p.define_item("item2", 10, 6, "UINT", None, "BIG_ENDIAN")
        p.define_item("item3", 16, 16, "UINT", None, "BIG_ENDIAN")
        self.assertEqual(
            p.check_bit_offsets()[0],
            "Bit definition overlap at bit offset 10 for packet TGT1 PKT1 items ITEM2 and ITEM1",
        )

    def test_does_not_complain_about_nonoverlapping_little_endian_bitfields(self):
        p = Packet("tgt1", "pkt1")
        # bit offset in LITTLE_ENDIAN refers to MSB
        p.define_item("item1", 12, 12, "UINT", None, "LITTLE_ENDIAN")
        p.define_item("item2", 16, 16, "UINT", None, "LITTLE_ENDIAN")
        self.assertEqual(p.check_bit_offsets(), [])

    def test_complains_about_overlapping_little_endian_bitfields(self):
        p = Packet("tgt1", "pkt1")
        # bit offset in LITTLE_ENDIAN refers to MSB
        p.define_item("item1", 12, 12, "UINT", None, "LITTLE_ENDIAN")
        p.define_item("item2", 10, 10, "UINT", None, "LITTLE_ENDIAN")
        self.assertEqual(
            p.check_bit_offsets()[0],
            "Bit definition overlap at bit offset 12 for packet TGT1 PKT1 items ITEM1 and ITEM2",
        )


class PacketIdItems(unittest.TestCase):
    def test_returns_an_array_of_the_identifying_items(self):
        p = Packet("tgt", "pkt")
        p.define_item(
            "item1",
            0,
            32,
            "FLOAT",
            None,
            "BIG_ENDIAN",
            "ERROR",
            "%5.1f",
            None,
            None,
            None,
        )
        p.define_item(
            "item2",
            64,
            32,
            "FLOAT",
            None,
            "BIG_ENDIAN",
            "ERROR",
            "%5.1f",
            None,
            None,
            5,
        )
        p.define_item(
            "item3",
            96,
            32,
            "FLOAT",
            None,
            "BIG_ENDIAN",
            "ERROR",
            "%5.1f",
            None,
            None,
            None,
        )
        p.define_item(
            "item4",
            32,
            32,
            "FLOAT",
            None,
            "BIG_ENDIAN",
            "ERROR",
            "%5.1f",
            None,
            None,
            6,
        )
        self.assertIsInstance(p.id_items, list)
        self.assertEqual(p.id_items[0].name, "ITEM4")
        self.assertEqual(p.id_items[1].name, "ITEM2")


class PacketReadIdValues(unittest.TestCase):
    def test_to_read_the_right_values(self):
        buffer = b"\x00\x00\x00\x04\x00\x00\x00\x03\x00\x00\x00\x02\x00\x00\x00\x01"
        p = Packet("tgt", "pkt")
        p.define_item(
            "item1", 0, 32, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, None
        )
        p.define_item(
            "item2", 64, 32, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 0
        )
        p.define_item(
            "item3", 96, 32, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, None
        )
        p.define_item(
            "item4", 32, 32, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 6
        )
        values = p.read_id_values(buffer)
        self.assertEqual(values[0], 3)
        self.assertEqual(values[1], 2)


class PacketIdentify(unittest.TestCase):
    def test_identifies_a_buffer_based_on_id_items(self):
        p = Packet("tgt", "pkt")
        p.append_item("item1", 8, "UINT")
        p.append_item(
            "item2", 16, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 5
        )
        p.append_item("item3", 32, "UINT")
        self.assertTrue(p.identify(b"\x00\x00\x05\x01\x02\x03\x04"))
        self.assertFalse(p.identify(b"\x00\x00\x04\x01\x02\x03\x04"))
        self.assertFalse(p.identify(b"\x00"))

    def test_identifies_if_the_buffer_is_too_short(self):
        p = Packet("tgt", "pkt")
        p.append_item("item1", 8, "UINT")
        p.append_item(
            "item2", 16, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 5
        )
        p.append_item("item3", 32, "UINT")
        self.assertTrue(p.identify(b"\x00\x00\x05\x01\x02\x03"))

    def test_identifies_if_the_buffer_is_too_long(self):
        p = Packet("tgt", "pkt")
        p.append_item("item1", 8, "UINT")
        p.append_item(
            "item2", 16, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 5
        )
        p.append_item("item3", 32, "UINT")
        self.assertTrue(p.identify(b"\x00\x00\x05\x01\x02\x03\x04\x05"))


class PacketIdentified(unittest.TestCase):
    def test_returns_True_if_the_target_name_and_packet_name_are_set(self):
        self.assertFalse(Packet("TGT", None).identified())
        self.assertFalse(Packet(None, "PKT").identified())
        self.assertTrue(Packet("TGT", "PKT").identified())


class PacketRestoreDefaults(unittest.TestCase):
    def test_loads_a_template(self):
        p = Packet("tgt", "pkt")
        p.template = b'{"test": 1, "other": "value"}'
        self.assertEqual(p.buffer, b"")
        p.restore_defaults()
        self.assertEqual(p.buffer, b'{"test": 1, "other": "value"}')

    def test_writes_all_the_items_back_to_their_default_values(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT", 16)
        i = p.get_item("TEST1")
        i.default = [3, 4]
        p.write("test1", [1, 2])
        p.append_item("test2", 16, "UINT")
        i = p.get_item("TEST2")
        i.default = 0x0102
        i.states = {"TRUE": 0x0304}
        p.write("test2", 0x0304)
        p.append_item("test3", 32, "UINT")
        i = p.get_item("TEST3")
        i.default = 0x02030405
        i.write_conversion = GenericConversion("value * 2")
        p.write("test3", 0x01020304)
        self.assertEqual(p.buffer, b"\x01\x02\x03\x04\x02\x04\x06\x08")
        p.restore_defaults()
        self.assertEqual(p.buffer, b"\x03\x04\x01\x02\x04\x06\x08\x0A")

    def test_writes_all_except_skipped_items_back_to_their_default_values(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT", 16)
        i = p.get_item("TEST1")
        i.default = [3, 4]
        p.write("test1", [1, 2])
        p.append_item("test2", 16, "UINT")
        i = p.get_item("TEST2")
        i.default = 0x0102
        i.states = {"TRUE": 0x0304}
        p.write("test2", 0x0304)
        p.append_item("test3", 32, "UINT")
        i = p.get_item("TEST3")
        i.default = 0x02030405
        i.write_conversion = GenericConversion("value * 2")
        p.write("test3", 0x01020304)
        self.assertEqual(p.buffer, b"\x01\x02\x03\x04\x02\x04\x06\x08")
        p.restore_defaults(p.buffer_no_copy(), ["test1", "test2", "test3"])
        self.assertEqual(p.buffer, b"\x01\x02\x03\x04\x02\x04\x06\x08")
        p.restore_defaults(p.buffer_no_copy(), ["test1", "test3"])
        self.assertEqual(p.buffer, b"\x01\x02\x01\x02\x02\x04\x06\x08")
        p.restore_defaults(p.buffer_no_copy(), ["test3"])
        self.assertEqual(p.buffer, b"\x03\x04\x01\x02\x02\x04\x06\x08")
        p.restore_defaults(p.buffer_no_copy())
        self.assertEqual(p.buffer, b"\x03\x04\x01\x02\x04\x06\x08\x0A")


class PacketLimits(unittest.TestCase):
    def test_enables_limits_on_each_packet_item(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT", 16)
        p.append_item("test2", 16, "UINT")
        self.assertFalse(p.get_item("TEST1").limits.enabled)
        self.assertFalse(p.get_item("TEST2").limits.enabled)
        p.enable_limits("TEST1")
        self.assertTrue(p.get_item("TEST1").limits.enabled)
        self.assertFalse(p.get_item("TEST2").limits.enabled)
        p.enable_limits("TEST2")
        self.assertTrue(p.get_item("TEST1").limits.enabled)
        self.assertTrue(p.get_item("TEST2").limits.enabled)

    def test_disables_limits_on_each_packet_item(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT")
        p.append_item("test2", 16, "UINT")
        p.enable_limits("TEST1")
        p.enable_limits("TEST2")
        self.assertTrue(p.get_item("TEST1").limits.enabled)
        self.assertTrue(p.get_item("TEST2").limits.enabled)
        p.disable_limits("TEST1")
        self.assertFalse(p.get_item("TEST1").limits.enabled)
        self.assertTrue(p.get_item("TEST2").limits.enabled)
        p.disable_limits("TEST2")
        self.assertFalse(p.get_item("TEST1").limits.enabled)
        self.assertFalse(p.get_item("TEST2").limits.enabled)

    def test_calls_the_limits_change_callback_for_all_non_stale_items(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT")
        i = p.get_item("TEST1")
        i.limits.values = {"DEFAULT": [1, 2, 4, 5]}
        p.update_limits_items_cache(i)
        p.append_item("test2", 16, "UINT")
        i = p.get_item("TEST2")
        i.limits.values = {"DEFAULT": [1, 2, 4, 5]}
        p.update_limits_items_cache(i)
        p.write("TEST1", 3)
        p.write("TEST2", 3)
        p.enable_limits("TEST1")
        p.enable_limits("TEST2")

        mock = Mock()
        p.limits_change_callback = mock
        p.check_limits()
        calls = [
            call.call(p, p.get_item("TEST1"), None, 3, True),
            call.call(p, p.get_item("TEST2"), None, 3, True),
        ]
        mock.assert_has_calls(calls)
        p.disable_limits("TEST1")
        p.disable_limits("TEST2")
        calls = [
            call.call(p, p.get_item("TEST1"), "GREEN", None, False),
            call.call(p, p.get_item("TEST2"), "GREEN", None, False),
        ]
        mock.assert_has_calls(calls)
        self.assertFalse(p.get_item("TEST1").limits.enabled)
        self.assertFalse(p.get_item("TEST2").limits.enabled)

    def test_returns_all_items_with_limits(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT")
        p.enable_limits("TEST1")
        p.append_item("test2", 16, "UINT")
        p.enable_limits("TEST2")
        self.assertEqual(p.limits_items, [])

        test1 = p.get_item("TEST1")
        test1.limits.values = {"DEFAULT": [1, 2, 4, 5]}
        p.update_limits_items_cache(test1)
        self.assertEqual(p.limits_items, [test1])
        test2 = p.get_item("TEST2")
        test2.limits.values = {"DEFAULT": [1, 2, 4, 5]}
        p.update_limits_items_cache(test2)
        self.assertEqual(p.limits_items, [test1, test2])

    def test_returns_an_array_indicating_all_items_out_of_limits(self):
        p = Packet("tgt", "pkt")
        p.append_item("test1", 8, "UINT")
        i = p.get_item("TEST1")
        i.limits.values = {"DEFAULT": [1, 2, 4, 5]}
        p.update_limits_items_cache(i)
        p.enable_limits("TEST1")
        p.write("TEST1", 3)
        p.append_item("test2", 16, "UINT")
        i = p.get_item("TEST2")
        i.limits.values = {"DEFAULT": [1, 2, 4, 5]}
        p.update_limits_items_cache(i)
        p.write("TEST2", 3)
        p.enable_limits("TEST2")
        p.check_limits()
        self.assertEqual(p.out_of_limits(), [])

        p.write("TEST1", 6)
        p.check_limits()
        self.assertEqual(p.out_of_limits(), [["TGT", "PKT", "TEST1", "RED_HIGH"]])
        p.write("TEST2", 2)
        p.check_limits()
        self.assertEqual(
            p.out_of_limits(),
            [
                ["TGT", "PKT", "TEST1", "RED_HIGH"],
                ["TGT", "PKT", "TEST2", "YELLOW_LOW"],
            ],
        )


class PacketCheckLimits(unittest.TestCase):
    def setUp(self):
        self.p = Packet("tgt", "pkt")
        self.p.append_item("test1", 8, "UINT")
        self.p.append_item("test2", 16, "UINT")
        self.p.append_item("test3", 32, "FLOAT")

    def test_does_not_call_the_limits_change_callback_if_limits_are_disabled(self):
        self.assertFalse(self.p.get_item("TEST1").limits.enabled)
        self.assertFalse(self.p.get_item("TEST2").limits.enabled)
        mock = Mock()
        self.p.limits_change_callback = mock
        self.p.check_limits()
        mock.assert_not_called()

    def test_calls_the_limits_change_callback(self):
        test1 = self.p.get_item("TEST1")
        self.assertFalse(test1.limits.enabled)
        test1.states = {"TRUE": 1, "FALSE": 0}
        test1.state_colors = {"TRUE": "GREEN", "FALSE": "RED"}
        self.p.update_limits_items_cache(test1)
        self.p.write("TEST1", 0)
        self.p.enable_limits("TEST1")
        test2 = self.p.get_item("TEST2")
        self.assertFalse(test2.limits.enabled)
        test2.states = {"TRUE": 1, "FALSE": 0}
        test2.state_colors = {"TRUE": "RED", "FALSE": "GREEN"}
        self.p.write("TEST2", 0)
        self.p.enable_limits("TEST2")
        self.p.update_limits_items_cache(test2)

        # Mock the callback so we can see if it is called properly:
        mock = Mock()
        self.p.limits_change_callback = mock

        # Check the limits for the first time, TEST1 should be 'RED' and TEST2
        # should be 'GREEN'
        self.p.check_limits()
        self.assertEqual(test1.limits.state, "RED")
        self.assertEqual(test2.limits.state, "GREEN")
        calls = [
            call.call(self.p, test1, None, "FALSE", True),
            call.call(self.p, test2, None, "FALSE", True),
        ]
        mock.assert_has_calls(calls)

        # Change the TEST2 state to 'RED', we were previously 'GREEN'
        self.p.write("TEST2", 1)
        self.p.check_limits()
        self.assertEqual(test2.limits.state, "RED")
        mock.call.assert_called_with(self.p, test2, "GREEN", "TRUE", True)

        # # Change the TEST2 value to something that doesn't map to a state
        self.p.write("TEST2", 2)
        self.p.check_limits()
        self.assertIsNone(test2.limits.state)
        mock.call.assert_called_with(self.p, test2, "RED", 2, False)


class PacketCheckLimitsValues(unittest.TestCase):
    def setUp(self):
        self.p = Packet("tgt", "pkt")
        self.p.append_item("test1", 8, "UINT")
        self.p.append_item("test2", 16, "UINT")
        self.p.append_item("test3", 32, "FLOAT")
        self.test1 = self.p.get_item("TEST1")
        self.assertFalse(self.test1.limits.enabled)
        self.test1.limits.values = {"DEFAULT": [1, 2, 4, 5]}  # red yellow
        self.p.update_limits_items_cache(self.test1)
        self.p.enable_limits("TEST1")

        self.test2 = self.p.get_item("TEST2")
        self.assertFalse(self.test2.limits.enabled)
        self.test2.limits.values = {
            "DEFAULT": [1, 2, 6, 7, 3, 5]
        }  # red yellow and blue
        self.p.update_limits_items_cache(self.test2)
        self.p.enable_limits("TEST2")

        self.test3 = self.p.get_item("TEST3")
        self.assertFalse(self.test3.limits.enabled)
        self.test3.limits.values = {"DEFAULT": [1, 1.5, 2.5, 3]}  # red yellow
        self.p.update_limits_items_cache(self.test3)
        self.p.enable_limits("TEST3")

        # Mock the callback so we can see if it is called properly:
        self.mock = Mock()
        self.p.limits_change_callback = self.mock

    def test_detects_initial_low_states(self):
        self.p.write("TEST1", 0)
        self.p.write("TEST2", 3)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()
        self.assertEqual(self.p.get_item("TEST1").limits.state, "RED_LOW")
        self.assertEqual(self.p.get_item("TEST2").limits.state, "GREEN_LOW")
        self.assertEqual(self.p.get_item("TEST3").limits.state, "YELLOW_LOW")

    def test_detects_initial_high_states(self):
        self.p.write("TEST1", 6)
        self.p.write("TEST2", 5)
        self.p.write("TEST3", 2.75)
        self.p.check_limits()
        self.assertEqual(self.p.get_item("TEST1").limits.state, "RED_HIGH")
        self.assertEqual(self.p.get_item("TEST2").limits.state, "GREEN_HIGH")
        self.assertEqual(self.p.get_item("TEST3").limits.state, "YELLOW_HIGH")

    def test_detects_initial_middle_states(self):
        self.p.write("TEST1", 3)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 2.0)
        self.p.check_limits()
        self.assertEqual(self.p.get_item("TEST1").limits.state, "GREEN")
        self.assertEqual(self.p.get_item("TEST2").limits.state, "BLUE")
        self.assertEqual(self.p.get_item("TEST3").limits.state, "GREEN")

    def test_clears_persistence_case_initial_state_is_None(self):
        self.p.get_item("TEST1").limits.persistence_count = 2
        self.p.get_item("TEST2").limits.persistence_count = 3
        self.p.get_item("TEST3").limits.persistence_count = 4
        self.p.check_limits()
        self.assertEqual(self.p.get_item("TEST1").limits.persistence_count, 0)
        self.assertEqual(self.p.get_item("TEST2").limits.persistence_count, 0)
        self.assertEqual(self.p.get_item("TEST3").limits.persistence_count, 0)

    def test_initializes_call_for_everything(self):
        self.p.write("TEST1", 0)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 1.25)

        # Check the limits for the first time, TEST1 should be 'RED_LOW', TEST2
        # should be 'BLUE', TEST3 should be YELLOW_LOW
        self.p.check_limits()
        self.assertEqual(self.test1.limits.state, "RED_LOW")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "YELLOW_LOW")
        calls = [
            call.call(self.p, self.test1, None, 0, True),
            call.call(self.p, self.test2, None, 4, True),
            call.call(self.p, self.test3, None, 1.25, True),
        ]
        self.mock.assert_has_calls(calls)

    def test_calls_case_limits_change_states(self):
        self.p.write("TEST1", 0)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()

        # Make TEST2 be GREEN_LOW, we were previously 'BLUE'
        self.p.write("TEST2", 3)
        self.p.check_limits()
        self.mock.call.assert_called_with(self.p, self.test2, "BLUE", 3, True)

    def test_calls_only_case_persistence_is_achieved(self):
        # First establish the green state case coming from None
        self.p.get_item("TEST1").limits.persistence_setting = 1
        self.p.get_item("TEST2").limits.persistence_setting = 1
        self.p.get_item("TEST3").limits.persistence_setting = 1
        self.p.write("TEST1", 3)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 2.0)
        self.p.check_limits()
        calls = [
            call.call(self.p, self.test1, None, 3, True),
            call.call(self.p, self.test2, None, 4, True),
            call.call(self.p, self.test3, None, 2.0, True),
        ]
        self.mock.assert_has_calls(calls)

        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

        # Now test the persistence setting by going out of limits
        self.p.get_item("TEST1").limits.persistence_setting = 2
        self.p.get_item("TEST2").limits.persistence_setting = 3
        self.p.get_item("TEST3").limits.persistence_setting = 4

        self.p.write("TEST1", 0)
        self.p.write("TEST2", 8)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

        self.p.write("TEST1", 0)
        self.p.write("TEST2", 8)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()
        self.mock.call.assert_called_with(self.p, self.test1, "GREEN", 0, True)
        self.assertEqual(self.test1.limits.state, "RED_LOW")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

        self.p.write("TEST1", 0)
        self.p.write("TEST2", 8)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()
        self.mock.call.assert_called_with(self.p, self.test2, "BLUE", 8, True)
        self.assertEqual(self.test1.limits.state, "RED_LOW")
        self.assertEqual(self.test2.limits.state, "RED_HIGH")
        self.assertEqual(self.test3.limits.state, "GREEN")

        self.p.write("TEST1", 0)
        self.p.write("TEST2", 8)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()
        self.mock.call.assert_called_with(self.p, self.test3, "GREEN", 1.25, True)
        self.assertEqual(self.test1.limits.state, "RED_LOW")
        self.assertEqual(self.test2.limits.state, "RED_HIGH")
        self.assertEqual(self.test3.limits.state, "YELLOW_LOW")

        # Now go back to good on everything and verify persistence still applies
        self.mock.reset_mock()
        self.p.write("TEST1", 3)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 2.0)
        self.p.check_limits()
        self.mock.call.assert_not_called()
        self.assertEqual(self.test1.limits.state, "RED_LOW")
        self.assertEqual(self.test2.limits.state, "RED_HIGH")
        self.assertEqual(self.test3.limits.state, "YELLOW_LOW")

        self.p.write("TEST1", 3)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 2.0)
        self.p.check_limits()
        self.mock.call.assert_called_with(self.p, self.test1, "RED_LOW", 3, True)
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "RED_HIGH")
        self.assertEqual(self.test3.limits.state, "YELLOW_LOW")

        self.p.write("TEST1", 3)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 2.0)
        self.p.check_limits()
        self.mock.call.assert_called_with(self.p, self.test2, "RED_HIGH", 4, True)
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "YELLOW_LOW")

        self.p.write("TEST1", 3)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 2.0)
        self.p.check_limits()
        self.mock.call.assert_called_with(self.p, self.test3, "YELLOW_LOW", 2.0, True)
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

    def test_does_not_call_case_state_changes_before_persistence_is_achieved(self):
        # First establish the green state case coming from None
        self.p.get_item("TEST1").limits.persistence_setting = 1
        self.p.get_item("TEST2").limits.persistence_setting = 1
        self.p.get_item("TEST3").limits.persistence_setting = 1
        self.p.write("TEST1", 3)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 2.0)
        self.p.check_limits()
        calls = [
            call.call(self.p, self.test1, None, 3, True),
            call.call(self.p, self.test2, None, 4, True),
            call.call(self.p, self.test3, None, 2.0, True),
        ]
        self.mock.assert_has_calls(calls)
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

        # Set all persistence the same
        self.p.get_item("TEST1").limits.persistence_setting = 3
        self.p.get_item("TEST2").limits.persistence_setting = 3
        self.p.get_item("TEST3").limits.persistence_setting = 3

        self.mock.reset_mock()

        # Write bad values twice
        self.p.write("TEST1", 0)
        self.p.write("TEST2", 8)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()
        self.mock.call.assert_not_called()
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

        self.p.write("TEST1", 0)
        self.p.write("TEST2", 8)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()
        self.mock.call.assert_not_called()
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

        # Set the values back to good
        self.p.write("TEST1", 3)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 2.0)
        self.p.check_limits()
        self.mock.call.assert_not_called()
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

        # Write bad values twice
        self.p.write("TEST1", 0)
        self.p.write("TEST2", 8)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()
        self.mock.call.assert_not_called()
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

        self.p.write("TEST1", 0)
        self.p.write("TEST2", 8)
        self.p.write("TEST3", 1.25)
        self.p.check_limits()
        self.mock.call.assert_not_called()
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")

        # Set the values back to good
        self.p.write("TEST1", 3)
        self.p.write("TEST2", 4)
        self.p.write("TEST3", 2.0)
        self.p.check_limits()
        self.mock.call.assert_not_called()
        self.assertEqual(self.test1.limits.state, "GREEN")
        self.assertEqual(self.test2.limits.state, "BLUE")
        self.assertEqual(self.test3.limits.state, "GREEN")


class Clone(unittest.TestCase):
    def test_duplicates_the_packet(self):
        p = Packet("tgt", "pkt")
        p.processors["PROCESSOR"] = Processor()
        p.processors["PROCESSOR"].name = "TestProcessor"
        p2 = p.clone()
        # No comparison operator
        # self.assertEqual(p, p2)
        self.assertIsNot(p, p2)
        self.assertEqual(p2.target_name, "TGT")
        self.assertEqual(p2.packet_name, "PKT")
        # No comparison operator
        # self.assertEqual(p2.processors['PROCESSOR'], p.processors['PROCESSOR'])
        self.assertIsNot(p2.processors["PROCESSOR"], p.processors["PROCESSOR"])
        self.assertEqual(
            p2.processors["PROCESSOR"].name, p.processors["PROCESSOR"].name
        )


class Reset(unittest.TestCase):
    def test_does_nothing_to_the_system_meta_packet(self):
        p = Packet("SYSTEM", "META")
        time = datetime.now()
        p.received_time = time
        p.received_count = 50
        p.reset()
        self.assertEqual(p.received_time, time)
        self.assertEqual(p.received_count, 50)

    def test_resets_the_received_time_and_received_count(self):
        p = Packet("tgt", "pkt")
        # p.processors['processor'] = double("reset", :reset : True)
        p.received_time = datetime.now()
        p.received_count = 50
        p.reset()
        self.assertEqual(p.received_time, None)
        self.assertEqual(p.received_count, 0)

    def test_clears_the_read_conversion_cache(self):
        p = Packet("tgt", "pkt")
        p.append_item("item", 8, "UINT")
        i = p.get_item("ITEM")
        p.buffer = b"\x04"
        i.read_conversion = GenericConversion("value / 2")
        self.assertEqual(p.read("ITEM"), 2)
        self.assertEqual(p.read_conversion_cache[i.name], 2)
        p.reset()
        self.assertEqual(p.read_conversion_cache, {})


class PacketJson(unittest.TestCase):
    def test_creates_a_hash(self):
        packet = Packet("tgt", "pkt")
        packet.template = b"\x00\x01\x02\x03"
        json = packet.as_json()
        self.assertEqual(json["target_name"], "TGT")
        self.assertEqual(json["packet_name"], "PKT")
        self.assertEqual(json["items"], [])
        self.assertIn("BinaryAccessor", json["accessor"])
        # self.assertEqual(json['template'], Base64.encode64("\x00\x01\x02\x03"))

    def test_creates_a_packet_from_a_hash(self):
        p = Packet("tgt", "pkt")
        p.template = b"\x00\x01\x02\x03"
        p.append_item("test1", 8, "UINT")
        p.accessor = BinaryAccessor()
        packet = Packet.from_json(p.as_json())
        self.assertEqual(packet.target_name, p.target_name)
        self.assertEqual(packet.packet_name, p.packet_name)
        self.assertEqual(packet.accessor.__class__.__name__, "BinaryAccessor")
        item = packet.sorted_items[0]
        self.assertEqual(item.name, "TEST1")
        self.assertEqual(packet.template, b"\x00\x01\x02\x03")


class PacketDecom(unittest.TestCase):
    def test_creates_decommutated_array_data(self):
        p = Packet("tgt", "pkt")
        i1 = p.append_item("test1", 8, "UINT", 16)
        i1.read_conversion = GenericConversion("value * 2")
        i1.format_string = "0x%X"
        i1.units = "C"

        p.buffer = b"\x01\x02"
        vals = p.decom()
        self.assertEqual(vals["TEST1"], [1, 2])
        self.assertEqual(vals["TEST1__C"], [2, 4])
        self.assertEqual(vals["TEST1__F"], ["0x2", "0x4"])
        self.assertEqual(vals["TEST1__U"], ["0x2 C", "0x4 C"])

    def test_creates_decommutated_block_data(self):
        p = Packet("tgt", "pkt")
        p.append_item("block", 40, "BLOCK")
        p.buffer = b"\x01\x02\x03\x04\05"
        vals = p.decom()
        self.assertEqual(vals["BLOCK"], b"\x01\x02\x03\x04\x05")

    def test_creates_decommutated_data(self):
        p = Packet("tgt", "pkt")
        i1 = p.append_item("test1", 8, "UINT", 16)
        i1.format_string = "0x%X"
        i1.units = "C"
        i2 = p.append_item("test2", 16, "UINT")
        i2.states = {"TRUE": 0x0304}
        i3 = p.append_item("test3", 32, "UINT")
        i3.read_conversion = GenericConversion("value / 2")
        i3.limits.state = "RED"
        i4 = p.define_item("test4", 0, 0, "DERIVED")
        i4.read_conversion = GenericConversion("packet.read('TEST1')")

        p.buffer = b"\x01\x02\x03\x04\x04\x06\x08\x0A"
        vals = p.decom()
        self.assertEqual(vals["TEST1"], [1, 2])
        self.assertEqual(vals["TEST2"], 0x0304)
        self.assertEqual(vals["TEST3"], 0x0406080A)
        self.assertEqual(vals["TEST4"], [1, 2])

        self.assertEqual(vals.get("TEST1__C"), None)
        self.assertEqual(vals.get("TEST2__C"), "TRUE")
        self.assertEqual(vals.get("TEST3__C"), 0x02030405)
        self.assertEqual(vals.get("TEST4__C"), None)

        self.assertEqual(vals.get("TEST1__F"), ["0x1", "0x2"])
        self.assertEqual(vals.get("TEST2__F"), None)
        self.assertEqual(vals.get("TEST3__F"), None)
        self.assertEqual(vals.get("TEST4__F"), None)

        self.assertEqual(vals.get("TEST1__U"), ["0x1 C", "0x2 C"])
        self.assertEqual(vals.get("TEST2__U"), None)
        self.assertEqual(vals.get("TEST3__U"), None)
        self.assertEqual(vals.get("TEST4__U"), None)

        self.assertEqual(vals["TEST3__L"], "RED")

        # p.accessor = JsonAccessor
        # p.buffer = '{"test1": [1, 2], "test2": 5, "test3": 104}'
        # vals = p.decom()
        # self.assertEqual(vals["TEST1"], [1, 2])
        # self.assertEqual(vals["TEST2"], 5)
        # self.assertEqual(vals["TEST3"], 104)
        # self.assertEqual(vals["TEST4"], [1, 2])

        # self.assertEqual(vals["TEST1__C"], None)
        # self.assertEqual(vals["TEST2__C"], 5)
        # self.assertEqual(vals["TEST3__C"], 52)
        # self.assertEqual(vals["TEST4__C"], None)

        # self.assertEqual(vals["TEST1__F"], ["0x1", "0x2"])
        # self.assertEqual(vals["TEST2__F"], None)
        # self.assertEqual(vals["TEST3__F"], None)
        # self.assertEqual(vals["TEST4__F"], None)

        # self.assertEqual(vals["TEST1__U"], ["0x1 C", "0x2 C"])
        # self.assertEqual(vals["TEST2__U"], None)
        # self.assertEqual(vals["TEST3__U"], None)
        # self.assertEqual(vals["TEST4__U"], None)

        # self.assertEqual(vals["TEST3__L"], "RED")
