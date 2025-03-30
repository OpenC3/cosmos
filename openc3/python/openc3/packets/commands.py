# Copyright 2025 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953 and https://github.com/OpenC3/cosmos/pull/1963

from datetime import datetime, timezone
from openc3.packets.packet import Packet
from openc3.utilities.string import simple_formatted
from openc3.utilities.extract import convert_to_value

class Commands:
    """Commands uses PacketConfig to parse the command and telemetry
    configuration files. It contains all the knowledge of which command packets
    exist in the system and how to access them. This class is the API layer
    which other classes use to access commands.

    This should not be confused with the Api module which implements the JSON
    API that is used by tools when accessing the Server. The Api module always
    provides Ruby primitives where the PacketConfig class can return actual
    Packet or PacketItem objects. While there are some overlapping methods between
    the two, these are separate interfaces into the system."""

    LATEST_PACKET_NAME = "LATEST"

    # @param config [PacketConfig] Packet configuration to use to access the
    #  commands
    def __init__(self, config, system):
        self.config = config
        self.system = system

    # (see PacketConfig#warnings)
    def warnings(self):
        return self.config.warnings

    # @return [Array<String>] The command target names (excluding UNKNOWN)
    def target_names(self):
        result = list(self.config.commands.keys())
        if "UNKNOWN" in result:
            result.remove("UNKNOWN")
        return result

    # @param target_name [String] The target name
    # @return [Hash<packet_name=>Packet>] Hash of the command packets for the given
    #   target name keyed by the packet name
    def packets(self, target_name):
        target_packets = self.config.commands.get(target_name.upper(), None)
        if target_packets is None:
            raise RuntimeError(f"Command target '{target_name.upper()}' does not exist")
        return target_packets

    # @param target_name [String] The target name
    # @param packet_name [String] The packet name. Must be a defined packet name
    #   and not 'LATEST'.
    # @return [Packet] The command packet for the given target and packet name
    def packet(self, target_name, packet_name):
        target_packets = self.packets(target_name)
        packet = target_packets.get(packet_name.upper(), None)
        if packet is None:
            raise RuntimeError(f"Command packet '{target_name.upper()} {packet_name.upper()}' does not exist")
        return packet

    # @param target_name (see #packet)
    # @param packet_name (see #packet)
    # @return [Array<PacketItem>] The command parameters for the given target and packet name
    def params(self, target_name, packet_name):
        return self.packet(target_name, packet_name).sorted_items

    # Identifies an unknown buffer of data as a defined command and sets the
    # commands's data to the given buffer. Identifying a command uses the fields
    # marked as ID_PARAMETER to identify if the buffer passed represents the
    # command defined. Incorrectly sized buffers are still processed but an
    # error is logged.
    #
    # Note: Subsequent requests for the command (using packet) will return
    # an uninitialized copy of the command. Thus you must use the return value
    # of this method.
    #
    # Note: this method does not increment received_count and it should be
    # incremented externally if needed.
    #
    # @param (see #identify_tlm!)
    # @return (see #identify_tlm!)
    def identify(self, packet_data, target_names=None):
        identified_packet = None

        if not target_names:
            target_names = self.target_names()

        for target_name in target_names:
            target_name = str(target_name).upper()
            target_packets = None
            try:
                target_packets = self.packets(target_name)
            except RuntimeError:
                # No commands for this target
                continue

            target = self.system.targets.get(target_name)
            if target and target.cmd_unique_id_mode:
                # Iterate through the packets and see if any represent the buffer
                for _, packet in target_packets.items():
                    if packet.identify(packet_data):
                        identified_packet = packet
                        break
            else:
                # Do a lookup to quickly identify the packet
                if len(target_packets) > 0:
                    packet = next(iter(target_packets.values()))
                    key = packet.read_id_values(packet_data)
                    id_values = self.config.cmd_id_value_hash[target_name]
                    identified_packet = id_values.get(str(key))
                    if identified_packet is None:
                        identified_packet = id_values.get("CATCHALL")

            if identified_packet is not None:

                identified_packet = identified_packet.clone()
                identified_packet.received_time = None
                identified_packet.stored = False
                identified_packet.extra = None
                identified_packet.buffer = packet_data
                break

        return identified_packet

    # Returns a copy of the specified command packet with the parameters
    # initialized to the given params values.
    #
    # Note: this method does not increment received_count and it should be
    # incremented externally if needed.
    #
    # @param target_name (see #packet)
    # @param packet_name (see #packet)
    # @param params [Hash<param_name=>param_value>] Parameter items to override
    #   in the given command.
    # @param range_checking [Boolean] Whether to perform range checking on the
    #   passed in parameters.
    # @param raw [Boolean] Indicates whether or not to run conversions on command parameters
    # @param check_required_params [Boolean] Indicates whether or not to check
    #   that the required command parameters are present
    def build_cmd(
        self,
        target_name,
        packet_name,
        params={},
        range_checking=True,
        raw=False,
        check_required_params=True,
    ):
        target_upcase = target_name.upper()
        packet_upcase = packet_name.upper()

        # Lookup the command and create a light weight copy
        pkt = self.packet(target_upcase, packet_upcase)

        command = pkt.clone()

        # Restore the command's buffer to a zeroed string of defined length
        # This will undo any side effects from earlier commands that may have altered the size
        # of the buffer
        command.buffer = bytearray(b"\x00" * command.defined_length)

        # Set time, parameters, and restore defaults
        command.received_time = datetime.now(timezone.utc)
        command.stored = False
        command.extra = None
        command.given_values = params
        command.restore_defaults(command.buffer_no_copy(), list(params.keys()))
        command.raw = raw

        given_item_names = self._set_parameters(command, params, range_checking)
        if check_required_params:
            self._check_required_params(command, given_item_names)

        return command

    # Formatted version of a command
    def format(self, packet, ignored_parameters=[]):
        if packet.raw:
            items = packet.read_all("RAW")
            raw = True
        else:
            items = packet.read_all("FORMATTED")
            raw = False
        items = [item for item in items if item[0] not in ignored_parameters]
        return self.build_cmd_output_string(packet.target_name, packet.packet_name, items, raw)

    def build_cmd_output_string(self, target_name, cmd_name, cmd_params, raw=False):
        if raw:
            output_string = 'cmd_raw("'
        else:
            output_string = 'cmd("'
        if not target_name:
            target_name = "UNKNOWN"
        if not cmd_name:
            cmd_name = "UNKNOWN"
        output_string += target_name + " " + cmd_name
        if cmd_params is None or len(cmd_params) == 0:
            output_string += '")'
        else:
            try:
                command_items = self.packet(target_name, cmd_name).items
            except RuntimeError:
                command_items = {}

            params = []
            for key, value in cmd_params:
                if key in Packet.RESERVED_ITEM_NAMES:
                    continue

                try:
                    item_type = command_items[key].data_type
                except KeyError:
                    item_type = None

                if isinstance(value, str):
                    if item_type == "BLOCK" or item_type == "STRING":
                        if not value.isascii():
                            value = "0x" + simple_formatted(value)
                        else:
                            value = f"'{str(value)}'"
                    else:
                        value = str(convert_to_value(value))
                    if len(value) > 256:
                        value = value[:256] + "...'"
                    value = value.replace('"', "'")
                elif isinstance(value, list):
                    value = f"[{', '.join(str(i) for i in value)}]"
                params.append(f"{key} {value}")
            params = (", ").join(params)
            output_string += " with " + params + '")'
        return output_string

    # Returns whether the given command is hazardous. Commands are hazardous
    # if they are marked hazardous overall or if any of their hardardous states
    # are set. Thus any given parameter values are first applied to the command
    # and then checked for hazardous states.
    #
    # @param command [Packet] The command to check for hazardous
    def cmd_pkt_hazardous(self, command):
        if command.hazardous:
            return (True, command.hazardous_description)

        # Check each item for hazardous states
        for item_name, item_def in command.items.items():
            if item_def.hazardous:
                state_name = command.read(item_name)
                # Nominally the command.read will return a valid state_name
                # If it doesn't, the if check will fail and we'll fall through to
                # the bottom where we return [false, nil] which means this
                # command is not hazardous.
                if item_def.hazardous.get(state_name) is not None:
                    return (True, item_def.hazardous[state_name])

        return (False, None)

    # Returns whether the given command is hazardous. Commands are hazardous
    # if they are marked hazardous overall or if any of their hardardous states
    # are set. Thus any given parameter values are first applied to the command
    # and then checked for hazardous states.
    #
    # @param target_name (see #packet)
    # @param packet_name (see #packet)
    # @param params (see #build_cmd)
    def cmd_hazardous(self, target_name, packet_name, params={}):
        # Build a command without range checking, perform conversions, and don't
        # check required parameters since we're not actually using the command.
        return self.cmd_pkt_hazardous(self.build_cmd(target_name, packet_name, params, False, False, False))

    def all(self):
        return self.config.commands

    def dynamic_add_packet(self, packet, affect_ids=False):
        self.config.dynamic_add_packet(packet, "COMMAND", affect_ids=affect_ids)

    def _set_parameters(self, command, params, range_checking):
        given_item_names = []
        for item_name, value in params.items():
            item_upcase = item_name.upper()
            item = command.get_item(item_upcase)
            range_check_value = value

            if range_checking:
                if item.states:
                    if item.states.get(str(value).upper()) is not None:
                        range_check_value = item.states[str(value).upper()]
                    else:
                        if value not in item.states.values():
                            if command.raw:
                                # Raw commands report missing value maps
                                raise RuntimeError(
                                    f"Command parameter '{command.target_name} {command.packet_name} {item_upcase}' = {value} not one of {', '.join(map(str, item.states.values()))}"
                                )
                            else:
                                # Normal commands report missing state maps
                                raise RuntimeError(
                                    f"Command parameter '{command.target_name} {command.packet_name} {item_upcase}' = {value} not one of {', '.join(item.states.keys())}"
                                )

                # Only range check if we have a min, max and not a string default value
                minimum = item.minimum
                maximum = item.maximum
                if minimum is not None and maximum is not None and not isinstance(item.default, str):
                    # Perform Range Check on command parameter
                    if isinstance(range_check_value, str) or range_check_value < minimum or range_check_value > maximum:
                        if isinstance(range_check_value, str):
                            range_check_value = f"'{range_check_value}'"
                        raise RuntimeError(
                            f"Command parameter '{command.target_name} {command.packet_name} {item_upcase}' = {range_check_value} not in valid range of {minimum} to {maximum}"
                        )

            # Update parameter in command
            if command.raw:
                command.write(item_upcase, value, "RAW")
            else:
                command.write(item_upcase, value, "CONVERTED")
            given_item_names.append(item_upcase)

        return given_item_names

    def _check_required_params(self, command, given_item_names):
        # Script Runner could call this command with only some parameters
        # so make sure any required parameters were actually passed in.
        for item_name, item_def in command.items.items():
            if item_def.required and item_name not in given_item_names:
                raise RuntimeError(
                    f"Required command parameter '{command.target_name} {command.packet_name} {item_name}' not given"
                )
