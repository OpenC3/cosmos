# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import unittest
from unittest.mock import Mock, patch
from test.test_helper import mock_redis
from openc3.script.storage import get_target_file
import openc3.script


class TestGetTargetFile(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)
        # Mock the API_SERVER
        self.api_server_mock = Mock()
        openc3.script.API_SERVER = self.api_server_mock
        openc3.script.OPENC3_IN_CLUSTER = True
        os.environ["OPENC3_SCOPE"] = "DEFAULT"
        os.environ["OPENC3_CLOUD"] = "local"

    def tearDown(self):
        # Clean up environment
        if "OPENC3_LOCAL_MODE" in os.environ:
            del os.environ["OPENC3_LOCAL_MODE"]

    @patch("openc3.script.storage.requests.get")
    def test_get_target_file_from_targets_modified(self, mock_get):
        """Test successfully retrieving a file from targets_modified"""
        # Setup mock responses
        presigned_response = Mock()
        presigned_response.status_code = 201
        presigned_response.text = '{"url": "/presigned/url"}'
        self.api_server_mock.request.return_value = presigned_response

        # Mock the file content response
        file_content = b"test file content"
        mock_file_response = Mock()
        mock_file_response.status_code = 200
        mock_file_response.content = file_content
        mock_get.return_value = mock_file_response

        # Call the function
        result = get_target_file("INST/procedures/test.rb", original=False, scope="DEFAULT")

        # Verify API calls
        self.api_server_mock.request.assert_called_once_with(
            "get",
            "/openc3-api/storage/download/DEFAULT/targets_modified/INST/procedures/test.rb",
            query={"bucket": "OPENC3_CONFIG_BUCKET", "internal": True},
            scope="DEFAULT",
        )

        # Verify the result
        self.assertIsNotNone(result)
        content = result.read()
        self.assertEqual(content, file_content)

    @patch("openc3.script.storage.requests.get")
    def test_get_target_file_falls_back_to_targets(self, mock_get):
        """Test falling back to targets directory when targets_modified fails"""
        # First call fails (targets_modified)
        # Second call succeeds (targets)
        presigned_response_success = Mock()
        presigned_response_success.status_code = 201
        presigned_response_success.text = '{"url": "/presigned/url"}'

        self.api_server_mock.request.return_value = presigned_response_success

        # First request fails (targets_modified), second succeeds (targets)
        file_content = b"original file content"
        mock_file_response_fail = Mock()
        mock_file_response_fail.status_code = 404
        mock_file_response_success = Mock()
        mock_file_response_success.status_code = 200
        mock_file_response_success.content = file_content

        mock_get.side_effect = [mock_file_response_fail, mock_file_response_success]

        # Call the function
        result = get_target_file("INST/procedures/test.rb", original=False, scope="DEFAULT")

        # Verify it tried targets_modified first, then targets
        self.assertEqual(self.api_server_mock.request.call_count, 2)
        first_call = self.api_server_mock.request.call_args_list[0]
        self.assertIn("targets_modified", first_call[0][1])
        second_call = self.api_server_mock.request.call_args_list[1]
        self.assertIn("targets/INST", second_call[0][1])

        # Verify the result
        self.assertIsNotNone(result)
        content = result.read()
        self.assertEqual(content, file_content)

    @patch("openc3.script.storage.requests.get")
    def test_get_target_file_with_original_true(self, mock_get):
        """Test retrieving original file directly from targets directory"""
        # Setup mock responses
        presigned_response = Mock()
        presigned_response.status_code = 201
        presigned_response.text = '{"url": "/presigned/url"}'
        self.api_server_mock.request.return_value = presigned_response

        # Mock the file content response
        file_content = b"original file content"
        mock_file_response = Mock()
        mock_file_response.status_code = 200
        mock_file_response.content = file_content
        mock_get.return_value = mock_file_response

        # Call the function with original=True
        result = get_target_file("INST/procedures/test.rb", original=True, scope="DEFAULT")

        # Verify it only called targets, not targets_modified
        self.api_server_mock.request.assert_called_once()
        call_args = self.api_server_mock.request.call_args[0]
        self.assertIn("targets/INST", call_args[1])
        self.assertNotIn("targets_modified", call_args[1])

        # Verify the result
        self.assertIsNotNone(result)
        content = result.read()
        self.assertEqual(content, file_content)

    @patch("openc3.script.storage.requests.get")
    def test_get_target_file_not_found(self, mock_get):
        """Test return value of None when file is not found in either location"""
        # Setup mock responses
        presigned_response = Mock()
        presigned_response.status_code = 201
        presigned_response.text = '{"url": "/presigned/url"}'
        self.api_server_mock.request.return_value = presigned_response

        # Both requests fail
        mock_file_response = Mock()
        mock_file_response.status_code = 404
        mock_get.return_value = mock_file_response

        # Call the function and expect None
        result = get_target_file("INST/procedures/nonexistent.rb", original=False, scope="DEFAULT")

        self.assertIsNone(result)

    @patch("openc3.script.storage.LocalMode.open_local_file")
    def test_get_target_file_local_mode(self, mock_open_local):
        """Test retrieving file in local mode"""
        os.environ["OPENC3_LOCAL_MODE"] = "true"

        # Mock local file
        mock_local_file = Mock()
        mock_local_file.read.return_value = b"local file content"
        mock_open_local.return_value = mock_local_file

        # Call the function
        result = get_target_file("INST/procedures/test.rb", original=False, scope="DEFAULT")

        # Verify local file was opened
        mock_open_local.assert_called_once_with("INST/procedures/test.rb", scope="DEFAULT")

        # Verify the result
        self.assertIsNotNone(result)
        content = result.read()
        self.assertEqual(content, b"local file content")

    @patch("openc3.script.storage.LocalMode.open_local_file")
    @patch("openc3.script.storage.requests.get")
    def test_get_target_file_local_mode_falls_back(self, mock_get, mock_open_local):
        """Test falling back to remote when local file not found"""
        os.environ["OPENC3_LOCAL_MODE"] = "true"

        # Mock local file not found
        mock_open_local.return_value = None

        # Setup mock responses for remote
        presigned_response = Mock()
        presigned_response.status_code = 201
        presigned_response.text = '{"url": "/presigned/url"}'
        self.api_server_mock.request.return_value = presigned_response

        # Mock the file content response
        file_content = b"remote file content"
        mock_file_response = Mock()
        mock_file_response.status_code = 200
        mock_file_response.content = file_content
        mock_get.return_value = mock_file_response

        # Call the function
        result = get_target_file("INST/procedures/test.rb", original=False, scope="DEFAULT")

        # Verify it tried local first
        mock_open_local.assert_called_once()

        # Verify it fell back to remote
        self.api_server_mock.request.assert_called()

        # Verify the result
        self.assertIsNotNone(result)
        content = result.read()
        self.assertEqual(content, file_content)

    @patch("openc3.script.storage.requests.get")
    def test_get_target_file_returns_tempfile(self, mock_get):
        """Test that the returned file is a NamedTemporaryFile"""
        # Setup mock responses
        presigned_response = Mock()
        presigned_response.status_code = 201
        presigned_response.text = '{"url": "/presigned/url"}'
        self.api_server_mock.request.return_value = presigned_response

        # Mock the file content response
        file_content = b"test file content"
        mock_file_response = Mock()
        mock_file_response.status_code = 200
        mock_file_response.content = file_content
        mock_get.return_value = mock_file_response

        # Call the function
        result = get_target_file("INST/procedures/test.rb", original=False, scope="DEFAULT")

        # Verify the result is a file-like object
        self.assertTrue(hasattr(result, "read"))
        self.assertTrue(hasattr(result, "seek"))
        self.assertTrue(hasattr(result, "name"))

        # Verify file position is at the beginning
        first_read = result.read()
        self.assertEqual(first_read, file_content)

        # Verify we can seek and read again
        result.seek(0)
        second_read = result.read()
        self.assertEqual(second_read, file_content)

    @patch("openc3.script.storage.requests.get")
    def test_get_target_file_with_custom_scope(self, mock_get):
        """Test retrieving file with a custom scope"""
        # Setup mock responses
        presigned_response = Mock()
        presigned_response.status_code = 201
        presigned_response.text = '{"url": "/presigned/url"}'
        self.api_server_mock.request.return_value = presigned_response

        # Mock the file content response
        file_content = b"custom scope file"
        mock_file_response = Mock()
        mock_file_response.status_code = 200
        mock_file_response.content = file_content
        mock_get.return_value = mock_file_response

        # Call the function with custom scope
        result = get_target_file("INST/procedures/test.rb", original=False, scope="CUSTOM_SCOPE")

        # Verify the scope was used correctly
        self.api_server_mock.request.assert_called_once()
        call_args = self.api_server_mock.request.call_args
        self.assertIn("CUSTOM_SCOPE/targets_modified", call_args[0][1])
        self.assertEqual(call_args[1]["scope"], "CUSTOM_SCOPE")

        # Verify the result
        self.assertIsNotNone(result)
        content = result.read()
        self.assertEqual(content, file_content)

    def test_get_target_file_presigned_url_failure(self):
        """Test return value of None when presigned URL request fails"""
        # Setup mock response with failure
        presigned_response = Mock()
        presigned_response.status_code = 500
        self.api_server_mock.request.return_value = presigned_response

        # Call the function and expect None
        result = get_target_file("INST/procedures/test.rb", original=False, scope="DEFAULT")

        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
