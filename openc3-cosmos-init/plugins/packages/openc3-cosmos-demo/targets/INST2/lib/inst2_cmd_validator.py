# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.packets.command_validator import CommandValidator
from openc3.api import *


class Inst2CmdValidator(CommandValidator):
    def pre_check(self, command):
        # Record the current value of CMD_ACPT_CNT for comparison in post_check
        self.cmd_acpt_cnt = tlm("<%= target_name %> HEALTH_STATUS CMD_ACPT_CNT")
        return [True, None]

    def post_check(self, command):
        if command.packet_name == "TIME_OFFSET":
            # Return Failure with a message
            return [False, "TIME_OFFSET failure description"]
        if command.packet_name == "MEMLOAD":
            # Return Unknown with a message
            return [None, "MEMLOAD validation unknown"]
        if command.packet_name == "CLEAR":
            wait_check("<%= target_name %> HEALTH_STATUS CMD_ACPT_CNT == 0", 10)
            # Return Success with a message
            return [True, "CMD_ACPT_CNT cleared"]
        else:
            wait_check(
                f"<%= target_name %> HEALTH_STATUS CMD_ACPT_CNT > {self.cmd_acpt_cnt}",
                10,
            )
            # Return Success without a message
            return [True, None]
