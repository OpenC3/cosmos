# Copyright 2026 OpenC3, Inc.
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

import os
import sys
import threading
import time
import unittest
from unittest.mock import Mock, patch

from openc3.microservices.decom_microservice import DecomMicroservice
from openc3.microservices.multi_microservice import MultiMicroservice
from openc3.microservices.tsdb_microservice import TsdbMicroservice
from openc3.models.microservice_model import MicroserviceModel
from openc3.utilities.logger import Logger
from openc3.utilities.thread_manager import ThreadManager
from test.test_helper import mock_redis


NAME = "DEFAULT__PYMULTIGROUP__HK"
WORK_DIR = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "..", "openc3", "microservices"))


class TestMultiMicroservice(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        patcher = patch("openc3.microservices.multi_microservice.System")
        self.system = patcher.start()
        self.addCleanup(patcher.stop)

        MicroserviceModel(NAME, scope="DEFAULT").create()
        for name, target_names, file, enabled, parent in (
            ("DEFAULT__TSDB__B", None, "tsdb_microservice.py", True, NAME),
            ("DEFAULT__DECOM__A", ["A"], "decom_microservice.py", True, NAME),
            ("DEFAULT__TSDB__A", None, "tsdb_microservice.py", True, NAME),
            ("DEFAULT__DECOM__C", ["C"], "decom_microservice.py", False, NAME),
            ("DEFAULT__DECOM__D", ["D"], "decom_microservice.py", True, "DEFAULT__MULTI__D"),
        ):
            MicroserviceModel(
                name,
                cmd=["python", file, name],
                work_dir=WORK_DIR,
                target_names=target_names or [],
                parent=parent,
                enabled=enabled,
                scope="DEFAULT",
            ).create()
        with patch("openc3.microservices.microservice.System"):
            self.mm = MultiMicroservice(NAME)

    def tearDown(self):
        self.mm.shutdown()

    def test_runs_the_microservices_given_on_the_command_line(self):
        with patch.object(sys, "argv", ["multi_microservice.py", "DEFAULT__DECOM__D", "DEFAULT__TSDB__A"]):
            self.assertEqual([m.name for m in self.mm.child_models()], ["DEFAULT__DECOM__D", "DEFAULT__TSDB__A"])

    def test_otherwise_runs_the_enabled_microservices_that_name_it_as_their_parent(self):
        with patch.object(sys, "argv", ["multi_microservice.py"]):
            self.assertEqual(
                [m.name for m in self.mm.child_models()],
                ["DEFAULT__DECOM__A", "DEFAULT__TSDB__A", "DEFAULT__TSDB__B"],
            )

    def test_loads_cosmos_microservices_by_module(self):
        model = MicroserviceModel.get_model(name="DEFAULT__TSDB__A", scope="DEFAULT")
        self.assertIs(MultiMicroservice.load_class(model), TsdbMicroservice)
        model = MicroserviceModel.get_model(name="DEFAULT__DECOM__A", scope="DEFAULT")
        self.assertIs(MultiMicroservice.load_class(model), DecomMicroservice)

    def test_raises_without_a_python_file(self):
        model = MicroserviceModel("DEFAULT__USER__X", cmd=["ruby", "x.rb"], scope="DEFAULT")
        with self.assertRaisesRegex(RuntimeError, "Could not determine class filename"):
            MultiMicroservice.load_class(model)

    def test_sets_up_system_for_every_child_before_starting_them(self):
        started = []

        class Child:
            def __init__(self, name):
                # System must already be set up when a child is created
                started.append((name, self_system.setup_targets.called))

            @classmethod
            def class_run_body(cls, microservice):
                pass

        self_system = self.system
        manager = Mock()
        with (
            patch.object(sys, "argv", ["multi_microservice.py"]),
            patch.object(MultiMicroservice, "load_class", return_value=Child),
            patch.object(ThreadManager, "instance", return_value=manager),
        ):
            self.mm.run()
        self.system.setup_targets.assert_called_once()
        self.assertEqual(self.system.setup_targets.call_args.args[0], ["A"])
        self.assertEqual(
            started,
            [("DEFAULT__DECOM__A", True), ("DEFAULT__TSDB__A", True), ("DEFAULT__TSDB__B", True)],
        )
        self.assertEqual(manager.register.call_count, 3)
        manager.monitor.assert_called_once()

    def test_logs_shared_code_under_its_own_name(self):
        class Child:
            def __init__(self, name):
                # What each real child does in Microservice.__init__
                Logger.microservice_name = name

            @classmethod
            def class_run_body(cls, microservice):
                pass

        with (
            patch.object(sys, "argv", ["multi_microservice.py"]),
            patch.object(MultiMicroservice, "load_class", return_value=Child),
            patch.object(ThreadManager, "instance", return_value=Mock()),
        ):
            self.mm.run()
        self.assertEqual(Logger.microservice_name, NAME)

    def test_sizes_the_redis_connection_pools_for_its_children(self):
        models = [MicroserviceModel("DEFAULT__DECOM__X", db_shard=1, scope="DEFAULT")] * 150
        stores = {}

        def instance(cls, db_shard=0):
            return stores.setdefault((cls, db_shard), Mock())

        with (
            patch("openc3.microservices.multi_microservice.Store") as store,
            patch("openc3.microservices.multi_microservice.EphemeralStore") as ephemeral,
        ):
            store.instance.side_effect = lambda db_shard=0: instance("Store", db_shard)
            ephemeral.instance.side_effect = lambda db_shard=0: instance("EphemeralStore", db_shard)
            MultiMicroservice.ensure_pool_sizes(models)
        # Two connections per child on top of the default, on shard 0 and every child's shard
        self.assertEqual(sorted(stores.keys()), sorted((c, s) for c in ("Store", "EphemeralStore") for s in (0, 1)))
        for mock in stores.values():
            mock.ensure_pool_size.assert_called_once_with(400)

    def test_waits_for_a_shutdown_if_it_has_no_children(self):
        with patch("openc3.microservices.microservice.System"):
            empty = MultiMicroservice("DEFAULT__PYMULTIGROUP__EMPTY")
        with patch.object(sys, "argv", ["multi_microservice.py"]):
            thread = threading.Thread(target=empty.run)
            thread.start()
            time.sleep(0.1)
            self.assertTrue(thread.is_alive())
            empty.shutdown()
            # Shutdown also stops metrics, which can take a moment on a busy machine
            thread.join(10)
        self.assertFalse(thread.is_alive())
