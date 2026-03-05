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
import os
import time
import unittest
from unittest.mock import Mock, patch

from openc3.utilities.authentication import (
    OpenC3Authentication,
    OpenC3AuthenticationError,
    OpenC3AuthenticationRetryableError,
    OpenC3KeycloakAuthentication,
)
from test.test_helper import *


class TestOpenC3Authentication(unittest.TestCase):
    def setUp(self):
        # Save original environment
        self.old_password = os.environ.get("OPENC3_API_PASSWORD")
        self.old_service_password = os.environ.get("OPENC3_SERVICE_PASSWORD")

    def tearDown(self):
        # Restore environment
        if self.old_password:
            os.environ["OPENC3_API_PASSWORD"] = self.old_password
        else:
            os.environ.pop("OPENC3_API_PASSWORD", None)
        if self.old_service_password:
            os.environ["OPENC3_SERVICE_PASSWORD"] = self.old_service_password
        else:
            os.environ.pop("OPENC3_SERVICE_PASSWORD", None)

    def test_raises_error_if_password_not_set(self):
        """Raises an error if OPENC3_API_PASSWORD is not set"""
        os.environ.pop("OPENC3_API_PASSWORD", None)
        with self.assertRaises(OpenC3AuthenticationError) as context:
            OpenC3Authentication()
        self.assertIn("Authentication requires environment variable", str(context.exception))

    @patch("openc3.utilities.authentication.Session")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "test_password")
    def test_initializes_with_password(self, mock_session_class):
        """Initializes with OPENC3_API_PASSWORD"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.text = "test_token_12345"
        mock_session.post.return_value = mock_response
        mock_session_class.return_value = mock_session

        auth = OpenC3Authentication()

        # Should have called post with password
        mock_session.post.assert_called_once()
        call_args = mock_session.post.call_args
        self.assertIn("password", call_args.kwargs["json"])
        self.assertEqual(call_args.kwargs["json"]["password"], "test_password")
        self.assertEqual(auth.token(), "test_token_12345")

    @patch("openc3.utilities.authentication.Session")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "test_password")
    def test_raises_error_on_empty_token(self, mock_session_class):
        """Raises error if authentication returns empty token"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.text = ""
        mock_session.post.return_value = mock_response
        mock_session_class.return_value = mock_session

        with self.assertRaises(OpenC3AuthenticationError) as context:
            OpenC3Authentication()
        self.assertIn("Authentication failed", str(context.exception))

    @patch("openc3.utilities.authentication.Session")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "test_password")
    def test_get_otp(self, mock_session_class):
        """Gets OTP with valid token"""
        mock_session = Mock()
        mock_post_response = Mock()
        mock_post_response.text = "test_token"
        mock_get_response = Mock()
        mock_get_response.text = "otp_12345"
        mock_session.post.return_value = mock_post_response
        mock_session.get.return_value = mock_get_response
        mock_session_class.return_value = mock_session

        auth = OpenC3Authentication()
        otp = auth.get_otp()

        self.assertEqual(otp, "otp_12345")
        # Verify get was called with correct parameters
        call_args = mock_session.get.call_args
        self.assertIn("scope", call_args.kwargs["params"])
        self.assertEqual(call_args.kwargs["params"]["scope"], "DEFAULT")

    @patch("openc3.utilities.authentication.Session")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "test_password")
    def test_get_otp_with_custom_scope(self, mock_session_class):
        """Gets OTP with custom scope"""
        mock_session = Mock()
        mock_post_response = Mock()
        mock_post_response.text = "test_token"
        mock_get_response = Mock()
        mock_get_response.text = "otp_custom"
        mock_session.post.return_value = mock_post_response
        mock_session.get.return_value = mock_get_response
        mock_session_class.return_value = mock_session

        auth = OpenC3Authentication()
        auth.get_otp(scope="CUSTOM")

        call_args = mock_session.get.call_args
        self.assertEqual(call_args.kwargs["params"]["scope"], "CUSTOM")

    @patch("openc3.utilities.authentication.Session")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "test_password")
    def test_raises_error_getting_otp_without_token(self, mock_session_class):
        """Raises error when getting OTP without initialized token"""
        mock_session = Mock()
        mock_response = Mock()
        mock_response.text = "test_token"
        mock_session.post.return_value = mock_response
        mock_session_class.return_value = mock_session

        auth = OpenC3Authentication()
        auth._token = None

        with self.assertRaises(OpenC3AuthenticationError) as context:
            auth.get_otp()
        self.assertIn("Uninitialized authentication", str(context.exception))


class TestOpenC3KeycloakAuthentication(unittest.TestCase):
    def setUp(self):
        self.test_url = "http://test-keycloak.local"
        # Save original environment
        self.old_env = {}
        env_vars = [
            "OPENC3_API_USER",
            "OPENC3_API_PASSWORD",
            "OPENC3_API_TOKEN",
            "OPENC3_KEYCLOAK_REALM",
            "OPENC3_API_CLIENT",
            "OPENC3_DEVEL",
        ]
        for var in env_vars:
            self.old_env[var] = os.environ.get(var)

    def tearDown(self):
        # Restore environment
        for var, value in self.old_env.items():
            if value is not None:
                os.environ[var] = value
            else:
                os.environ.pop(var, None)

    def test_initializes_with_url(self):
        """Initializes with a URL"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        self.assertEqual(auth.url, self.test_url)
        self.assertIsNone(auth._token)
        self.assertIsNone(auth.refresh_token)

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    @patch("openc3.utilities.authentication.OPENC3_DEVEL", None)
    def test_password_obfuscation_in_logs_disabled_debug(self):
        """Obfuscates password in error messages when debug mode is disabled"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 401
        mock_response.headers = {}
        mock_response.text = '{"error":"invalid_grant"}'
        auth.http.post = Mock(return_value=mock_response)

        with self.assertRaises(OpenC3AuthenticationError) as context:
            auth.token()

        error_msg = str(context.exception)
        # Password should be obfuscated
        self.assertIn("***", error_msg)
        self.assertNotIn("testpassword", error_msg)
        # Other parameters should still be visible
        self.assertIn("testuser", error_msg)

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    @patch("openc3.utilities.authentication.OPENC3_DEVEL", "true")
    def test_password_shown_in_logs_when_debug_enabled(self):
        """Shows actual password in error messages when debug is enabled"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 401
        mock_response.headers = {}
        mock_response.text = '{"error":"invalid_grant"}'
        auth.http.post = Mock(return_value=mock_response)

        with self.assertRaises(OpenC3AuthenticationError) as context:
            auth.token()

        error_msg = str(context.exception)
        # In debug mode, password should be visible
        self.assertIn("testpassword", error_msg)

    @patch("openc3.utilities.authentication.OPENC3_API_USER", None)
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", None)
    @patch("openc3.utilities.authentication.OPENC3_API_TOKEN", "test_refresh_token")
    @patch("openc3.utilities.authentication.OPENC3_DEVEL", None)
    def test_obfuscates_refresh_token_in_normal_mode(self):
        """Obfuscates refresh_token in normal mode"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 401
        mock_response.headers = {}
        mock_response.text = '{"error":"invalid_grant"}'
        auth.http.post = Mock(return_value=mock_response)

        with self.assertRaises(OpenC3AuthenticationError) as context:
            auth.token()

        error_msg = str(context.exception)
        # Refresh token should be obfuscated
        self.assertIn("***", error_msg)
        self.assertNotIn("test_refresh_token", error_msg)

    @patch("openc3.utilities.authentication.OPENC3_API_USER", None)
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", None)
    @patch("openc3.utilities.authentication.OPENC3_API_TOKEN", "test_refresh_token")
    @patch("openc3.utilities.authentication.OPENC3_DEVEL", "true")
    def test_shows_refresh_token_when_debug_enabled(self):
        """Shows actual refresh_token when debug is enabled"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 401
        mock_response.headers = {}
        mock_response.text = '{"error":"invalid_grant"}'
        auth.http.post = Mock(return_value=mock_response)

        with self.assertRaises(OpenC3AuthenticationError) as context:
            auth.token()

        error_msg = str(context.exception)
        # In debug mode, refresh token should be visible
        self.assertIn("test_refresh_token", error_msg)

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    def test_successful_authentication(self):
        """Returns token with Bearer prefix by default"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.headers = {}
        mock_response.text = json.dumps(
            {
                "access_token": "access_token_123",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "refresh_token_123",
                "token_type": "bearer",
            }
        )
        auth.http.post = Mock(return_value=mock_response)

        token = auth.token()
        self.assertEqual(token, "Bearer access_token_123")

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    def test_token_without_bearer_prefix(self):
        """Returns token without Bearer prefix when requested"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.headers = {}
        mock_response.text = json.dumps(
            {
                "access_token": "access_token_123",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "refresh_token_123",
                "token_type": "bearer",
            }
        )
        auth.http.post = Mock(return_value=mock_response)

        token = auth.token(include_bearer=False)
        self.assertEqual(token, "access_token_123")

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    def test_raises_retryable_error_for_5xx_status(self):
        """Raises retryable error for 5xx status codes"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 503
        mock_response.headers = {}
        mock_response.text = '{"error":"service_unavailable"}'
        auth.http.post = Mock(return_value=mock_response)

        with self.assertRaises(OpenC3AuthenticationRetryableError):
            auth.token()

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    def test_raises_error_for_4xx_status(self):
        """Raises non-retryable error for 4xx status codes"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 401
        mock_response.headers = {}
        mock_response.text = '{"error":"invalid_grant"}'
        auth.http.post = Mock(return_value=mock_response)

        with self.assertRaises(OpenC3AuthenticationError) as context:
            auth.token()
        # Should not be retryable error
        self.assertNotIsInstance(context.exception, OpenC3AuthenticationRetryableError)

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    def test_token_refresh_before_expiration(self):
        """Refreshes token before expiration"""
        auth = OpenC3KeycloakAuthentication(self.test_url)

        # Mock first token response
        mock_response1 = Mock()
        mock_response1.status_code = 200
        mock_response1.text = json.dumps(
            {
                "access_token": "token_1",
                "expires_in": 1,  # Expires in 1 second
                "refresh_expires_in": 1800,
                "refresh_token": "refresh_1",
                "token_type": "bearer",
            }
        )

        # Mock refresh response
        mock_response2 = Mock()
        mock_response2.status_code = 200
        mock_response2.text = json.dumps(
            {
                "access_token": "token_2",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "refresh_2",
                "token_type": "bearer",
            }
        )

        auth.http.post = Mock(side_effect=[mock_response1, mock_response2])

        # Get first token
        token1 = auth.token()
        self.assertEqual(token1, "Bearer token_1")

        # Wait for token to expire
        time.sleep(2)

        # Get token again - should refresh
        token2 = auth.token()
        self.assertEqual(token2, "Bearer token_2")

        # Should have called post twice (initial + refresh)
        self.assertEqual(auth.http.post.call_count, 2)

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    def test_reuses_valid_token(self):
        """Reuses valid token without making new requests"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.text = json.dumps(
            {
                "access_token": "token_1",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "refresh_1",
                "token_type": "bearer",
            }
        )
        auth.http.post = Mock(return_value=mock_response)

        # Get token twice
        token1 = auth.token()
        token2 = auth.token()

        # Should be the same token
        self.assertEqual(token1, token2)
        # Should only have called post once
        self.assertEqual(auth.http.post.call_count, 1)

    def test_get_token_from_refresh_token(self):
        """Gets token from refresh token"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.text = json.dumps(
            {
                "access_token": "new_access_token",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "new_refresh_token",
                "token_type": "bearer",
            }
        )
        auth.http.post = Mock(return_value=mock_response)

        token = auth.get_token_from_refresh_token("provided_refresh_token")

        self.assertEqual(token, "new_access_token")
        self.assertEqual(auth.refresh_token, "new_refresh_token")

    def test_get_token_from_refresh_token_returns_none_on_error(self):
        """Returns None when refresh token is invalid"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 401
        mock_response.headers = {}
        mock_response.text = '{"error":"invalid_grant"}'
        auth.http.post = Mock(return_value=mock_response)

        token = auth.get_token_from_refresh_token("invalid_refresh_token")

        self.assertIsNone(token)

    @patch("openc3.utilities.authentication.OPENC3_API_USER", None)
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", None)
    @patch("openc3.utilities.authentication.OPENC3_API_TOKEN", "offline_token")
    def test_uses_offline_access_token_when_no_user_password(self):
        """Uses offline access token when no user/password provided"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.text = json.dumps(
            {
                "access_token": "access_from_offline",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "new_refresh",
                "token_type": "bearer",
            }
        )
        auth.http.post = Mock(return_value=mock_response)

        token = auth.token()

        self.assertEqual(token, "Bearer access_from_offline")
        # Verify it sent the offline token as refresh_token
        call_args = auth.http.post.call_args
        self.assertIn("refresh_token=offline_token", call_args.kwargs["data"])

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    def test_custom_openid_scope(self):
        """Uses custom openid scope"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.text = json.dumps(
            {
                "access_token": "token",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "refresh",
                "token_type": "bearer",
            }
        )
        auth.http.post = Mock(return_value=mock_response)

        auth.token(openid_scope="openid profile email")

        # Verify scope was sent
        call_args = auth.http.post.call_args
        self.assertIn("scope=openid+profile+email", call_args.kwargs["data"])

    @patch("openc3.utilities.authentication.OPENC3_API_USER", "testuser")
    @patch("openc3.utilities.authentication.OPENC3_API_PASSWORD", "testpassword")
    @patch("openc3.utilities.authentication.OPENC3_API_CLIENT", "custom_client")
    def test_uses_custom_client_id(self):
        """Uses custom client ID from environment"""
        auth = OpenC3KeycloakAuthentication(self.test_url)
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.text = json.dumps(
            {
                "access_token": "token",
                "expires_in": 600,
                "refresh_expires_in": 1800,
                "refresh_token": "refresh",
                "token_type": "bearer",
            }
        )
        auth.http.post = Mock(return_value=mock_response)

        auth.token()

        # Verify custom client_id was sent
        call_args = auth.http.post.call_args
        self.assertIn("client_id=custom_client", call_args.kwargs["data"])


if __name__ == "__main__":
    unittest.main()
