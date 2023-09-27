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

import json
from requests import Session
from threading import Lock
from openc3.environment import *
from openc3.utilities.authentication import (
    OpenC3Authentication,
    OpenC3KeycloakAuthentication,
)


class JsonApiError(Exception):
    pass


# Used to forward all method calls to the remote server object. Before using
# this class ensure the remote service has been started in the server class:
#
#   json = JsonDrb.new
#   json.start_service('127.0.0.1', 7777, self)
#
# Now the JsonApiObject can be used to call server methods directly:
#
#   server = JsonApiObject('http://openc3-cosmos-cmd-tlm-api:2901', 1.0)
#   server.cmd(*args)
#
class JsonApiObject:
    # attr_reader :request_data
    # attr_reader :response_data

    USER_AGENT = "OpenC3 / v5 (ruby/openc3/lib/io/json_api_object)"

    # @param url [String] The url of openc3-cosmos-cmd-tlm-api http://openc3-cosmos-cmd-tlm-api:2901
    # @param timeout [Float] The time to wait before disconnecting 1.0
    # @param authentication [OpenC3Authentication] The authentication object if Nonel initialize will generate
    def __init__(self, url, timeout=1.0, authentication=None):
        self.http = None
        self.mutex = Lock()
        self.request_data = ""
        self.response_data = ""
        self.url = url
        self.log = [None, None, None]
        if authentication:
            self.authentication = authentication
        else:
            self.authentication = self.generate_auth()
        self.timeout = timeout
        self.shutdown = False

    # generate the auth object
    def generate_auth(self):
        if OPENC3_API_TOKEN is None and OPENC3_API_USER is None:
            if OPENC3_API_PASSWORD:
                return OpenC3Authentication()
            else:
                return None
        else:
            return OpenC3KeycloakAuthentication(OPENC3_KEYCLOAK_URL)

    # Forwards all method calls to the remote service.
    #
    # @param method_params [Array] Array of parameters to pass to the method
    # @param keyword_params [Hash<Symbol, Variable>] Hash of keyword parameters
    # @return The result of the method call.
    def request(self, *method_params, **keyword_params):
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

    # Disconnects from http server
    def disconnect(self):
        if self.http:
            self.http.close()
        self.http = None

    # Permanently disconnects from the http server
    def shutdown(self):
        self.shutdown = True
        self.disconnect()

    def connect(self):
        try:
            self.http = Session()
        except Exception as error:
            raise JsonApiError(error)

    # NOTE: This is a helper method and should not be called directly
    def _generate_kwargs(self, keyword_params):
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

    # NOTE: This is a helper method and should not be called directly
    def _generate_scope(self, kwargs):
        scope = kwargs.get("scope", None)
        if not scope:
            raise JsonApiError(f"no scope keyword found: {kwargs}")
        elif type(scope) != str:
            raise JsonApiError(
                f"incorrect type for keyword 'scope' MUST be String: {scope}"
            )
        return scope

    # NOTE: This is a helper method and should not be called directly
    def _generate_headers(self, kwargs):
        headers = kwargs.get("headers", None)
        if not headers:
            headers = kwargs["headers"] = {}
        elif type(headers) != dict:
            raise JsonApiError(
                f"incorrect type for keyword 'headers' MUST be Dictionary: {headers}"
            )

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

    # NOTE: This is a helper method and should not be called directly
    def _generate_data(self, kwargs):
        data = kwargs.get("data", None)
        if not data:
            data = kwargs["data"] = {}
        elif type(data) != dict and type(data) != str:
            raise JsonApiError(
                f"incorrect type for keyword 'data' MUST be Dictionary or String: {data}"
            )
        if "json" in kwargs and kwargs["json"]:
            return json.dumps(kwargs["data"])
        else:
            return kwargs["data"]

    # NOTE: This is a helper method and should not be called directly
    def _generate_query(self, kwargs):
        query = kwargs.get("query", None)
        if not query:
            query = kwargs["query"] = {}
        elif type(query) != dict:
            raise JsonApiError(
                f"incorrect type for keyword 'query' MUST be Dictionary: {query}"
            )
        if "scope" in kwargs and kwargs["scope"]:
            kwargs["query"]["scope"] = kwargs["scope"]
        return kwargs["query"]

    # NOTE: This is a helper method and should not be called directly
    def _send_request(self, method, endpoint, kwargs):
        try:
            kwargs["url"] = f"{self.url}{endpoint}"
            self.log[0] = f"{method} Request: {kwargs}"
            resp = getattr(self.http, method)(**kwargs)
            self.log[
                1
            ] = f"{method} Response: {resp.status_code} {resp.headers} {resp.text}"
            self.response_data = resp.text
            return resp
        except Exception as error:
            self.log[2] = f"{method} Exception: {repr(error)}"
            self.disconnect()
            error = f"Api Exception: {self.log[0]} ::: {self.log[1]} ::: {self.log[2]}"
            raise error
