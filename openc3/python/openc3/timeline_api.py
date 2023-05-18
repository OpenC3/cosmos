#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
timeline_api.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

import cosmosc2


def cosmos_timelines():
    """Get the cosmos timeline api.
    Syntax / Example:
        timelines = cosmos_timelines()
    """
    resp = cosmosc2.COSMOS.get(
        "/cosmos-api/timeline", headers={"Accept": "application/json"}
    )
    return resp.json()


def cosmos_timeline_activities(timeline: str):
    """Get the cosmos health api.
    Syntax / Example:
        activities = cosmos_timeline_activities("alpha")
    """
    resp = cosmosc2.COSMOS.get(
        f"/cosmos-api/timeline/{timeline}/activities",
        headers={"Accept": "application/json"},
    )
    return resp.json()


def cosmos_timeline_activity_count(timeline: str):
    """Get the cosmos timeline activity count.
    Syntax / Example:
        count = cosmos_timeline_activity_count("alpha")
    """
    resp = cosmosc2.COSMOS.get(
        f"/cosmos-api/timeline/{timeline}/count", headers={"Accept": "plain/txt"}
    )
    return resp.text
