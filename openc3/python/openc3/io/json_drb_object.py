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
from openc3.io.json_api_object import JsonApiObject, JsonApiError
from .json_rpc import (
    JsonRpcRequest,
    JsonRpcResponse,
    JsonRpcSuccessResponse,
    JsonRpcErrorResponse,
)
from openc3.top_level import HazardousError, CriticalCmdError, DisabledError  # noqa: F401


class JsonDrbUnknownError(Exception):
    pass


# The Ruby side implements from_hash directly on Exception but Python says:
# TypeError: cannot set 'from_hash' attribute of immutable typ 'Exception'
# So we implement it on our custom Exception


class JsonDRbError(JsonApiError):
    @classmethod
    def from_hash(cls, hash):
        # Hash contains class, message, backtrace, and instance_variables
        error_class = None
        try:
            error_class = globals()[hash["class"]]
        except KeyError:
            error_class = RuntimeError
            if "message" not in hash and "class" in hash:
                hash["message"] = hash["class"]
        error = None
        if error_class is RuntimeError and "message" in hash:
            error = error_class(hash["message"])
        else:
            error = error_class()
        if "instance_variables" in hash:
            for name, value in hash["instance_variables"].items():
                # Backend is Ruby so remove '@' from instance_variables
                setattr(error, name[1:], value)
        return error


# Used to forward all method calls to the remote server object. Before using
# this class ensure the remote service has been started in the server class:
#
#   json = JsonDrb.new
#   json.start_service('127.0.0.1', 7777, self)
#
# Now the JsonDRbObject can be used to call server methods directly:
#
#   server = JsonDRbObject('http://openc3-cosmos-cmd-tlm-api:2901', 1.0)
#   server.cmd(*args)
#
class JsonDRbObject(JsonApiObject):
    USER_AGENT = "OpenC3 / v5 (ruby/openc3/lib/io/json_drb_object)"

    # @param url [String] The url of openc3-cosmos-cmd-tlm-api http://openc3-cosmos-cmd-tlm-api:2901
    # @param timeout [Float] The time to wait before disconnecting 1.0
    # @param authentication [OpenC3Authentication] The authentication object if Nonel initialize will generate
    def __init__(self, url, timeout=1.0, authentication=None):
        super().__init__(url, timeout, authentication)
        self.uri = f"{url}/openc3-api/api"

    # Forwards all method calls to the remote service.
    #
    # @param method_name [Symbol] Name of the method to call
    # @param method_params [Array] Array of parameters to pass to the method
    # @param keyword_params [Hash<Symbol, Variable>] Hash of keyword parameters
    # @return The result of the method call. If the method raises an exception
    #   the same exception is also raised. If something goes wrong with the
    #   protocol a JsonDRbError exception is raised.
    def __getattr__(self, func):
        if self.shutdown:
            raise JsonDRbError("Shutdown")

        def method(*args, **kwargs):
            with self.mutex:
                self.log = [None, None, None]
                if not self.http:
                    self.connect()
                json_rpc_request = JsonRpcRequest(0, func, *args, **kwargs)
                token = kwargs.get("token", None)
                response_body = self.make_request(json_rpc_request, token)
                if not response_body:
                    self.disconnect()
                    error = f"No response from server: {self.log[0]} ::: {self.log[1]} ::: {self.log[2]}"
                    raise JsonDRbError(error)
                else:
                    response = JsonRpcResponse.from_hash(response_body)
                    return self.handle_response(response)

        return method

    def make_request(self, request, token=None):
        if self.authentication and not token:
            token = self.authentication.token()
        if token:
            headers = {
                "User-Agent": self.USER_AGENT,
                "Content-Type": "application/json-rpc",
                "Authorization": token,
            }
        else:
            headers = {
                "User-Agent": self.USER_AGENT,
                "Content-Type": "application/json-rpc",
            }
        try:
            request_kwargs = {
                "url": self.uri,
                "data": json.dumps(request.to_hash()),
                "headers": headers,
            }
            self.log[0] = f"Request: {request_kwargs}"
            # print(self.log[0])
            resp = self.http.post(**request_kwargs)
            self.log[1] = f"Response: {resp.status_code} {resp.headers} {resp.text}"
            # print(self.log[1])
            self.response_data = resp.json()
            return resp.json()
        except Exception as e:  # Typically JSONDecodeError when error in resp.json()
            self.log[2] = f"Exception: {repr(e)}"
            return None

    def handle_response(self, response: JsonRpcSuccessResponse | JsonRpcErrorResponse):
        # The code below will always either raise or return breaking out of the loop
        if isinstance(response, JsonRpcErrorResponse):
            if response.error.data:
                error = JsonDRbError.from_hash(response.error.data)
                raise error
            else:
                raise RuntimeError(f"JsonDRb Error ({response})")
        else:
            return response.result
