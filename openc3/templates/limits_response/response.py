from openc3.packets.limits_response import LimitsResponse
from openc3.api import *


class <%= response_class %>(LimitsResponse):
    # @param packet [Packet] Packet the limits response is assigned to
    # @param item [PacketItem] PacketItem the limits response is assigned to
    # @param old_limits_state [Symbol] Previous value of the limit. One of nil,
    #   "GREEN_HIGH", "GREEN_LOW", "YELLOW", "YELLOW_HIGH", "YELLOW_LOW",
    #   "RED", "RED_HIGH", "RED_LOW". nil if the previous limit state has not yet
    #   been established.
    def call(self, packet, item, old_limits_state):
        # Take action based on the current limits state
        # Delete any of the case lines that do not apply or you don't care about
        match item.limits.state:
            case "RED_HIGH":
                # Take action like sending a command:
                # cmd("TARGET SAFE")
                pass
            case "RED_LOW":
                pass
            case "YELLOW_LOW":
                pass
            case "YELLOW_HIGH":
                pass
            # GREEN limits are only available if a telemetry item has them defined
            # COSMOS refers to these as "operational limits"
            # See https://docs.openc3.com/docs/configuration/telemetry#limits
            case "GREEN_LOW":
                pass
            case "GREEN_HIGH":
                pass
            # :RED and :YELLOW limits are triggered for STATES with defined RED and YELLOW states
            # See https://docs.openc3.com/docs/configuration/telemetry#state
            case "RED":
                pass
            case "YELLOW":
                pass
