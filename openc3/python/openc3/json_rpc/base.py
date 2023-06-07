#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
json_rpc/__init__.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

class CosmosJsonRpc(dict):
    """Base class for all JSON Remote Procedure Calls.

    Provides basic comparison and Hash to JSON conversions.
    """

    def __init__(self):
        super().__init__()
        self["jsonrpc"] = "2.0"

    @property
    def id(self):
        return self.get("id")

    @property
    def json_rpc(self):
        return self.get("jsonrpc", "2.0")
