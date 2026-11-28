import tempfile
import unittest

from openc3.packets.packet_config import PacketConfig


class TestLimitsIntegerPrecision(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def test_preserves_all_integer_limits_above_float_precision(self):
        base = 2**54
        limits = [base + offset for offset in (1, 2, 10, 11, 4, 7)]
        with tempfile.NamedTemporaryFile(mode="w") as tf:
            tf.write('TELEMETRY TGT1 PKT1 BIG_ENDIAN "Packet"\n')
            tf.write('  APPEND_ITEM COUNT 64 UINT "Counter"\n')
            tf.write("    LIMITS DEFAULT 1 ENABLED " + " ".join(map(str, limits)) + "\n")
            tf.flush()
            self.pc.process_file(tf.name, "TGT1")
        item = self.pc.telemetry["TGT1"]["PKT1"].get_item("COUNT")
        self.assertEqual(item.limits.values["DEFAULT"], limits)

    def test_reports_red_high_for_uint64_above_configured_red_high(self):
        value = 2**64 - 1
        with tempfile.NamedTemporaryFile(mode="w") as tf:
            tf.write('TELEMETRY TGT1 PKT1 BIG_ENDIAN "Packet"\n')
            tf.write('  APPEND_ITEM COUNT 64 UINT "Counter"\n')
            tf.write(f"    LIMITS DEFAULT 1 ENABLED 0 1 {value - 2} {value - 1}\n")
            tf.flush()
            self.pc.process_file(tf.name, "TGT1")
        packet = self.pc.telemetry["TGT1"]["PKT1"]
        packet.buffer = bytearray(value.to_bytes(8, "big"))
        packet.check_limits()
        self.assertEqual(packet.read("COUNT"), value)
        self.assertEqual(packet.get_item("COUNT").limits.state, "RED_HIGH")
        self.assertEqual(packet.out_of_limits(), [["TGT1", "PKT1", "COUNT", "RED_HIGH"]])

    def test_reports_red_low_for_int64_at_configured_red_low(self):
        value = -(2**54) - 7
        with tempfile.NamedTemporaryFile(mode="w") as tf:
            tf.write('TELEMETRY TGT1 PKT1 BIG_ENDIAN "Packet"\n')
            tf.write('  APPEND_ITEM COUNT 64 INT "Counter"\n')
            tf.write(f"    LIMITS DEFAULT 1 ENABLED {value} {value + 1} 0 1\n")
            tf.flush()
            self.pc.process_file(tf.name, "TGT1")
        packet = self.pc.telemetry["TGT1"]["PKT1"]
        packet.buffer = bytearray(value.to_bytes(8, "big", signed=True))
        packet.check_limits()
        self.assertEqual(packet.read("COUNT"), value)
        self.assertEqual(packet.get_item("COUNT").limits.state, "RED_LOW")
        self.assertEqual(packet.out_of_limits(), [["TGT1", "PKT1", "COUNT", "RED_LOW"]])
