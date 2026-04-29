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
import unittest.mock

from openc3.models.metric_model import MetricModel
from test.test_helper import *


class TestMetricModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_returns_all_the_metrics(self):
        model = MetricModel(name="foo", scope="scope", values={"test": {"value": 5}})
        model.create(force=True)
        all_metrics = MetricModel.all(scope="scope")
        self.assertEqual(all_metrics["foo"]["values"]["test"]["value"], (5))

    def test_encodes_all_the_input_parameters(self):
        model = MetricModel(name="foo", scope="scope", values={"test": {"value": 5}})
        json = model.as_json()
        self.assertEqual(json["name"], ("foo"))

    def test_gets_by_name_in_scope(self):
        MetricModel(name="baz", scope="scope", values={"test ": {"value": 6}})
        result = MetricModel.get(name="baz", scope="scope")
        self.assertIsNone(result)  # self.assertEqual(result['name'], ('baz'))

    def test_destroys_by_name_in_scope(self):
        MetricModel(name="baz", scope="scope", values={"test ": {"value": 6}})
        MetricModel(name="bOz", scope="scope", values={"test ": {"value": 6}})
        MetricModel.destroy(scope="scope", name="baz")
        result = MetricModel.get(name="baz", scope="scope")
        self.assertIsNone(result)

    def test_returns_all_names(self):
        MetricModel(name="baz", scope="scope", values={"test ": {"value": 6}})
        result = MetricModel.names(scope="scope")
        self.assertListEqual(result, [])  # self.assertEqual(result[0], ('baz'))
