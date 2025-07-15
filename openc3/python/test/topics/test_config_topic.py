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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.topics.config_topic import ConfigTopic


class TestConfigTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_write_requires_kind_type_name_keys(self):
        """Test that write method requires kind, type, and name keys"""
        # Missing kind key
        with self.assertRaisesRegex(ValueError, "ConfigTopic error"):
            ConfigTopic.write({'type': 'target', 'name': 'INST', 'plugin': 'PLUGIN'}, scope='DEFAULT')

        # Missing type key
        with self.assertRaisesRegex(ValueError, "ConfigTopic error"):
            ConfigTopic.write({'kind': 'created', 'name': 'INST', 'plugin': 'PLUGIN'}, scope='DEFAULT')

        # Missing name key
        with self.assertRaisesRegex(ValueError, "ConfigTopic error"):
            ConfigTopic.write({'kind': 'created', 'type': 'target', 'plugin': 'PLUGIN'}, scope='DEFAULT')

    def test_write_requires_kind_to_be_created_or_deleted(self):
        """Test that write method requires kind to be 'created' or 'deleted'"""
        with self.assertRaisesRegex(ValueError, "ConfigTopic error"):
            ConfigTopic.write({'kind': 'unknown', 'type': 'target', 'name': 'INST', 'plugin': 'PLUGIN'}, scope='DEFAULT')

    def test_write_succeeds_with_valid_data(self):
        """Test that write method succeeds with valid data"""
        # Should not raise any exception
        ConfigTopic.write({'kind': 'created', 'type': 'target', 'name': 'INST', 'plugin': 'PLUGIN'}, scope='DEFAULT')
        ConfigTopic.write({'kind': 'deleted', 'type': 'target', 'name': 'INST', 'plugin': 'PLUGIN'}, scope='DEFAULT')

    def test_read_from_offset(self):
        """Test reading from a specific offset"""
        ConfigTopic.write({'kind': 'created', 'type': 'target', 'name': 'INST', 'plugin': 'PLUGIN'}, scope='DEFAULT')
        ConfigTopic.write({'kind': 'deleted', 'type': 'target', 'name': 'INST', 'plugin': 'PLUGIN'}, scope='DEFAULT')

        config = ConfigTopic.read(offset=0, scope='DEFAULT')  # read all

        # Check that we have results
        self.assertEqual(config[0][1][b'kind'], b'created')
        self.assertEqual(config[0][1][b'type'], b'target')
        self.assertEqual(config[0][1][b'name'], b'INST')
        self.assertEqual(config[0][1][b'plugin'], b'PLUGIN')
        self.assertEqual(config[1][1][b'kind'], b'deleted')
        self.assertEqual(config[1][1][b'type'], b'target')
        self.assertEqual(config[1][1][b'name'], b'INST')
        self.assertEqual(config[1][1][b'plugin'], b'PLUGIN')

    def test_read_latest(self):
        """Test reading the latest entry"""
        ConfigTopic.write({'kind': 'created', 'type': 'target', 'name': 'INST', 'plugin': 'PLUGIN'}, scope='DEFAULT')
        ConfigTopic.write({'kind': 'deleted', 'type': 'target', 'name': 'INST', 'plugin': 'PLUGIN'}, scope='DEFAULT')

        config = ConfigTopic.read(scope='DEFAULT')  # read latest

        self.assertEqual(config[0][1][b'kind'], b'deleted')
        self.assertEqual(config[0][1][b'type'], b'target')
        self.assertEqual(config[0][1][b'name'], b'INST')
        self.assertEqual(config[0][1][b'plugin'], b'PLUGIN')

    def test_read_returns_empty_array_when_no_data(self):
        """Test that read returns empty array when no data exists"""
        config = ConfigTopic.read(scope='DEFAULT')
        self.assertEqual(config, [])

        config = ConfigTopic.read(offset=0, scope='DEFAULT')
        self.assertEqual(config, [])

    def test_read_with_count_parameter(self):
        """Test reading with count parameter"""
        # Write multiple entries
        for i in range(5):
            ConfigTopic.write({'kind': 'created', 'type': 'target', 'name': f'INST{i}', 'plugin': 'PLUGIN'}, scope='DEFAULT')

        config = ConfigTopic.read(offset=0, count=3, scope='DEFAULT')

        # Should return at most 3 entries
        self.assertLessEqual(len(config), 3)