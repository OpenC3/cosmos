#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
json_rpc/error.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

from cosmosc2.environment import JSON_RPC_VERSION


class CosmosJsonRpcError(dict):
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
    def from_hash(cls, hash_):
        """Creates a JsonRpcError object from a Hash

        Parameters:
        hash -- Hash containing the following keys: code, message, and optionally data
        """
        try:
            code = int(hash_["code"])
            return cls(code, hash_["message"], hash_["data"])
        except ValueError as err:
            error = "Invalid JSON-RPC {}".format(JSON_RPC_VERSION)
            raise RuntimeError("{} {}: {}".format(error, type(err), err)) from err
