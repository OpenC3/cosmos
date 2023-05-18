#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
json_rpc/request.py
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
from cosmosc2.exceptions import CosmosRequestError
from cosmosc2.json_rpc.base import CosmosJsonRpc


class CosmosJsonRpcRequest(CosmosJsonRpc):
    """Represents a JSON Remote Procedure Call Request"""

    DANGEROUS_METHODS = ["__send__", "send", "instance_eval", "instance_exec"]

    def __init__(self, id_: int, method_name: str, scope: str, *args, **kwargs):
        """Constructor

        Arguments:
        id_ -- The identifier which will be matched to the response
        method_name -- The name of the method to call
        scope -- The scope
        args -- Array of strings which represent the parameters to send to the method
        kwargs -- Dict of Key, Value parameters to send to the method
        """
        super().__init__()
        self["method"] = str(method_name)
        self["params"] = args
        self["keyword_params"] = {**{"scope": scope}, **kwargs}
        self["id"] = int(id_)

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

    @property
    def id(self):
        """Returns the request identifier"""
        return self["id"]

    def to_hash(self):
        """Returns the request in a string"""
        return _convert_bytearray_to_string_raw(self)

    @classmethod
    def from_json(cls, request_data):
        """Creates and returns a JsonRpcRequest object from a JSON encoded String.

        The version must be 2.0 and the JSON must include the method and id members.

        Parameters:
        request_data -- JSON encoded string representing the request
        """
        msg = "invaid json-rpc {} request".format(JSON_RPC_VERSION)
        try:
            hash_ = json.loads(request_data)
            # Verify the jsonrpc version is correct and there is a method and id
            if hash_["jsonrpc"] != JSON_RPC_VERSION:
                raise ValueError("message jsonrpc version: {}".format(hash_["jsonrpc"]))
            return cls.from_hash(hash_)
        except (ValueError, KeyError) as e:
            raise CosmosRequestError(msg, request_data) from e
        except Exception as e:
            raise RuntimeError(msg) from e

    @classmethod
    def from_hash(cls, hash_):
        """Creates a JsonRpcRequest object from a Hash

        Parameters:
        hash_ -- Hash containing the following keys: method, params, id, and keyword_params
        """
        return cls(
            hash_["id"],
            hash_["method"],
            hash_.get("keyword_params", {}).get("scope"),
            *hash_.get("params", []),
        )


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
