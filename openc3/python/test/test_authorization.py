# Copyright 2023 OpenC3, Inc.
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

import unittest
from openc3.script.authorization import CosmosAuthorization


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


# class TestCosmosKeycloakAuthorization(unittest.TestCase):
#     HOST, PORT = "127.0.0.1", 7777

#     @patch("requests.post")
#     def test_object(self, post):
#         """
#         Test json request
#         """
#         keycloak = CosmosKeycloakAuthorization(hostname=self.HOST, port=self.PORT)
#         post.assert_not_called()
#         self.assertIsNotNone(keycloak.request_url)
#         self.assertTrue(self.HOST in keycloak.request_url)
#         self.assertTrue(str(self.PORT) in keycloak.request_url)

# @patch("requests.post")
# def test_object_localhost(self, post):
#     """
#     Test json request
#     """
#     keycloak = CosmosKeycloakAuthorization()
#     post.assert_not_called()
#     self.assertIsNotNone(keycloak.request_url)
#     self.assertTrue(self.HOST in keycloak.request_url)
#     self.assertTrue("2900" in keycloak.request_url)

# @patch("requests.post")
# def test_object_tacocat(self, post):
#     """
#     Test hostname in request_url
#     """
#     hostname = "tacocat"
#     keycloak = CosmosKeycloakAuthorization(hostname=hostname, port=self.PORT)
#     post.assert_not_called()
#     self.assertIsNotNone(keycloak.request_url)
#     self.assertTrue(hostname in keycloak.request_url)
#     self.assertTrue(str(self.PORT) in keycloak.request_url)

# @patch("requests.post")
# def test_keycloak(self, post):
#     """
#     Test keycloak status 200
#     """
#     ret = {
#         "access_token": "",
#         "expires_in": 600,
#         "refresh_expires_in": 1800,
#         "refresh_token": "",
#         "token_type": "bearer",
#         "id_token": "",
#         "not-before-policy": 0,
#         "session_state": "",
#         "scope": "openid email profile",
#     }
#     post.return_value = MagicMock(status_code=200, json=lambda: ret)
#     requ = CosmosMockRequest()
#     auth = CosmosKeycloakAuthorization()
#     auth(requ)
#     self.assertTrue("Authorization" in requ.headers)
#     post.assert_called_once()


if __name__ == "__main__":
    unittest.main()
