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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.packets.limits_response import LimitsResponse
from openc3.api.cmd_api import cmd, cmd_no_hazardous_check


class ExampleLimitsResponse(LimitsResponse):
    def call(self, packet, item, old_limits_state):
        match item.limits.state:
            case "RED_HIGH":
                cmd("<%= target_name %>", "COLLECT", {"TYPE": "NORMAL", "DURATION": 5})
            case "RED_LOW":
                cmd_no_hazardous_check("<%= target_name %>", "CLEAR")
