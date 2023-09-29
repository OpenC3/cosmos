#!/usr/bin/env python3

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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import threading
import time
import json
from openc3.environment import *
from requests import Session


# Basic exception for known errors
class OpenC3AuthenticationError(RuntimeError):
    pass


class OpenC3AuthenticationRetryableError(OpenC3AuthenticationError):
    pass


# OpenC3 base / open source authentication code
class OpenC3Authentication:
    def __init__(self):
        self._token = OPENC3_API_PASSWORD
        if not self._token:
            raise OpenC3AuthenticationError(
                "Authentication requires environment variable OPENC3_API_PASSWORD"
            )

    def token(self):
        return self._token


# OpenC3 enterprise Keycloak authentication code
class OpenC3KeycloakAuthentication(OpenC3Authentication):
    # {
    #     "access_token": "",
    #     "expires_in": 600,
    #     "refresh_expires_in": 1800,
    #     "refresh_token": "",
    #     "token_type": "bearer",
    #     "id_token": "",
    #     "not-before-policy": 0,
    #     "session_state": "",
    #     "scope": "openid email profile"
    # }

    REFRESH_OFFSET_SECONDS = 60

    # @param url [String] The url of the openc3 or keycloak in the cluster
    def __init__(self, url):
        self.url = url
        self.auth_mutex = threading.Lock()
        self.refresh_token = None
        self.expires_at = None
        self.refresh_expires_at = None
        self._token = None
        self.log = [None, None]
        self.http = Session()

    # Load the token from the environment
    def token(self):
        with self.auth_mutex:
            self.log = [None, None]
            current_time = time.time()
            if self._token is None:
                self._make_token(current_time)
            elif self.refresh_expires_at < current_time:
                self._make_token(current_time)
            elif self.expires_at < current_time:
                self._refresh_token(current_time)
        return f"Bearer {self._token}"

    def get_token_from_refresh_token(self, refresh_token):
        current_time = time.time()
        try:
            self.refresh_token = refresh_token
            self._refresh_token(current_time)
            return self._token
        except OpenC3AuthenticationError:
            return None

    # Make the token and save token to instance
    def _make_token(self, current_time):
        client_id = OPENC3_API_CLIENT or "api"
        if OPENC3_API_USER and OPENC3_API_PASSWORD:
            # Username and password
            data = f"username={OPENC3_API_USER}&password={OPENC3_API_PASSWORD}&client_id={client_id}&grant_type=password&scope=openid"
            headers = {
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": OPENC3_USER_AGENT,
            }
            oath = self._make_request(headers, data)
            self._token = oath["access_token"]
            self.refresh_token = oath["refresh_token"]
            self.expires_at = (
                current_time + oath["expires_in"] - self.REFRESH_OFFSET_SECONDS
            )
            self.refresh_expires_at = (
                current_time + oath["refresh_expires_in"] - self.REFRESH_OFFSET_SECONDS
            )
        else:
            # Offline Access Token
            if self.refresh_token is None:
                self.refresh_token = OPENC3_API_TOKEN
            self._refresh_token(current_time)
        return None

    # Refresh the token and save token to instance
    def _refresh_token(self, current_time):
        client_id = OPENC3_API_CLIENT or "api"
        data = f"client_id={client_id}&refresh_token={self.refresh_token}&grant_type=refresh_token"
        headers = {
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": OPENC3_USER_AGENT,
        }
        oath = self._make_request(headers, data)
        self._token = oath["access_token"]
        self.refresh_token = oath["refresh_token"]
        self.expires_at = (
            current_time + oath["expires_in"] - self.REFRESH_OFFSET_SECONDS
        )
        self.refresh_expires_at = (
            current_time + oath["refresh_expires_in"] - self.REFRESH_OFFSET_SECONDS
        )

    # Make the post request to keycloak
    def _make_request(self, headers, data):
        realm = OPENC3_KEYCLOAK_REALM or "openc3"
        url = f"{self.url}/realms/{realm}/protocol/openid-connect/token"
        request_kwargs = {
            "url": url,
            "data": data,
            "headers": headers,
        }
        self.log[0] = f"Request: {request_kwargs}"
        # print(self.log[0])
        resp = self.http.post(**request_kwargs)
        self.log[
            1
        ] = f"response status: #{resp.status_code} header: #{resp.headers} body: #{resp.text}"
        # print(self.log[1])
        if resp.status_code >= 200 and resp.status_code <= 299:
            return json.loads(resp.text)
        elif resp.status_code >= 500 and resp.status_code <= 599:
            raise OpenC3AuthenticationRetryableError(
                f"authentication request retryable {self.log[0]} ::: {self.log[1]}"
            )
        else:
            raise OpenC3AuthenticationError(
                f"authentication request failed {self.log[0]} ::: {self.log[1]}"
            )
