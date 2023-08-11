#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
test_authorization.py
"""

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
