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
from unittest.mock import patch

from openc3.api.offline_access_api import offline_access_needed
from test.test_helper import mock_redis, setup_system


class TestOfflineAccessApi(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_offline_access_needed_returns_false_when_user_info_has_no_roles(self):
        # https://github.com/OpenC3/cosmos/issues/4297
        # The COSMOS Core user_info returns {}
        with patch("openc3.api.offline_access_api.user_info", return_value={}):
            self.assertFalse(offline_access_needed())

    def test_offline_access_needed_returns_false_without_the_offline_access_role(self):
        with patch("openc3.api.offline_access_api.user_info", return_value={"roles": ["viewer"], "username": "user"}):
            self.assertFalse(offline_access_needed())

    def test_offline_access_needed_returns_true_with_the_role_and_no_stored_token(self):
        with patch(
            "openc3.api.offline_access_api.user_info", return_value={"roles": ["offline_access"], "username": "user"}
        ):
            self.assertTrue(offline_access_needed())
