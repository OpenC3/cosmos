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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.api.settings_api import *


class TestSettingsApi(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_sets_a_value_in_the_stash(self):
        save_setting("key", "val", local_mode=False)
        self.assertEqual(get_setting("key"), "val")

    def test_sets_an_array_in_the_stash(self):
        data = [1, 2, [3, 4]]
        save_setting("key", data, local_mode=False)
        self.assertEqual(get_setting("key"), data)

    def test_sets_a_hash_in_the_stash(self):
        data = {"key": "val", "more": 1}
        save_setting("key", data, local_mode=False)
        self.assertEqual(get_setting("key"), ({"key": "val", "more": 1}))

    def test_get_returns_none_if_the_value_doesnt_exist(self):
        self.assertIsNone(get_setting("nope"))

    def test_list_returns_empty_array_with_no_keys(self):
        self.assertEqual(list_settings(), ([]))

    def test_returns_all_the_setting_keys_as_an_array(self):
        save_setting("key1", "val", local_mode=False)
        save_setting("key2", "val", local_mode=False)
        save_setting("key3", "val", local_mode=False)
        self.assertEqual(list_settings(), ["key1", "key2", "key3"])

    def test_get_all_returns_empty_hash_with_no_keys(self):
        self.assertEqual(get_all_settings(), ({}))

    def test_returns_all_setting_values_as_a_hash(self):
        save_setting("key1", 1, local_mode=False)
        save_setting("key2", 2, local_mode=False)
        save_setting("key3", 3, local_mode=False)
        result = {"key1": 1, "key2": 2, "key3": 3}
        self.assertEqual(get_all_settings().keys(), result.keys())
        self.assertEqual(get_all_settings()["key1"]["name"], "key1")
        self.assertEqual(get_all_settings()["key1"]["data"], 1)
        self.assertEqual(get_all_settings()["key2"]["name"], "key2")
        self.assertEqual(get_all_settings()["key2"]["data"], 2)
        self.assertEqual(get_all_settings()["key3"]["name"], "key3")
        self.assertEqual(get_all_settings()["key3"]["data"], 3)

    def test_get_returns_empty_array_with_no_keys(self):
        self.assertEqual(get_settings(), ([]))

    def test_returns_specified_settings_as_an_array_of_results(self):
        save_setting("key1", "string", local_mode=False)
        save_setting("key2", 2, local_mode=False)
        save_setting("key3", 3, local_mode=False)
        self.assertEqual(get_settings("key1", "key3"), ["string", 3])
