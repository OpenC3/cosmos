# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import math
import os

from lxml import etree  # type: ignore[import]

from openc3.conversions.polynomial_conversion import PolynomialConversion


class XtceConverter:
    """Converts OpenC3 packet definitions to XTCE (XML Telemetric and Command Exchange) format"""

    # XML namespaces are opaque identifiers matched by exact string comparison, not URLs
    # that get fetched, so these must stay http to match the namespaces OMG and W3C
    # defined. The schema location below is the only URL actually dereferenced and it
    # uses https.
    # XTCE 1.2, matching the Ruby converter so both implementations emit the same version
    XTCE_NAMESPACE = "http://www.omg.org/spec/XTCE/20180204"  # NOSONAR
    XSI_NAMESPACE = "http://www.w3.org/2001/XMLSchema-instance"  # NOSONAR
    SCHEMA_LOCATION = (
        "http://www.omg.org/spec/XTCE/20180204 https://www.omg.org/spec/XTCE/20180204/SpaceSystem.xsd"  # NOSONAR
    )

    # IntegerRangeType declares minInclusive / maxInclusive as xs:long, so an integer
    # range outside these bounds (a full 64 bit UINT, for example) cannot be expressed.
    # FloatRangeType uses xs:double and needs no such clamp.
    XS_LONG_MIN = -9223372036854775808
    XS_LONG_MAX = 9223372036854775807

    @classmethod
    def convert(cls, commands, telemetry, output_dir):
        """Output packet definitions in XTCE format

        Args:
            commands (dict): Hash of all command packets keyed by target name
            telemetry (dict): Hash of all telemetry packets keyed by target name
            output_dir (str): Directory to write XTCE files to
        """
        return cls(commands, telemetry, output_dir)

    def __init__(self, commands, telemetry, output_dir):
        """Initialize and perform the XTCE conversion

        Args:
            commands (dict): Hash of all command packets keyed by target name
            telemetry (dict): Hash of all telemetry packets keyed by target name
            output_dir (str): Directory to write XTCE files to
        """
        os.makedirs(output_dir, exist_ok=True)

        # Build target list
        targets = set()
        for target_name in telemetry:
            targets.add(target_name)
        for target_name in commands:
            targets.add(target_name)

        for target_name in targets:
            if target_name == "UNKNOWN":
                continue

            # Reverse order of packets for the target so things are in expected order for XTCE
            self._reverse_packet_order(target_name, commands)
            self._reverse_packet_order(target_name, telemetry)

            # Create output directory structure
            target_dir = os.path.join(output_dir, target_name, "cmd_tlm")
            os.makedirs(target_dir, exist_ok=True)
            filename = os.path.join(target_dir, f"{target_name.lower()}.xtce")

            # Remove existing file if it exists
            if os.path.exists(filename):
                os.remove(filename)

            # Create the XTCE file for this target
            self._create_xtce_file(filename, target_name, commands, telemetry)

    def _reverse_packet_order(self, target_name, cmd_or_tlm_hash):
        """Reverse the order of packets in the hash

        Args:
            target_name (str): Name of the target
            cmd_or_tlm_hash (dict): Hash of packets to reverse
        """
        if target_name not in cmd_or_tlm_hash:
            return

        packets = []
        names_to_remove = []

        for packet_name, packet in cmd_or_tlm_hash[target_name].items():
            packets.append(packet)
            names_to_remove.append(packet_name)

        # Remove all packets
        for name in names_to_remove:
            del cmd_or_tlm_hash[target_name][name]

        # Add them back in reverse order
        for packet in reversed(packets):
            cmd_or_tlm_hash[target_name][packet.packet_name] = packet

    def _create_xtce_file(self, filename, target_name, commands, telemetry):
        """Create an XTCE XML file for a target

        Args:
            filename (str): Path to the output file
            target_name (str): Name of the target
            commands (dict): Command packets hash
            telemetry (dict): Telemetry packets hash
        """
        # Create root element with namespaces
        nsmap = {
            "xtce": self.XTCE_NAMESPACE,
            "xsi": self.XSI_NAMESPACE,
        }
        root = etree.Element(
            f"{{{self.XTCE_NAMESPACE}}}SpaceSystem",
            nsmap=nsmap,
            attrib={
                "name": target_name,
                f"{{{self.XSI_NAMESPACE}}}schemaLocation": self.SCHEMA_LOCATION,
            },
        )

        # Create telemetry metadata
        self._create_telemetry(root, telemetry, target_name)

        # Create command metadata
        self._create_commands(root, commands, target_name)

        # Write to file
        tree = etree.ElementTree(root)
        tree.write(filename, encoding="UTF-8", xml_declaration=True, pretty_print=True)

    def _create_telemetry(self, root, telemetry, target_name):
        """Create telemetry metadata in XTCE format

        Args:
            root: XML root element
            telemetry (dict): Telemetry packets hash
            target_name (str): Name of the target
        """
        # Nothing to emit for targets without telemetry (e.g. command-only targets).
        # An empty ParameterTypeSet/ParameterSet is invalid per the XTCE schema.
        if target_name not in telemetry:
            return

        # Gather and make unique all the packet items
        unique_items = self._get_unique(telemetry[target_name])

        tlm_meta = etree.SubElement(root, f"{{{self.XTCE_NAMESPACE}}}TelemetryMetaData")

        # ParameterTypeSet / ParameterSet (only when non-empty; the schema requires children)
        if unique_items:
            param_type_set = etree.SubElement(tlm_meta, f"{{{self.XTCE_NAMESPACE}}}ParameterTypeSet")
            for _item_name, item in unique_items.items():
                self._to_xtce_type(item, "Parameter", param_type_set)

            param_set = etree.SubElement(tlm_meta, f"{{{self.XTCE_NAMESPACE}}}ParameterSet")
            for _item_name, item in unique_items.items():
                self._to_xtce_item(item, "Parameter", param_set)

        # ContainerSet
        container_set = etree.SubElement(tlm_meta, f"{{{self.XTCE_NAMESPACE}}}ContainerSet")
        for packet_name, packet in telemetry[target_name].items():
            attrs = {"name": packet_name}
            if packet.description:
                attrs["shortDescription"] = packet.description

            # A RestrictionCriteria only exists on a BaseContainer, so a packet with ID
            # items needs an abstract container to inherit from and restrict. Without ID
            # items there is nothing to restrict, so emit a single container holding the
            # entries directly rather than an inheritance pair that says nothing.
            if packet.id_items and len(packet.id_items) > 0:
                base_attrs = {"name": f"{packet_name}_Base", "abstract": "true"}
                base_container = etree.SubElement(
                    container_set,
                    f"{{{self.XTCE_NAMESPACE}}}SequenceContainer",
                    attrib=base_attrs,
                )
                self._process_entry_list(base_container, packet, "TELEMETRY")

                container = etree.SubElement(
                    container_set,
                    f"{{{self.XTCE_NAMESPACE}}}SequenceContainer",
                    attrib=attrs,
                )
                etree.SubElement(container, f"{{{self.XTCE_NAMESPACE}}}EntryList")
                base_container_elem = etree.SubElement(
                    container,
                    f"{{{self.XTCE_NAMESPACE}}}BaseContainer",
                    attrib={"containerRef": f"{packet_name}_Base"},
                )
                restriction = etree.SubElement(
                    base_container_elem,
                    f"{{{self.XTCE_NAMESPACE}}}RestrictionCriteria",
                )
                comparison_list = etree.SubElement(restriction, f"{{{self.XTCE_NAMESPACE}}}ComparisonList")
                for item in packet.id_items:
                    etree.SubElement(
                        comparison_list,
                        f"{{{self.XTCE_NAMESPACE}}}Comparison",
                        attrib={
                            "parameterRef": item.name,
                            "value": str(item.id_value),
                        },
                    )
            else:
                container = etree.SubElement(
                    container_set,
                    f"{{{self.XTCE_NAMESPACE}}}SequenceContainer",
                    attrib=attrs,
                )
                self._process_entry_list(container, packet, "TELEMETRY")

    def _create_commands(self, root, commands, target_name):
        """Create command metadata in XTCE format

        Args:
            root: XML root element
            commands (dict): Command packets hash
            target_name (str): Name of the target
        """
        if target_name not in commands:
            return

        cmd_meta = etree.SubElement(root, f"{{{self.XTCE_NAMESPACE}}}CommandMetaData")

        # ArgumentTypeSet
        arg_type_set = etree.SubElement(cmd_meta, f"{{{self.XTCE_NAMESPACE}}}ArgumentTypeSet")
        unique_items = self._get_unique(commands[target_name])
        for _arg_name, arg in unique_items.items():
            self._to_xtce_type(arg, "Argument", arg_type_set)

        # MetaCommandSet
        meta_cmd_set = etree.SubElement(cmd_meta, f"{{{self.XTCE_NAMESPACE}}}MetaCommandSet")
        for packet_name, packet in commands[target_name].items():
            has_id_items = bool(packet.id_items)

            # The ID values are ArgumentAssignments on a BaseMetaCommand, so a packet
            # with ID items needs an abstract MetaCommand to hold the arguments and
            # entries and inherit from. A packet without them gets neither, matching
            # the Ruby converter rather than emitting an unused abstract command.
            if has_id_items:
                arg_and_container_parent = etree.SubElement(
                    meta_cmd_set,
                    f"{{{self.XTCE_NAMESPACE}}}MetaCommand",
                    attrib={"name": f"{packet_name}_Base", "abstract": "true"},
                )
            else:
                attrs = {"name": packet_name}
                if packet.description:
                    attrs["shortDescription"] = packet.description
                arg_and_container_parent = etree.SubElement(
                    meta_cmd_set, f"{{{self.XTCE_NAMESPACE}}}MetaCommand", attrib=attrs
                )

            # ArgumentList. An empty one is not valid, so a packet of nothing but
            # DERIVED items gets none.
            arg_items = [item for item in packet.sorted_items if item.data_type != "DERIVED"]
            if arg_items:
                arg_list = etree.SubElement(arg_and_container_parent, f"{{{self.XTCE_NAMESPACE}}}ArgumentList")
                for item in arg_items:
                    self._to_xtce_item(item, "Argument", arg_list)

            # CommandContainer
            cmd_container = etree.SubElement(
                arg_and_container_parent,
                f"{{{self.XTCE_NAMESPACE}}}CommandContainer",
                attrib={"name": f"{target_name}_{packet_name}_CommandContainer"},
            )
            self._process_entry_list(cmd_container, packet, "COMMAND")

            if not has_id_items:
                continue

            # Actual MetaCommand
            attrs = {"name": packet_name}
            if packet.description:
                attrs["shortDescription"] = packet.description
            meta_cmd = etree.SubElement(meta_cmd_set, f"{{{self.XTCE_NAMESPACE}}}MetaCommand", attrib=attrs)
            base_meta_cmd = etree.SubElement(
                meta_cmd,
                f"{{{self.XTCE_NAMESPACE}}}BaseMetaCommand",
                attrib={"metaCommandRef": f"{packet_name}_Base"},
            )
            arg_assign_list = etree.SubElement(base_meta_cmd, f"{{{self.XTCE_NAMESPACE}}}ArgumentAssignmentList")
            for item in packet.id_items:
                etree.SubElement(
                    arg_assign_list,
                    f"{{{self.XTCE_NAMESPACE}}}ArgumentAssignment",
                    attrib={
                        "argumentName": item.name,
                        "argumentValue": str(item.id_value),
                    },
                )

    def _get_unique(self, packets):
        """Get unique items from packets

        Args:
            packets (dict): Hash of packets

        Returns:
            dict: Hash of unique items
        """
        unique = {}
        for _packet_name, packet in packets.items():
            for item in packet.sorted_items:
                if item.data_type == "DERIVED":
                    continue

                if item.name not in unique:
                    unique[item.name] = []
                unique[item.name].append(item)

        # Flatten arrays with single items, keep first for duplicates
        for item_name, unique_items in unique.items():
            if len(unique_items) <= 1:
                unique[item_name] = unique_items[0] if unique_items else None
            else:
                # TODO: Verify all items in the array are exactly the same
                unique[item_name] = unique_items[0]

        return unique

    def _process_entry_list(self, parent, packet, cmd_vs_tlm):
        """Process packet entry list for XTCE

        Args:
            parent: Parent XML element
            packet: Packet to process
            cmd_vs_tlm (str): "COMMAND" or "TELEMETRY"
        """
        type_name = "Argument" if cmd_vs_tlm == "COMMAND" else "Parameter"
        entry_list = etree.SubElement(parent, f"{{{self.XTCE_NAMESPACE}}}EntryList")

        # packed is a method on Packet, not a property, so it must be called.
        # Unpacked packets need an explicit LocationInContainerInBits per entry.
        packed = packet.packed()
        for item in packet.sorted_items:
            if item.data_type == "DERIVED":
                continue

            # Handle arrays
            if item.array_size:
                # XTCE 1.2 gives Array{Argument,Parameter}RefEntry a dedicated
                # argumentRef / parameterRef attribute, so derive it from the type.
                array_ref = etree.SubElement(
                    entry_list,
                    f"{{{self.XTCE_NAMESPACE}}}Array{type_name}RefEntry",
                    attrib={f"{type_name.lower()}Ref": item.name},
                )
                if not packed:
                    self._set_fixed_value(array_ref, item)

                dim_list = etree.SubElement(array_ref, f"{{{self.XTCE_NAMESPACE}}}DimensionList")
                dimension = etree.SubElement(dim_list, f"{{{self.XTCE_NAMESPACE}}}Dimension")
                start_idx = etree.SubElement(dimension, f"{{{self.XTCE_NAMESPACE}}}StartingIndex")
                etree.SubElement(start_idx, f"{{{self.XTCE_NAMESPACE}}}FixedValue").text = "0"
                end_idx = etree.SubElement(dimension, f"{{{self.XTCE_NAMESPACE}}}EndingIndex")
                etree.SubElement(end_idx, f"{{{self.XTCE_NAMESPACE}}}FixedValue").text = str(
                    self._array_ending_index(item)
                )
            else:
                # Regular item
                ref_attrs = {f"{type_name.lower()}Ref": item.name}
                if packed:
                    etree.SubElement(
                        entry_list,
                        f"{{{self.XTCE_NAMESPACE}}}{type_name}RefEntry",
                        attrib=ref_attrs,
                    )
                else:
                    ref_entry = etree.SubElement(
                        entry_list,
                        f"{{{self.XTCE_NAMESPACE}}}{type_name}RefEntry",
                        attrib=ref_attrs,
                    )
                    self._set_fixed_value(ref_entry, item)

    def _set_fixed_value(self, parent, item):
        """Set fixed value location for an item

        Args:
            parent: Parent XML element
            item: Packet item
        """
        if item.bit_offset >= 0:
            location = etree.SubElement(
                parent,
                f"{{{self.XTCE_NAMESPACE}}}LocationInContainerInBits",
                attrib={"referenceLocation": "containerStart"},
            )
            etree.SubElement(location, f"{{{self.XTCE_NAMESPACE}}}FixedValue").text = str(item.bit_offset)
        else:
            location = etree.SubElement(
                parent,
                f"{{{self.XTCE_NAMESPACE}}}LocationInContainerInBits",
                attrib={"referenceLocation": "containerEnd"},
            )
            etree.SubElement(location, f"{{{self.XTCE_NAMESPACE}}}FixedValue").text = str(-item.bit_offset)

    def _array_ending_index(self, item):
        """Ending index of an array item's single dimension

        XTCE indices are inclusive, so an array of N elements ends at N - 1. A
        non-positive bit size means a variable length array whose element count isn't
        known at export time, which is reported as a single element.

        Args:
            item: Packet item with an array_size

        Returns:
            int: The EndingIndex FixedValue
        """
        if item.bit_size <= 0 or item.array_size <= 0:
            return 0
        return (item.array_size // item.bit_size) - 1

    def _to_xtce_type(self, item, param_or_arg, parent):
        """Convert item to XTCE type definition

        Args:
            item: Packet item
            param_or_arg (str): "Parameter" or "Argument"
            parent: Parent XML element
        """
        # Convert based on data type
        if item.data_type in ["INT", "UINT"]:
            self._to_xtce_int(item, param_or_arg, parent)
        elif item.data_type == "FLOAT":
            self._to_xtce_float(item, param_or_arg, parent)
        elif item.data_type == "STRING":
            self._to_xtce_string(item, param_or_arg, parent, "String")
        elif item.data_type == "BLOCK":
            self._to_xtce_string(item, param_or_arg, parent, "Binary")
        elif item.data_type == "DERIVED":
            raise ValueError("DERIVED data type not supported in XTCE")

        # Handle arrays
        if item.array_size:
            attrs = {"name": f"{item.name}_ArrayType"}
            if item.description:
                attrs["shortDescription"] = item.description
            attrs["arrayTypeRef"] = f"{item.name}_Type"
            # XTCE 1.2 replaced the numberOfDimensions attribute with a required
            # DimensionList. OpenC3 only supports one-dimensional arrays, which is a
            # single Dimension; the indices give that dimension's length, not the
            # number of dimensions.
            array_type = etree.SubElement(
                parent,
                f"{{{self.XTCE_NAMESPACE}}}Array{param_or_arg}Type",
                attrib=attrs,
            )
            dim_list = etree.SubElement(array_type, f"{{{self.XTCE_NAMESPACE}}}DimensionList")
            dimension = etree.SubElement(dim_list, f"{{{self.XTCE_NAMESPACE}}}Dimension")
            start_idx = etree.SubElement(dimension, f"{{{self.XTCE_NAMESPACE}}}StartingIndex")
            etree.SubElement(start_idx, f"{{{self.XTCE_NAMESPACE}}}FixedValue").text = "0"
            end_idx = etree.SubElement(dimension, f"{{{self.XTCE_NAMESPACE}}}EndingIndex")
            etree.SubElement(end_idx, f"{{{self.XTCE_NAMESPACE}}}FixedValue").text = str(self._array_ending_index(item))

    def _to_xtce_int(self, item, param_or_arg, parent):
        """Convert integer item to XTCE

        Args:
            item: Packet item
            param_or_arg (str): "Parameter" or "Argument"
            parent: Parent XML element
        """
        attrs = {"name": f"{item.name}_Type"}
        if item.default and item.array_size is None:
            attrs["initialValue"] = str(item.default)
        if item.description:
            attrs["shortDescription"] = item.description

        # Check if item has states and set initial value from states
        if item.states and item.default:
            for state_name, state_value in item.states.items():
                if state_value == item.default:
                    attrs["initialValue"] = state_name
                    break

        signed = item.data_type == "INT"
        # XTCE 1.2 corrected the 1.0 'twosCompliment' misspelling
        encoding = "twosComplement" if signed else "unsigned"

        if item.states:
            # Enumerated type
            enum_type = etree.SubElement(
                parent,
                f"{{{self.XTCE_NAMESPACE}}}Enumerated{param_or_arg}Type",
                attrib=attrs,
            )
            self._to_xtce_units(item, enum_type)
            enum_encoding = etree.SubElement(
                enum_type,
                f"{{{self.XTCE_NAMESPACE}}}IntegerDataEncoding",
                attrib={"sizeInBits": str(item.bit_size), "encoding": encoding},
            )
            self._to_xtce_endianness(item, enum_encoding)
            enum_list = etree.SubElement(enum_type, f"{{{self.XTCE_NAMESPACE}}}EnumerationList")
            for state_name, state_value in item.states.items():
                if state_value == "ANY":  # Skip special OpenC3 state
                    continue
                etree.SubElement(
                    enum_list,
                    f"{{{self.XTCE_NAMESPACE}}}Enumeration",
                    attrib={"value": str(state_value), "label": state_name},
                )
        else:
            # Check for polynomial conversion
            has_poly_conversion = (item.read_conversion and isinstance(item.read_conversion, PolynomialConversion)) or (
                item.write_conversion and isinstance(item.write_conversion, PolynomialConversion)
            )

            if has_poly_conversion:
                type_string = f"Float{param_or_arg}Type"
            else:
                type_string = f"Integer{param_or_arg}Type"
                attrs["signed"] = "true" if signed else "false"

            int_type = etree.SubElement(parent, f"{{{self.XTCE_NAMESPACE}}}{type_string}", attrib=attrs)
            self._to_xtce_units(item, int_type)

            encoding_elem = etree.SubElement(
                int_type,
                f"{{{self.XTCE_NAMESPACE}}}IntegerDataEncoding",
                attrib={"sizeInBits": str(item.bit_size), "encoding": encoding},
            )
            self._to_xtce_endianness(item, encoding_elem)
            if has_poly_conversion:
                self._to_xtce_conversion(item, encoding_elem)

            # ValidRange comes first: it's on IntegerDataType while DefaultAlarm is on
            # the extending Integer{Parameter,Argument}Type, and the XSD requires the
            # base type's elements before the extension's.
            self._to_xtce_valid_range(item, param_or_arg, int_type)
            self._to_xtce_limits(item, int_type)

    def _to_xtce_float(self, item, param_or_arg, parent):
        """Convert float item to XTCE

        Args:
            item: Packet item
            param_or_arg (str): "Parameter" or "Argument"
            parent: Parent XML element
        """
        attrs = {"name": f"{item.name}_Type", "sizeInBits": str(item.bit_size)}
        if item.default and item.array_size is None:
            attrs["initialValue"] = str(item.default)
        if item.description:
            attrs["shortDescription"] = item.description

        float_type = etree.SubElement(parent, f"{{{self.XTCE_NAMESPACE}}}Float{param_or_arg}Type", attrib=attrs)
        self._to_xtce_units(item, float_type)

        has_poly_conversion = (item.read_conversion and isinstance(item.read_conversion, PolynomialConversion)) or (
            item.write_conversion and isinstance(item.write_conversion, PolynomialConversion)
        )

        encoding_elem = etree.SubElement(
            float_type,
            f"{{{self.XTCE_NAMESPACE}}}FloatDataEncoding",
            attrib={"sizeInBits": str(item.bit_size), "encoding": "IEEE754_1985"},
        )
        self._to_xtce_endianness(item, encoding_elem)
        if has_poly_conversion:
            self._to_xtce_conversion(item, encoding_elem)

        # ValidRange before DefaultAlarm, same base / extension ordering as the int type
        self._to_xtce_valid_range(item, param_or_arg, float_type)
        self._to_xtce_limits(item, float_type)

    def _to_xtce_string(self, item, param_or_arg, parent, string_or_binary):
        """Convert string/binary item to XTCE

        Args:
            item: Packet item
            param_or_arg (str): "Parameter" or "Argument"
            parent: Parent XML element
            string_or_binary (str): "String" or "Binary"
        """
        attrs = {"name": f"{item.name}_Type"}
        if string_or_binary == "String":
            attrs["characterWidth"] = "8"

        if item.default and item.array_size is None:
            try:
                default = item.default
                # A STRING default comes out of the config parser as str, a BLOCK
                # default as bytes / bytearray. Both are compared as bytes below.
                if isinstance(default, str):
                    default = default.encode("utf-8")
                if isinstance(default, bytes | bytearray):
                    if string_or_binary == "Binary":
                        # Binary initialValue is xs:hexBinary: raw hex digits, no 0x
                        # prefix. Upper case is hexBinary's canonical form and matches
                        # the Ruby converter.
                        attrs["initialValue"] = default.hex().upper()
                    elif all(32 <= b < 127 for b in default) and bytes(default[0:2]).upper() != b"0X":
                        # String initialValue is the value itself, unquoted
                        attrs["initialValue"] = default.decode("utf-8")
                    else:
                        # XML can't carry the non printable bytes of a string default, so
                        # COSMOS writes them as a 0x prefixed hex escape. A printable
                        # default that starts with 0x is escaped the same way, otherwise
                        # the importer reads it back as binary and "0xABCD" round trips
                        # as the bytes \xAB\xCD.
                        attrs["initialValue"] = "0x" + default.hex().upper()
                else:
                    attrs["initialValue"] = str(item.default)
            except Exception:
                pass

        if item.description:
            attrs["shortDescription"] = item.description

        str_type = etree.SubElement(
            parent,
            f"{{{self.XTCE_NAMESPACE}}}{string_or_binary}{param_or_arg}Type",
            attrib=attrs,
        )
        self._to_xtce_units(item, str_type)

        if string_or_binary == "String":
            encoding_elem = etree.SubElement(
                str_type,
                f"{{{self.XTCE_NAMESPACE}}}StringDataEncoding",
                attrib={"encoding": "UTF-8"},
            )
            size_in_bits = etree.SubElement(encoding_elem, f"{{{self.XTCE_NAMESPACE}}}SizeInBits")
            fixed = etree.SubElement(size_in_bits, f"{{{self.XTCE_NAMESPACE}}}Fixed")
            etree.SubElement(fixed, f"{{{self.XTCE_NAMESPACE}}}FixedValue").text = str(item.bit_size)
        else:
            encoding_elem = etree.SubElement(str_type, f"{{{self.XTCE_NAMESPACE}}}BinaryDataEncoding")
            size_in_bits = etree.SubElement(encoding_elem, f"{{{self.XTCE_NAMESPACE}}}SizeInBits")
            etree.SubElement(size_in_bits, f"{{{self.XTCE_NAMESPACE}}}FixedValue").text = str(item.bit_size)

    def _to_xtce_item(self, item, param_or_arg, parent):
        """Create XTCE item reference

        Args:
            item: Packet item
            param_or_arg (str): "Parameter" or "Argument"
            parent: Parent XML element
        """
        type_ref = f"{item.name}_ArrayType" if item.array_size else f"{item.name}_Type"
        etree.SubElement(
            parent,
            f"{{{self.XTCE_NAMESPACE}}}{param_or_arg}",
            attrib={"name": item.name, f"{param_or_arg.lower()}TypeRef": type_ref},
        )

    def _to_xtce_units(self, item, parent):
        """Add units to XTCE type

        Args:
            item: Packet item
            parent: Parent XML element
        """
        unit_set = etree.SubElement(parent, f"{{{self.XTCE_NAMESPACE}}}UnitSet")
        if hasattr(item, "units") and item.units:
            attrs = {}
            if hasattr(item, "units_full") and item.units_full:
                attrs["description"] = item.units_full
            etree.SubElement(unit_set, f"{{{self.XTCE_NAMESPACE}}}Unit", attrib=attrs).text = item.units

    def _to_xtce_endianness(self, item, encoding):
        """Add endianness to an XTCE DataEncoding element

        XTCE 1.2 removed ByteOrderList in favor of the byteOrder attribute on the
        DataEncoding. mostSignificantByteFirst is the schema default so it is only
        emitted for little endian items larger than a single byte.

        Args:
            item: Packet item
            encoding: DataEncoding XML element
        """
        if item.endianness == "LITTLE_ENDIAN" and item.bit_size > 8:
            encoding.set("byteOrder", "leastSignificantByteFirst")

    def _to_xtce_conversion(self, item, parent):
        """Add conversion to XTCE type

        Args:
            item: Packet item
            parent: Parent XML element
        """
        conversion = item.read_conversion if item.read_conversion else item.write_conversion
        if conversion and isinstance(conversion, PolynomialConversion):
            calibrator = etree.SubElement(parent, f"{{{self.XTCE_NAMESPACE}}}DefaultCalibrator")
            poly_cal = etree.SubElement(calibrator, f"{{{self.XTCE_NAMESPACE}}}PolynomialCalibrator")
            for index, coeff in enumerate(conversion.coeffs):
                etree.SubElement(
                    poly_cal,
                    f"{{{self.XTCE_NAMESPACE}}}Term",
                    attrib={"coefficient": str(coeff), "exponent": str(index)},
                )

    def _to_xtce_valid_range(self, item, param_or_arg, parent):
        """Add the item minimum / maximum as an XTCE ValidRange

        Arguments require the range to be wrapped in a ValidRangeSet.

        Args:
            item: Packet item
            param_or_arg (str): "Parameter" or "Argument"
            parent: Type XML element
        """
        if item.minimum is None or item.maximum is None:
            return
        if item.data_type in ["INT", "UINT"]:
            # IntegerRangeType is xs:long, so a wider range (a full 64 bit UINT, for
            # example) can't be expressed and is dropped rather than emitted invalid.
            if item.minimum < self.XS_LONG_MIN or item.maximum > self.XS_LONG_MAX:
                return
        elif not (math.isfinite(item.minimum) and math.isfinite(item.maximum)):
            # FloatRangeType is xs:double, which covers any finite float. Infinity and
            # NaN have no valid xs:double lexical form here, so skip them.
            return

        attrs = {"minInclusive": str(item.minimum), "maxInclusive": str(item.maximum)}
        if param_or_arg == "Parameter":
            etree.SubElement(parent, f"{{{self.XTCE_NAMESPACE}}}ValidRange", attrib=attrs)
        else:
            range_set = etree.SubElement(parent, f"{{{self.XTCE_NAMESPACE}}}ValidRangeSet")
            etree.SubElement(range_set, f"{{{self.XTCE_NAMESPACE}}}ValidRange", attrib=attrs)

    def _to_xtce_limits(self, item, parent):
        """Add limits to XTCE type

        Args:
            item: Packet item
            parent: Parent XML element
        """
        if not item.limits or not item.limits.values:
            return

        for limits_set, limits_values in item.limits.values.items():
            if limits_set == "DEFAULT":
                alarm = etree.SubElement(parent, f"{{{self.XTCE_NAMESPACE}}}DefaultAlarm")
                ranges = etree.SubElement(alarm, f"{{{self.XTCE_NAMESPACE}}}StaticAlarmRanges")
                etree.SubElement(
                    ranges,
                    f"{{{self.XTCE_NAMESPACE}}}WarningRange",
                    attrib={
                        "minInclusive": str(limits_values[1]),
                        "maxInclusive": str(limits_values[2]),
                    },
                )
                etree.SubElement(
                    ranges,
                    f"{{{self.XTCE_NAMESPACE}}}CriticalRange",
                    attrib={
                        "minInclusive": str(limits_values[0]),
                        "maxInclusive": str(limits_values[3]),
                    },
                )
