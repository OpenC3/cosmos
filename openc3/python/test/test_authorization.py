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
import warnings
from unittest.mock import patch

import requests

from openc3.script.authorization import CosmosAuthorization, CosmosKeycloakAuthorization
from openc3.script.decorators import request_wrapper


class CosmosMockRequest:
    def __init__(self):
        self.headers = {}


class TestCosmosAuthorization(unittest.TestCase):
    def test_object(self):
        """
        Test auth
        """
        auth = CosmosAuthorization()
        requ = CosmosMockRequest()
        auth(requ)
        self.assertTrue("Authorization" in requ.headers)


class TestCosmosKeycloakAuthorization(unittest.TestCase):
    def error_response(self, status_code):
        response = requests.Response()
        response.status_code = status_code
        response.url = "http://keycloak/realms/openc3/protocol/openid-connect/token"
        response.request = requests.Request("POST", response.url).prepare()
        response._content = b'{"error": "invalid_grant"}'
        return response

    def test_no_deprecation_warning_by_default(self):
        with warnings.catch_warnings():
            warnings.simplefilter("error")
            CosmosKeycloakAuthorization()

    def test_schema_hostname_port_are_deprecated(self):
        with self.assertWarns(DeprecationWarning):
            auth = CosmosKeycloakAuthorization(schema="https", hostname="other-host", port=443)
        self.assertNotIn("other-host", str(auth.request_url))

    @patch("requests.post")
    def test_token_request_raises_for_http_errors(self, post):
        for status_code in (400, 401, 404, 500):
            post.return_value = self.error_response(status_code)
            auth = CosmosKeycloakAuthorization()
            with self.assertRaisesRegex(RuntimeError, f"Error response {status_code} while requesting"):
                auth._make_token_request()
            with self.assertRaisesRegex(RuntimeError, f"Error response {status_code} while requesting"):
                auth._make_refresh_request()


class TestRequestWrapper(unittest.TestCase):
    def test_http_errors_above_400_raise(self):
        response = requests.Response()
        response.status_code = 500
        response.url = "http://example.org"

        @request_wrapper
        def failing_request():
            raise requests.HTTPError(response=response, request=requests.Request("GET", response.url).prepare())

        with self.assertRaisesRegex(RuntimeError, "Error response 500 while requesting 'http://example.org/'"):
            failing_request()


if __name__ == "__main__":
    unittest.main()
