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

import copy
import base64
import hashlib
import datetime
from .structure import Structure
from .packet_item import PacketItem
from .packet_item_limits import PacketItemLimits
from openc3.conversions.packet_time_formatted_conversion import (
    PacketTimeFormattedConversion,
)
from openc3.conversions.packet_time_seconds_conversion import (
    PacketTimeSecondsConversion,
)
from openc3.conversions.received_count_conversion import ReceivedCountConversion
from openc3.conversions.received_time_formatted_conversion import (
    ReceivedTimeFormattedConversion,
)
from openc3.conversions.received_time_seconds_conversion import (
    ReceivedTimeSecondsConversion,
)
from openc3.utilities.logger import Logger
from openc3.utilities.string import (
    simple_formatted,
    quote_if_necessary,
    class_name_to_filename,
)
from openc3.top_level import get_class_from_module


class Packet(Structure):
    RESERVED_ITEM_NAMES = [
        "PACKET_TIMESECONDS",
        "PACKET_TIMEFORMATTED",
        "RECEIVED_TIMESECONDS",
        "RECEIVED_TIMEFORMATTED",
        "RECEIVED_COUNT",
    ]
    ANY_STATE = "ANY"
    # Valid format types
    VALUE_TYPES = ["RAW", "CONVERTED", "FORMATTED", "WITH_UNITS"]

    def __init__(
        self,
        target_name=None,
        packet_name=None,
        default_endianness="BIG_ENDIAN",
        description=None,
        buffer=None,
        item_class=PacketItem,
    ):
        super().__init__(default_endianness, buffer, item_class)
        # Explictly call the defined setter methods
        self.target_name = target_name
        self.packet_name = packet_name
        self.description = description
        self.packet_time = None
        self.received_time = None
        self.received_count = 0
        self.id_items = None
        self.hazardous = False
        self.hazardous_description = None
        self.given_values = None
        self.limits_items = []
        self.limits_items_hash = {}
        self.processors = {}
        self.limits_change_callback = None
        self.read_conversion_cache = None
        # self.short_buffer_allowed = None
        self.raw = None
        self.messages_disabled = False
        self.meta = {}
        self.hidden = False
        self.disabled = False
        self.stored = False
        self.extra = None
        self.cmd_or_tlm = None
        self.template = None

    @property
    def target_name(self):
        return self.__target_name

    @target_name.setter
    def target_name(self, target_name):
        """Sets the target name this packet is associated with. Unidentified packets
        will have target name set to None."""
        if target_name is not None:
            if type(target_name) != str:
                raise AttributeError(
                    f"target_name must be a str but is a {target_name.__class__.__name__}"
                )

            self.__target_name = target_name.upper()
        else:
            self.__target_name = None

    @property
    def packet_name(self):
        return self.__packet_name

    @packet_name.setter
    def packet_name(self, packet_name):
        """Sets the packet name. Unidentified packets will have packet name set to None"""
        if packet_name is not None:
            if type(packet_name) != str:
                raise AttributeError(
                    f"packet_name must be a str but is a {packet_name.__class__.__name__}"
                )

            self.__packet_name = packet_name.upper()
        else:
            self.__packet_name = None

    @property
    def description(self):
        return self.__description

    @description.setter
    def description(self, description):
        """Sets the packet description"""
        if description is not None:
            if type(description) != str:
                raise AttributeError(
                    f"description must be a str but is a {description.__class__.__name__}"
                )

            self.__description = description
        else:
            self.__description = None

    @property
    def received_time(self):
        return self.__received_time

    @received_time.setter
    def received_time(self, received_time):
        """Sets the received time of the packet"""
        if received_time is not None:
            if type(received_time) is not datetime.datetime:
                raise AttributeError(
                    f"received_time must be a datetime but is a {received_time.__class__.__name__}"
                )

            self.__received_time = received_time
        else:
            self.__received_time = None

    @property
    def received_count(self):
        return self.__received_count

    @received_count.setter
    def received_count(self, received_count):
        """Sets the packet name. Unidentified packets will have packet name set to None"""
        if type(received_count) != int:
            raise AttributeError(
                f"received_count must be an int but is a {received_count.__class__.__name__}"
            )

        self.__received_count = received_count

    # Tries to identify if a buffer represents the currently defined packet. It:
    # does this by iterating over all the packet items that were created with
    # an ID value and checking whether that ID value is present at the correct
    # location in the buffer.
    #
    # Incorrectly sized buffers will still positively identify if there is:
    # enough data to match the ID values. This is to allow incorrectly sized
    # packets to still be processed as well as possible given the incorrectly
    # sized data.
    #
    # self.param buffer [String] Raw buffer of binary data
    # self.return [Boolean] Whether or not the buffer of data is this packet
    def identify(self, buffer):
        if not buffer:
            return False
        if not self.id_items:
            return True

        for item in self.id_items:
            try:
                value = self.read_item(item, "RAW", buffer)
            except AttributeError:
                value = None
            if item.id_value != value:
                return False
        return True

    # Reads the values from a buffer at the position of each id_item defined
    # in the packet.
    #
    # self.param buffer [String] Raw buffer of binary data
    # self.return [Array] Array of read id values in order
    def read_id_values(self, buffer):
        if not buffer:
            return []
        if not self.id_items:
            return []

        values = []
        for item in self.id_items:
            try:
                values.append(self.read_item(item, "RAW", buffer))
            except AttributeError:
                values.append(None)
        return values

    # Returns self.received_time unless a packet item called PACKET_TIME exists that returns
    # a Ruby Time object that represents a different timestamp for the packet
    def packet_time(self):
        item = self.items["PACKET_TIME"]
        if item is not None:
            return self.read_item(item, "CONVERTED", self.buffer)
        else:
            if self.packet_time is not None:
                return self.packet_time
            else:
                return self.received_time

    # Calculates a unique hashing sum that changes if the parts of the packet configuration change that could affect:
    # the "shape" of the packet.  This value is cached and that packet should not be changed if this method is being used:
    def config_name(self):
        if self.config_name:
            return self.config_name

        string = f"{self.target_name} {self.packet_name}"
        for item in self.sorted_items:
            string += f" ITEM {item.name} {item.bit_offset} {item.bit_size} {item.data_type} {item.array_size} {item.endianness} {item.overflow} {item.states} {item.read_conversion.__class__.__name__ if item.read_conversion else 'NO_CONVERSION'}"

        # Use the hashing algorithm established by System
        digest = hashlib.sha256()
        digest.update(string)
        self.config_name = digest.hexdigest()
        return self.config_name

    @property
    def buffer(self, copy=True):
        return self.allocate_buffer_if_needed()[:]

    @buffer.setter
    def buffer(self, buffer):
        with self.synchronize():
            try:
                self.internal_buffer_equals(buffer)
            except AttributeError:
                Logger.error(
                    f"{self.target_name} {self.packet_name} received with actual packet length of {len(buffer)} but defined length of {self.defined_length}"
                )
            if self.read_conversion_cache:
                self.read_conversion_cache = {}
            self.process()

    # Sets the received time of the packet (without cloning)
    #
    # self.param received_time [Time] Time this packet was received
    def set_received_time_fast(self, received_time):
        self.received_time = received_time
        if self.read_conversion_cache:
            with self.synchronize():
                self.read_conversion_cache = {}

    @property
    def hazardous_description(self):
        return self.__hazardous_description

    @hazardous_description.setter
    def hazardous_description(self, hazardous_description):
        """Sets the packet hazardous_description"""
        if hazardous_description is not None:
            if type(hazardous_description) != str:
                raise AttributeError(
                    f"hazardous_description must be a str but is a {hazardous_description.__class__.__name__}"
                )

            self.__hazardous_description = hazardous_description
        else:
            self.__hazardous_description = None

    @property
    def given_values(self):
        return self.__given_values

    @given_values.setter
    def given_values(self, given_values):
        """Sets the packet given_values"""
        if given_values is not None:
            if type(given_values) != dict:
                raise AttributeError(
                    f"given_values must be a dict but is a {given_values.__class__.__name__}"
                )

            self.__given_values = given_values
        else:
            self.__given_values = None

    @property
    def limits_change_callback(self):
        return self.__limits_change_callback

    @limits_change_callback.setter
    def limits_change_callback(self, limits_change_callback_var):
        """Sets the packet limits_change_callback"""
        if limits_change_callback_var is not None:
            if not hasattr(limits_change_callback_var, "call"):
                raise AttributeError("limits_change_callback must implement call")

            self.__limits_change_callback = limits_change_callback_var
        else:
            self.__limits_change_callback = None

    @property
    def template(self):
        return self.__template

    @template.setter
    def template(self, template):
        """Sets the packet template"""
        if template is not None:
            if not isinstance(template, (bytes, bytearray)):
                raise AttributeError(
                    f"template must be bytes but is a {template.__class__.__name__}"
                )

            self.__template = template
        else:
            self.__template = None

    # Review bit offset to look for overlapping definitions. This will allow
    # gaps in the packet, but not allow the same bits to be used for multiple
    # variables.
    #
    # self.return [Array<String>] Warning messages for big definition overlaps
    def check_bit_offsets(self):
        expected_next_offset = None
        previous_item = None
        warnings = []
        for item in self.sorted_items:
            if (
                expected_next_offset
                and (item.bit_offset < expected_next_offset)
                and not item.overlap
            ):
                msg = f"Bit definition overlap at bit offset {item.bit_offset} for packet {self.target_name} {self.packet_name} items {item.name} and {previous_item.name}"
                Logger.warn(msg)
                warnings.append(msg)
            expected_next_offset = Packet.next_bit_offset(item)
            previous_item = item
        return warnings

    # Checks if the packet has any gaps or overlapped items:
    #
    # self.return [Boolean] True if the packet has no gaps or overlapped items:
    def packed(self):
        expected_next_offset = None
        for item in self.sorted_items:
            if expected_next_offset and item.bit_offset != expected_next_offset:
                return False
            expected_next_offset = Packet.next_bit_offset(item)
        return True

    # Returns the bit offset of the next item after the current item if items are packed:
    #
    # self.param item [PacketItem] The item to calculate the next offset for
    # self.return [Integer] Bit Offset of Next Item if Packed:
    @classmethod
    def next_bit_offset(cls, item: PacketItem):
        if item.array_size:
            if item.array_size > 0:
                next_offset = item.bit_offset + item.array_size
            else:
                next_offset = item.array_size
        else:
            next_offset = None
            if item.bit_offset > 0:
                if item.little_endian_bit_field:
                    # Bit offset always refers to the most significant bit of a bitfield
                    bits_remaining_in_last_byte = 8 - (item.bit_offset % 8)
                    if item.bit_size > bits_remaining_in_last_byte:
                        next_offset = item.bit_offset + bits_remaining_in_last_byte
            if not next_offset:
                if item.bit_size > 0:
                    next_offset = item.bit_offset + item.bit_size
                else:
                    next_offset = item.bit_size
        return next_offset

    # Indicates if the packet has been identified:
    # self.return [TrueClass or FalseClass]
    def identified(self):
        return self.target_name is not None and self.packet_name is not None

    # Define an item in the packet. This creates a new instance of the
    # item_class as given in the constructor and adds it to the items hash. It
    # also resizes the buffer to accomodate the new item.
    #
    # self.param name [String] Name of the item. Used by the items hash to retrieve
    #   the item.
    # self.param bit_offset [Integer] Bit offset of the item in the raw buffer
    # self.param bit_size [Integer] Bit size of the item in the raw buffer
    # self.param data_type [Symbol] Type of data contained by the item. This is
    #   dependant on the item_class but by default see StructureItem.
    # self.param array_size [Integer] Set to a non None value if the item is to:
    #   represented as an array.
    # self.param endianness [Symbol] Endianness of this item. By default the
    #   endianness as set in the constructure is used.
    # self.param overflow [Symbol] How to handle value overflows. This is
    #   dependant on the item_class but by default see StructureItem.
    # self.param format_string [String] String to pass to Kernel#sprintf
    # self.param read_conversion [Conversion] Conversion to apply case reading the
    #   item from the packet buffer
    # self.param write_conversion [Conversion] Conversion to apply before writing
    #   the item to the packet buffer
    # self.param id_value [Object] Set to something other than None to indicate that
    #   this item should be used to identify a buffer as this packet. The
    #   id_value should make sense according to the data_type.
    # self.return [PacketItem] The new packet item
    def define_item(
        self,
        name,
        bit_offset,
        bit_size,
        data_type,
        array_size=None,
        endianness=None,
        overflow="ERROR",
        format_string=None,
        read_conversion=None,
        write_conversion=None,
        id_value=None,
    ):
        if endianness is None:
            endianness = self.default_endianness
        item = super().define_item(
            name, bit_offset, bit_size, data_type, array_size, endianness, overflow
        )
        return self.packet_define_item(
            item, format_string, read_conversion, write_conversion, id_value
        )

    # Add an item to the packet by adding it to the items hash. It also
    # resizes the buffer to accomodate the new item.
    #
    # self.param item [PacketItem] Item to add to the packet
    # self.return [PacketItem] The same packet item
    def define(self, item):
        item = super().define(item)
        self.update_id_items(item)
        self.update_limits_items_cache(item)
        return item

    # Define an item at the end of the packet. This creates a new instance of the
    # item_class as given in the constructor and adds it to the items hash. It
    # also resizes the buffer to accomodate the new item.
    #
    # self.param name (see #define_item)
    # self.param bit_size (see #define_item)
    # self.param data_type (see #define_item)
    # self.param array_size (see #define_item)
    # self.param endianness (see #define_item)
    # self.param overflow (see #define_item)
    # self.param format_string (see #define_item)
    # self.param read_conversion (see #define_item)
    # self.param write_conversion (see #define_item)
    # self.param id_value (see #define_item)
    # self.return (see #define_item)
    def append_item(
        self,
        name,
        bit_size,
        data_type,
        array_size=None,
        endianness=None,
        overflow="ERROR",
        format_string=None,
        read_conversion=None,
        write_conversion=None,
        id_value=None,
    ):
        if endianness is None:
            endianness = self.default_endianness
        item = super().append_item(
            name, bit_size, data_type, array_size, endianness, overflow
        )
        return self.packet_define_item(
            item, format_string, read_conversion, write_conversion, id_value
        )

    # (see Structure#get_item)
    def get_item(self, name):
        try:
            return super().get_item(name)
        except AttributeError:
            raise AttributeError(
                f"Packet item '{self.target_name} {self.packet_name} {name.upper()}' does not exist"
            )

    # Read an item in the packet
    #
    # self.param item [PacketItem] Instance of PacketItem or one of its subclasses
    # self.param value_type [Symbol] How to convert the item before returning it.
    #   Must be one of {VALUE_TYPES}
    # self.param buffer (see Structure#read_item)
    # self.param given_raw Given raw value to optimize
    # self.return The value. 'FORMATTED' and 'WITH_UNITS' values are always returned
    #   as Strings. 'RAW' values will match their data_type. 'CONVERTED' values
    #   can be any type.
    def read_item(self, item, value_type="CONVERTED", buffer=None, given_raw=None):
        if not buffer:
            buffer = self._buffer
        if given_raw:
            # Must clone this since value is returned
            value = copy.copy(given_raw)
        else:
            value = super().read_item(item, "RAW", buffer)
        derived_raw = False
        if item.data_type == "DERIVED" and value_type == "RAW":
            value_type = "CONVERTED"
            derived_raw = True
        match value_type:
            case "RAW":
                # Done above
                pass
            case "CONVERTED" | "FORMATTED" | "WITH_UNITS":
                if item.read_conversion:
                    using_cached_value = False
                    check_cache = buffer == self.buffer
                    if check_cache and self.read_conversion_cache is not None:
                        with self.synchronize_allow_reads():
                            if self.read_conversion_cache.get(item.name):
                                value = self.read_conversion_cache[item.name]
                                # Make sure cached value is not modified by anyone by creating a deep copy
                                if type(value) is str:
                                    value = copy.copy(value)
                                elif type(value) is list:
                                    value = value.copy()
                                using_cached_value = True

                    if not using_cached_value:
                        if item.array_size:
                            for index, val in enumerate(value):
                                value[index] = item.read_conversion.call(
                                    val, self, buffer
                                )
                        else:
                            value = item.read_conversion.call(value, self, buffer)

                        if check_cache:
                            with self.synchronize_allow_reads():
                                if self.read_conversion_cache is None:
                                    self.read_conversion_cache = {}
                                self.read_conversion_cache[item.name] = value

                                # Make sure cached value is not modified by anyone by creating a deep copy
                                if type(value) is str:
                                    value = copy.copy(value)
                                elif type(value) is list:
                                    value = value.copy()

                # Derived raw values perform read_conversions but nothing else:
                if derived_raw:
                    return value

                # Convert from value to state if possible:
                if item.states:
                    if type(value) is list:
                        for index, val in enumerate(value):
                            key = item.states_by_value().get(value[index])
                            if key is not None:
                                value[index] = key
                            elif Packet.ANY_STATE in item.states_by_value().keys():
                                value[index] = item.states_by_value()[Packet.ANY_STATE]
                            else:
                                value[index] = self.apply_format_string_and_units(
                                    item, val, value_type
                                )
                    else:
                        key = item.states_by_value().get(value)
                        if key is not None:
                            value = key
                        elif Packet.ANY_STATE in item.states_by_value().keys():
                            value = item.states_by_value()[Packet.ANY_STATE]
                        else:
                            value = self.apply_format_string_and_units(
                                item, value, value_type
                            )
                else:
                    if type(value) is list:
                        for index, val in enumerate(value):
                            value[index] = self.apply_format_string_and_units(
                                item, val, value_type
                            )
                    else:
                        value = self.apply_format_string_and_units(
                            item, value, value_type
                        )
            case _:
                # Trim a potentially long string (like if they accidentally pass buffer as value_type):
                if len(str(value_type)) > 10:
                    value_type = str(value_type)[0:10]
                    # Ensure we're not trying to output binary
                    if not value_type.isascii():
                        value_type = simple_formatted(value_type)
                    value_type += "..."
                raise AttributeError(
                    f"Unknown value type '{value_type}', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'"
                )
        return value

    # Read a list of items in the structure
    #
    # self.param items [StructureItem] Array of PacketItem or one of its subclasses
    # self.param value_type [Symbol] Value type to read for every item
    # self.param buffer [String] The binary buffer to read the items from
    # self.return Hash of read names and values
    def read_items(self, items, value_type="RAW", buffer=None, raw_value=None):
        if not buffer:
            buffer = self._buffer
        if not buffer:
            buffer = self.allocate_buffer_if_needed()
        if value_type == "RAW":
            result = super().read_items(items, value_type, buffer)
            # Must handle DERIVED special
            for item in items:
                if item.data_type == "DERIVED":
                    result[item.name] = self.read_item(item, value_type, buffer)
        else:
            result = {}
            for item in items:
                result[item.name] = self.read_item(item, value_type, buffer)
        return result

    # Write an item in the packet
    #
    # self.param item [PacketItem] Instance of PacketItem or one of its subclasses
    # self.param value (see Structure#write_item)
    # self.param value_type (see #read_item)
    # self.param buffer (see Structure#write_item)
    def write_item(self, item, value, value_type="CONVERTED", buffer=None):
        if not buffer:
            buffer = self._buffer
        match value_type:
            case "RAW":
                super().write_item(item, value, value_type, buffer)
            case "CONVERTED":
                if item.states:
                    # Convert from state to value if possible:
                    state_value = item.states.get(str(value).upper())
                    if state_value:
                        value = state_value
                if item.write_conversion:
                    value = item.write_conversion.call(value, self, buffer)
                else:
                    if (
                        item.data_type == "DERIVED"
                        and self.accessor.enforce_derived_write_conversion(item)
                    ):
                        raise RuntimeError(
                            f"Cannot write DERIVED item {item.name} without a write conversion"
                        )
                try:
                    super().write_item(item, value, "RAW", buffer)
                except ValueError as error:
                    if (
                        item.states
                        and type(value) is str
                        and "invalid literal for" in repr(error)
                    ):
                        raise ValueError(
                            f"Unknown state {value} for {item.name}"
                        ) from error
                    else:
                        raise error
            case "FORMATTED" | "WITH_UNITS":
                raise AttributeError(f"Invalid value type on write= {value_type}")
            case _:
                # Trim potentially long string (like if they accidentally pass buffer as value_type):
                if len(str(value_type)) > 10:
                    value_type = str(value_type)[0:10]
                    # Ensure we're not trying to output binary
                    if not value_type.isascii():
                        value_type = simple_formatted(value_type)
                    value_type += "..."
                raise AttributeError(
                    f"Unknown value type '{value_type}', must be 'RAW', 'CONVERTED', 'FORMATTED', or 'WITH_UNITS'"
                )
        if self.read_conversion_cache:
            with self.synchronize():
                self.read_conversion_cache = {}

    # Write values to the buffer based on the item definitions
    #
    # self.param items [StructureItem] Array of StructureItem or one of its subclasses
    # self.param value [Object] Array of values based on the item definitions.
    # self.param value_type [Symbol] Value type of each item to write
    # self.param buffer [String] The binary buffer to write the values to
    def write_items(self, items, values, value_type="RAW", buffer=None):
        if not buffer:
            buffer = self._buffer
        if not buffer:
            buffer = self.allocate_buffer_if_needed()
        if value_type == "RAW":
            return super().write_items(items, values, value_type, buffer)
        else:
            for index, item in enumerate(items):
                self.write_item(item, values[index], value_type, buffer)
        return buffer

    # Read an item in the packet by name
    #
    # self.param name [String] Name of the item to read
    # self.param value_type (see #read_item)
    # self.param buffer (see #read_item)
    # self.return (see #read_item)
    def read(self, name, value_type="CONVERTED", buffer=None):
        if not buffer:
            buffer = self._buffer
        return super().read(name, value_type, buffer)

    # Write an item in the packet by name
    #
    # self.param name [String] Name of the item to write
    # self.param value (see #write_item)
    # self.param value_type (see #write_item)
    # self.param buffer (see #write_item)
    def write(self, name, value, value_type="CONVERTED", buffer=None):
        if not buffer:
            buffer = self._buffer
        super().write(name, value, value_type, buffer)

    # Read all items in the packet into an array of arrays
    #   [[item name, item value], ...]
    #
    # self.param value_type (see #read_item)
    # self.param buffer (see Structure#read_all)
    # self.param top (See Structure#read_all)
    # self.return (see Structure#read_all)
    def read_all(self, value_type="CONVERTED", buffer=None, top=True):
        if not buffer:
            buffer = self._buffer
        return super().read_all(value_type, buffer, top)

    # Read all items in the packet into an array of arrays
    #   [[item name, item value], [item limits state], ...]
    #
    # self.param value_type (see #read_all)
    # self.param buffer (see #read_all)
    # self.return [Array<String, Object, Symbol|None>] Returns an Array consisting
    #   of [item name, item value, item limits state] where the item limits
    #   state can be one of {OpenC3:'L'imits='LIMITS_STATES'}
    def read_all_with_limits_states(self, value_type="CONVERTED", buffer=None):
        if not buffer:
            buffer = self._buffer
        result = None
        with self.synchronize_allow_reads(True):
            result = self.read_all(value_type, buffer, False)
            for item in result:
                item.append(self.items[item[0]].limits.state)
        return result

    # Create a string that shows the name and value of each item in the packet
    #
    # self.param value_type (see #read_item)
    # self.param indent (see Structure#formatted)
    # self.param buffer (see Structure#formatted)
    # self.param ignored (see Structure#ignored)
    # self.return (see Structure#formatted)
    def formatted(self, value_type="CONVERTED", indent=0, buffer=None, ignored=None):
        if not buffer:
            buffer = self._buffer
        return super().formatted(value_type, indent, buffer, ignored)

    # Restore all items in the packet to their default value
    #
    # self.param buffer [String] Raw buffer of binary data
    # self.param skip_item_names [Array] Array of item names to skip
    # self.param use_templase [Boolean] Apply template before setting defaults (or not)
    def restore_defaults(self, buffer=None, skip_item_names=None, use_template=True):
        if not buffer:
            buffer = self._buffer
        if not buffer:
            buffer = self.allocate_buffer_if_needed()
        if skip_item_names:
            upcase_skip_item_names = [name.upper() for name in skip_item_names]
        if self.template and use_template:
            buffer[0:-1] = self.template
        for item in self.sorted_items:
            if item.name in Packet.RESERVED_ITEM_NAMES:
                continue
            if item.default is not None:
                if not (skip_item_names and item.name in upcase_skip_item_names):
                    self.write_item(item, item.default, "CONVERTED", buffer)

    # Define the reserved items on the current telemetry packet
    def define_reserved_items(self):
        item = self.define_item(
            "PACKET_TIMESECONDS",
            0,
            0,
            "DERIVED",
            None,
            self.default_endianness,
            "ERROR",
            "%0.6f",
            PacketTimeSecondsConversion(),
        )
        item.description = "OpenC3 Packet Time (UTC, Floating point, Unix epoch)"
        item = self.define_item(
            "PACKET_TIMEFORMATTED",
            0,
            0,
            "DERIVED",
            None,
            self.default_endianness,
            "ERROR",
            None,
            PacketTimeFormattedConversion(),
        )
        item.description = "OpenC3 Packet Time (Local time zone, Formatted string)"
        item = self.define_item(
            "RECEIVED_TIMESECONDS",
            0,
            0,
            "DERIVED",
            None,
            self.default_endianness,
            "ERROR",
            "%0.6f",
            ReceivedTimeSecondsConversion(),
        )
        item.description = "OpenC3 Received Time (UTC, Floating point, Unix epoch)"
        item = self.define_item(
            "RECEIVED_TIMEFORMATTED",
            0,
            0,
            "DERIVED",
            None,
            self.default_endianness,
            "ERROR",
            None,
            ReceivedTimeFormattedConversion(),
        )
        item.description = "OpenC3 Received Time (Local time zone, Formatted string)"
        item = self.define_item(
            "RECEIVED_COUNT",
            0,
            0,
            "DERIVED",
            None,
            self.default_endianness,
            "ERROR",
            None,
            ReceivedCountConversion(),
        )
        item.description = "OpenC3 packet received count"

    # Enable limits on an item by name
    #
    # self.param name [String] Name of the item to enable limits
    def enable_limits(self, name):
        self.get_item(name).limits.enabled = True

    # Disable limits on an item by name
    #
    # self.param name [String] Name of the item to disable limits
    def disable_limits(self, name):
        item = self.get_item(name)
        item.limits.enabled = False
        if not item.limits.state == "STALE":
            old_limits_state = item.limits.state
            item.limits.state = None
            if self.limits_change_callback:
                self.limits_change_callback.call(
                    self, item, old_limits_state, None, False
                )

    # Add an item to the limits items cache if necessary.:
    # You MUST call this after adding limits to an item
    # This is an optimization so we don't have to iterate through all the items case
    # checking for limits.
    def update_limits_items_cache(self, item):
        if item.limits.values or item.state_colors:
            if not self.limits_items_hash.get(item.name):
                self.limits_items.append(item)
                self.limits_items_hash[item.name] = True

    # Return an array of arrays indicating all items in the packet that are out of limits
    #   [[target name, packet name, item name, item limits state], ...]
    #
    # self.return [Array<Array<String, String, String, Symbol>>]
    def out_of_limits(self):
        items = []
        if not self.limits_items:
            return items

        for item in self.limits_items:
            if (
                item.limits.enabled
                and item.limits.state
                and item.limits.state in PacketItemLimits.OUT_OF_LIMITS_STATES
            ):
                items.append(
                    [self.target_name, self.packet_name, item.name, item.limits.state]
                )
        return items

    # Check all the items in the packet against their defined limits. Update
    # their internal limits state and persistence and call the
    # limits_change_callback as necessary.
    #
    # self.param limits_set [Symbol] Which limits set to check the item values
    #   against.
    # self.param ignore_persistence [Boolean] Whether to ignore persistence case
    #   checking for out of limits
    def check_limits(self, limits_set="DEFAULT", ignore_persistence=False):
        if not self.limits_items:
            return

        for item in self.limits_items:
            # Verify limits monitoring is enabled for this item
            if item.limits.enabled:
                value = self.read_item(item)

                # Handle state monitoring and value monitoring differently
                if item.states is not None:
                    self.handle_limits_states(item, value)
                elif item.limits.values is not None:
                    self.handle_limits_values(
                        item, value, limits_set, ignore_persistence
                    )

    # Reset temporary packet data
    # This includes packet received time, received count, and processor state
    def reset(self):
        # The SYSTEM META packet is a special case that does not get reset
        if self.target_name == "SYSTEM" and self.packet_name == "META":
            return

        self.received_time = None
        self.received_count = 0
        self.stored = False
        self.extra = None
        if self.read_conversion_cache is not None:
            with self.synchronize():
                self.read_conversion_cache = {}
        if not self.processors:
            return

        for _, processor in self.processors:
            processor.reset

    # Make a light weight clone of this packet. This only creates a new buffer
    # of data and clones the processors. The defined packet items are the same.
    #
    # self.return [Packet] A copy of the current packet with a new underlying
    #   buffer of data and processors
    def clone(self):
        packet = super().clone()
        if self.processors is not None:
            packet.processors = copy.deepcopy(packet.processors)
        packet.read_conversion_cache = None
        if packet.extra is not None:
            packet.extra = copy.deepcopy(packet.extra)
        return packet

    def update_id_items(self, item):
        if item.id_value is not None:
            if self.id_items is None:
                self.id_items = []
            # Add to Id Items
            if len(self.id_items) > 0:
                last_item = self.id_items[-1]
                self.id_items.append(item)
                # If the current item or last item have a negative offset then we have
                # to re-sort. We also re-sort if the current item is less than the last:
                # item because we are inserting.
                if (
                    last_item.bit_offset <= 0
                    or item.bit_offset <= 0
                    or item.bit_offset < last_item.bit_offset
                ):
                    self.id_items.sort()
            else:
                self.id_items.append(item)
        return item

    def to_config(self, cmd_or_tlm):
        config = ""

        if cmd_or_tlm == "TELEMETRY":
            config += f'TELEMETRY {quote_if_necessary(self.target_name)} {quote_if_necessary(self.packet_name)} {self.default_endianness} "{self.description}"\n'
        else:
            config += f'COMMAND {quote_if_necessary(self.target_name)} {quote_if_necessary(self.packet_name)} {self.default_endianness} "{self.description}"\n'
        if self.short_buffer_allowed:
            config += "  ALLOW_SHORT\n"
        if self.hazardous:
            config += f"  HAZARDOUS {self.hazardous_description.quote_if_necessary}\n"
        if self.messages_disabled:
            config += "  DISABLE_MESSAGES\n"
        if self.disabled:
            config += "  DISABLED\n"
        elif self.hidden:
            config += "  HIDDEN\n"

        if self.processors:
            for _, processor in self.processors:
                config += processor.to_config

        if self.meta:
            for key, values in self.meta:
                vals = " ".join([quote_if_necessary(a) for a in values])
                config += f"  META {quote_if_necessary(key)} {vals}\n"

        # Items with derived items last
        for item in self.sorted_items:
            if item.data_type != "DERIVED":
                config += item.to_config(cmd_or_tlm, self.default_endianness)
        for item in self.sorted_items:
            if item.data_type == "DERIVED":
                if item.name not in Packet.RESERVED_ITEM_NAMES:
                    config += item.to_config(cmd_or_tlm, self.default_endianness)
        return config

    def as_json(self):
        config = {}
        config["target_name"] = self.target_name
        config["packet_name"] = self.packet_name
        config["endianness"] = self.default_endianness
        config["description"] = self.description
        if self.short_buffer_allowed:
            config["short_buffer_allowed"] = True
        if self.hazardous:
            config["hazardous"] = True
        if self.hazardous_description:
            config["hazardous_description"] = self.hazardous_description
        if self.messages_disabled:
            config["messages_disabled"] = True
        if self.disabled:
            config["disabled"] = True
        if self.hidden:
            config["hidden"] = True
        config["accessor"] = self.accessor.__class__.__name__
        # config["accessor_args"] = self.accessor.args
        if self.template:
            config["template"] = base64.b64encode(self.template)

        if self.processors:
            processors = []
            for _, processor in self.processors():
                processors << processor.as_json()
            config["processors"] = processors

        if self.meta:
            config["meta"] = self.meta

        items = []
        config["items"] = items
        # Items with derived items last
        for item in self.sorted_items:
            if item.data_type != "DERIVED":
                items.append(item.as_json())

        for item in self.sorted_items:
            if item.data_type == "DERIVED":
                items.append(item.as_json())

        return config

    @classmethod
    def from_json(cls, hash):
        endianness = hash.get("endianness")
        packet = Packet(
            hash["target_name"], hash["packet_name"], endianness, hash["description"]
        )
        packet.short_buffer_allowed = hash.get("short_buffer_allowed")
        packet.hazardous = hash.get("hazardous")
        packet.hazardous_description = hash.get("hazardous_description")
        packet.messages_disabled = hash.get("messages_disabled")
        packet.disabled = hash.get("disabled")
        packet.hidden = hash.get("hidden")
        if hash["accessor"]:
            try:
                filename = class_name_to_filename(hash["accessor"])
                accessor = get_class_from_module(
                    f"openc3.accessors.{filename}", hash["accessor"]
                )
                if hash.get("accessor_args") and len(hash["accessor_args"]) > 0:
                    packet.accessor = accessor(*hash["accessor_args"])
                else:
                    packet.accessor = accessor()
            except RuntimeError as error:
                Logger.error(
                    f"#{packet.target_name} #{packet.packet_name} accessor of #{hash['accessor']} could not be found due to #{repr(error)}"
                )
        if hash["template"]:
            packet.template = base64.b64decode(hash["template"])
        packet.meta = hash.get("meta")
        # Can't convert processors
        for item in hash["items"]:
            packet.define(PacketItem.from_json(item))
        return packet

    def decom(self):
        # Read all the RAW at once because this could be optimized by the accessor
        json_hash = self.read_items(self.sorted_items)

        # Decom extra into the values (overrides packet items)
        if self.extra is not None:
            for key, value in self.extra.items():
                json_hash[key.upper()] = value

        # Now read all other value types - no accessor required
        for item in self.sorted_items:
            given_raw = json_hash[item.name]
            if item.states or (item.read_conversion and item.data_type != "DERIVED"):
                json_hash[f"{item.name}__C"] = self.read_item(
                    item, "CONVERTED", self.buffer, given_raw
                )
            if item.format_string:
                json_hash[f"{item.name}__F"] = self.read_item(
                    item, "FORMATTED", self.buffer, given_raw
                )
            if item.units:
                json_hash[f"{item.name}__U"] = self.read_item(
                    item, "WITH_UNITS", self.buffer, given_raw
                )
            limits_state = item.limits.state
            if limits_state:
                json_hash[f"{item.name}__L"] = limits_state

        return json_hash

    # Performs packet specific processing on the packet.
    # Intended to only be run once for each packet received
    def process(self, buffer=None):
        if not buffer:
            buffer = self._buffer
        if not self.processors:
            return

        for _, processor in self.processors.items():
            processor.call(self, buffer)

    def handle_limits_states(self, item, value):
        # Retrieve limits state for the given value
        limits_state = item.state_colors.get(value)

        if item.limits.state != limits_state:  # PacketItemLimits state has changed
            # Save old limits state
            old_limits_state = item.limits.state
            # Update to new limits state
            item.limits.state = limits_state

            if self.limits_change_callback:
                if item.limits.state is None:
                    self.limits_change_callback.call(
                        self, item, old_limits_state, value, False
                    )
                else:
                    self.limits_change_callback.call(
                        self, item, old_limits_state, value, True
                    )

    def handle_limits_values(self, item, value, limits_set, ignore_persistence):
        # Retrieve limits settings for the specified limits_set
        limits = item.limits.values[limits_set]

        # Use the default limits set if limits aren't specified for the:
        # particular limits set
        if not limits:
            limits = item.limits.values["DEFAULT"]

        # Extract limits from array
        red_low = limits[0]
        yellow_low = limits[1]
        yellow_high = limits[2]
        red_high = limits[3]
        if len(limits) > 4:
            green_low = limits[4]
            green_high = limits[5]
        else:
            green_low = None
            green_high = None
        limits_state = None

        # Determine the limits_state based on the limits values and the current
        # value of the item
        if value > yellow_low:
            if value < yellow_high:
                if green_low:
                    if value < green_high:
                        if value > green_low:
                            limits_state = "BLUE"
                        else:
                            limits_state = "GREEN_LOW"
                    else:
                        limits_state = "GREEN_HIGH"
                else:
                    limits_state = "GREEN"
            elif value < red_high:
                limits_state = "YELLOW_HIGH"
            else:
                limits_state = "RED_HIGH"
        else:  # value <= yellow_low
            if value > red_low:
                limits_state = "YELLOW_LOW"
            else:
                limits_state = "RED_LOW"

        if item.limits.state != limits_state:  # limits state has changed
            # Save old limits state for use in the callback
            old_limits_state = item.limits.state

            item.limits.persistence_count += 1

            # Check for item to achieve its persistence which means we
            # have to update the state and call the callback
            # Note case going back to green (or blue) persistence is ignored
            if (
                item.limits.persistence_count >= item.limits.persistence_setting
            ) or ignore_persistence:
                item.limits.state = limits_state

                # Additional actions for limits change
                if self.limits_change_callback:
                    self.limits_change_callback.call(
                        self, item, old_limits_state, value, True
                    )

                # Clear persistence since we've entered a new state
                item.limits.persistence_count = 0
        else:  # limits state has not changed so clear persistence
            item.limits.persistence_count = 0

    def apply_format_string_and_units(self, item, value, value_type):
        if value_type == "FORMATTED" or value_type == "WITH_UNITS":
            if item.format_string and value is not None:
                value = f"{item.format_string}" % value
            else:
                value = str(value)
        if value_type == "WITH_UNITS" and item.units:
            value += " " + item.units
        return value

    def packet_define_item(
        self, item, format_string, read_conversion, write_conversion, id_value
    ):
        item.format_string = format_string
        item.read_conversion = read_conversion
        item.write_conversion = write_conversion

        # Change id_value to the correct type
        if id_value is not None:
            item.id_value = id_value
            self.update_id_items(item)
        return item
