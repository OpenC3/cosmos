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


class RequestError(RuntimeError):
    """
    RequestError

    Parameters:
        message (str): The Request Error from Cosmos v5
        request (openc3.execptions.CosmosJsonRpcRequest): CosmosJsonRpcRequest v5
    """

    def __init__(self, message: str, request):
        super().__init__(message, request)
        self.request = request


class ResponseError(RuntimeError):
    """
    ResponseError

    Parameters:
        request (openc3.execptions.CosmosJsonRpcRequest): CosmosJsonRpcRequest v5
        response (openc3.execptions.CosmosJsonRpcErrorResponse): CosmosJsonRpcErrorResponse v5
    """

    def __init__(self, request, response):
        super().__init__(request, response)
        self.request = request
        self.response = response


class JsonRpc(dict):
    def __init__(self):
        super().__init__()
        self["jsonrpc"] = "2.0"

    @property
    def id(self):
        return self.get("id")

    @property
    def json_rpc(self):
        return self.get("jsonrpc", "2.0")

    def to_json(self):
        return json.dumps(self)


class JsonRpcRequest(JsonRpc):
    """Represents a JSON Remote Procedure Call Request"""

    DANGEROUS_METHODS = ["__send__", "send", "instance_eval", "instance_exec"]

    def __init__(self, id: int, method_name: str, *args, **kwargs):
        """Constructor

        Arguments:
        id_ -- The identifier which will be matched to the response
        method_name -- The name of the method to call
        scope -- The scope
        args -- Array of strings which represent the parameters to send to the method
        kwargs -- Dict of Key, Value parameters to send to the method
        """
        super().__init__()
        self["method"] = method_name
        if args:
            self["params"] = args
        if kwargs:
            self["keyword_params"] = kwargs  # {**{"scope": scope}, **kwargs}
        self["id"] = int(id)

    @property
    def method(self):
        """Returns the method to call"""
        return self["method"]

    @property
    def params(self):
        """Returns the array of strings which represent the parameters to send to the method"""
        return self.get("params")

    @property
    def keyword_params(self):
        """Returns a dictionary of strings which represent the keyword parameters to send to the method"""
        return self.get("keyword_params")

    def to_hash(self):
        """Returns the request in a string"""
        return _convert_bytearray_to_string_raw(self)

    @classmethod
    def from_json(cls, request_data, request_headers):
        """Creates and returns a JsonRpcRequest object from a JSON encoded String.
        The version must be 2.0 and the JSON must include the method and id members.

        Parameters:
        request_data -- JSON encoded string representing the request
        request_headers -- Request header to include the auth token
        """
        msg = "invaid json-rpc 2.0 request"
        try:
            hash = json.loads(request_data)
            if request_headers.get("HTTP_AUTHORIZATION"):
                hash["keyword_params"]["token"] = request_headers["HTTP_AUTHORIZATION"]
            # Verify the jsonrpc version is correct and there is a method and id
            if hash["jsonrpc"] != "2.0" or not hash["method"] or not hash["id"]:
                raise ValueError("message jsonrpc version: {}".format(hash["jsonrpc"]))
            return cls.from_hash(hash)
        except (ValueError, KeyError) as e:
            raise RequestError(msg, request_data) from e
        except Exception as e:
            raise RuntimeError(msg) from e

    @classmethod
    def from_hash(cls, hash):
        """Creates a JsonRpcRequest object from a Hash

        Parameters:
        hash -- Hash containing the following keys: method, params, id, and keyword_params
        """
        return cls(
            hash["id"],
            hash["method"],
            *hash.get("params", []),
            **hash.get("keyword_params", {}),
        )


class JsonRpcResponse(JsonRpc):
    """Represents a JSON Remote Procedure Call Response"""

    def __init__(self, id):
        """Constructor

        Parameters:
        id_ -- The identifier which will be matched to the request
        """
        super().__init__()
        self["id"] = id

    @classmethod
    def from_json(cls, response_data):
        """Creates a JsonRpcResponse object from a JSON encoded String.

        The version must be 2.0 and the JSON must include the id members. It
        must also include either result for success or error for failure but
        never both.

        Parameters:
        response_data -- JSON encoded string representing the response
        """

        msg = f"invalid json-rpc 2.0 response{response_data}\n"
        if type(response_data) == str:
            try:
                return json.loads(response_data)  # .decode("latin-1"))
            except Exception as e:
                raise RuntimeError(msg, response_data) from e

    @classmethod
    def from_hash(cls, hash):
        # Verify the jsonrpc version is correct and there is an ID
        if hash.get("jsonrpc", None) != "2.0" or "id" not in hash:
            raise RuntimeError(f"invalid json-rpc 2.0 response:{hash}")

        if "result" in hash:
            if "error" in hash:
                raise RuntimeError(f"invalid json-rpc 2.0 response:{hash}")
            return JsonRpcSuccessResponse.from_hash(hash)
        elif "error" in hash:
            return JsonRpcErrorResponse.from_hash(hash)
        else:
            raise RuntimeError(f"invalid json-rpc 2.0 response:{hash}")


class JsonRpcSuccessResponse(JsonRpcResponse):
    """Represents a JSON Remote Procedure Call Success Response"""

    def __init__(self, id, result):
        """Constructor

        Parameters:
        id_ -- The identifier which will be matched to the request
        result -- The result of the request
        """
        super().__init__(id)
        result = convert_json_class(result)
        self["result"] = result

    @property
    def result(self):
        """Return the result of the method request"""
        return self["result"]

    @classmethod
    def from_hash(cls, hash):
        """Creates a JsonRpcSuccessResponse object from a Hash

        Parameters
        hash_ -- Hash containing the following keys: result and id
        """
        return cls(hash["id"], hash["result"])


class JsonRpcErrorResponse(JsonRpcResponse):
    """Represents a JSON Remote Procedure Call Error Response"""

    def __init__(self, id, error):
        """Constructor

        Parameters:
        id -- The identifier which will be matched to the request
        error -- The error object
        """
        super().__init__(id)
        self["error"] = JsonRpcError.from_hash(error)

    @property
    def error(self):
        """Returns the error object"""
        return self["error"]

    @classmethod
    def from_hash(cls, hash):
        """Creates a JsonRpcErrorResponse object from a Hash

        Parameters:
        hash -- Hash containing the following keys: error and id
        """
        return cls(hash["id"], hash["error"])


class JsonRpcError(dict):
    """Represents a JSON Remote Procedure Call Error"""

    def __init__(self, code, message, data=None):
        """Constructor

        Parameters:
        code -- The error type that occurred
        message -- A short description of the error
        data -- Additional information about the error
        """
        super().__init__()
        self["code"] = code
        self["message"] = message
        self["data"] = data

    @property
    def code(self):
        """Returns the error type that occurred"""
        return self.get("code")

    @property
    def message(self):
        """Returns a short description of the error"""
        return self.get("message")

    @property
    def data(self):
        """Returns additional information about the error"""
        return self.get("data")

    @classmethod
    def from_hash(cls, hash):
        """Creates a JsonRpcError object from a Hash

        Parameters:
        hash -- Hash containing the following keys: code, message, and optionally data
        """
        try:
            code = int(hash["code"])
            return cls(code, hash["message"], hash["data"])
        except ValueError as err:
            error = "Invalid JSON-RPC 2.0"
            raise RuntimeError("{} {}: {}".format(error, type(err), err)) from err


def convert_json_class(object_):
    if isinstance(object_, dict):
        try:
            json_class = object_["json_class"]
            raw = object_["raw"]
            if json_class == "Float":
                if raw == "Infinity":
                    return float("inf")
                elif raw == "-Infinity":
                    return -float("inf")
                elif raw == "NaN":
                    return float("nan")
                return raw
            return bytearray(raw)
        except Exception:
            for key, value in object_.items():
                object_[key] = convert_json_class(value)
            return object_
    elif isinstance(object_, (tuple, list)):
        object_ = list(object_)
        index = 0
        for value in object_:
            object_[index] = convert_json_class(value)
            index += 1
        return object_
    else:
        return object_


def _convert_bytearray_to_string_raw(object_):
    if isinstance(object_, (bytes, bytearray)):
        return object_.decode("latin-1")
    if isinstance(object_, dict):
        for key, value in object_.items():
            object_[key] = _convert_bytearray_to_string_raw(value)
        return object_
    if isinstance(object_, (tuple, list)):
        object_ = list(object_)
        index = 0
        for value in object_:
            object_[index] = _convert_bytearray_to_string_raw(value)
            index += 1
        return object_
    return object_
