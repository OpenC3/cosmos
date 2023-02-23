# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

require 'openc3/packets/limits_response'

module OpenC3
  class <%= response_class %> < LimitsResponse
    # @param packet [Packet] Packet the limits response is assigned to
    # @param item [PacketItem] PacketItem the limits response is assigned to
    # @param old_limits_state [Symbol] Previous value of the limit. One of nil,
    #   :GREEN_HIGH, :GREEN_LOW, :YELLOW, :YELLOW_HIGH, :YELLOW_LOW,
    #   :RED, :RED_HIGH, :RED_LOW. nil if the previous limit state has not yet
    #   been established.
    def call(packet, item, old_limits_state)
      # Take action based on the current limits state
      # Delete any of the 'when' lines that do not apply or you don't care about
      case item.limits.state
      when :RED_HIGH
        # Take action like sending a command:
        # cmd('TARGET SAFE')
      when :RED_LOW
      when :YELLOW_LOW
      when :YELLOW_HIGH
      # GREEN limits are only available if a telemetry item has them defined
      # COSMOS refers to these as "operational limits"
      # See https://openc3.com/docs/v5/telemetry#limits
      when :GREEN_LOW
      when :GREEN_HIGH
      # :RED and :YELLOW limits are triggered for STATES with defined RED and YELLOW states
      # See https://openc3.com/docs/v5/telemetry#state
      when :RED
      when :YELLOW
      end
    end
  end
end
