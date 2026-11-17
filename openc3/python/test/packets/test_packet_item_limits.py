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

from openc3.packets.packet_item_limits import PacketItemLimits


class TestPacketItemLimits(unittest.TestCase):
    def setUp(self):
        self.limits = PacketItemLimits()

    def test_sets_the_change_type(self):
        for change_type in PacketItemLimits.CHANGE_TYPES:
            self.limits.change_type = change_type
            self.assertEqual(self.limits.change_type, change_type)
        self.limits.change_type = None
        self.assertIsNone(self.limits.change_type)

    def test_complains_about_bad_change_type(self):
        with self.assertRaisesRegex(ValueError, "change_type must be one of .* but is DELTA"):
            self.limits.change_type = "DELTA"

    def test_sets_the_change_color(self):
        for change_color in PacketItemLimits.CHANGE_COLORS:
            self.limits.change_color = change_color
            self.assertEqual(self.limits.change_color, change_color)
        self.limits.change_color = None
        self.assertIsNone(self.limits.change_color)

    def test_complains_about_bad_change_color(self):
        with self.assertRaisesRegex(ValueError, "change_color must be one of .* but is GREEN"):
            self.limits.change_color = "GREEN"

    def test_sets_the_sequence_step(self):
        self.assertEqual(self.limits.sequence_step, 1)
        self.limits.sequence_step = -2
        self.assertEqual(self.limits.sequence_step, -2)

    def test_complains_about_bad_sequence_step(self):
        for sequence_step in [0, 1.5, "1", None, True]:
            with self.assertRaisesRegex(ValueError, "sequence_step must be a non-zero integer"):
                self.limits.sequence_step = sequence_step

    def test_as_json_without_change_limits(self):
        json = self.limits.as_json()
        self.assertNotIn("change_type", json)
        self.assertNotIn("change_color", json)
        self.assertNotIn("sequence_step", json)

    def test_as_json_with_sequence_change_limits(self):
        self.limits.change_type = "SEQUENCE"
        self.limits.change_color = "RED"
        self.limits.sequence_step = 2
        json = self.limits.as_json()
        self.assertEqual(json["change_type"], "SEQUENCE")
        self.assertEqual(json["change_color"], "RED")
        self.assertEqual(json["sequence_step"], 2)

    def test_as_json_with_non_sequence_change_limits(self):
        self.limits.change_type = "STATIC"
        self.limits.change_color = "YELLOW"
        json = self.limits.as_json()
        self.assertEqual(json["change_type"], "STATIC")
        self.assertEqual(json["change_color"], "YELLOW")
        self.assertNotIn("sequence_step", json)
