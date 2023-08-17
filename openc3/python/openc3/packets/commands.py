#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.


class Commands:
    """Commands uses PacketConfig to parse the command and telemetry
    configuration files. It contains all the knowledge of which command packets
    exist in the system and how to access them. This class is the API layer
    which other classes use to access commands.

    This should not be confused with the Api module which implements the JSON
    API that is used by tools when accessing the Server. The Api module always
    provides Ruby primatives where the PacketConfig class can return actual
    Packet or PacketItem objects. While there are some overlapping methods between
    the two, these are separate interfaces into the system."""

    LATEST_PACKET_NAME = "LATEST"

    # @param config [PacketConfig] Packet configuration to use to access the
    #  commands
    def __init__(self, config):
        self.config = config

    # (see PacketConfig#warnings)
    def warnings(self):
        return self.config.warnings

    # @return [Array<String>] The command target names (excluding UNKNOWN)
    def target_names(self):
        result = self.config.commands.keys().sort()
        result.delete("UNKNOWN")
        return result

    # @param target_name [String] The target name
    # @return [Hash<packet_name=>Packet>] Hash of the command packets for the given
    #   target name keyed by the packet name
    def packets(self, target_name):
        target_packets = self.config.commands.get(target_name.upper(), None)
        if not target_packets:
            raise Exception(f"Command target '{target_name.upper()}' does not exist")
        return target_packets

    # @param target_name [String] The target name
    # @param packet_name [String] The packet name. Must be a defined packet name
    #   and not 'LATEST'.
    # @return [Packet] The command packet for the given target and packet name
    def packet(self, target_name, packet_name):
        target_packets = self.packets(target_name)
        packet = target_packets.get(packet_name.upper(), None)
        if not packet:
            raise Exception(
                f"Command packet '{target_name.upper()} {packet_name.upper()}' does not exist"
            )
        return packet

    # @param target_name (see #packet)
    # @param packet_name (see #packet)
    # @return [Array<PacketItem>] The command parameters for the given target and packet name
    def params(self, target_name, packet_name):
        return self.packet(target_name, packet_name).sorted_items


#   # Identifies an unknown buffer of data as a defined command and sets the
#   # commands's data to the given buffer. Identifying a command uses the fields
#   # marked as ID_PARAMETER to identify if the buffer passed represents the
#   # command defined. Incorrectly sized buffers are still processed but an
#   # error is logged.
#   #
#   # Note: Subsequent requests for the command (using packet) will return
#   # an uninitialized copy of the command. Thus you must use the return value
#   # of this method.
#   #
#   # @param (see #identify_tlm!)
#   # @return (see #identify_tlm!)
#   def identify(packet_data, target_names = nil)
#     identified_packet = nil

#     target_names = target_names() unless target_names

#     target_names.each do |target_name|
#       target_name = target_name.to_s.upcase
#       target_packets = nil
#       begin
#         target_packets = packets(target_name)
#       rescue RuntimeError
#         # No commands for this target
#         next


#       target = System.targets[target_name]
#       if target and target.cmd_unique_id_mode
#         # Iterate through the packets and see if any represent the buffer
#         target_packets.each do |packet_name, packet|
#           if packet.identify?(packet_data)
#             identified_packet = packet
#             break


#       else
#         # Do a hash lookup to quickly identify the packet
#         if target_packets.length > 0
#           packet = target_packets.first[1]
#           key = packet.read_id_values(packet_data)
#           hash = self.config.cmd_id_value_hash[target_name]
#           identified_packet = hash[repr(key)]
#           identified_packet = hash['CATCHALL'.freeze] unless identified_packet


#       if identified_packet
#         identified_packet.received_count += 1
#         identified_packet = identified_packet.clone
#         identified_packet.received_time = nil
#         identified_packet.stored = false
#         identified_packet.extra = nil
#         identified_packet.buffer = packet_data
#         break


#     return identified_packet


#   # Returns a copy of the specified command packet with the parameters
#   # initialzed to the given params values.
#   #
#   # @param target_name (see #packet)
#   # @param packet_name (see #packet)
#   # @param params [Hash<param_name=>param_value>] Parameter items to override
#   #   in the given command.
#   # @param range_checking [Boolean] Whether to perform range checking on the
#   #   passed in parameters.
#   # @param raw [Boolean] Indicates whether or not to run conversions on command parameters
#   # @param check_required_params [Boolean] Indicates whether or not to check
#   #   that the required command parameters are present
#   def build_cmd(target_name, packet_name, params = {}, range_checking = true, raw = false, check_required_params = true)
#     target_upcase = target_name.to_s.upcase
#     packet_upcase = packet_name.to_s.upcase

#     # Lookup the command and create a light weight copy
#     pkt = packet(target_upcase, packet_upcase)
#     pkt.received_count += 1
#     command = pkt.clone

#     # Restore the command's buffer to a zeroed string of defined length
#     # This will undo any side effects from earlier commands that may have altered the size
#     # of the buffer
#     command.buffer = "\x00" * command.defined_length

#     # Set time, parameters, and restore defaults
#     command.received_time = Time.now.sys
#     command.stored = false
#     command.extra = nil
#     command.given_values = params
#     command.restore_defaults(command.buffer(false), params.keys)
#     command.raw = raw

#     given_item_names = set_parameters(command, params, range_checking)
#     check_required_params(command, given_item_names) if check_required_params

#     return command


#   # Formatted version of a command
#   def format(packet, ignored_parameters = [])
#     if packet.raw
#       items = packet.read_all(:RAW)
#       raw = true
#     else
#       items = packet.read_all(:FORMATTED)
#       raw = false

#     items.delete_if { |item_name, item_value| ignored_parameters.include?(item_name) }
#     return build_cmd_output_string(packet.target_name, packet.packet_name, items, raw)


#   def build_cmd_output_string(target_name, cmd_name, cmd_params, raw = false)
#     if raw
#       output_string = 'cmd_raw("'
#     else
#       output_string = 'cmd("'

#     target_name = 'UNKNOWN' unless target_name
#     cmd_name = 'UNKNOWN' unless cmd_name
#     output_string << target_name + ' ' + cmd_name
#     if cmd_params.nil? or cmd_params.empty?
#       output_string << '")'
#     else
#       begin
#         command_items = packet(target_name, cmd_name).items
#       rescue


#       params = []
#       cmd_params.each do |key, value|
#         next if Packet::RESERVED_ITEM_NAMES.include?(key)

#         begin
#           item_type = command_items[key].data_type
#         rescue
#           item_type = nil


#         if value.is_a?(String)
#           value = value.dup
#           if item_type == :BLOCK or item_type == :STRING
#             if !value.is_printable?
#               value = "0x" + value.simple_formatted
#             else
#               value = value.inspect

#           else
#             value = value.convert_to_value.to_s

#           if value.length > 256
#             value = value[0..255] + "...'"

#           value.tr!('"', "'")
#         elsif value.is_a?(Array)
#           value = "[{value.join(", ")}]"

#         params << "{key} {value}"

#       params = params.join(", ")
#       output_string << ' with ' + params + '")'

#     return output_string


#   # Returns whether the given command is hazardous. Commands are hazardous
#   # if they are marked hazardous overall or if any of their hardardous states
#   # are set. Thus any given parameter values are first applied to the command
#   # and then checked for hazardous states.
#   #
#   # @param command [Packet] The command to check for hazardous
#   def cmd_pkt_hazardous?(command)
#     return [true, command.hazardous_description] if command.hazardous

#     # Check each item for hazardous states
#     item_defs = command.items
#     item_defs.each do |item_name, item_def|
#       if item_def.hazardous
#         state_name = command.read(item_name)
#         # Nominally the command.read will return a valid state_name
#         # If it doesn't, the if check will fail and we'll fall through to
#         # the bottom where we return [false, nil] which means this
#         # command is not hazardous.
#         return [true, item_def.hazardous[state_name]] if item_def.hazardous[state_name]


#     return [false, nil]


#   # Returns whether the given command is hazardous. Commands are hazardous
#   # if they are marked hazardous overall or if any of their hardardous states
#   # are set. Thus any given parameter values are first applied to the command
#   # and then checked for hazardous states.
#   #
#   # @param target_name (see #packet)
#   # @param packet_name (see #packet)
#   # @param params (see #build_cmd)
#   def cmd_hazardous?(target_name, packet_name, params = {})
#     # Build a command without range checking, perform conversions, and don't
#     # check required parameters since we're not actually using the command.
#     cmd_pkt_hazardous?(build_cmd(target_name, packet_name, params, false, false, false))


#   def clear_counters
#     self.config.commands.each do |target_name, target_packets|
#       target_packets.each do |packet_name, packet|
#         packet.received_count = 0


#   def all
#     self.config.commands


#   protected

#   def set_parameters(command, params, range_checking)
#     given_item_names = []
#     params.each do |item_name, value|
#       item_upcase = item_name.to_s.upcase
#       item = command.get_item(item_upcase)
#       range_check_value = value

#       # Convert from state to value if possible
#       if item.states and item.states[value.to_s.upcase]
#         range_check_value = item.states[value.to_s.upcase]


#       if range_checking
#         range = item.range
#         if range
#           # Perform Range Check on command parameter
#           if not range.include?(range_check_value)
#             range_check_value = "'{range_check_value}'" if String === range_check_value
#             raise "Command parameter '{command.target_name} {command.packet_name} {item_upcase}' = {range_check_value} not in valid range of {range.first} to {range.last}"


#       # Update parameter in command
#       if command.raw
#         command.write(item_upcase, value, :RAW)
#       else
#         command.write(item_upcase, value, :CONVERTED)


#       given_item_names << item_upcase

#     given_item_names


#   def check_required_params(command, given_item_names)
#     # Script Runner could call this command with only some parameters
#     # so make sure any required parameters were actually passed in.
#     item_defs = command.items
#     item_defs.each do |item_name, item_def|
#       if item_def.required and not given_item_names.include? item_name
#         raise "Required command parameter '{command.target_name} {command.packet_name} {item_name}' not given"
