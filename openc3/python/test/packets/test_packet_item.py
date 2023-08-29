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
from openc3.conversions.conversion import Conversion
from openc3.packets.packet_item import PacketItem
from openc3.packets.packet_item_limits import PacketItemLimits
from openc3.packets.limits_response import LimitsResponse


class TestPacketItem(unittest.TestCase):
    def setUp(self):
        self.pi = PacketItem("test", 0, 32, "UINT", "BIG_ENDIAN", None)

    def test_sets_the_format_string(self):
        self.pi.format_string = "%5.1f"
        self.assertEqual(self.pi.format_string, "%5.1f")
        self.assertIn(
            "FORMAT_STRING %5.1f", self.pi.to_config("TELEMETRY", "BIG_ENDIAN")
        )

    def test_sets_the_format_string_to_None(self):
        self.pi.format_string = None
        self.assertIsNone(self.pi.format_string)

    def test_complains_about_non_string_format_strings(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"{self.pi.name}: format_string must be a str but is a float",
        ):
            self.pi.format_string = 5.1

    def test_complains_about_badly_formatted_format_strings(self):
        with self.assertRaisesRegex(
            AttributeError, f"{self.pi.name}: format_string invalid '%'"
        ):
            self.pi.format_string = "%"
        with self.assertRaisesRegex(
            AttributeError, f"{self.pi.name}: format_string invalid '5'"
        ):
            self.pi.format_string = "5"
        with self.assertRaisesRegex(
            AttributeError, f"{self.pi.name}: format_string invalid '%Q'"
        ):
            self.pi.format_string = "%Q"

    def test_accepts_read_conversion_instances(self):
        c = Conversion()
        self.pi.read_conversion = c
        config = self.pi.to_config("TELEMETRY", "BIG_ENDIAN")
        self.assertIn("READ_CONVERSION Conversion", config)

    def test_sets_the_read_conversion_to_None(self):
        self.pi.read_conversion = None
        self.assertIsNone(self.pi.read_conversion)

    def test_complains_about_non_conversion_read_conversions(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"{self.pi.name}: read_conversion must be a Conversion but is a str",
        ):
            self.pi.read_conversion = "HI"

    def test_accepts_write_conversion_instances(self):
        c = Conversion()
        self.pi.write_conversion = c
        config = self.pi.to_config("TELEMETRY", "BIG_ENDIAN")
        self.assertIn("WRITE_CONVERSION Conversion", config)

    def test_sets_the_write_conversion_to_None(self):
        self.pi.write_conversion = None
        self.assertIsNone(self.pi.write_conversion)

    def test_complains_about_non_conversion_write_conversions(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"{self.pi.name}: write_conversion must be a Conversion but is a str",
        ):
            self.pi.write_conversion = "HI"

    def test_accepts_id_values_according_to_data_type(self):
        self.pi.minimum = 0
        self.pi.maximum = 10
        self.pi.id_value = 10
        self.assertEqual(self.pi.id_value, 10)
        self.pi.data_type = "FLOAT"
        self.pi.id_value = 10.0
        self.assertEqual(self.pi.id_value, 10.0)
        self.assertIn(
            "ID_PARAMETER TEST 0 32 FLOAT 0 10 10.0",
            self.pi.to_config("COMMAND", "BIG_ENDIAN"),
        )
        self.assertIn(
            "ID_ITEM TEST 0 32 FLOAT 10.0", self.pi.to_config("TELEMETRY", "BIG_ENDIAN")
        )
        self.pi.data_type = "STRING"
        self.pi.id_value = "HI"
        self.assertEqual(self.pi.id_value, "HI")
        self.assertIn(
            'ID_PARAMETER TEST 0 32 STRING "HI"',
            self.pi.to_config("COMMAND", "BIG_ENDIAN"),
        )
        self.assertIn(
            'ID_ITEM TEST 0 32 STRING "HI"',
            self.pi.to_config("TELEMETRY", "BIG_ENDIAN"),
        )
        self.pi.id_value = b"\xDE\xAD\xBE\xEF"  # binary
        self.assertIn(
            "ID_PARAMETER TEST 0 32 STRING 0xDEADBEEF",
            self.pi.to_config("COMMAND", "BIG_ENDIAN"),
        )
        self.assertIn(
            "ID_ITEM TEST 0 32 STRING 0xDEADBEEF",
            self.pi.to_config("TELEMETRY", "BIG_ENDIAN"),
        )

    def test_sets_the_id_value_to_None(self):
        self.pi.id_value = None
        self.assertIsNone(self.pi.id_value)

    def test_sets_the_id_value_to_zero(self):
        self.pi.id_value = 0
        self.assertEqual(self.pi.id_value, 0)

    def test_complains_about_id_values_that_dont_match_the_data_type(self):
        with self.assertRaisesRegex(
            ValueError, f"{self.pi.name}: Invalid value: HI for data type: UINT"
        ):
            self.pi.id_value = "HI"
        self.pi.data_type = "FLOAT"
        with self.assertRaisesRegex(
            ValueError, f"{self.pi.name}: Invalid value: HI for data type: FLOAT"
        ):
            self.pi.id_value = "HI"

    def test_accepts_states_as_a_hash(self):
        states = {"TRUE": 1, "FALSE": 0}
        self.pi.states = states
        self.assertEqual(self.pi.states, states)
        config = self.pi.to_config("TELEMETRY", "BIG_ENDIAN")
        self.assertIn("STATE TRUE 1", config)
        self.assertIn("STATE FALSE 0", config)
        self.assertEqual(self.pi.states["TRUE"], 1)
        self.assertEqual(self.pi.states["FALSE"], 0)
        self.assertEqual(self.pi.states_by_value()[1], "TRUE")
        self.assertEqual(self.pi.states_by_value()[0], "FALSE")

    def test_sets_the_states_to_None(self):
        self.pi.states = None
        self.assertIsNone(self.pi.states)

    def test_complains_about_states_that_arent_hashes(self):
        with self.assertRaisesRegex(
            AttributeError, f"{self.pi.name}: states must be a dict but is a str"
        ):
            self.pi.states = "state"

    def test_accepts_description_as_a_string(self):
        description = "this is it"
        self.pi.description = description
        self.assertEqual(self.pi.description, description)
        self.assertIn(
            'ITEM TEST 0 32 UINT "this is it"',
            self.pi.to_config("TELEMETRY", "BIG_ENDIAN"),
        )

    def test_sets_the_description_to_None(self):
        self.pi.description = None
        self.assertIsNone(self.pi.description)

    def test_complains_about_description_that_arent_strings(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"{self.pi.name}: description must be a str but is a float",
        ):
            self.pi.description = 5.1

    def test_accepts_units_full_as_a_string(self):
        units_full = "Volts"
        self.pi.units_full = units_full
        self.assertEqual(self.pi.units_full, units_full)

    def test_sets_the_units_full_to_None(self):
        self.pi.units_full = None
        self.assertIsNone(self.pi.units_full)

    def test_complains_about_units_full_that_arent_strings(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"{self.pi.name}: units_full must be a str but is a float",
        ):
            self.pi.units_full = 5.1

    def test_accepts_units_as_a_string(self):
        units = "V"
        self.pi.units = units
        self.assertEqual(self.pi.units, units)
        self.pi.units_full = "Volts"
        self.assertIn("UNITS Volts V", self.pi.to_config("TELEMETRY", "BIG_ENDIAN"))

    def test_sets_the_units_to_None(self):
        self.pi.units = None
        self.assertIsNone(self.pi.units)

    def test_complains_about_units_that_arent_strings(self):
        with self.assertRaisesRegex(
            AttributeError, f"{self.pi.name}: units must be a str but is a float"
        ):
            self.pi.units = 5.1

    def test_accepts_default_according_to_the_data_type(self):
        pi = PacketItem("test", 0, 8, "INT", "BIG_ENDIAN", 16)
        pi.default = [1, -1]
        self.assertEqual(pi.default, [1, -1])
        self.assertIn(
            "ARRAY_PARAMETER TEST 0 8 INT 16", pi.to_config("COMMAND", "BIG_ENDIAN")
        )
        self.assertIn(
            "ARRAY_ITEM TEST 0 8 INT 16", pi.to_config("TELEMETRY", "BIG_ENDIAN")
        )
        pi = PacketItem("test", 0, 32, "UINT", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 10
        pi.default = 0x01020304
        self.assertEqual(pi.default, 0x01020304)
        self.assertIn(
            "PARAMETER TEST 0 32 UINT 0 10 16909060",
            pi.to_config("COMMAND", "BIG_ENDIAN"),
        )
        pi = PacketItem("test", 0, 32, "FLOAT", "BIG_ENDIAN", None)
        pi.minimum = -10
        pi.maximum = 10
        pi.default = 5.5
        self.assertEqual(pi.default, 5.5)
        self.assertIn(
            "PARAMETER TEST 0 32 FLOAT -10 10 5.5",
            pi.to_config("COMMAND", "BIG_ENDIAN"),
        )
        pi = PacketItem("test", 0, 32, "STRING", "BIG_ENDIAN", None)
        pi.default = "HI"
        self.assertEqual(pi.default, "HI")
        self.assertIn(
            'PARAMETER TEST 0 32 STRING "HI"', pi.to_config("COMMAND", "BIG_ENDIAN")
        )
        pi = PacketItem("test", 0, 32, "STRING", "BIG_ENDIAN", None)
        pi.default = b"\xDE\xAD\xBE\xEF"
        self.assertIn(
            "PARAMETER TEST 0 32 STRING 0xDEADBEEF",
            pi.to_config("COMMAND", "BIG_ENDIAN"),
        )

    def test_sets_the_default_to_None(self):
        self.pi.default = None
        self.assertIsNone(self.pi.default)

    def test_complains_about_default_not_matching_data_type(self):
        pi = PacketItem("test", 0, 8, "UINT", "BIG_ENDIAN", 16)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = 1.1
        with self.assertRaisesRegex(
            AttributeError, "TEST: default must be a list but is a float"
        ):
            pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 8, "UINT", "BIG_ENDIAN", 16)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = []
        pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "UINT", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = 5.5
        with self.assertRaisesRegex(
            AttributeError, "TEST: default must be a int but is a float"
        ):
            pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "UINT", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = 5
        pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "FLOAT", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = "test"
        with self.assertRaisesRegex(
            AttributeError, "TEST: default must be a float but is a str"
        ):
            pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "FLOAT", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = 5
        pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "FLOAT", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = 5.5
        pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "STRING", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = 5.1
        with self.assertRaisesRegex(
            AttributeError, "TEST: default must be a str but is a float"
        ):
            pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "STRING", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = ""
        pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "BLOCK", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = 5.5
        with self.assertRaisesRegex(
            AttributeError, "TEST: default must be a str but is a float"
        ):
            pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "BLOCK", "BIG_ENDIAN", None)
        pi.minimum = 0
        pi.maximum = 0xFFFF
        pi.default = ""
        pi.check_default_and_range_data_types()

    def test_complains_about_range_not_matching_data_type(self):
        pi = PacketItem("test", 0, 32, "UINT", "BIG_ENDIAN", None)
        pi.default = 5
        pi.minimum = 5.5
        pi.maximum = 10
        with self.assertRaisesRegex(
            AttributeError, "TEST: minimum must be a int but is a float"
        ):
            pi.check_default_and_range_data_types()
        pi.minimum = 5
        pi.maximum = 10.5
        with self.assertRaisesRegex(
            AttributeError, "TEST: maximum must be a int but is a float"
        ):
            pi.check_default_and_range_data_types()
        pi = PacketItem("test", 0, 32, "FLOAT", "BIG_ENDIAN", None)
        pi.default = 5.5
        pi.minimum = 5
        pi.maximum = 10
        pi.check_default_and_range_data_types()
        pi.minimum = "a"
        pi.maximum = "z"
        with self.assertRaisesRegex(
            AttributeError, "TEST: minimum must be a float but is a str"
        ):
            pi.check_default_and_range_data_types()
        pi.minimum = 5
        with self.assertRaisesRegex(
            AttributeError, "TEST: maximum must be a float but is a str"
        ):
            pi.check_default_and_range_data_types()

    def test_accepts_hazardous_as_a_hash(self):
        hazardous = {"TRUE": None, "FALSE": "NO FALSE ALLOWED"}
        self.pi.hazardous = hazardous
        self.assertEqual(self.pi.hazardous, hazardous)
        self.assertEqual(self.pi.hazardous["TRUE"], hazardous["TRUE"])
        self.assertEqual(self.pi.hazardous["FALSE"], hazardous["FALSE"])

        self.pi.minimum = 0
        self.pi.maximum = 1
        self.pi.states = {"TRUE": 1, "FALSE": 0}
        config = self.pi.to_config("COMMAND", "BIG_ENDIAN")
        self.assertIn("STATE TRUE 1", config)
        self.assertIn('STATE FALSE 0 HAZARDOUS "NO FALSE ALLOWED"', config)

    def test_sets_hazardous_to_None(self):
        self.pi.hazardous = None
        self.assertIsNone(self.pi.hazardous)

    def test_complains_about_hazardous_that_arent_hashes(self):
        with self.assertRaisesRegex(
            AttributeError, f"{self.pi.name}: hazardous must be a dict but is a str"
        ):
            self.pi.hazardous = ""

    def test_accepts_messages_disabled_as_a_hash(self):
        messages_disabled = {"TRUE": True, "FALSE": None}
        self.pi.messages_disabled = messages_disabled
        self.assertEqual(self.pi.messages_disabled, messages_disabled)
        self.assertTrue(self.pi.messages_disabled["TRUE"])
        self.assertFalse(self.pi.messages_disabled["FALSE"])

        self.pi.minimum = 0
        self.pi.maximum = 1
        self.pi.states = {"TRUE": 1, "FALSE": 0}
        config = self.pi.to_config("COMMAND", "BIG_ENDIAN")
        self.assertIn("STATE TRUE 1 DISABLE_MESSAGES", config)
        self.assertIn("STATE FALSE 0", config)

    def test_sets_messages_disabled_to_None(self):
        self.pi.messages_disabled = None
        self.assertIsNone(self.pi.messages_disabled)

    def test_complains_about_messages_disabled_that_arent_hashes(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"{self.pi.name}: messages_disabled must be a dict but is a str",
        ):
            self.pi.messages_disabled = ""

    def test_accepts_state_colors_as_a_hash(self):
        state_colors = {"TRUE": "GREEN", "FALSE": "RED"}
        self.pi.state_colors = state_colors
        self.assertEqual(self.pi.state_colors, state_colors)

        self.pi.minimum = 0
        self.pi.maximum = 1
        self.pi.states = {"TRUE": 1, "FALSE": 0}
        config = self.pi.to_config("TELEMETRY", "BIG_ENDIAN")
        self.assertIn("STATE TRUE 1 GREEN", config)
        self.assertIn("STATE FALSE 0 RED", config)

    def test_sets_the_state_colors_to_None(self):
        self.pi.state_colors = None
        self.assertIsNone(self.pi.state_colors)

    def test_complains_about_state_colors_that_arent_hashes(self):
        with self.assertRaisesRegex(
            AttributeError, f"{self.pi.name}: state_colors must be a dict but is a str"
        ):
            self.pi.state_colors = ""

    def test_accepts_limits_as_a_packetitemlimits(self):
        limits = PacketItemLimits()
        limits.values = {
            "DEFAULT": [10, 20, 80, 90, 40, 50],
            "TVAC": [100, 200, 800, 900],
        }
        self.pi.limits = limits
        config = self.pi.to_config("TELEMETRY", "BIG_ENDIAN")
        self.assertIn("LIMITS DEFAULT 1 DISABLED 10 20 80 90 40 50", config)
        self.assertIn("LIMITS TVAC 1 DISABLED 100 200 800 900", config)
        self.pi.limits.enabled = True
        self.pi.limits.persistence_setting = 3
        config = self.pi.to_config("TELEMETRY", "BIG_ENDIAN")
        self.assertIn("LIMITS DEFAULT 3 ENABLED 10 20 80 90 40 50", config)
        self.assertIn("LIMITS TVAC 3 ENABLED 100 200 800 900", config)

    def test_sets_the_limits_to_None(self):
        self.pi.limits = None
        self.assertIsNone(self.pi.limits)

    def test_complains_about_limits_that_arent_packetitemlimits(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"{self.pi.name}: limits must be a PacketItemLimits but is a str",
        ):
            self.pi.limits = ""

    def test_only_allows_a_hash(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"{self.pi.name}: meta must be a dict but is a int",
        ):
            self.pi.meta = 1

    def test_sets_the_meta_hash(self):
        self.pi.meta = {"TYPE": ["float32", "uint8"], "TEST": ["test string"]}
        self.assertEqual(self.pi.meta["TYPE"], ["float32", "uint8"])
        self.assertEqual(self.pi.meta["TEST"], ["test string"])
        config = self.pi.to_config("TELEMETRY", "BIG_ENDIAN")
        self.assertIn("META TYPE float32 uint8", config)
        self.assertIn('META TEST "test string"', config)
        self.pi.meta = None  # Clear the meta hash
        self.assertEqual(len(self.pi.meta), 0)  # Clearing it results in empty hash

    def test_duplicates_the_entire_packet_item(self):
        pi2 = self.pi.clone()
        self.assertIsInstance(pi2, PacketItem)

    def test_converts_to_a_hash(self):
        self.pi.format_string = "%5.1f"
        self.pi.id_value = 10
        self.pi.array_size = 64
        self.pi.states = {"TRUE": 1, "FALSE": 0}
        self.pi.read_conversion = Conversion()
        self.pi.write_conversion = Conversion()
        self.pi.description = "description"
        self.pi.units_full = "Celsius"
        self.pi.units = "C"
        self.pi.default = 0
        self.pi.minimum = 0
        self.pi.maximum = 100
        self.pi.required = True
        self.pi.hazardous = {"TRUE": None, "FALSE": "NO!"}
        self.pi.messages_disabled = {"TRUE": True, "FALSE": None}
        self.pi.state_colors = {"TRUE": "GREEN", "FALSE": "RED"}
        pil = PacketItemLimits()
        pil.enabled = False
        pil.values = {"DEFAULT": [0, 1, 2, 3, 4, 5]}
        pil.state = "RED_LOW"
        r = LimitsResponse()
        pil.response = r
        pil.persistence_setting = 1
        pil.persistence_count = 2
        self.pi.limits = pil

        hash = self.pi.as_json()
        self.assertEqual(hash["name"], "TEST")
        self.assertEqual(hash["bit_offset"], 0)
        self.assertEqual(hash["bit_size"], 32)
        self.assertEqual(hash["data_type"], "UINT")
        self.assertEqual(hash["endianness"], "BIG_ENDIAN")
        self.assertEqual(hash["array_size"], 64)
        self.assertEqual(hash["overflow"], "ERROR")
        self.assertEqual(hash["format_string"], "%5.1f")
        self.assertIsInstance(hash["read_conversion"], dict)
        self.assertIsInstance(hash["write_conversion"], dict)
        self.assertEqual(hash["id_value"], 10)
        true_hash = {"value": 1, "color": "GREEN", "messages_disabled": True}
        false_hash = {"value": 0, "hazardous": "NO!", "color": "RED"}
        self.assertEqual(hash["states"], {"TRUE": true_hash, "FALSE": false_hash})
        self.assertEqual(hash["description"], "description")
        self.assertEqual(hash["units_full"], "Celsius")
        self.assertEqual(hash["units"], "C")
        self.assertEqual(hash["default"], 0)
        # range turns into minimum and maximum
        self.assertEqual(hash["minimum"], 0)
        self.assertEqual(hash["maximum"], 100)
        self.assertTrue(hash["required"])
        self.assertFalse(hash["limits"]["enabled"])
        # State is actually stored in Redis so it doesn't make sense to return via PacketItemLimits
        self.assertIsInstance(hash["limits"]["response"], LimitsResponse)
        self.assertEqual(hash["limits"]["persistence_setting"], 1)
        # limits values are broken out by set and individual values
        self.assertEqual(hash["limits"]["DEFAULT"]["red_low"], 0)
        self.assertEqual(hash["limits"]["DEFAULT"]["yellow_low"], 1)
        self.assertEqual(hash["limits"]["DEFAULT"]["yellow_high"], 2)
        self.assertEqual(hash["limits"]["DEFAULT"]["red_high"], 3)
        self.assertEqual(hash["limits"]["DEFAULT"]["green_low"], 4)
        self.assertEqual(hash["limits"]["DEFAULT"]["green_high"], 5)
        self.assertIsNone(hash.get("meta"))

    def test_creates_empty_packetitem_from_hash(self):
        item = PacketItem.from_json(self.pi.as_json())
        self.assertEqual(item.name, self.pi.name)
        self.assertEqual(item.bit_offset, self.pi.bit_offset)
        self.assertEqual(item.bit_size, self.pi.bit_size)
        self.assertEqual(item.data_type, self.pi.data_type)
        self.assertEqual(item.endianness, self.pi.endianness)
        self.assertEqual(item.array_size, self.pi.array_size)
        self.assertEqual(item.overflow, self.pi.overflow)
        self.assertEqual(item.format_string, self.pi.format_string)
        # conversions don't round trip
        # self.assertEqual(item.read_conversion, self.pi.read_conversion)
        # self.assertEqual(item.write_conversion, self.pi.write_conversion)
        self.assertEqual(item.id_value, self.pi.id_value)
        self.assertEqual(item.states, self.pi.states)
        self.assertEqual(item.description, self.pi.description)
        self.assertEqual(item.units_full, self.pi.units_full)
        self.assertEqual(item.units, self.pi.units)
        self.assertEqual(item.default, self.pi.default)
        self.assertEqual(item.minimum, self.pi.minimum)
        self.assertEqual(item.maximum, self.pi.maximum)
        self.assertEqual(item.required, self.pi.required)
        self.assertEqual(item.state_colors, self.pi.state_colors)
        self.assertEqual(item.hazardous, self.pi.hazardous)
        self.assertEqual(item.messages_disabled, self.pi.messages_disabled)
        self.assertEqual(item.limits.enabled, self.pi.limits.enabled)
        self.assertEqual(
            item.limits.persistence_setting, self.pi.limits.persistence_setting
        )
        self.assertEqual(item.limits.values, self.pi.limits.values)
        self.assertEqual(item.meta, self.pi.meta)

    def test_converts_a_populated_item_to_and_from_json(self):
        self.pi.format_string = "%5.1f"
        self.pi.id_value = 10
        self.pi.states = {"TRUE": 1, "FALSE": 0}
        # self.pi.read_conversion = GenericConversion("value / 2")
        # self.pi.write_conversion = PolynomialConversion(1, 2, 3)
        self.pi.description = "description"
        self.pi.units_full = "Celsius"
        self.pi.units = "C"
        self.pi.default = 0
        self.pi.minimum = 0
        self.pi.maximum = 100
        self.pi.required = True
        self.pi.hazardous = {"TRUE": None, "FALSE": "NO!"}
        self.pi.messages_disabled = {"TRUE": True, "FALSE": None}
        self.pi.state_colors = {"TRUE": "GREEN", "FALSE": "RED"}
        self.pi.limits = PacketItemLimits()
        self.pi.limits.values = {
            "DEFAULT": [10, 20, 80, 90, 40, 50],
            "TVAC": [100, 200, 800, 900],
        }
        item = PacketItem.from_json(self.pi.as_json())
        self.assertEqual(item.name, self.pi.name)
        self.assertEqual(item.bit_offset, self.pi.bit_offset)
        self.assertEqual(item.bit_size, self.pi.bit_size)
        self.assertEqual(item.data_type, self.pi.data_type)
        self.assertEqual(item.endianness, self.pi.endianness)
        self.assertEqual(item.array_size, self.pi.array_size)
        self.assertEqual(item.overflow, self.pi.overflow)
        self.assertEqual(item.format_string, self.pi.format_string)
        # expect(item.read_conversion).to be_a GenericConversion
        # expect(item.write_conversion).to be_a PolynomialConversion
        self.assertEqual(item.id_value, self.pi.id_value)
        self.assertEqual(item.states, self.pi.states)
        self.assertEqual(item.description, self.pi.description)
        self.assertEqual(item.units_full, self.pi.units_full)
        self.assertEqual(item.units, self.pi.units)
        self.assertEqual(item.default, self.pi.default)
        self.assertEqual(item.minimum, self.pi.minimum)
        self.assertEqual(item.maximum, self.pi.maximum)
        self.assertEqual(item.required, self.pi.required)
        self.assertEqual(item.state_colors, self.pi.state_colors)
        self.assertEqual(item.hazardous, self.pi.hazardous)
        self.assertEqual(item.messages_disabled, self.pi.messages_disabled)
        self.assertEqual(item.limits.enabled, self.pi.limits.enabled)
        self.assertEqual(
            item.limits.persistence_setting, self.pi.limits.persistence_setting
        )
        self.assertEqual(item.limits.values, self.pi.limits.values)
        self.assertEqual(item.meta, self.pi.meta)
