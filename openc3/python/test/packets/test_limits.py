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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import tempfile
import unittest
from test.test_helper import mock_redis, setup_system
from openc3.system.system import System
from openc3.packets.limits import Limits
from openc3.packets.packet_config import PacketConfig
from openc3.packets.telemetry import Telemetry

class TestLimits(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('# This is a comment\n')
        tf.write('#\n')
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "TGT1 PKT1 Description"\n')
        tf.write('  APPEND_ID_ITEM item1 8 UINT 1 "Item1"\n')
        tf.write('    LIMITS DEFAULT 1 ENABLED 1 2 4 5\n')
        tf.write('    LIMITS TVAC 1 ENABLED 6 7 12 13 9 10\n')
        tf.write('  APPEND_ITEM item2 8 UINT "Item2"\n')
        tf.write('    LIMITS DEFAULT 1 ENABLED 1 2 4 5\n')
        tf.write('    LIMITS TVAC 1 ENABLED 6 7 12 13 9 10\n')
        tf.write('  APPEND_ITEM item3 8 UINT "Item3"\n')
        tf.write('    LIMITS DEFAULT 1 ENABLED 1 2 4 5\n')
        tf.write('    LIMITS TVAC 1 ENABLED 6 7 12 13 9 10\n')
        tf.write('  APPEND_ITEM item4 8 UINT "Item4"\n')
        tf.write('    LIMITS DEFAULT 1 ENABLED 1 2 4 5\n')
        tf.write('    LIMITS TVAC 1 ENABLED 6 7 12 13 9 10\n')
        tf.write('  APPEND_ITEM item5 8 UINT "Item5"\n')
        tf.write('TELEMETRY tgt1 pkt2 LITTLE_ENDIAN "TGT1 PKT2 Description"\n')
        tf.write('  APPEND_ID_ITEM item1 8 UINT 2 "Item1"\n')
        tf.write('    LIMITS DEFAULT 1 ENABLED 1 2 4 5\n')
        tf.write('  APPEND_ITEM item2 8 UINT "Item2"\n')
        tf.write('TELEMETRY tgt2 pkt1 LITTLE_ENDIAN "TGT2 PKT1 Description"\n')
        tf.write('  APPEND_ID_ITEM item1 8 UINT 3 "Item1"\n')
        tf.write('  APPEND_ITEM item2 8 UINT "Item2"\n')
        tf.write('LIMITS_GROUP GROUP1\n')
        tf.write('  LIMITS_GROUP_ITEM TGT1 PKT1 ITEM1\n')
        tf.write('  LIMITS_GROUP_ITEM TGT1 PKT1 ITEM2\n')
        tf.write('LIMITS_GROUP GROUP2\n')
        tf.write('  LIMITS_GROUP_ITEM TGT1 PKT1 ITEM1\n')
        tf.write('  LIMITS_GROUP_ITEM TGT1 PKT1 ITEM2\n')
        tf.seek(0)

        # Verify initially that everything is empty
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        self.tlm = Telemetry(pc, System)
        self.limits = Limits(pc, System)
        tf.close()

    def test_has_no_warnings(self):
        self.assertEqual(Limits(PacketConfig(), System).warnings(), [])

    def test_returns_the_defined_limits_set(self):
        sets = self.limits.sets()
        sets.sort()
        self.assertEqual(sets,  ['DEFAULT', 'TVAC'])

    def test_returns_the_limits_groups(self):
        self.assertEqual(list(self.limits.groups().keys()), ['GROUP1', 'GROUP2'])

    def test_sets_the_underlying_configuration(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('\n')
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        self.assertIn('TVAC', self.limits.sets())
        self.assertEqual(list(self.limits.groups().keys()), ['GROUP1', 'GROUP2'])
        self.limits.config = pc
        self.assertEqual(self.limits.sets(),  ['DEFAULT'])
        self.assertEqual(self.limits.groups(), ({}))
        tf.close()

    def test_enabled_complains_about_non_existent_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry target 'TGTX' does not exist"):
            self.limits.enabled("TGTX", "PKT1", "ITEM1")

    def test_enabled_complains_about_non_existent_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry packet 'TGT1 PKTX' does not exist"):
            self.limits.enabled("TGT1", "PKTX", "ITEM1")

    def test_enabled_complains_about_non_existent_items(self):
        with self.assertRaisesRegex(RuntimeError, "Packet item 'TGT1 PKT1 ITEMX' does not exist"):
            self.limits.enabled("TGT1", "PKT1", "ITEMX")

    def test_returns_whether_limits_are_enable_for_an_item(self):
        pkt = self.tlm.packet("TGT1", "PKT1")
        self.assertFalse(self.limits.enabled("TGT1", "PKT1", "ITEM5"))
        pkt.enable_limits("ITEM5")
        self.assertTrue(self.limits.enabled("TGT1", "PKT1", "ITEM5"))

    def test_enable_complains_about_non_existent_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry target 'TGTX' does not exist"):
             self.limits.enable("TGTX", "PKT1", "ITEM1")

    def test_enable_complains_about_non_existent_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry packet 'TGT1 PKTX' does not exist"):
             self.limits.enable("TGT1", "PKTX", "ITEM1")

    def test_enable_complains_about_non_existent_items(self):
        with self.assertRaisesRegex(RuntimeError, "Packet item 'TGT1 PKT1 ITEMX' does not exist"):
             self.limits.enable("TGT1", "PKT1", "ITEMX")

    def test_enables_limits_for_an_item(self):
        self.tlm.packet("TGT1", "PKT1")
        self.assertFalse(self.limits.enabled("TGT1", "PKT1", "ITEM5"))
        self.limits.enable("TGT1", "PKT1", "ITEM5")
        self.assertTrue(self.limits.enabled("TGT1", "PKT1", "ITEM5"))

    def test_disable_complains_about_non_existent_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry target 'TGTX' does not exist"):
             self.limits.disable("TGTX", "PKT1", "ITEM1")

    def test_disable_complains_about_non_existent_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry packet 'TGT1 PKTX' does not exist"):
             self.limits.disable("TGT1", "PKTX", "ITEM1")

    def test_disable_complains_about_non_existent_items(self):
        with self.assertRaisesRegex(RuntimeError, "Packet item 'TGT1 PKT1 ITEMX' does not exist"):
             self.limits.disable("TGT1", "PKT1", "ITEMX")

    def test_disables_limits_for_an_item(self):
        self.tlm.packet("TGT1", "PKT1")
        self.limits.enable("TGT1", "PKT1", "ITEM1")
        self.assertTrue(self.limits.enabled("TGT1", "PKT1", "ITEM1"))
        self.limits.disable("TGT1", "PKT1", "ITEM1")
        self.assertFalse(self.limits.enabled("TGT1", "PKT1", "ITEM1"))

    def test_gets_the_limits_for_an_item_with_limits(self):
        self.assertEqual(self.limits.get("TGT1", "PKT1", "ITEM1"),  ['DEFAULT', 1, True, 1.0, 2.0, 4.0, 5.0, None, None])

    def test_handles_an_item_without_limits(self):
        self.assertEqual(self.limits.get("TGT1", "PKT1", "ITEM5"),  [None, None, None, None, None, None, None, None, None])

    def test_supports_a_specified_limits_set(self):
        self.assertEqual(self.limits.get("TGT1", "PKT1", "ITEM1", 'TVAC'),  ['TVAC', 1, True, 6.0, 7.0, 12.0, 13.0, 9.0, 10.0])

    def test_handles_an_item_without_limits_for_the_given_limits_set(self):
        self.assertEqual(self.limits.get("TGT1", "PKT2", "ITEM1", 'TVAC'),  [None, None, None, None, None, None, None, None, None])

    def test_sets_limits_for_an_item(self):
        self.assertEqual(self.limits.set("TGT1", "PKT1", "ITEM5", 1, 2, 3, 4, None, None, 'DEFAULT'),  ['DEFAULT', 1, True, 1.0, 2.0, 3.0, 4.0, None, None])

    def test_enforces_setting_default_limits_first(self):
        with self.assertRaisesRegex(RuntimeError, "DEFAULT limits must be defined for TGT1 PKT1 ITEM5 before setting limits set CUSTOM"):
             self.limits.set("TGT1", "PKT1", "ITEM5", 1, 2, 3, 4)
        self.assertEqual(self.limits.set("TGT1", "PKT1", "ITEM5", 5, 6, 7, 8, None, None, 'DEFAULT'),  ['DEFAULT', 1, True, 5.0, 6.0, 7.0, 8.0, None, None])
        self.assertEqual(self.limits.set("TGT1", "PKT1", "ITEM5", 1, 2, 3, 4),  ['CUSTOM', 1, True, 1.0, 2.0, 3.0, 4.0, None, None])

    def test_allows_setting_other_limits_sets(self):
        self.assertEqual(self.limits.set("TGT1", "PKT1", "ITEM1", 1, 2, 3, 4, None, None, 'TVAC'),  ['TVAC', 1, True, 1.0, 2.0, 3.0, 4.0, None, None])

    def test_handles_green_limits(self):
        self.assertEqual(self.limits.set("TGT1", "PKT1", "ITEM1", 1, 2, 5, 6, 3, 4, None),  ['DEFAULT', 1, True, 1.0, 2.0, 5.0, 6.0, 3.0, 4.0])
