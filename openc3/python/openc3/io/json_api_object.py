# Copyright 2024 OpenC3, Inc.
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

import json
from requests import Session
from threading import Lock
from typing import Optional
from openc3.environment import *
from openc3.utilities.authentication import (
    OpenC3Authentication,
    OpenC3KeycloakAuthentication,
)


class JsonApiError(Exception):
    pass


class JsonApiObject:
    """Used to forward all method calls to the remote server object. Before using
    this class ensure the remote service has been started in the server class:

        json = JsonApiObject('127.0.0.1', 7777, self)

    Now the JsonApiObject can be used to call server methods directly:

        server = JsonApiObject('http://openc3-cosmos-cmd-tlm-api:2901', 1.0)
        server.cmd(*args)

    """

    USER_AGENT = "OpenC3 v5 (python/openc3/io/json_api_object)"

    def __init__(
        self,
        url: str,
        timeout: float = 1.0,
        authentication: Optional[OpenC3Authentication] = None,
    ):
        """
        Args:
            url (str): The url of openc3-cosmos-cmd-tlm-api http://openc3-cosmos-cmd-tlm-api:2901
            timeout (float): The time to wait before disconnecting default = 1.0
            authentication (OpenC3Authentication): The authentication object if None initialize will generate default
        """
        self.http = None
        self.mutex = Lock()
        self.request_data = ""
        self.response_data = ""
        self.url: str = url
        self.log = [None, None, None]
        self.authentication = authentication if authentication else self.generate_auth()
        self.timeout: float = timeout
        self.shutdown: bool = False

    @staticmethod
    def generate_auth():
        """generate the auth object"""
        if OPENC3_API_TOKEN is None and OPENC3_API_USER is None:
            return OpenC3Authentication() if OPENC3_API_PASSWORD else None
        else:
            return OpenC3KeycloakAuthentication(OPENC3_KEYCLOAK_URL)

    def request(self, *method_params, **keyword_params):
        """Forwards all method calls to the remote service.
        Args:
            method_params (list) Array of parameters to pass to the method
            keyword_params (dict <Symbol, Variable>) Hash of keyword parameters
        Returns:
            return The result of the method call.
        """
        if self.shutdown:
            raise JsonApiError("Shutdown")
        method = method_params[0]
        endpoint = method_params[1]
        with self.mutex:
            kwargs = self._generate_kwargs(keyword_params)
            self.log = [None, None, None]
            if not self.http:
                self.connect()
            return self._send_request(method, endpoint, kwargs)

    def disconnect(self):
        """Disconnects from http server"""
        if self.http:
            self.http.close()
        self.http = None

    def shutdown(self):
        """Permanently disconnects from the http server"""
        self.shutdown = True
        self.disconnect()

    def connect(self):
        try:
            self.http = Session()
        except Exception as error:
            raise JsonApiError(error)

    def _generate_kwargs(self, keyword_params):
        """NOTE: This is a helper method and should not be called directly"""
        kwargs = {}
        for key, value in keyword_params.items():
            kwargs[key] = value

        kwargs["scope"] = self._generate_scope(kwargs)
        kwargs["headers"] = self._generate_headers(kwargs)
        kwargs["data"] = self._generate_data(kwargs)
        kwargs["query"] = self._generate_query(kwargs)
        kwargs["params"] = kwargs["query"]
        del kwargs["query"]
        del kwargs["scope"]
        return kwargs

    @staticmethod
    def _generate_scope(kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        scope = kwargs.get("scope", None)
        if not scope:
            raise JsonApiError(f"no scope keyword found: {kwargs}")
        elif not isinstance(scope, str):
            raise JsonApiError(f"incorrect type for keyword 'scope' MUST be String: {scope}")
        return scope

    def _generate_headers(self, kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        headers = kwargs.get("headers", None)
        if not headers:
            headers = kwargs["headers"] = {}
        elif not isinstance(headers, dict):
            raise JsonApiError(f"incorrect type for keyword 'headers' MUST be Dictionary: {headers}")

        if "json" in kwargs and kwargs["json"]:
            headers["Content-Type"] = "application/json"
        token = kwargs.get("token", None)
        if self.authentication and not token:
            token = self.authentication.token()
        if token:
            headers["User-Agent"] = self.USER_AGENT
            headers["Authorization"] = token
        else:
            headers["User-Agent"] = self.USER_AGENT
        return headers

    @staticmethod
    def _generate_data(kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        data = kwargs.get("data", None)
        if not data:
            data = kwargs["data"] = {}
        elif not isinstance(data, dict) and not isinstance(data, str):
            raise JsonApiError(f"incorrect type for keyword 'data' MUST be Dictionary or String: {data}")
        if "json" in kwargs and kwargs["json"]:
            return json.dumps(kwargs["data"])
        else:
            return kwargs["data"]

    @staticmethod
    def _generate_query(kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        query = kwargs.get("query", None)
        if query is None:
            query = kwargs["query"] = {}
        elif not isinstance(query, dict):
            raise JsonApiError(f"incorrect type for keyword 'query' MUST be Dictionary: {query}")
        if "scope" in kwargs and kwargs["scope"]:
            kwargs["query"]["scope"] = kwargs["scope"]
        return kwargs["query"]

    def _send_request(self, method, endpoint, kwargs):
        """NOTE: This is a helper method and should not be called directly"""
        try:
            kwargs["url"] = f"{self.url}{endpoint}"
            self.log[0] = f"{method} Request: {kwargs}"
            resp = getattr(self.http, method)(**kwargs)
            self.log[1] = f"{method} Response: {resp.status_code} {resp.headers} {resp.text}"
            self.response_data = resp.text
            return resp
        except Exception as error:
            self.log[2] = f"{method} Exception: {repr(error)}"
            self.disconnect()
            error = f"Api Exception: {self.log[0]} ::: {self.log[1]} ::: {self.log[2]}"
            raise RuntimeError(error)
