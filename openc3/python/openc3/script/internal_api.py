#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
internal_api.py
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

import openc3.script


def cosmos_status():
    """Get the cosmos status api.
    Syntax / Example:
        status = cosmos_status()
    """
    resp = openc3.script.API_SERVER.get(
        "/openc3-api/internal/status", headers={"Accept": "application/json"}
    )
    return resp.json()


def cosmos_health():
    """Get the cosmos health api.
    Syntax / Example:
        health = cosmos_health()
    """
    resp = openc3.script.API_SERVER.get(
        "/openc3-api/internal/health", headers={"Accept": "application/json"}
    )
    return resp.json()


def cosmos_metrics():
    """Get the cosmos metrics api.
    Syntax / Example:
        metrics = cosmos_metrics()
    """
    resp = openc3.script.API_SERVER.get(
        "/openc3-api/internal/metrics", headers={"Accept": "plain/txt"}
    )
    return resp.text
