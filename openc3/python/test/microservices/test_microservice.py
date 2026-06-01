# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
import unittest
from unittest.mock import *

from openc3.microservices.microservice import Microservice
from openc3.models.microservice_model import MicroserviceModel
from openc3.utilities.bucket import Bucket
from test.test_helper import *


class TestMicroservice(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)

    def test_expects_scope__type__name_parameter_as_env(self):
        # These exceptions all get caught and logged now
        with self.assertRaisesRegex(RuntimeError, "Microservice must be named"):
            Microservice.class_run()
        os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT"
        with self.assertRaisesRegex(RuntimeError, "Name DEFAULT doesn't match convention"):
            Microservice.class_run()
        os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT_TYPE_NAME"
        with self.assertRaisesRegex(RuntimeError, "Name DEFAULT_TYPE_NAME doesn't match convention"):
            Microservice.class_run()
        os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT__TYPE__NAME"
        Microservice.class_run()
        time.sleep(0.1)

    def test_logs_message_when_run_method_returns_cleanly(self):
        from openc3.utilities.logger import Logger

        os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT__TYPE__NAME"
        with patch.object(Logger.instance(), "info") as mock_logger_info:
            Microservice.class_run()
            time.sleep(0.1)
            # Check that Logger.info was called with the expected message
            mock_logger_info.assert_any_call(
                "Microservice DEFAULT__TYPE__NAME run method returned cleanly and will now shutdown."
            )

    def test_retries_transient_bucket_failures_on_startup(self):
        os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT__TYPE__NAME"
        config = {
            "topics": [],
            "plugin": None,
            "secrets": [],
            "cmd": [],
            "target_names": [],
            "work_dir": None,
        }
        self.list_calls = 0

        def list_objects(*args, **kwargs):
            self.list_calls += 1
            if self.list_calls < 3:
                raise RuntimeError("connection timed out")
            return []  # Succeed on the third attempt with no files

        client = Mock()
        client.list_objects.side_effect = list_objects
        with (
            patch.object(MicroserviceModel, "get", return_value=config),
            patch.object(Bucket, "get_client", return_value=client),
            patch("openc3.microservices.microservice.atexit.register"),
            patch("openc3.microservices.microservice.time.sleep"),
        ):
            Microservice("DEFAULT__TYPE__NAME", is_plugin=True)
        self.assertEqual(self.list_calls, 3)

    def test_raises_if_bucket_unreachable_past_startup_timeout(self):
        os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT__TYPE__NAME"
        os.environ["OPENC3_MICROSERVICE_STARTUP_BUCKET_TIMEOUT"] = "0"
        config = {
            "topics": [],
            "plugin": None,
            "secrets": [],
            "cmd": [],
            "target_names": [],
            "work_dir": None,
        }
        client = Mock()
        client.list_objects.side_effect = RuntimeError("connection refused")
        try:
            with (
                patch.object(MicroserviceModel, "get", return_value=config),
                patch.object(Bucket, "get_client", return_value=client),
                patch("openc3.microservices.microservice.atexit.register"),
                self.assertRaisesRegex(RuntimeError, "connection refused"),
            ):
                Microservice("DEFAULT__TYPE__NAME", is_plugin=True)
        finally:
            del os.environ["OPENC3_MICROSERVICE_STARTUP_BUCKET_TIMEOUT"]
