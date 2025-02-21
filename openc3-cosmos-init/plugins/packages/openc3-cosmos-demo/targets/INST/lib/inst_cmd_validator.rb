# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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

require 'openc3/packets/command_validator'

class InstCmdValidator < OpenC3::CommandValidator
  def pre_check(command)
    # Record the current value of CMD_ACPT_CNT for comparison in post_check
    @cmd_acpt_cnt = tlm("<%= target_name %> HEALTH_STATUS CMD_ACPT_CNT")
    @cmd_acpt_cnt ||= 0 # If the telemetry value is nil, set it to 0
    return [true, nil]
  end

  def post_check(command)
    if command.packet_name == 'TIME_OFFSET'
      # Return Failure with a message
      return [false, 'TIME_OFFSET failure description']
    end
    if command.packet_name == 'MEMLOAD'
      # Return Unknown with a message
      return [nil, 'MEMLOAD validation unknown']
    end
    if command.packet_name == 'CLEAR'
      wait_check("<%= target_name %> HEALTH_STATUS CMD_ACPT_CNT == 0", 10)
      # Return Success with a message
      return [true, "CMD_ACPT_CNT cleared"]
    else
      wait_check("<%= target_name %> HEALTH_STATUS CMD_ACPT_CNT > #{@cmd_acpt_cnt}", 10)
      # Return Success without a message
      return [true, nil]
    end
  end
end
