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

from openc3.models.secret_model import SecretModel
from test.test_helper import *


class TestSecretModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_creates_new(self):
        model = SecretModel(name="secret", value="tacit", scope="DEFAULT")
        self.assertIsInstance(model, SecretModel)

    def test_self_get(self):
        name = SecretModel.get(name="secret", scope="DEFAULT")
        self.assertIsNone(name)  # eq('secret')

    def test_self_all(self):
        all_secrets = SecretModel.all(scope="DEFAULT")
        self.assertEqual(all_secrets, {})  # eq('secret')

    def test_self_names(self):
        names = SecretModel.names(scope="DEFAULT")
        self.assertEqual(names, [])  # eq('secret')

    def test_as_json(self):
        model = SecretModel(name="secreter", value="silent", scope="DEFAULT")
        self.assertEqual(model.as_json()["name"], ("secreter"))
