import importlib
import itertools
import operator
import tempfile
import unittest
from pathlib import Path

from openc3.packets.packet_config import PacketConfig
from openc3.packets.parsers.xtce_converter import XtceConverter


etree = importlib.import_module("lxml.etree")


class TestXtceSemantics(unittest.TestCase):
    def parse(self, definition):
        with tempfile.NamedTemporaryFile(mode="w") as file:
            file.write(definition)
            file.flush()
            config = PacketConfig()
            config.process_file(file.name, "INST")
        return config

    def assert_exported_parameter_counts(self, config, directory, expected_refs):
        XtceConverter.convert(config.commands, config.telemetry, directory)
        document = etree.parse(str(Path(directory) / "INST/cmd_tlm/inst.xtce"))
        ns = {"x": XtceConverter.XTCE_NAMESPACE}
        self.assertEqual(len(document.xpath("//x:Parameter[@name='VALUE']", namespaces=ns)), 1)
        self.assertEqual(
            len(document.xpath("//x:ParameterRefEntry[@parameterRef='VALUE']", namespaces=ns)), expected_refs
        )

    def byte_order_config(self, entries, command=False, data_type="UINT", bits=8):
        definitions = []
        command_names = [
            ("FIRST_PART_MORE_VALUE", "ITEM"),
            ("FIRST_PART_MORE", "VALUE_ITEM"),
            ("FIRST_PART", "MORE_VALUE_ITEM"),
            ("FIRST", "PART_MORE_VALUE_ITEM"),
        ]
        for index, (order, offset) in enumerate(entries):
            packet_name, item_name = command_names[index] if command else (f"PACKET{index}", "VALUE")
            kind = "COMMAND" if command else "TELEMETRY"
            declaration = "PARAMETER" if command else "ITEM"
            bounds = " 0 127 0" if command else ""
            definitions.append(
                f'{kind} INST {packet_name} {order} "Packet"\n'
                f'  {declaration} {item_name} {offset} {bits} {data_type}{bounds} "Value"\n'
            )
        return self.parse("".join(definitions))

    def test_rejects_conflicting_signedness_without_replacing_an_existing_export(self):
        config = self.parse(
            'TELEMETRY INST UNSIGNED BIG_ENDIAN "Unsigned channel"\n'
            '  APPEND_ITEM VALUE 16 UINT "Unsigned reading"\n'
            'TELEMETRY INST SIGNED BIG_ENDIAN "Signed channel"\n'
            '  APPEND_ITEM VALUE 16 INT "Signed reading"\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "INST/cmd_tlm/inst.xtce"
            path.parent.mkdir(parents=True)
            path.write_text("previous export")
            with self.assertRaisesRegex(ValueError, "conflicting XTCE definitions"):
                XtceConverter.convert(config.commands, config.telemetry, directory)
            self.assertEqual(path.read_text(), "previous export")

    def test_rejects_conflicting_limits_even_when_the_binary_type_matches(self):
        config = self.parse(
            'TELEMETRY INST CRITICAL BIG_ENDIAN "Critical channel"\n'
            '  APPEND_ITEM TEMP 16 INT "Temperature"\n'
            "    LIMITS DEFAULT 1 ENABLED 0 1 10 20\n"
            'TELEMETRY INST RELAXED BIG_ENDIAN "Relaxed channel"\n'
            '  APPEND_ITEM TEMP 16 INT "Temperature"\n'
            "    LIMITS DEFAULT 1 ENABLED 0 1 100 200\n"
        )
        with (
            tempfile.TemporaryDirectory() as directory,
            self.assertRaisesRegex(ValueError, "conflicting XTCE definitions"),
        ):
            XtceConverter.convert(config.commands, config.telemetry, directory)

    def test_shares_equal_definitions_with_different_descriptions(self):
        config = self.parse(
            'TELEMETRY INST FIRST BIG_ENDIAN "First channel"\n'
            '  APPEND_ITEM VALUE 16 UINT "First description"\n'
            'TELEMETRY INST SECOND BIG_ENDIAN "Second channel"\n'
            '  APPEND_ITEM VALUE 16 UINT "Different description"\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            self.assert_exported_parameter_counts(config, directory, 2)

    def test_ignores_derived_items_when_a_numeric_item_has_the_same_name(self):
        definitions = [
            'TELEMETRY INST NUMERIC BIG_ENDIAN "Numeric"\n  APPEND_ITEM VALUE 16 UINT "Reading"\n',
            'TELEMETRY INST COMPUTED BIG_ENDIAN "Computed"\n'
            '  APPEND_ITEM OTHER 16 UINT "Wire field"\n'
            '  APPEND_ITEM VALUE 0 DERIVED "Computed field"\n',
        ]
        for ordered in [definitions, definitions[::-1]]:
            with self.subTest(order=ordered), tempfile.TemporaryDirectory() as directory:
                config = self.parse("".join(ordered))
                self.assert_exported_parameter_counts(config, directory, 1)

    def test_preserves_command_scoped_types_when_argument_names_match(self):
        config = self.parse(
            'COMMAND INST FIRST BIG_ENDIAN "First"\n'
            '  APPEND_PARAMETER VALUE 8 UINT 0 10 3 "Value"\n'
            'COMMAND INST SECOND BIG_ENDIAN "Second"\n'
            '  APPEND_PARAMETER VALUE 16 UINT 0 1000 300 "Value"\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            XtceConverter.convert(config.commands, config.telemetry, directory)
            tree = etree.parse(str(Path(directory) / "INST/cmd_tlm/inst.xtce"))
            ns = {"x": XtceConverter.XTCE_NAMESPACE}
            for command, bits, maximum, default in [("FIRST", "8", "10", "3"), ("SECOND", "16", "1000", "300")]:
                with self.subTest(command=command):
                    argument = tree.find(f".//x:MetaCommand[@name='{command}']/x:ArgumentList/x:Argument", ns)
                    self.assertEqual(argument.get("argumentTypeRef"), f"{command}_VALUE_Type")
                    definition = tree.find(f".//x:IntegerArgumentType[@name='{command}_VALUE_Type']", ns)
                    self.assertEqual(definition.find("x:IntegerDataEncoding", ns).get("sizeInBits"), bits)
                    self.assertEqual(definition.find("x:ValidRangeSet/x:ValidRange", ns).get("maxInclusive"), maximum)
                    self.assertEqual(definition.get("initialValue"), default)

    def test_rejects_generated_command_type_name_collisions_without_replacing_export(self):
        config = self.parse(
            'COMMAND INST FIRST_VALUE BIG_ENDIAN "First"\n'
            '  APPEND_PARAMETER ITEM 8 UINT 0 10 0 "Item"\n'
            'COMMAND INST FIRST BIG_ENDIAN "Second"\n'
            '  APPEND_PARAMETER VALUE_ITEM 16 UINT 0 1000 0 "Item"\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "INST/cmd_tlm/inst.xtce"
            path.parent.mkdir(parents=True)
            path.write_text("previous export")
            with self.assertRaisesRegex(ValueError, "conflicting XTCE definitions"):
                XtceConverter.convert(config.commands, config.telemetry, directory)
            self.assertEqual(path.read_text(), "previous export")

    def test_rejects_lossy_integer_alarm_export_but_accepts_exact_double_values(self):
        config = self.parse(
            'TELEMETRY INST STATUS BIG_ENDIAN "Large integer"\n'
            '  APPEND_ITEM TEMP 64 INT "Temperature"\n'
            "    LIMITS DEFAULT 1 ENABLED 0 1 9007199254740990 9007199254740993\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "INST/cmd_tlm/inst.xtce"
            path.parent.mkdir(parents=True)
            path.write_text("previous export")
            with self.assertRaisesRegex(ValueError, "cannot be represented exactly as an XTCE xs:double"):
                XtceConverter.convert(config.commands, config.telemetry, directory)
            self.assertEqual(path.read_text(), "previous export")
            config.telemetry["INST"]["STATUS"].get_item("TEMP").limits.values["DEFAULT"][3] = 9007199254740994
            XtceConverter.convert(config.commands, config.telemetry, directory)
            tree = etree.parse(str(path))
            critical = tree.find(".//x:CriticalRange", {"x": XtceConverter.XTCE_NAMESPACE})
            self.assertEqual(float(critical.get("maxInclusive")), 9007199254740994)

    def test_exported_alarm_intervals_preserve_native_boundary_severity(self):
        config = self.parse(
            'TELEMETRY INST STATUS BIG_ENDIAN "Temperature"\n'
            '  APPEND_ITEM TEMP 16 INT "Temperature"\n'
            "    LIMITS DEFAULT 1 ENABLED -80 -70 60 80\n"
        )
        packet = config.telemetry["INST"]["STATUS"]
        with tempfile.TemporaryDirectory() as directory:
            XtceConverter.convert(config.commands, config.telemetry, directory)
            document = etree.parse(str(Path(directory) / "INST/cmd_tlm/inst.xtce"))
            schema = etree.XMLSchema(
                etree.parse(str(Path(__file__).resolve().parents[4] / "data/xtce_schemas/SpaceSystem_20180204.xsd"))
            )
            self.assertTrue(schema.validate(document))
            ns = {"x": XtceConverter.XTCE_NAMESPACE}
            warning = document.find(".//x:WarningRange", ns)
            critical = document.find(".//x:CriticalRange", ns)
            # CCSDS 660.1-G-2 4.3.2.3.7.2.1: inclusive endpoints belong
            # to the outside alarm; these comparisons describe the normal region.
            comparisons = {
                "minInclusive": operator.gt,
                "minExclusive": operator.ge,
                "maxInclusive": operator.lt,
                "maxExclusive": operator.le,
            }
            for value in [-81, -80, -79, -70, -69, 0, 59, 60, 61, 79, 80, 81]:
                with self.subTest(value=value):
                    packet.buffer = bytearray(value.to_bytes(2, "big", signed=True))
                    packet.check_limits()
                    state = packet.get_item("TEMP").limits.state
                    expected = (
                        "CRITICAL" if state.startswith("RED") else "WARNING" if state.startswith("YELLOW") else "NORMAL"
                    )
                    normal_for_critical = all(
                        comparisons[key](value, float(bound)) for key, bound in critical.attrib.items()
                    )
                    normal_for_warning = all(
                        comparisons[key](value, float(bound)) for key, bound in warning.attrib.items()
                    )
                    observed = (
                        "CRITICAL" if not normal_for_critical else "WARNING" if not normal_for_warning else "NORMAL"
                    )
                    self.assertEqual(observed, expected)

    def test_rejects_inexact_xtce_integer_limits_before_replacing_export(self):
        for sign in [-1, 1]:
            for index in range(4):
                limits = [sign * 2**54 + offset for offset in [0, 4, 8, 12]]
                limits[index] += 1
                with self.subTest(sign=sign, index=index), tempfile.TemporaryDirectory() as directory:
                    config = self.parse(
                        'TELEMETRY INST STATUS BIG_ENDIAN "Counter"\n'
                        '  APPEND_ITEM COUNT 64 INT "Counter"\n'
                        "    LIMITS DEFAULT 1 ENABLED " + " ".join(map(str, limits)) + "\n"
                    )
                    path = Path(directory) / "INST/cmd_tlm/inst.xtce"
                    path.parent.mkdir(parents=True)
                    path.write_text("previous export")
                    with self.assertRaisesRegex(ValueError, "cannot be represented exactly as (?:an )?XTCE xs:double"):
                        XtceConverter.convert(config.commands, config.telemetry, directory)
                    self.assertEqual(path.read_text(), "previous export")

    def test_shares_equivalent_colliding_scoped_command_types(self):
        config = self.parse(
            'COMMAND INST FIRST_PART BIG_ENDIAN "First"\n'
            '  APPEND_PARAMETER VALUE 8 UINT 0 10 0 "First argument"\n'
            'COMMAND INST FIRST BIG_ENDIAN "Second"\n'
            '  APPEND_PARAMETER PART_VALUE 8 UINT 0 10 0 "Second argument"\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            XtceConverter.convert(config.commands, config.telemetry, directory)
            document = etree.parse(str(Path(directory) / "INST/cmd_tlm/inst.xtce"))
            ns = {"x": XtceConverter.XTCE_NAMESPACE}
            self.assertEqual(len(document.xpath("//x:IntegerArgumentType", namespaces=ns)), 1)
            self.assertEqual(
                document.xpath("//x:Argument/@argumentTypeRef", namespaces=ns),
                ["FIRST_PART_VALUE_Type", "FIRST_PART_VALUE_Type"],
            )

    def test_shares_numerically_equal_alarm_threshold_spellings(self):
        for sign in [-1, 1]:
            for index in range(4):
                first = [str(sign * 2**54 + offset) for offset in [0, 4, 8, 12]]
                second = first.copy()
                second[index] += ".0"
                with self.subTest(sign=sign, index=index), tempfile.TemporaryDirectory() as directory:
                    config = self.parse(
                        "".join(
                            f'TELEMETRY INST PACKET{number} BIG_ENDIAN "Packet"\n'
                            '  APPEND_ITEM VALUE 64 INT "Value"\n'
                            f"    LIMITS DEFAULT 1 ENABLED {' '.join(limits)}\n"
                            for number, limits in enumerate([first, second])
                        )
                    )
                    self.assert_exported_parameter_counts(config, directory, 2)

    def test_shares_positive_and_negative_zero_alarm_thresholds(self):
        config = self.parse(
            'TELEMETRY INST FIRST BIG_ENDIAN "First"\n'
            '  APPEND_ITEM VALUE 64 INT "Value"\n'
            "    LIMITS DEFAULT 1 ENABLED -10 0 10 20\n"
            'TELEMETRY INST SECOND BIG_ENDIAN "Second"\n'
            '  APPEND_ITEM VALUE 64 INT "Value"\n'
            "    LIMITS DEFAULT 1 ENABLED -10 -0.0 10 20\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            self.assert_exported_parameter_counts(config, directory, 2)

    def test_one_byte_byte_order_control_and_multibyte_conflict(self):
        for bits in [8, 16]:
            with self.subTest(bits=bits), tempfile.TemporaryDirectory() as directory:
                config = self.parse(
                    'TELEMETRY INST FIRST BIG_ENDIAN "First"\n'
                    f'  APPEND_ITEM VALUE {bits} UINT "Value"\n'
                    'TELEMETRY INST SECOND LITTLE_ENDIAN "Second"\n'
                    f'  APPEND_ITEM VALUE {bits} UINT "Value"\n'
                )
                if bits == 8:
                    self.assert_exported_parameter_counts(config, directory, 2)
                else:
                    with self.assertRaisesRegex(ValueError, "conflicting XTCE definitions"):
                        XtceConverter.convert(config.commands, config.telemetry, directory)

    def test_rejects_unaligned_one_byte_byte_order_conflicts(self):
        for command, data_type, offsets in itertools.product([False, True], ["INT", "UINT"], [(9, 9), (0, 9), (9, 0)]):
            entries = [("BIG_ENDIAN", offsets[0]), ("LITTLE_ENDIAN", offsets[1])]
            for ordered in [entries, entries[::-1]]:
                with (
                    self.subTest(command=command, data_type=data_type, entries=ordered),
                    tempfile.TemporaryDirectory() as directory,
                ):
                    config = self.byte_order_config(ordered, command, data_type)
                    with self.assertRaisesRegex(ValueError, "conflicting XTCE definitions"):
                        XtceConverter.convert(config.commands, config.telemetry, directory)

    def test_rejects_opposite_byte_orders_when_a_later_shared_field_is_unaligned(self):
        entries = [("BIG_ENDIAN", 0), ("LITTLE_ENDIAN", 0), ("LITTLE_ENDIAN", 9)]
        for command, data_type, ordered in itertools.product(
            [False, True], ["INT", "UINT"], itertools.permutations(entries)
        ):
            with (
                self.subTest(command=command, data_type=data_type, entries=ordered),
                tempfile.TemporaryDirectory() as directory,
            ):
                config = self.byte_order_config(ordered, command, data_type)
                with self.assertRaisesRegex(ValueError, "conflicting XTCE definitions"):
                    XtceConverter.convert(config.commands, config.telemetry, directory)

    def test_shares_matching_byte_order_across_integer_field_alignments(self):
        for command, data_type, order, offsets in itertools.product(
            [False, True], ["INT", "UINT"], ["BIG_ENDIAN", "LITTLE_ENDIAN"], [(0, 9), (9, 0), (9, 9)]
        ):
            with (
                self.subTest(command=command, data_type=data_type, order=order, offsets=offsets),
                tempfile.TemporaryDirectory() as directory,
            ):
                config = self.byte_order_config([(order, offset) for offset in offsets], command, data_type)
                XtceConverter.convert(config.commands, config.telemetry, directory)
                tree = etree.parse(str(Path(directory) / "INST/cmd_tlm/inst.xtce"))
                ns = {"x": XtceConverter.XTCE_NAMESPACE}
                type_name = "IntegerArgumentType" if command else "IntegerParameterType"
                self.assertEqual(len(tree.findall(f".//x:{type_name}", ns)), 1)

    def test_rejects_unaligned_conflicts_between_matching_aligned_group_endpoints(self):
        entries = [("LITTLE_ENDIAN", 0), ("BIG_ENDIAN", 0), ("LITTLE_ENDIAN", 9), ("LITTLE_ENDIAN", 0)]
        for command, data_type, ordered in itertools.product(
            [False, True], ["INT", "UINT"], itertools.permutations(entries)
        ):
            with (
                self.subTest(command=command, data_type=data_type, entries=ordered),
                tempfile.TemporaryDirectory() as directory,
            ):
                config = self.byte_order_config(ordered, command, data_type)
                with self.assertRaisesRegex(ValueError, "conflicting XTCE definitions"):
                    XtceConverter.convert(config.commands, config.telemetry, directory)

    def test_shares_aligned_one_byte_colliding_command_types_across_byte_orders(self):
        entries = [("BIG_ENDIAN", 0), ("LITTLE_ENDIAN", 0)]
        for data_type, ordered in itertools.product(["INT", "UINT"], [entries, entries[::-1]]):
            with self.subTest(data_type=data_type, entries=ordered), tempfile.TemporaryDirectory() as directory:
                config = self.byte_order_config(ordered, command=True, data_type=data_type)
                XtceConverter.convert(config.commands, config.telemetry, directory)
                tree = etree.parse(str(Path(directory) / "INST/cmd_tlm/inst.xtce"))
                ns = {"x": XtceConverter.XTCE_NAMESPACE}
                self.assertEqual(len(tree.findall(".//x:IntegerArgumentType", ns)), 1)

    def test_rejects_multibyte_scoped_command_byte_order_conflicts(self):
        entries = [("BIG_ENDIAN", 0), ("LITTLE_ENDIAN", 0)]
        for data_type, ordered in itertools.product(["INT", "UINT"], [entries, entries[::-1]]):
            with (
                self.subTest(data_type=data_type, entries=ordered),
                tempfile.TemporaryDirectory() as directory,
            ):
                config = self.byte_order_config(ordered, command=True, data_type=data_type, bits=16)
                with self.assertRaisesRegex(ValueError, "conflicting XTCE definitions"):
                    XtceConverter.convert(config.commands, config.telemetry, directory)
