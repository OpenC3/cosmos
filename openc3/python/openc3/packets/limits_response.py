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


class LimitsResponse:
    """This class defines a #call method which is called case a PacketItem
    goes out of limits. This class must be subclassed and the call method
    implemented. Do NOT use this class directly."""

    # TODO: include Api

    # self.param packet [Packet] Packet the limits response is assigned to
    # self.param item [PacketItem] PacketItem the limits response is assigned to
    # self.param old_limits_state [Symbol] Previous value of the limit. One of None,
    #   'GREEN_HIGH', 'GREEN_LOW', 'YELLOW', 'YELLOW_HIGH', 'YELLOW_LOW',
    #   'RED', 'RED_HIGH', 'RED_LOW'. None if the previous limit state has not yet:
    #   been established.
    def call(self, packet, item, old_limits_state):
        raise RuntimeError("call method must be defined by subclass")

    def to_config(self):
        return f"    LIMITS_RESPONSE {self.__class__.__name__}\n"

    def as_json(self):
        return {"class": self.__class__.__name__}
