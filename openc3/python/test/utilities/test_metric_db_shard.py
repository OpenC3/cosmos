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

import json
import unittest
from unittest.mock import patch

from openc3.utilities.metric import Metric
from openc3.utilities.store import Store
from test.test_helper import mock_redis_db_shards


class TestMetricDbShard(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)
        # Don't start the update thread, tests run a single pass of it
        for name, value in (("update_thread", "Test"), ("instances", []), ("update_generators", [])):
            patcher = patch.object(Metric, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_uses_the_given_db_shard(self):
        self.assertEqual(Metric("DEFAULT__DECOM__INST", "DEFAULT", db_shard=2).db_shard, 2)

    def test_looks_up_the_db_shard_of_the_microservice_on_db_shard_0(self):
        Store.instance(db_shard=0).hset(
            "openc3_microservices",
            "DEFAULT__DECOM__INST",
            json.dumps({"name": "DEFAULT__DECOM__INST", "db_shard": "2"}),
        )
        self.assertEqual(Metric("DEFAULT__DECOM__INST", "DEFAULT").db_shard, 2)

    def test_uses_db_shard_0_for_a_microservice_which_doesnt_exist_or_cant_be_looked_up(self):
        self.assertEqual(Metric("DEFAULT__DECOM__MISSING", "DEFAULT").db_shard, 0)
        with patch.object(Store, "hget", side_effect=RuntimeError("down")):
            self.assertEqual(Metric("DEFAULT__DECOM__INST", "DEFAULT").db_shard, 0)

    def test_sets_the_metrics_with_the_db_shard_of_each_microservice(self):
        metric1 = Metric("DEFAULT__DECOM__INST", "DEFAULT", db_shard=1)
        metric1.set("count", 1)
        metric2 = Metric("OTHER__DECOM__INST2", "OTHER", db_shard=2)
        metric2.set("count", 2)
        # No values so nothing is set
        Metric("DEFAULT__DECOM__EMPTY", "DEFAULT", db_shard=3)
        with (
            patch("openc3.utilities.metric.MetricModel.set") as metric_set,
            patch("openc3.utilities.metric.Sleeper.sleep", return_value=True),
        ):
            metric1.update_thread_body()
        sets = [
            (call[0][0]["name"], call[0][0]["db_shard"], call.kwargs["scope"]) for call in metric_set.call_args_list
        ]
        self.assertEqual(sets, [("DEFAULT__DECOM__INST", 1, "DEFAULT"), ("OTHER__DECOM__INST2", 2, "OTHER")])
