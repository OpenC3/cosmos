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
from unittest.mock import MagicMock, patch

from openc3.environment import OPENC3_SCOPE
from openc3.script import initialize_offline_access


class TestInitializeOfflineAccess(unittest.TestCase):
    def setUp(self):
        auth = MagicMock()
        auth.refresh_token = "REFRESH"
        # Patch the WHITELIST forwarder directly since it is only generated when
        # every openc3.api module is imported before openc3.script
        patcher = patch("openc3.script.set_offline_access", create=True)
        self.set_offline_access = patcher.start()
        self.addCleanup(patcher.stop)
        for patcher in (
            patch("openc3.script.OPENC3_KEYCLOAK_URL", "http://keycloak"),
            patch("openc3.script.OpenC3KeycloakAuthentication", return_value=auth),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_sets_the_token_in_the_given_scope(self):
        initialize_offline_access(scope="OTHER")
        self.set_offline_access.assert_called_once_with("REFRESH", scope="OTHER")

    def test_sets_the_token_in_the_default_scope(self):
        initialize_offline_access()
        self.set_offline_access.assert_called_once_with("REFRESH", scope=OPENC3_SCOPE)

    def test_raises_outside_of_enterprise(self):
        with (
            patch("openc3.script.OPENC3_KEYCLOAK_URL", None),
            self.assertRaisesRegex(RuntimeError, "only valid in COSMOS Enterprise"),
        ):
            initialize_offline_access()
        self.set_offline_access.assert_not_called()


if __name__ == "__main__":
    unittest.main()
