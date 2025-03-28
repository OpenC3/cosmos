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
            if not isinstance(values, dict):
                raise TypeError(f"values must be a Hash but is a {values.__class__.__name__}")
            if "DEFAULT" not in values:
                raise ValueError("values must be a Hash with a 'DEFAULT' key")
            self.__values = values
        else:
            self.__values = None

    @property
    def state(self):
        return self.__state

    @state.setter
    def state(self, state):
        if state not in PacketItemLimits.LIMITS_STATES:
            raise ValueError(f"state must be one of {PacketItemLimits.LIMITS_STATES} but is {state}")
        self.__state = state

    @property
    def response(self):
        return self.__response

    @response.setter
    def response(self, response):
        if response is not None:
            if "LimitsResponse" not in response.__class__.__name__:
                raise TypeError(f"response must be a LimitsResponse but is a {response.__class__.__name__}")
            self.__response = response
        else:
            self.__response = None

    def as_json(self):
        limits = {}
        limits['values'] = self.__values
        limits['enabled'] = self.enabled
        limits['state'] = self.__state
        if self.__response:
            limits['response'] = str(self.__response)
        else:
            limits['response'] = None
        limits['persistence_setting'] = self.persistence_setting
        limits['persistence_count'] = self.persistence_count
        return limits
