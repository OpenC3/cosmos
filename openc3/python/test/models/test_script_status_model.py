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
from datetime import datetime, timezone

from openc3.models.script_status_model import ScriptStatusModel
from openc3.utilities.time import to_nsec_from_epoch
from test.test_helper import *


class TestScriptStatusModel(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)

    def test_sets_updated_at_to_nsec_from_epoch_on_create(self):
        before = to_nsec_from_epoch(datetime.now(timezone.utc))
        model = ScriptStatusModel(name="1000", state="running", scope="DEFAULT")
        model.create()
        after = to_nsec_from_epoch(datetime.now(timezone.utc))

        # updated_at should be an integer number of nanoseconds since the epoch,
        # not the previous ISO 8601 string representation
        self.assertIsInstance(model.updated_at, int)
        self.assertGreaterEqual(model.updated_at, before)
        self.assertLessEqual(model.updated_at, after)

    def test_persists_updated_at_as_integer_in_as_json(self):
        model = ScriptStatusModel(name="1001", state="running", scope="DEFAULT")
        model.create()
        retrieved = ScriptStatusModel.get(name="1001", scope="DEFAULT", type="running")
        self.assertIsNotNone(retrieved)
        self.assertIsInstance(retrieved["updated_at"], int)
        self.assertEqual(retrieved["updated_at"], model.updated_at)
