# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
import logging
import requests

from openc3.__version__ import __title__
from openc3.environment import *
from .decorators import request_wrapper

LOGGER = logging.getLogger(__title__)


def generate_auth():
    """
    Pick Auth class base on environment variables
    """
    if OPENC3_API_USER is None:
        return CosmosAuthorization()
    return CosmosKeycloakAuthorization()


class CosmosAuthorization(requests.auth.AuthBase):
    """Class to hold token for COSMOS

    The CosmosAuthorization can be used to call COSMOS server methods directly:
      auth = CosmosAuthorization()
      requests.get("example.org", auth=auth)
    """

    def get(self):
        return OPENC3_API_PASSWORD

    def __call__(self, r: requests.Request):
        r.headers["Authorization"] = OPENC3_API_PASSWORD
        return r

    def __repr__(self):
        return f"<{self.__class__.__name__}>"

    def __str__(self):
        return f"<{self.__class__.__name__}>"


class CosmosKeycloakAuthorization(CosmosAuthorization):
    """Class to generate Keycloak token for COSMOS Enterprise
    https://developers.redhat.com/blog/2020/01/29/api-login-and-jwt-token-generation-using-keycloak

    The CosmosKeycloakAuthorization can be used to call the COSMOS keycloak server methods directly:
      auth = CosmosKeycloakAuthorization(schema="", hostname="127.0.0.1", port=7777)
      requests.get("example.org", auth=auth)
    """

    def __init__(
        self,
        schema: str = OPENC3_API_SCHEMA,
        hostname: str = OPENC3_API_HOSTNAME,
        port: int = OPENC3_API_PORT,
    ):
        """Constructor

        Parameters:
        schema -- The schema to connect to cosmos with
        hostname -- The name of the machine which has started the JSON service
        port -- The port number of the JSON service
        """
        self.request_url = OPENC3_KEYCLOAK_URL
        self.refresh_token = None
        self.expires_at = None
        self.refresh_expires_at = None
        self.token = None

    def _time_logic(self):
        current_time = time.time()
        if self.token is None:
            self._make_token()
        elif self.refresh_expires_at < current_time:
            self._make_token()
        elif self.expires_at < current_time:
            self._refresh_token()

    def get(self):
        self._time_logic()
        return f"Bearer {self.token}"

    def __call__(self, r: requests.Request):
        self._time_logic()
        r.headers["Authorization"] = f"Bearer {self.token}"
        return r

    def _make_token(self):
        """
        {
            "access_token": "",
            "expires_in": 600,
            "refresh_expires_in": 1800,
            "refresh_token": "",
            "token_type": "bearer",
            "id_token": "",
            "not-before-policy": 0,
            "session_state": "",
            "scope": "openid email profile"
        }
        """
        oath = None
        if OPENC3_API_USER and OPENC3_API_PASSWORD:
            oath = self._make_token_request().json()
        else:
            oath = self._make_refresh_request().json()
        self.token = oath["access_token"]
        self.refresh_token = oath["refresh_token"]
        current_time = time.time()
        self.expires_at = current_time + oath["expires_in"]
        self.refresh_expires_at = current_time + oath["refresh_expires_in"]

    @request_wrapper
    def _make_token_request(self):
        """Use the python requests library to request a token from Cosmos Keycloak.

        This is an internal method that uses two decorators. request_wrapper
        captures errors from the request library.
        return -- request.Response
            https://docs.python-requests.org/en/master/user/quickstart/#json-response-content
        """
        request_kwargs = {
            "url": f"{self.request_url}/realms/{OPENC3_KEYCLOAK_REALM}/protocol/openid-connect/token",
            "data": f"username={OPENC3_API_USER}&password={OPENC3_API_PASSWORD}&client_id={OPENC3_API_CLIENT}&grant_type=password&scope=openid",
            "headers": {
                "User-Agent": OPENC3_USER_AGENT,
                "Content-Type": "application/x-www-form-urlencoded",
            },
        }
        resp = requests.post(**request_kwargs)
        LOGGER.debug(
            "resp: %s total_seconds: %f content: %s",
            resp,
            resp.elapsed.total_seconds(),
            resp.content,
        )
        return resp

    def _refresh_token(self):
        """
        {
            "access_token": "",
            "expires_in": 600,
            "refresh_expires_in": 1800,
            "refresh_token": "",
            "token_type": "bearer",
            "id_token": "",
            "not-before-policy": 0,
            "session_state": "",
            "scope": "openid email profile"
        }
        """
        oath = self._make_refresh_request().json()
        self.token = oath["access_token"]
        self.refresh_token = oath["refresh_token"]
        current_time = time.time()
        self.expires_at = current_time + oath["expires_in"]
        self.refresh_expires_at = current_time + oath["refresh_expires_in"]

    @request_wrapper
    def _make_refresh_request(self):
        """Use the python requests library to refresh the token.

        This is an internal method that uses two decorators. request_wrapper
        captures errors from the request library.
        return -- request.Response
            https://docs.python-requests.org/en/master/user/quickstart/#json-response-content
        """
        request_kwargs = {
            "url": f"{self.request_url}/realms/{OPENC3_KEYCLOAK_REALM}/protocol/openid-connect/token",
            "data": f"client_id={OPENC3_API_CLIENT}&grant_type=refresh_token&refresh_token={self.refresh_token}",
            "headers": {
                "User-Agent": OPENC3_USER_AGENT,
                "Content-Type": "application/x-www-form-urlencoded",
            },
        }
        LOGGER.debug("calling with %s", request_kwargs)
        resp = requests.post(**request_kwargs)
        LOGGER.debug(
            "resp: %s total_seconds: %f content: %s",
            resp,
            resp.elapsed.total_seconds(),
            resp.content,
        )
        return resp
