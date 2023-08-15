#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.packets.limits_response import LimitsResponse


class PacketItemLimits:
    """Maintains knowledge of limits for a PacketItem"""

    # Array of all limit states
    LIMITS_STATES = [
        "RED",
        "RED_HIGH",
        "RED_LOW",
        "YELLOW",
        "YELLOW_HIGH",
        "YELLOW_LOW",
        "GREEN",
        "GREEN_HIGH",
        "GREEN_LOW",
        "BLUE",
        "STALE",
        None,
    ]
    # Array of all limit states which should be considered in error
    OUT_OF_LIMITS_STATES = [
        "RED",
        "RED_HIGH",
        "RED_LOW",
        "YELLOW",
        "YELLOW_HIGH",
        "YELLOW_LOW",
    ]

    def __init__(self):
        self.values = None
        self.enabled = False
        self.state = None
        self.response = None
        self.persistence_setting = 1
        self.persistence_count = 0

    @property
    def values(self):
        return self.__values

    @values.setter
    def values(self, values):
        if values is not None:
            if type(values) is not dict:
                raise AttributeError(
                    f"values must be a Hash but is a {values.__class__.__name__}"
                )
            if "DEFAULT" not in values:
                raise AttributeError("values must be a Hash with a 'DEFAULT' key")
            self.__values = values
        else:
            self.__values = None

    @property
    def state(self):
        return self.__state

    @state.setter
    def state(self, state):
        if state not in PacketItemLimits.LIMITS_STATES:
            raise AttributeError(
                f"state must be one of {PacketItemLimits.LIMITS_STATES} but is {state}"
            )
        self.__state = state

    @property
    def response(self):
        return self.__response

    @response.setter
    def response(self, response):
        if response is not None:
            if type(response) is not LimitsResponse:
                raise AttributeError(
                    f"response must be a LimitsResponse but is a {response.__class__.__name__}"
                )
            self.__response = response
        else:
            self.__response = None

    # def persistence_setting=(persistence_setting):
    #   if 0.__class__.__name__ == Integer:
    #     # Ruby version >= 2.4.0
    #     raise AttributeError(f"persistence_setting must be an Integer but is a {persistence_setting.__class__.__name__}" unless Integer === persistence_setting
    #   else:
    #     # Ruby version < 2.4.0
    #     raise AttributeError(f"persistence_setting must be a Fixnum but is a {persistence_setting.__class__.__name__}" unless Fixnum === persistence_setting
    #   self.persistence_setting = persistence_setting

    # def persistence_count=(persistence_count):
    #   if 0.__class__.__name__ == Integer:
    #     # Ruby version >= 2.4.0
    #     raise AttributeError(f"persistence_count must be an Integer but is a {persistence_count.__class__.__name__}" unless Integer === persistence_count
    #   else:
    #     # Ruby version < 2.4.0
    #     raise AttributeError(f"persistence_count must be a Fixnum but is a {persistence_count.__class__.__name__}" unless Fixnum === persistence_count
    #   self.persistence_count = persistence_count

    # # Make a light weight clone of this limits
    # def clone:
    #   limits = super()
    #   limits.values = self.values.clone if self.values:
    #   limits.response = self.response.clone if self.response:
    #   limits
    # alias dup clone

    # def as_json(*a):
    #   hash = {}
    #   hash['values'] = self.values
    #   hash['enabled'] = self.enabled
    #   hash['state'] = self.state
    #   if self.response:
    #     hash['response'] = self.response.to_s
    #   else:
    #     hash['response'] = None
    #   hash['persistence_setting'] = self.persistence_setting
    #   hash['persistence_count'] = self.persistence_count
    #   hash

    # @classmethod
    # def from_json(cls, hash):
    #   limits = PacketItemLimits()
    #   limits.values = hash['values'].transform_keys(&:to_sym) if hash['values']:
    #   limits.enabled = hash['enabled']
    #   limits.state = hash['state'] ? hash['state'].to_sym : None
    #   # Can't recreate a LimitsResponse class
    #   # limits.response = hash['response']
    #   limits.persistence_setting = hash['persistence_setting'] if hash['persistence_setting']:
    #   limits.persistence_count = hash['persistence_count'] if hash['persistence_count']:
    #   limits
