# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import signal
import subprocess
import sys
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

    def test_as_json_supports_custom_dict(self):
        microservice = Microservice("DEFAULT__TYPE__CUSTOM")
        microservice.custom = {"processed": 100, "errors": 2}
        self.assertEqual(microservice.as_json()["custom"], {"processed": 100, "errors": 2})
        microservice.shutdown()
        time.sleep(0.1)

    def test_as_json_supports_custom_object_with_as_json(self):
        class CustomStatus:
            def as_json(self):
                return {"processed": 100}

        microservice = Microservice("DEFAULT__TYPE__CUSTOM")
        microservice.custom = CustomStatus()
        self.assertEqual(microservice.as_json()["custom"], {"processed": 100})
        microservice.shutdown()
        time.sleep(0.1)

    def test_as_json_supports_custom_object_with_non_callable_as_json(self):
        class CustomStatus:
            as_json = "not callable"

        custom = CustomStatus()
        microservice = Microservice("DEFAULT__TYPE__CUSTOM")
        microservice.custom = custom
        self.assertEqual(microservice.as_json()["custom"], custom)
        microservice.shutdown()
        time.sleep(0.1)

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


# Runs in a subprocess so the SIGTERM doesn't hit the test runner
SIGTERM_CHILD = """
import os
import time

from test.test_helper import mock_redis


class Cleanups:
    def addCleanup(self, *args, **kwargs):
        pass


mock_redis(Cleanups())

from openc3.microservices.microservice import Microservice


class SigtermMicroservice(Microservice):
    def run(self):
        print("running", flush=True)
        while not self.cancel_thread:
            time.sleep(0.05)

    def shutdown(self, state="STOPPED"):
        print("shutdown ran", flush=True)
        super().shutdown(state)


os.environ["OPENC3_MICROSERVICE_NAME"] = "DEFAULT__TYPE__NAME"
SigtermMicroservice.class_run()
"""


class TestMicroserviceSigterm(unittest.TestCase):
    def test_shuts_down_on_sigterm(self):
        # Kubernetes stops a microservice's pod with SIGTERM. Python skips atexit
        # handlers when SIGTERM kills it, so shutdown must still run or the
        # microservice and interface status are left RUNNING and CONNECTED.
        python_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        process = subprocess.Popen(
            [sys.executable, "-c", SIGTERM_CHILD],
            cwd=python_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert process.stdout is not None and process.stderr is not None
        try:
            # Log messages also go to stdout so read until run has started
            for line in process.stdout:
                if line.strip() == "running":
                    break
            else:
                self.fail(f"Microservice never ran: {process.stderr.read()}")
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=30)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
        self.assertIn("shutdown ran", stdout, stderr)
