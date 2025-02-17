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


class Limits:
    """Limits uses PacketConfig to parse the command and telemetry
    configuration files. It provides the API layer which other classes use to
    access information about and manipulate limits. This includes getting,
    setting and checking individual limit items as well as manipulating limits groups.
    """

    LATEST_PACKET_NAME = "LATEST"

    # @param config [PacketConfig] Packet configuration to use to access the
    #  limits
    def __init__(self, config, system):
        self.config = config
        self.system = system

    # (see PacketConfig#warnings)
    def warnings(self):
        return self.config.warnings

    # (see PacketConfig#limits_sets)
    def sets(self):
        return self.config.limits_sets

    # @return [Hash(String, Array)] The defined limits groups
    def groups(self):
        return self.config.limits_groups

    # Checks whether the limits are enabled for the specified item
    #
    # @param target_name [String] The target name
    # @param packet_name [String] The packet name. Must be a defined packet name and not 'LATEST'.
    # @param item_name [String] The item name
    def enabled(self, target_name, packet_name, item_name):
        return self._get_packet(target_name, packet_name).get_item(item_name).limits.enabled

    # Enables limit checking for the specified item
    #
    # @param (see #enabled?)
    def enable(self, target_name, packet_name, item_name):
        self._get_packet(target_name, packet_name).enable_limits(item_name)

    # Disables limit checking for the specified item
    #
    # @param (see #enabled?)
    def disable(self, target_name, packet_name, item_name):
        self._get_packet(target_name, packet_name).disable_limits(item_name)

    # Get the limits for a telemetry item
    #
    # @param target_name [String] Target Name
    # @param packet_name [String] Packet Name
    # @param item_name [String] Item Name
    # @param limits_set [String or Symbol or nil] Desired Limits set.  nil = current limits set
    # @return [Array<limits_set, persistence, enabled, red_low, yellow_low, red_high, yellow_high, green_low (optional), green_high (optional)] Limits information
    def get(self, target_name, packet_name, item_name, limits_set=None):
        limits = self._get_packet(target_name, packet_name).get_item(item_name).limits
        if limits.values:
            if limits_set:
                limits_set = str(limits_set).upper()
            else:
                limits_set = self.system.limits_set()
            limits_for_set = limits.values.get(limits_set)
            if limits_for_set is not None:
                gl = None
                gh = None
                if len(limits_for_set) > 4:
                    gl = limits_for_set[4]
                    gh = limits_for_set[5]
                return [
                    limits_set,
                    limits.persistence_setting,
                    limits.enabled,
                    limits_for_set[0],
                    limits_for_set[1],
                    limits_for_set[2],
                    limits_for_set[3],
                    gl, gh,
                ]
            else:
                return [None, None, None, None, None, None, None, None, None]
        else:
            return [None, None, None, None, None, None, None, None, None]

    # Set the limits for a telemetry item
    #
    # @param target_name [String] Target Name
    # @param packet_name [String] Packet Name
    # @param item_name [String] Item Name
    # @param red_low [Float] Red Low Limit
    # @param yellow_low [Float] Yellow Low Limit
    # @param yellow_high [Float] Yellow High Limit
    # @param red_high [Float] Red High Limit
    # @param green_low [Float] Green Low Limit
    # @param green_high [Float] Green High Limit
    # @param limits_set [String or Symbol or nil] Desired Limits set.  nil = current limits set, recommend using :CUSTOM
    # @param persistence [Integer] The number of samples the value must be out of limits before detecting a limits change. nil = Leave unchanged
    # @param enabled [Boolean] If limits monitoring is enabled for this item
    # @return [Array<limits_set, persistence, enabled, red_low, yellow_low, red_high, yellow_high, green_low (optional), green_high (optional)] Limits information
    def set(
        self,
        target_name,
        packet_name,
        item_name,
        red_low,
        yellow_low,
        yellow_high,
        red_high,
        green_low=None,
        green_high=None,
        limits_set="CUSTOM",
        persistence=None,
        enabled=True,
    ):
        packet = self._get_packet(target_name, packet_name)
        item = packet.get_item(item_name)
        limits = item.limits
        if limits_set:
            limits_set = str(limits_set).upper()
        else:
            limits_set = self.system.limits_set()
        if limits.values is None:
            if limits_set == "DEFAULT":
                limits.values = {"DEFAULT": []}
            else:
                raise RuntimeError(
                    f"DEFAULT limits must be defined for {target_name} {packet_name} {item_name} before setting limits set {limits_set}"
                )
        limits_for_set = limits.values.get(limits_set)
        if limits_for_set is None:
            limits.values[limits_set] = []
            limits_for_set = limits.values[limits_set]
        while len(limits_for_set) < 6:
            limits_for_set.append(None)
        limits_for_set[0] = float(red_low)
        limits_for_set[1] = float(yellow_low)
        limits_for_set[2] = float(yellow_high)
        limits_for_set[3] = float(red_high)
        if green_low and green_high:
            limits_for_set[4] = float(green_low)
            limits_for_set[5] = float(green_high)
        else:
            limits_for_set[4] = None
            limits_for_set[5] = None
        if enabled is not None:
            limits.enabled = enabled
        if persistence is not None:
            limits.persistence_setting = int(persistence)
        packet.update_limits_items_cache(item)
        if limits_set not in self.config.limits_sets:
            self.config.limits_sets.append(limits_set)
        return [
            limits_set,
            limits.persistence_setting,
            limits.enabled,
            limits_for_set[0],
            limits_for_set[1],
            limits_for_set[2],
            limits_for_set[3],
            limits_for_set[4],
            limits_for_set[5],
        ]

    def _get_packet(self, target_name, packet_name):
        if packet_name.upper() == Limits.LATEST_PACKET_NAME:
            raise RuntimeError("LATEST packet not valid")

        packets = self.config.telemetry.get(target_name.upper())
        if packets is None:
            raise RuntimeError(f"Telemetry target '{target_name.upper()}' does not exist")

        packet = packets.get(packet_name.upper())
        if packet is None:
            raise RuntimeError(f"Telemetry packet '{target_name.upper()} { packet_name.upper()}' does not exist")

        return packet
