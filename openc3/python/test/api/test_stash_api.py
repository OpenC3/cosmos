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
from openc3.api.stash_api import *


class TestStashApi(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_sets_a_value_in_the_stash(self):
        stash_set("key", "val")
        self.assertEqual(stash_get("key"), "val")
        # Override with binary data
        stash_set("key", "\xDE\xAD\xBE\xEF")
        self.assertEqual(stash_get("key"), "\xDE\xAD\xBE\xEF")

    def test_sets_an_array_in_the_stash(self):
        data = [1, 2, [3, 4]]
        stash_set("key", data)
        self.assertEqual(stash_get("key"), data)

    def test_sets_a_hash_in_the_stash(self):
        data = {"key": "val", "more": 1}
        stash_set("key", data)
        self.assertEqual(stash_get("key"), ({"key": "val", "more": 1}))

    def test_returns_None_if_the_value_doesnt_exist(self):
        self.assertIsNone(stash_get("nope"))

    def test_deletes_an_existing_key(self):
        stash_set("key", "val")
        stash_delete("key")
        self.assertIsNone(stash_get("key"))

    def test_ignores_keys_that_do_not_exist(self):
        stash_delete("nope")

    def test_returns_empty_array_with_no_keys(self):
        self.assertEqual(stash_keys(), ([]))

    def test_returns_all_the_stash_keys_as_an_array(self):
        stash_set("key1", "val")
        stash_set("key2", "val")
        stash_set("key3", "val")
        self.assertEqual(stash_keys(), ["key1", "key2", "key3"])

    def test_returns_empty_hash_with_no_keys(self):
        self.assertEqual(stash_all(), ({}))

    def test_returns_all_stash_values_as_a_hash(self):
        stash_set("key1", 1)
        stash_set("key2", 2)
        stash_set("key3", 3)
        result = {"key1": 1, "key2": 2, "key3": 3}
        self.assertEqual(stash_all(), result)
