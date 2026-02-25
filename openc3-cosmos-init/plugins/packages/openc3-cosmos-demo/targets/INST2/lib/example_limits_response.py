# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.packets.limits_response import LimitsResponse
from openc3.api.cmd_api import cmd


class ExampleLimitsResponse(LimitsResponse):
    def call(self, _packet, item, _old_limits_state):
        match item.limits.state:
            case "RED_HIGH":
                cmd(
                    "<%= target_name %> COLLECT with TYPE NORMAL, DURATION 8",
                    validate=False,
                )
            case "RED_LOW":
                cmd("<%= target_name %> ABORT", validate=False)
