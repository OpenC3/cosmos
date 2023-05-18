#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
limits.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

import cosmosc2


def get_out_of_limits():
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("get_out_of_limits")


def get_overall_limits_state(ignored_items=None):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("get_overall_limits_state", ignored_items)


def limits_enabled(*args):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("limits_enabled?", *args)


def enable_limits(*args):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("enable_limits", *args)


def disable_limits(*args):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("disable_limits", *args)


def get_stale(with_limits_only=False, target_name=None):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("get_stale", with_limits_only, target_name)


def get_limits(target_name, packet_name, item_name, limits_set=None):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request(
        "get_limits", target_name, packet_name, item_name, limits_set
    )


def set_limits(
    target_name,
    packet_name,
    item_name,
    red_low,
    yellow_low,
    yellow_high,
    red_high,
    green_low=None,
    green_high=None,
    limits_set="CUSTOM",
    persistence=None,
    enabled=True,
):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request(
        "set_limits",
        target_name,
        packet_name,
        item_name,
        red_low,
        yellow_low,
        yellow_high,
        red_high,
        green_low,
        green_high,
        limits_set,
        persistence,
        enabled,
    )


def get_limits_groups():
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("get_limits_groups")


def enable_limits_group(group_name):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("enable_limits_group", group_name)


def disable_limits_group(group_name):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("disable_limits_group", group_name)


def get_limits_sets():
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("get_limits_sets")


def get_current_limits_set():
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("get_current_limits_set")


def set_limits_set(limits_set):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("set_limits_set", limits_set)


def get_limits_set():
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("get_limits_set")


def subscribe_limits_events(queue_size=1000):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("subscribe_limits_events", queue_size)


def unsubscribe_limits_events(id_):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("unsubscribe_limits_events", id_)


def get_limits_event(id_, non_block=False):
    """
    TODO
    """
    return cosmosc2.COSMOS.json_rpc_request("get_limits_event", id_, non_block)
