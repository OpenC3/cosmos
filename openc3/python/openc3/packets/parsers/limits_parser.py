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

from openc3.utilities.logger import Logger


class LimitsParser:
    # self.param parser [ConfigParser] Configuration parser
    # self.param packet [Packet] The current packet
    # self.param cmd_or_tlm [String] Whether this is a command or telemetry packet
    # self.param item [PacketItem] The packet item to create limits on
    # self.param warnings [Array<String>] Array of string warnings which will be
    #   appended with any warnings found case parsing the limits:
    @classmethod
    def parse(cls, parser, packet, cmd_or_tlm, item, warnings):
        if item.states:
            raise parser.error("Items with STATE can't define LIMITS")

        parser = LimitsParser(parser)
        parser.verify_parameters(cmd_or_tlm)
        return parser.create_limits(packet, item, warnings)

    def __init__(self, parser):
        self.parser = parser

    # self.param cmd_or_tlm [String] Whether this is a command or telemetry packet
    def verify_parameters(self, cmd_or_tlm):
        if cmd_or_tlm == "Command":
            raise self.parser.error("LIMITS only applies to telemetry items")

        self.usage = "LIMITS <LIMITS SET> <PERSISTENCE> <ENABLED/DISABLED> <RED LOW LIMIT> <YELLOW LOW LIMIT> <YELLOW HIGH LIMIT> <RED HIGH LIMIT> <GREEN LOW LIMIT (Optional)> <GREEN HIGH LIMIT (Optional)>"
        self.parser.verify_num_parameters(7, 9, self.usage)

    # self.param packet [Packet] The packet the item should be added to
    def create_limits(self, packet, item, warnings):
        limits_set = self._get_limits_set()
        self._initialize_limits_values(packet, item)
        self._ensure_consistency_with_default(packet, item, warnings)

        item.limits.values[limits_set] = self._get_values()
        item.limits.enabled = self._get_enabled()
        item.limits.persistence_setting = self._get_persistence()
        item.limits.persistence_count = 0

        packet.update_limits_items_cache(item)
        return limits_set

    def _initialize_limits_values(self, packet, item):
        limits_set = self._get_limits_set()
        # Values must be initialized with a 'DEFAULT' key
        if item.limits.values is None:
            if limits_set == "DEFAULT":
                item.limits.values = {"DEFAULT": []}
            else:
                raise self.parser.error(
                    f"DEFAULT limits set must be defined for {packet.target_name} {packet.packet_name} {item.name} before setting limits set {limits_set}"
                )

    def _ensure_consistency_with_default(self, packet, item, warnings):
        # Nothing to do if we're already 'DEFAULT':
        if self._get_limits_set() == "DEFAULT":
            return

        msg = f"TELEMETRY Item {packet.target_name} {packet.packet_name} {item.name} {self._get_limits_set()} limits _TYPE_ setting conflict with DEFAULT"
        # XOR our setting with the items current setting
        # If it returns True then we have a mismatch and log the error
        if self._get_enabled() ^ item.limits.enabled:
            warnings.append(msg.replace("_TYPE_", "enable"))
            Logger.warn(warnings[-1])
        if item.limits.persistence_setting != self._get_persistence():
            warnings.append(msg.replace("_TYPE_", "persistence"))
            Logger.warn(warnings[-1])

    def _get_limits_set(self):
        return self.parser.parameters[0].upper()

    def _get_persistence(self):
        try:
            return int(self.parser.parameters[1])
        except ValueError as error:
            raise self.parser.error("Persistence must be an integer.", self.usage) from error

    def _get_enabled(self):
        enabled = self.parser.parameters[2].upper()
        if enabled != "ENABLED" and enabled != "DISABLED":
            raise self.parser.error("Initial LIMITS state must be ENABLED or DISABLED.", self.usage)
        if enabled == "ENABLED":
            return True
        else:
            return False

    def _get_values(self):
        values = self._get_red_yellow_values()
        return values + self._get_green_values(values[1], values[2])

    def _get_red_yellow_values(self):
        params = self.parser.parameters
        err = None
        try:
            err = "red low"
            red_low = float(params[3])
            err = "yellow low"
            yellow_low = float(params[4])
            err = "yellow high"
            yellow_high = float(params[5])
            err = "red high"
            red_high = float(params[6])
        except ValueError as error:
            raise self.parser.error(
                f"Invalid {err} limit value. Limits can be integers or floats.",
                self.usage,
            ) from error

        # Verify valid limits are specified
        if (red_low > yellow_low) or (yellow_low >= yellow_high) or (yellow_high > red_high):
            raise self.parser.error(
                "Invalid limits specified. Ensure yellow limits are within red limits.",
                self.usage,
            )

        return [red_low, yellow_low, yellow_high, red_high]

    def _get_green_values(self, yellow_low, yellow_high):
        params = self.parser.parameters
        # Since our initial parameter check verifies between 7 and 9 we do a
        # special check for 8 parameters which is an error
        if len(params) == 8:
            raise self.parser.error("Must give both a green low and green high value.", self.usage)
        if not len(params) == 9:
            return []

        try:
            err = "green low"
            green_low = float(params[7])
            err = "green high"
            green_high = float(params[8])
        except ValueError as error:
            raise self.parser.error(
                f"Invalid {err} limit value. Limits can be integers or floats.",
                self.usage,
            ) from error

        if (yellow_low > green_low) or (green_low >= green_high) or (green_high > yellow_high):
            raise self.parser.error(
                "Invalid limits specified. Ensure green limits are within yellow limits.",
                self.usage,
            )

        return [green_low, green_high]
