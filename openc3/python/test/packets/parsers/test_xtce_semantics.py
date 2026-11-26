import importlib
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
            XtceConverter.convert(config.commands, config.telemetry, directory)
            document = etree.parse(str(Path(directory) / "INST/cmd_tlm/inst.xtce"))
            ns = {"x": XtceConverter.XTCE_NAMESPACE}
            self.assertEqual(len(document.xpath("//x:Parameter[@name='VALUE']", namespaces=ns)), 1)
            self.assertEqual(len(document.xpath("//x:ParameterRefEntry[@parameterRef='VALUE']", namespaces=ns)), 2)

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
                XtceConverter.convert(config.commands, config.telemetry, directory)
                document = etree.parse(str(Path(directory) / "INST/cmd_tlm/inst.xtce"))
                ns = {"x": XtceConverter.XTCE_NAMESPACE}
                self.assertEqual(len(document.xpath("//x:Parameter[@name='VALUE']", namespaces=ns)), 1)
                self.assertEqual(len(document.xpath("//x:ParameterRefEntry[@parameterRef='VALUE']", namespaces=ns)), 1)

    def test_rejects_command_conflicts_before_replacing_an_existing_export(self):
        for size, maximum in [(16, 10), (8, 20)]:
            with self.subTest(size=size, maximum=maximum), tempfile.TemporaryDirectory() as directory:
                config = self.parse(
                    'COMMAND INST FIRST BIG_ENDIAN "First command"\n'
                    '  APPEND_PARAMETER VALUE 8 UINT 0 10 0 "First argument"\n'
                    'COMMAND INST SECOND BIG_ENDIAN "Second command"\n'
                    f'  APPEND_PARAMETER VALUE {size} UINT 0 {maximum} 0 "Second argument"\n'
                )
                path = Path(directory) / "INST/cmd_tlm/inst.xtce"
                path.parent.mkdir(parents=True)
                path.write_text("previous export")
                with self.assertRaisesRegex(ValueError, "conflicting XTCE definitions"):
                    XtceConverter.convert(config.commands, config.telemetry, directory)
                self.assertEqual(path.read_text(), "previous export")

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
            comparisons = {
                "minInclusive": operator.ge,
                "minExclusive": operator.gt,
                "maxInclusive": operator.le,
                "maxExclusive": operator.lt,
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
