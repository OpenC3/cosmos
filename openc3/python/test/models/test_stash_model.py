# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
import unittest.mock

from openc3.models.stash_model import StashModel
from test.test_helper import *


class TestStashModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_creates_new(self):
        model = StashModel(name="sm", value="stash", scope="DEFAULT")
        self.assertIsInstance(model, StashModel)

    def test_self_get(self):
        name = StashModel.get(name="sm", scope="DEFAULT")
        self.assertIsNone(name)  # eq('sm')

    def test_self_all(self):
        all_stash = StashModel.all(scope="DEFAULT")
        self.assertEqual(all_stash, {})  # eq('sm')

    def test_self_names(self):
        names = StashModel.names(scope="DEFAULT")
        self.assertEqual(names, [])  # eq('sm')

    def test_as_json(self):
        model = StashModel(name="sm", value="stashef", scope="DEFAULT")
        self.assertEqual(model.as_json()["name"], ("sm"))
