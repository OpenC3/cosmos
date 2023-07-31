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

from .structure import Structure


class Packet(Structure):
    RESERVED_ITEM_NAMES = [
        "PACKET_TIMESECONDS",
        "PACKET_TIMEFORMATTED",
        "RECEIVED_TIMESECONDS",
        "RECEIVED_TIMEFORMATTED",
        "RECEIVED_COUNT",
    ]

    # TODO: item_class
    def __init__(
        self,
        target_name=None,
        packet_name=None,
        default_endianness="BIG_ENDIAN",
        description=None,
        buffer=None,
    ):
        # TODO: super to structure
        self.default_endianness = default_endianness

        self.target_name = target_name
        self.packet_name = packet_name
        self.description = description
        self.received_time = None
        self.received_count = 0
        self.id_items = None
        self.hazardous = False
        self.hazardous_description = None
        self.given_values = None
        self.limits_items = None
        self.processors = None
        self.limits_change_callback = None
        self.read_conversion_cache = None
        self.raw = None
        self.messages_disabled = False
        self.meta = None
        self.hidden = False
        self.disabled = False
        self.stored = False
        self.extra = None
        self.cmd_or_tlm = None
        self.template = None

    def as_json(self):
        config = {}
        config["target_name"] = self.target_name
        config["packet_name"] = self.packet_name
        config["endianness"] = self.default_endianness
        config["description"] = self.description
        # if self.short_buffer_allowed:
        #     config["short_buffer_allowed"] = True
        if self.hazardous:
            config["hazardous"] = True
        if self.hazardous_description:
            config["hazardous_description"] = self.hazardous_description
        if self.messages_disabled:
            config["messages_disabled"] = True
        if self.disabled:
            config["disabled"] = True
        if self.hidden:
            config["hidden"] = True
        # config["accessor"] = self.accessor
        # if self.template:
        #     config["template"] = Base64.encode64(self.template)

        # if self.processors:
        #     processors = []
        #     config["processors"] = processors
        #     for _, processor in self.processors():
        #         processors << processor.as_json(*a)

        if self.meta:
            config["meta"] = self.meta

        items = []
        config["items"] = items
        # Items with derived items last
        # for item in self.sorted_items():
        #     if item.data_type != "DERIVED":
        #         items << item.as_json(*a)

        # for item in self.sorted_items():
        #     if item.data_type == "DERIVED":
        #         items << item.as_json(*a)

        return config
