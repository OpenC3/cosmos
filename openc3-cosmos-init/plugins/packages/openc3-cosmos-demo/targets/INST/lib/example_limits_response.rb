# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# This file implements a class to handle responses to limits state changes.

require 'openc3/packets/limits_response'

class ExampleLimitsResponse < OpenC3::LimitsResponse
  def call(packet, item, old_limits_state)
    case item.limits.state
    when :RED_HIGH
      cmd('<%= target_name %> COLLECT with TYPE NORMAL, DURATION 7', validate: false)
    when :RED_LOW
      cmd('<%= target_name %> ABORT', validate: false)
    end
  end
end
