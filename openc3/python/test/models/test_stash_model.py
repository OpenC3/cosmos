
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

import time
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.models.stash_model import StashModel
from openc3.conversions.generic_conversion import GenericConversion


class TestStashModel(unittest.TestCase):
    def setUp(self):
      mock_redis(self)
      setup_system()

    def test_creates_new(self):
        model = StashModel(name= 'sm', value= 'stash', scope= 'DEFAULT')
        self.assertIsInstance(model, StashModel)

    def test_self_get(self):
        name = StashModel.get(name= 'sm', scope= 'DEFAULT')
        self.assertIsNone(name) # eq('sm')

    def test_self_all(self):
        all_stash = StashModel.all(scope= 'DEFAULT')
        self.assertEqual(all_stash, {}) # eq('sm')

    def test_self_names(self):
        names = StashModel.names(scope= 'DEFAULT')
        self.assertEqual(names, []) # eq('sm')

    def test_as_json(self):
        model = StashModel(name= 'sm', value= 'stashef', scope= 'DEFAULT')
        self.assertEqual(model.as_json()['name'], ('sm'))
