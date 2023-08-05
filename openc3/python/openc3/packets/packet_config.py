#!/usr/bin/env python3

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

import os
from openc3.config.config_parser import ConfigParser
from openc3.packets.packet import Packet
from openc3.packets.parsers.packet_parser import PacketParser


class PacketConfig:
    COMMAND = "Command"
    TELEMETRY = "Telemetry"

    def __init__(self):
        self.name = None
        self.telemetry = {}
        self.commands = {}
        self.limits_groups = {}
        self.limits_sets = ["DEFAULT"]
        # Hash of Hashes. First index by target name and then item name.
        # Returns an array of packets with that target and item.
        self.latest_data = {}
        self.warnings = []
        self.cmd_id_value_hash = {}
        self.tlm_id_value_hash = {}

        # Create unknown packets
        self.commands["UNKNOWN"] = {}
        self.commands["UNKNOWN"]["UNKNOWN"] = Packet("UNKNOWN", "UNKNOWN", "BIG_ENDIAN")
        self.telemetry["UNKNOWN"] = {}
        self.telemetry["UNKNOWN"]["UNKNOWN"] = Packet(
            "UNKNOWN", "UNKNOWN", "BIG_ENDIAN"
        )

        self.reset_processing_variables()

    #########################################################################
    # The following methods process a command or telemetry packet config file
    #########################################################################

    # Processes a OpenC3 configuration file and uses the keywords to build up
    # knowledge of the commands, telemetry, and limits groups.
    #
    # self.param filename [String] The name of the configuration file
    # self.param process_target_name [String] The target name. Pass None when parsing
    #   an xtce file to automatically determine the target name.
    def process_file(self, filename, process_target_name):
        # TODO: Handle .xtce files
        # if File.extname(filename).downcase == ".xtce"
        #   XtceParser.process(self.commands, self.telemetry, self.warnings, filename, process_target_name)
        #   return

        # Partial files are included into another file and thus aren't directly processed
        if os.path.basename(filename)[0] == "_":  # Partials start with underscore
            return

        self.converted_type = None
        self.converted_bit_size = None
        self.proc_text = ""
        self.building_generic_conversion = False

        process_target_name = process_target_name.upper()
        parser = ConfigParser("https://openc3.com/docs/v5")
        setattr(parser, "target_name", process_target_name)
        for keyword, params in parser.parse_file(filename):
            match keyword:
                # Start a new packet
                case "COMMAND":
                    self.finish_packet()
                    self.current_packet = PacketParser.parse_command(
                        parser, process_target_name, self.commands, self.warnings
                    )
                    self.current_cmd_or_tlm = PacketConfig.COMMAND

                case "TELEMETRY":
                    self.finish_packet()
                    self.current_packet = PacketParser.parse_telemetry(
                        parser,
                        process_target_name,
                        self.telemetry,
                        self.latest_data,
                        self.warnings,
                    )
                    self.current_cmd_or_tlm = PacketConfig.TELEMETRY

                # Select an existing packet for editing
                case "SELECT_COMMAND" | "SELECT_TELEMETRY":
                    usage = f"{keyword} <TARGET NAME> <PACKET NAME>"
                    self.finish_packet()
                    parser.verify_num_parameters(2, 2, usage)
                    target_name = process_target_name
                    if target_name == "SYSTEM":
                        target_name = params[0].upper()
                    packet_name = params[1].upper()

                    self.current_packet = None
                    if "COMMAND" in keyword:
                        self.current_cmd_or_tlm = PacketConfig.COMMAND
                        if self.commands[target_name]:
                            self.current_packet = self.commands[target_name][
                                packet_name
                            ]
                    else:
                        self.current_cmd_or_tlm = PacketConfig.TELEMETRY
                        if self.telemetry[target_name]:
                            self.current_packet = self.telemetry[target_name][
                                packet_name
                            ]

                    if not self.current_packet:
                        raise parser.error("Packet not found", usage)

                # Start the creation of a new limits group
                case "LIMITS_GROUP":
                    usage = "LIMITS_GROUP <GROUP NAME>"
                    parser.verify_num_parameters(1, 1, usage)
                    self.current_limits_group = params[0].upper()
                    if self.current_limits_group not in self.limits_groups:
                        self.limits_groups[self.current_limits_group] = []

                # Add a telemetry item to the limits group
                case "LIMITS_GROUP_ITEM":
                    usage = "LIMITS_GROUP_ITEM <TARGET NAME> <PACKET NAME> <ITEM NAME>"
                    parser.verify_num_parameters(3, 3, usage)
                    if self.current_limits_group:
                        self.limits_groups[self.current_limits_group].append(
                            [params[0].upper(), params[1].upper(), params[2].upper()]
                        )

                #######################################################################
                # All the following keywords must have a current packet defined
                #######################################################################
                case (
                    "SELECT_ITEM"
                    | "SELECT_PARAMETER"
                    | "DELETE_ITEM"
                    | "DELETE_PARAMETER"
                    | "ITEM"
                    | "PARAMETER"
                    | "ID_ITEM"
                    | "ID_PARAMETER"
                    | "ARRAY_ITEM"
                    | "ARRAY_PARAMETER"
                    | "APPEND_ITEM"
                    | "APPEND_PARAMETER"
                    | "APPEND_ID_ITEM"
                    | "APPEND_ID_PARAMETER"
                    | "APPEND_ARRAY_ITEM"
                    | "APPEND_ARRAY_PARAMETER"
                    | "ALLOW_SHORT"
                    | "HAZARDOUS"
                    | "PROCESSOR"
                    | "META"
                    | "DISABLE_MESSAGES"
                    | "HIDDEN"
                    | "DISABLED"
                    | "ACCESSOR"
                    | "TEMPLATE"
                    | "TEMPLATE_FILE"
                ):
                    if not self.current_packet:
                        raise parser.error(f"No current packet for {keyword}")
                    self.process_current_packet(parser, keyword, params)

                #######################################################################
                # All the following keywords must have a current item defined
                #######################################################################
                case (
                    "STATE"
                    | "READ_CONVERSION"
                    | "WRITE_CONVERSION"
                    | "POLY_READ_CONVERSION"
                    | "POLY_WRITE_CONVERSION"
                    | "SEG_POLY_READ_CONVERSION"
                    | "SEG_POLY_WRITE_CONVERSION"
                    | "GENERIC_READ_CONVERSION_START"
                    | "GENERIC_WRITE_CONVERSION_START"
                    | "REQUIRED"
                    | "LIMITS"
                    | "LIMITS_RESPONSE"
                    | "UNITS"
                    | "FORMAT_STRING"
                    | "DESCRIPTION"
                    | "MINIMUM_VALUE"
                    | "MAXIMUM_VALUE"
                    | "DEFAULT_VALUE"
                    | "OVERFLOW"
                    | "OVERLAP"
                    | "KEY"
                ):
                    if not self.current_item:
                        raise parser.error(f"No current item for {keyword}")
                    self.process_current_item(parser, keyword, params)

                case _:
                    # blank config.lines will have a None keyword and should not raise an exception
                    if keyword:
                        raise parser.error(f"Unknown keyword '{keyword}'")

        # Complete the last defined packet
        self.finish_packet()

    # # Convert the PacketConfig back to OpenC3 configuration files for each target
    # def to_config(output_dir)
    #   FileUtils.mkdir_p(output_dir)

    #   self.telemetry.each do |target_name, packets|
    #     next if target_name == 'UNKNOWN'

    #     FileUtils.mkdir_p(File.join(output_dir, target_name, 'cmd_tlm'))
    #     filename = File.join(output_dir, target_name, 'cmd_tlm', target_name.downcase + '_tlm.txt')
    #     begin
    #       File.delete(filename)
    #     rescue
    #       # Doesn't exist

    #     packets.each do |packet_name, packet|
    #       File.open(filename, 'a') do |file|
    #         file.puts packet.to_config(:TELEMETRY)
    #         file.puts ""

    #   self.commands.each do |target_name, packets|
    #     next if target_name == 'UNKNOWN'

    #     FileUtils.mkdir_p(File.join(output_dir, target_name, 'cmd_tlm'))
    #     filename = File.join(output_dir, target_name, 'cmd_tlm', target_name.downcase + '_cmd.txt')
    #     begin
    #       File.delete(filename)
    #     rescue
    #       # Doesn't exist

    #     packets.each do |packet_name, packet|
    #       File.open(filename, 'a') do |file|
    #         file.puts packet.to_config(:COMMAND)
    #         file.puts ""

    #   # Put limits groups into SYSTEM target
    #   if self.limits_groups.length > 0
    #     FileUtils.mkdir_p(File.join(output_dir, 'SYSTEM', 'cmd_tlm'))
    #     filename = File.join(output_dir, 'SYSTEM', 'cmd_tlm', 'limits_groups.txt')
    #     File.open(filename, 'w') do |file|
    #       self.limits_groups.each do |limits_group_name, limits_group_items|
    #         file.puts "LIMITS_GROUP {limits_group_name.quote_if_necessary}"
    #         limits_group_items.each do |target_name, packet_name, item_name|
    #           file.puts "  LIMITS_GROUP_ITEM {target_name.quote_if_necessary} {packet_name.quote_if_necessary} {item_name.quote_if_necessary}"

    #         file.puts ""

    #  # def to_config

    # def to_xtce(output_dir)
    #   XtceConverter.convert(self.commands, self.telemetry, output_dir)

    # Add current packet into hash if it exists
    def finish_packet(self):
        self.finish_item()
        if self.current_packet:
            self.warnings += self.current_packet.check_bit_offsets
            if self.current_cmd_or_tlm == PacketConfig.COMMAND:
                PacketParser.check_item_data_types(self.current_packet)
                self.commands[self.current_packet.target_name][
                    self.current_packet.packet_name
                ] = self.current_packet
                hash = self.cmd_id_value_hash[self.current_packet.target_name]
                if not hash:
                    hash = {}
                self.cmd_id_value_hash[self.current_packet.target_name] = hash
                self.update_id_value_hash(hash)
            else:
                self.telemetry[self.current_packet.target_name][
                    self.current_packet.packet_name
                ] = self.current_packet
                hash = self.tlm_id_value_hash[self.current_packet.target_name]
                if not hash:
                    hash = {}
                self.tlm_id_value_hash[self.current_packet.target_name] = hash
                self.update_id_value_hash(hash)

            self.current_packet = None
            self.current_item = None

    def update_id_value_hash(self, hash):
        if self.current_packet.id_items.length > 0:
            key = []
            for item in self.current_packet.id_items:
                key << item.id_value

            hash[key] = self.current_packet
        else:
            hash["CATCHALL"] = self.current_packet

    def reset_processing_variables(self):
        self.current_cmd_or_tlm = None
        self.current_packet = None
        self.current_item = None
        self.current_limits_group = None

    # def process_current_packet(parser, keyword, params)
    #   case keyword

    #   # Select or delete an item in the current packet
    #   when 'SELECT_PARAMETER', 'SELECT_ITEM', 'DELETE_PARAMETER', 'DELETE_ITEM'
    #     if (self.current_cmd_or_tlm == COMMAND) && (keyword.split('_')[1] == 'ITEM')
    #       raise parser.error("{keyword} only applies to telemetry packets")

    #     if (self.current_cmd_or_tlm == TELEMETRY) && (keyword.split('_')[1] == 'PARAMETER')
    #       raise parser.error("{keyword} only applies to command packets")

    #     usage = "{keyword} <{keyword.split('_')[1]} NAME>"
    #     finish_item()
    #     parser.verify_num_parameters(1, 1, usage)
    #     begin
    #       if keyword.include?("SELECT")
    #         self.current_item = self.current_packet.get_item(params[0])
    #       else # DELETE
    #         self.current_packet.delete_item(params[0])

    #     rescue # Rescue the default execption to provide a nicer error message
    #       raise parser.error("{params[0]} not found in {self.current_cmd_or_tlm.downcase} packet {self.current_packet.target_name} {self.current_packet.packet_name}", usage)

    #   # Start a new telemetry item in the current packet
    #   when 'ITEM', 'PARAMETER', 'ID_ITEM', 'ID_PARAMETER', 'ARRAY_ITEM', 'ARRAY_PARAMETER',\
    #       'APPEND_ITEM', 'APPEND_PARAMETER', 'APPEND_ID_ITEM', 'APPEND_ID_PARAMETER',\
    #       'APPEND_ARRAY_ITEM', 'APPEND_ARRAY_PARAMETER'
    #     start_item(parser)

    #   # Allow this packet to be received with less data than the defined length
    #   # without generating a warning.
    #   when 'ALLOW_SHORT'
    #     self.current_packet.short_buffer_allowed = True

    #   # Mark the current command as hazardous
    #   when 'HAZARDOUS'
    #     usage = "HAZARDOUS <HAZARDOUS DESCRIPTION (Optional)>"
    #     parser.verify_num_parameters(0, 1, usage)
    #     self.current_packet.hazardous = True
    #     self.current_packet.hazardous_description = params[0] if params[0]

    #   # Define a processor class that will be called once when a packet is received
    #   when 'PROCESSOR'
    #     ProcessorParser.parse(parser, self.current_packet, self.current_cmd_or_tlm)

    #   when 'DISABLE_MESSAGES'
    #     usage = "{keyword}"
    #     parser.verify_num_parameters(0, 0, usage)
    #     self.current_packet.messages_disabled = True

    #   # Store user defined metadata for the packet or a packet item
    #   when 'META'
    #     usage = "META <META NAME> <META VALUES (optional)>"
    #     parser.verify_num_parameters(1, None, usage)
    #     if params.length > 1
    #       meta_values = params[1..-1]
    #     else
    #       meta_values = []

    #     meta_values.each_with_index do |value, index|
    #       if String === value
    #         meta_values[index] = value.to_utf8

    #     if self.current_item
    #       # Item META
    #       self.current_item.meta[params[0].upper()] = meta_values
    #     else
    #       # Packet META
    #       self.current_packet.meta[params[0].upper()] = meta_values

    #   when 'HIDDEN'
    #     usage = "{keyword}"
    #     parser.verify_num_parameters(0, 0, usage)
    #     self.current_packet.hidden = True

    #   when 'DISABLED'
    #     usage = "{keyword}"
    #     parser.verify_num_parameters(0, 0, usage)
    #     self.current_packet.hidden = True
    #     self.current_packet.disabled = True
    #   when 'ACCESSOR'
    #     usage = "{keyword} <Accessor class name>"
    #     parser.verify_num_parameters(1, 1, usage)
    #     begin
    #       klass = OpenC3.require_class(params[0])
    #       self.current_packet.accessor = klass
    #     rescue Exception => err
    #       raise parser.error(err)

    #   when 'TEMPLATE'
    #     usage = "{keyword} <Template string>"
    #     parser.verify_num_parameters(1, 1, usage)
    #     self.current_packet.template = params[0]

    #   when 'TEMPLATE_FILE'
    #     usage = "{keyword} <Template file path>"
    #     parser.verify_num_parameters(1, 1, usage)

    #     begin
    #       self.current_packet.template = parser.read_file(params[0])
    #     rescue Exception => err
    #       raise parser.error(err)

    # def process_current_item(parser, keyword, params)
    #   case keyword

    #   # Add a state to the current telemety item
    #   when 'STATE'
    #     StateParser.parse(parser, self.current_packet, self.current_cmd_or_tlm, self.current_item, self.warnings)

    #   # Apply a conversion to the current item after it is read to or
    #   # written from the packet
    #   when 'READ_CONVERSION', 'WRITE_CONVERSION'
    #     usage = "{keyword} <conversion class filename> <custom parameters> ..."
    #     parser.verify_num_parameters(1, None, usage)
    #     begin
    #       klass = OpenC3.require_class(params[0])
    #       conversion = klass.new(*params[1..(params.length - 1)])
    #       self.current_item.public_send("{keyword.downcase}=".to_sym, conversion)
    #       if klass != ProcessorConversion and (conversion.converted_type.None? or conversion.converted_bit_size.None?)
    #         msg = "Read Conversion {params[0]} on item {self.current_item.name} does not specify converted type or bit size"
    #         self.warnings << msg
    #         Logger.instance.warn self.warnings[-1]

    #     rescue Exception => err
    #       raise parser.error(err)

    #   # Apply a polynomial conversion to the current item
    #   when 'POLY_READ_CONVERSION', 'POLY_WRITE_CONVERSION'
    #     usage = "{keyword} <C0> <C1> <C2> ..."
    #     parser.verify_num_parameters(1, None, usage)
    #     self.current_item.read_conversion = PolynomialConversion.new(*params) if keyword.include? "READ"
    #     self.current_item.write_conversion = PolynomialConversion.new(*params) if keyword.include? "WRITE"

    #   # Apply a segmented polynomial conversion to the current item
    #   # after it is read from the telemetry packet
    #   when 'SEG_POLY_READ_CONVERSION'
    #     usage = "SEG_POLY_READ_CONVERSION <Lower Bound> <C0> <C1> <C2> ..."
    #     parser.verify_num_parameters(2, None, usage)
    #     if !(self.current_item.read_conversion &&
    #          SegmentedPolynomialConversion === self.current_item.read_conversion)
    #       self.current_item.read_conversion = SegmentedPolynomialConversion.new

    #     self.current_item.read_conversion.add_segment(params[0].to_f, *params[1..-1])

    #   # Apply a segmented polynomial conversion to the current item
    #   # before it is written to the telemetry packet
    #   when 'SEG_POLY_WRITE_CONVERSION'
    #     usage = "SEG_POLY_WRITE_CONVERSION <Lower Bound> <C0> <C1> <C2> ..."
    #     parser.verify_num_parameters(2, None, usage)
    #     if !(self.current_item.write_conversion &&
    #          SegmentedPolynomialConversion === self.current_item.write_conversion)
    #       self.current_item.write_conversion = SegmentedPolynomialConversion.new

    #     self.current_item.write_conversion.add_segment(params[0].to_f, *params[1..-1])

    #   # Start the definition of a generic conversion.
    #   # All config.lines following this config.line are considered part
    #   # of the conversion until an  of conversion marker is found
    #   when 'GENERIC_READ_CONVERSION_START', 'GENERIC_WRITE_CONVERSION_START'
    #     usage = "{keyword} <Converted Type (optional)> <Converted Bit Size (optional)>"
    #     parser.verify_num_parameters(0, 2, usage)
    #     self.proc_text = ''
    #     self.building_generic_conversion = True
    #     self.converted_type = None
    #     self.converted_bit_size = None
    #     if params[0]
    #       self.converted_type = params[0].upper().intern
    #       raise parser.error("Invalid converted_type: {self.converted_type}.") unless [:INT, :UINT, :FLOAT, :STRING, :BLOCK, :RUBY_TIME].include? self.converted_type

    #     self.converted_bit_size = Integer(params[1]) if params[1]
    #     if self.converted_type.None? or self.converted_bit_size.None?
    #       msg = "Generic Conversion on item {self.current_item.name} does not specify converted type or bit size"
    #       self.warnings << msg
    #       Logger.instance.warn self.warnings[-1]

    #   # Define a set of limits for the current telemetry item
    #   when 'LIMITS'
    #     self.limits_sets << LimitsParser.parse(parser, self.current_packet, self.current_cmd_or_tlm, self.current_item, self.warnings)
    #     self.limits_sets.uniq!

    #   # Define a response class that will be called when the limits state of the
    #   # current item changes.
    #   when 'LIMITS_RESPONSE'
    #     LimitsResponseParser.parse(parser, self.current_item, self.current_cmd_or_tlm)

    #   # Define a printf style formatting string for the current telemetry item
    #   when 'FORMAT_STRING'
    #     FormatStringParser.parse(parser, self.current_item)

    #   # Define the units of the current telemetry item
    #   when 'UNITS'
    #     usage = "UNITS <FULL UNITS NAME> <ABBREVIATED UNITS NAME>"
    #     parser.verify_num_parameters(2, 2, usage)
    #     self.current_item.units_full = params[0]
    #     self.current_item.units = params[1]

    #   # Update the description for the current telemetry item
    #   when 'DESCRIPTION'
    #     usage = "DESCRIPTION <DESCRIPTION>"
    #     parser.verify_num_parameters(1, 1, usage)
    #     self.current_item.description = params[0]

    #   # Mark the current command parameter as required.
    #   # This means it must be given a value and not just use its default.
    #   when 'REQUIRED'
    #     usage = "REQUIRED"
    #     parser.verify_num_parameters(0, 0, usage)
    #     if self.current_cmd_or_tlm == COMMAND
    #       self.current_item.required = True
    #     else
    #       raise parser.error("{keyword} only applies to command parameters")

    #   # Update the mimimum value for the current command parameter
    #   when 'MINIMUM_VALUE'
    #     if self.current_cmd_or_tlm == TELEMETRY
    #       raise parser.error("{keyword} only applies to command parameters")

    #     usage = "MINIMUM_VALUE <MINIMUM VALUE>"
    #     parser.verify_num_parameters(1, 1, usage)
    #     min = ConfigParser.handle_defined_constants(
    #       params[0].convert_to_value, self.current_item.data_type, self.current_item.bit_size
    #     )
    #     self.current_item.range = Range.new(min, self.current_item.range.)

    #   # Update the maximum value for the current command parameter
    #   when 'MAXIMUM_VALUE'
    #     if self.current_cmd_or_tlm == TELEMETRY
    #       raise parser.error("{keyword} only applies to command parameters")

    #     usage = "MAXIMUM_VALUE <MAXIMUM VALUE>"
    #     parser.verify_num_parameters(1, 1, usage)
    #     max = ConfigParser.handle_defined_constants(
    #       params[0].convert_to_value, self.current_item.data_type, self.current_item.bit_size
    #     )
    #     self.current_item.range = Range.new(self.current_item.range.begin, max)

    #   # Update the default value for the current command parameter
    #   when 'DEFAULT_VALUE'
    #     if self.current_cmd_or_tlm == TELEMETRY
    #       raise parser.error("{keyword} only applies to command parameters")

    #     usage = "DEFAULT_VALUE <DEFAULT VALUE>"
    #     parser.verify_num_parameters(1, 1, usage)
    #     if (self.current_item.data_type == :STRING) ||
    #        (self.current_item.data_type == :BLOCK)
    #       self.current_item.default = params[0]
    #     else
    #       self.current_item.default = ConfigParser.handle_defined_constants(
    #         params[0].convert_to_value, self.current_item.data_type, self.current_item.bit_size
    #       )

    #   # Update the overflow type for the current command parameter
    #   when 'OVERFLOW'
    #     usage = "OVERFLOW <OVERFLOW VALUE - ERROR, ERROR_ALLOW_HEX, TRUNCATE, or SATURATE>"
    #     parser.verify_num_parameters(1, 1, usage)
    #     self.current_item.overflow = params[0].upper().intern

    #   when 'OVERLAP'
    #     parser.verify_num_parameters(0, 0, 'OVERLAP')
    #     self.current_item.overlap = True

    #   when 'KEY'
    #     parser.verify_num_parameters(1, 1, 'KEY <key or path into data>')
    #     self.current_item.key = params[0]

    # def start_item(self, parser):
    #   self.finish_item()
    #   self.current_item = PacketItemParser.parse(parser, self.current_packet, self.current_cmd_or_tlm, self.warnings)

    # Finish updating packet item
    def finish_item(self):
        if self.current_item:
            self.current_packet.set_item(self.current_item)
            if self.current_cmd_or_tlm == PacketConfig.TELEMETRY:
                target_latest_data = self.latest_data[self.current_packet.target_name]
                if not target_latest_data.get(self.current_item.name):
                    target_latest_data[self.current_item.name] = []
                latest_data_packets = target_latest_data[self.current_item.name]
                if self.current_packet not in latest_data_packets:
                    latest_data_packets.append(self.current_packet)
            self.current_item = None
