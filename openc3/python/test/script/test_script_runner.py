# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import unittest
from unittest.mock import Mock

import requests

import openc3.script
from openc3.script.script_runner import script_instrumented


class TestScriptRunner(unittest.TestCase):
    def setUp(self):
        self.orig_server = openc3.script.SCRIPT_RUNNER_API_SERVER
        self.server = Mock()
        openc3.script.SCRIPT_RUNNER_API_SERVER = self.server

    def tearDown(self):
        openc3.script.SCRIPT_RUNNER_API_SERVER = self.orig_server

    def stub_request(self, body, status_code=200):
        response = requests.Response()
        response.status_code = status_code
        response._content = json.dumps(body).encode()
        self.server.request.return_value = response

    def test_script_instrumented_returns_instrumented_script(self):
        self.stub_request({"title": "Instrumented Script", "description": json.dumps(["line 1", "line 2"])})
        self.assertEqual(script_instrumented("print('hi')"), "line 1\nline 2")

    def test_script_instrumented_raises_instrumentation_error(self):
        self.stub_request({"title": "Error Instrumenting Script", "description": "SyntaxError: invalid syntax"})
        with self.assertRaisesRegex(RuntimeError, "Error Instrumenting Script: SyntaxError: invalid syntax"):
            script_instrumented("def foo(:\n    pass\n")


if __name__ == "__main__":
    unittest.main()
