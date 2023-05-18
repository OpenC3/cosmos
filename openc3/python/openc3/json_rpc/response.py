#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
json_rpc/response.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

import json

from cosmosc2.environment import JSON_RPC_VERSION
from cosmosc2.exceptions import CosmosError
from cosmosc2.json_rpc.base import CosmosJsonRpc
from cosmosc2.json_rpc.error import CosmosJsonRpcError


class CosmosJsonRpcResponse(CosmosJsonRpc):
    """Represents a JSON Remote Procedure Call Response"""

    def __init__(self, id_):
        """Constructor

        Parameters:
        id_ -- The identifier which will be matched to the request
        """
        super().__init__()
        self["id"] = id_

    @classmethod
    def from_bytes(cls, response_data: bytes):
        """Creates a JsonRpcResponse object from a JSON encoded String.

        The version must be 2.0 and the JSON must include the id members. It
        must also include either result for success or error for failure but
        never both.

        Parameters:
        response_data -- JSON encoded string representing the response
        """

        msg = "invalid json-rpc {} response".format(JSON_RPC_VERSION)
        try:
            hash_ = json.loads(response_data.decode("latin-1"))
        except Exception as e:
            raise CosmosError(msg, response_data) from e

            # Verify the jsonrpc version is correct and there is an ID
        if hash_.get("jsonrpc") != JSON_RPC_VERSION:
            raise CosmosError(msg, response_data)

        try:
            return CosmosJsonRpcErrorResponse.from_hash(hash_)
        except KeyError:
            pass

        try:
            return CosmosJsonRpcSuccessResponse.from_hash(hash_)
        except KeyError:
            pass

        raise CosmosError(msg, response_data)


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


class CosmosJsonRpcSuccessResponse(CosmosJsonRpcResponse):
    """Represents a JSON Remote Procedure Call Success Response"""

    def __init__(self, id_, result):
        """Constructor

        Parameters:
        id_ -- The identifier which will be matched to the request
        result -- The result of the request
        """
        super().__init__(id_)
        result = convert_json_class(result)
        self["result"] = result

    @property
    def result(self):
        """Return the result of the method request"""
        return self["result"]

    @classmethod
    def from_hash(cls, hash_):
        """Creates a JsonRpcSuccessResponse object from a Hash

        Parameters
        hash_ -- Hash containing the following keys: result and id
        """
        return cls(hash_["id"], hash_["result"])


class CosmosJsonRpcErrorResponse(CosmosJsonRpcResponse):
    """Represents a JSON Remote Procedure Call Error Response"""

    def __init__(self, id_, error):
        """Constructor

        Parameters:
        id -- The identifier which will be matched to the request
        error -- The error object
        """
        super().__init__(id_)
        self["error"] = CosmosJsonRpcError.from_hash(error)

    @property
    def error(self):
        """Returns the error object"""
        return self["error"]

    @classmethod
    def from_hash(cls, hash_):
        """Creates a JsonRpcErrorResponse object from a Hash

        Parameters:
        hash -- Hash containing the following keys: error and id
        """
        return cls(hash_["id"], hash_["error"])
