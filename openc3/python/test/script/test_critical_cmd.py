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
from openc3.script.critical_cmd import (
    critical_cmd_approve,
    critical_cmd_info,
    critical_cmd_reject,
    critical_cmd_status,
)


class TestCriticalCmd(unittest.TestCase):
    def setUp(self):
        self.orig_api_server = openc3.script.API_SERVER
        self.api_server = Mock()
        openc3.script.API_SERVER = self.api_server

    def tearDown(self):
        openc3.script.API_SERVER = self.orig_api_server

    def stub_request(self, status_code=200, body=None):
        # Use a real Response since it is falsy for error status codes
        response = requests.Response()
        response.status_code = status_code
        response._content = json.dumps(body or {}).encode()
        self.api_server.request.return_value = response

    def test_critical_cmd_status(self):
        self.stub_request(body={"status": "WAITING", "approvers": ["alice"], "approvers_required": 2})
        self.assertEqual(critical_cmd_status("UUID"), "WAITING")
        self.assertEqual(self.api_server.request.call_args.args, ("get", "/openc3-api/criticalcmd/status/UUID"))

    def test_critical_cmd_info(self):
        self.stub_request(body={"status": "WAITING", "approvers": ["alice"], "approvers_required": 2})
        self.assertEqual(
            critical_cmd_info("UUID"),
            {"status": "WAITING", "approvers": ["alice"], "approvers_required": 2},
        )
        self.assertEqual(self.api_server.request.call_args.args, ("get", "/openc3-api/criticalcmd/status/UUID"))

    def test_critical_cmd_info_defaults_for_older_servers(self):
        self.stub_request(body={"status": "APPROVED"})
        self.assertEqual(
            critical_cmd_info("UUID"),
            {"status": "APPROVED", "approvers": [], "approvers_required": 1},
        )

    def test_critical_cmd_info_raises_on_error(self):
        self.stub_request(status_code=404, body={"status": "error", "message": "not found"})
        with self.assertRaisesRegex(RuntimeError, "critical_cmd_info failed"):
            critical_cmd_info("UUID")

    def test_critical_cmd_approve_raises_with_server_message(self):
        self.stub_request(status_code=500, body={"status": "error", "message": "already approved by alice"})
        with self.assertRaisesRegex(RuntimeError, "already approved by alice"):
            critical_cmd_approve("UUID")

    def test_critical_cmd_reject_raises_with_server_message(self):
        self.stub_request(status_code=500, body={"status": "error", "message": "already APPROVED"})
        with self.assertRaisesRegex(RuntimeError, "already APPROVED"):
            critical_cmd_reject("UUID")

    def test_critical_cmd_approve_raises_without_response(self):
        self.api_server.request.return_value = None
        with self.assertRaisesRegex(RuntimeError, "critical_cmd_approve failed"):
            critical_cmd_approve("UUID")

    def test_critical_cmd_reject_raises_without_response(self):
        self.api_server.request.return_value = None
        with self.assertRaisesRegex(RuntimeError, "critical_cmd_reject failed"):
            critical_cmd_reject("UUID")
