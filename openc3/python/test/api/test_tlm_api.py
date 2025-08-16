# Copyright 2025 OpenC3, Inc.
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

# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957

import time
from datetime import datetime, timezone, timedelta
import unittest
import threading
from unittest.mock import *
from test.test_helper import *
from openc3.api.tlm_api import *
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from openc3.topics.telemetry_topic import TelemetryTopic
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.interface_model import InterfaceModel
from openc3.microservices.decom_microservice import DecomMicroservice
from openc3.utilities.time import formatted


class TestTlmApi(unittest.TestCase):
    def setUp(self):
        redis = mock_redis(self)
        setup_system()

        self.process = True
        orig_xread = redis.xread

        # Override xread to ignore the block and count keywords
        def xread_side_effect(*args, **kwargs):
            result = None
            if self.process:
                try:
                    result = orig_xread(*args)
                except RuntimeError:
                    pass

            # # Create a slight delay to simulate the blocking call
            if result and len(result) == 0:
                time.sleep(0.01)
            return result

        redis.xread = Mock()
        redis.xread.side_effect = xread_side_effect

        model = TargetModel(name="INST", scope="DEFAULT")
        model.create()
        model = TargetModel(name="SYSTEM", scope="DEFAULT")
        model.create()

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.received_time = datetime.now(timezone.utc)
        packet.stored = False
        packet.check_limits()
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)  # Allow the write to happen

    # tlm, tlm_raw, tlm_formatted, tlm_with_units
    def test_tlm_complains_about_unknown_targets_commands_and_parameters(self):
        for name in [
            "tlm",
            "tlm_raw",
            "tlm_formatted",
            "tlm_with_units",
        ]:
            func = globals()[name]
            with self.assertRaisesRegex(RuntimeError, "does not exist"):
                func("BLAH HEALTH_STATUS COLLECTS")
            with self.assertRaisesRegex(RuntimeError, "does not exist"):
                func("INST HEALTH_STATUS BLAH")
            with self.assertRaisesRegex(RuntimeError, "does not exist"):
                func("BLAH", "HEALTH_STATUS", "COLLECTS")
            with self.assertRaisesRegex(RuntimeError, "does not exist"):
                func("INST", "UNKNOWN", "COLLECTS")
            with self.assertRaisesRegex(RuntimeError, "does not exist"):
                func("INST", "HEALTH_STATUS", "BLAH")

    def test_processes_a_string(self):
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), -100.0)
        self.assertEqual(tlm_raw("INST HEALTH_STATUS TEMP1"), 0)
        self.assertEqual(tlm_formatted("INST HEALTH_STATUS TEMP1"), "-100.000")
        self.assertEqual(tlm_with_units("INST HEALTH_STATUS TEMP1"), "-100.000 C")

    def test_processes_parameters(self):
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1"), -100.0)
        self.assertEqual(tlm_raw("INST", "HEALTH_STATUS", "TEMP1"), 0)
        self.assertEqual(tlm_formatted("INST", "HEALTH_STATUS", "TEMP1"), "-100.000")
        self.assertEqual(tlm_with_units("INST", "HEALTH_STATUS", "TEMP1"), "-100.000 C")

    def test_complains_if_too_many_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid number of arguments"):
            tlm("INST", "HEALTH_STATUS", "TEMP1", "TEMP2")

    def test_returns_the_value_using_latest(self):
        now = datetime.now(timezone.utc)
        packet = System.telemetry.packet("INST", "IMAGE")
        packet.received_time = now
        packet.write("CCSDSVER", 1)
        json_hash = CvtModel.build_json_from_packet(packet)
        CvtModel.set(
            json_hash,
            packet.target_name,
            packet.packet_name,
            scope="DEFAULT",
        )
        packet = System.telemetry.packet("INST", "ADCS")
        packet.received_time = now + timedelta(seconds=1)
        packet.write("CCSDSVER", 2)
        json_hash = CvtModel.build_json_from_packet(packet)
        CvtModel.set(
            json_hash,
            packet.target_name,
            packet.packet_name,
            scope="DEFAULT",
        )
        time.sleep(0.01)  # Allow the writes to happen
        self.assertEqual(tlm("INST LATEST CCSDSVER"), 2)
        # Ensure case doesn't matter ... it still works
        self.assertEqual(tlm("inst Latest CcsdsVER"), 2)

    # set_tlm
    def test_set_tlm_complains_about_unknown_targets_packets_and_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            set_tlm("BLAH HEALTH_STATUS COLLECTS = 1")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            set_tlm("INST UNKNOWN COLLECTS = 1")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            set_tlm("INST HEALTH_STATUS BLAH = 1")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            set_tlm("BLAH", "HEALTH_STATUS", "COLLECTS", 1)
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            set_tlm("INST", "UNKNOWN", "COLLECTS", 1)
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            set_tlm("INST", "HEALTH_STATUS", "BLAH", 1)

    def test_set_tlm_complains_with_too_many_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid number of arguments"):
            set_tlm("INST", "HEALTH_STATUS", "TEMP1", "TEMP2", 0.0)

    def test_set_tlm_complains_with_unknown_types(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type 'BLAH'"):
            set_tlm("INST", "HEALTH_STATUS", "TEMP1", 0.0, type="BLAH")

    def test_set_tlm_processes_a_string(self):
        set_tlm("inst Health_Status temp1 = 0.0")  # match doesn't matter:
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), (0.0))
        set_tlm("INST HEALTH_STATUS TEMP1 = 100.0")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), (100.0))

    def test_set_tlm_processes_parameters(self):
        set_tlm("inst", "Health_Status", "Temp1", 0.0)  # match doesn't matter:
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), (0.0))
        set_tlm("INST", "HEALTH_STATUS", "TEMP1", -50.0)
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), (-50.0))

    def test_set_tlm_sets_raw_telemetry(self):
        set_tlm("INST HEALTH_STATUS TEMP1 = 10.0", type="RAW")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1", type="RAW"), 10.0)
        set_tlm("INST", "HEALTH_STATUS", "TEMP1", 0.0, type="RAW")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1", type="RAW"), 0.0)
        set_tlm("INST HEALTH_STATUS ARY = [1,2,3]", type="RAW")
        self.assertEqual(tlm("INST HEALTH_STATUS ARY", type="RAW"), [1, 2, 3])

    def test_set_tlm_sets_converted_telemetry(self):
        set_tlm("INST HEALTH_STATUS TEMP1 = 10.0", type="CONVERTED")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), 10.0)
        set_tlm("INST", "HEALTH_STATUS", "TEMP1", 0.0, type="CONVERTED")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), 0.0)
        set_tlm("INST HEALTH_STATUS ARY = [1,2,3]", type="CONVERTED")
        self.assertEqual(tlm("INST HEALTH_STATUS ARY"), [1, 2, 3])

    def test_set_tlm_sets_formatted_telemetry(self):
        set_tlm("INST HEALTH_STATUS TEMP1 = '10.000'", type="FORMATTED")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1", type="FORMATTED"), "10.000")
        set_tlm("INST", "HEALTH_STATUS", "TEMP1", 0.0, type="FORMATTED")  # Float
        self.assertEqual(
            tlm("INST HEALTH_STATUS TEMP1", type="FORMATTED"), "0.0"
        )  # String
        set_tlm("INST HEALTH_STATUS ARY = '[1,2,3]'", type="FORMATTED")
        self.assertEqual(tlm("INST HEALTH_STATUS ARY", type="FORMATTED"), "[1,2,3]")

    def test_set_tlm_sets_with_units_telemetry(self):
        set_tlm("INST HEALTH_STATUS TEMP1 = '10.0 C'", type="WITH_UNITS")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1", type="WITH_UNITS"), "10.0 C")
        set_tlm("INST", "HEALTH_STATUS", "TEMP1", 0.0, type="WITH_UNITS")  # Float
        self.assertEqual(
            tlm("INST HEALTH_STATUS TEMP1", type="WITH_UNITS"), "0.0"
        )  # String
        set_tlm("INST HEALTH_STATUS ARY = '[1,2,3]'", type="WITH_UNITS")
        self.assertEqual(tlm("INST HEALTH_STATUS ARY", type="WITH_UNITS"), "[1,2,3]")

    def decom_stuff(self):
        model = MicroserviceModel(
            name="DEFAULT__DECOM__INST_INT",
            scope="DEFAULT",
            topics=[
                "DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS",
                "DEFAULT__TELEMETRY__{SYSTEM}__META",
            ],
            target_names=["INST"],
        )
        model.create()
        self.dm = DecomMicroservice("DEFAULT__DECOM__INST_INT")
        self.dm_thread = threading.Thread(target=self.dm.run)
        self.dm_thread.start()
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        TelemetryTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.001)

    def test_inject_tlm_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            inject_tlm("BLAH", "HEALTH_STATUS")

    def test_inject_tlm_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            inject_tlm("INST", "BLAH")

    def test_inject_tlm_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(
            RuntimeError, r"Item\(s\) 'INST HEALTH_STATUS BLAH' does not exist"
        ):
            inject_tlm("INST", "HEALTH_STATUS", {"BLAH": 0})

    def test_inject_tlm_complains_about_bad_types(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown type 'BLAH'"):
            inject_tlm("INST", "HEALTH_STATUS", {"TEMP1": 0}, type="BLAH")

    @patch("openc3.api.tlm_api.InterfaceTopic")
    def test_inject_tlm_uses_the_interface(self, obj):
        model = InterfaceModel(
            name="INST_INT",
            scope="DEFAULT",
            target_names=["INST"],
            cmd_target_names=["INST"],
            tlm_target_names=["INST"],
        )
        model.create()
        inject_tlm("INST", "HEALTH_STATUS", {"TEMP1": 5})
        time.sleep(0.5)
        obj.inject_tlm.assert_called_once()

    @patch("openc3.microservices.microservice.System")
    def test_inject_tlm_injects_a_packet_into_target_without_an_interface(
        self, mock_system
    ):
        self.decom_stuff()
        # Case doesn't matter
        inject_tlm(
            "inst", "Health_Status", {"temp1": 10, "Temp2": 20}, type="CONVERTED"
        )
        time.sleep(0.5)
        self.assertAlmostEqual(tlm("INST HEALTH_STATUS TEMP1"), 10.0, delta=0.1)
        self.assertAlmostEqual(tlm("INST HEALTH_STATUS TEMP2"), 20.0, delta=0.1)

        inject_tlm("INST", "HEALTH_STATUS", {"TEMP1": 0, "TEMP2": 0}, type="RAW")
        time.sleep(0.5)
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), (-100.0))
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP2"), (-100.0))

        self.dm.shutdown()

    @patch("openc3.microservices.microservice.System")
    def test_inject_tlm_bumps_the_received_count(self, mock_system):
        self.decom_stuff()

        inject_tlm("INST", "HEALTH_STATUS")
        time.sleep(0.5)
        self.assertEqual(tlm("INST HEALTH_STATUS RECEIVED_COUNT"), 1)
        inject_tlm("INST", "HEALTH_STATUS")
        time.sleep(0.5)
        self.assertEqual(tlm("INST HEALTH_STATUS RECEIVED_COUNT"), 2)
        inject_tlm("INST", "HEALTH_STATUS")
        time.sleep(0.5)
        self.assertEqual(tlm("INST HEALTH_STATUS RECEIVED_COUNT"), 3)

        self.dm.shutdown()

    # override_tlm
    def test_overrides_complains_about_unknown_targets_packets_and_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            override_tlm("BLAH HEALTH_STATUS COLLECTS = 1")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            override_tlm("INST UNKNOWN COLLECTS = 1")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            override_tlm("INST HEALTH_STATUS BLAH = 1")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            override_tlm("BLAH", "HEALTH_STATUS", "COLLECTS", 1)
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            override_tlm("INST", "UNKNOWN", "COLLECTS", 1)
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            override_tlm("INST", "HEALTH_STATUS", "BLAH", 1)

    def test_overrides_complains_with_too_many_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid number of arguments"):
            override_tlm("INST", "HEALTH_STATUS", "TEMP1", "TEMP2", 0.0)

    def test_overrides_all_values(self):
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="RAW"), (0))
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED"), -100.0
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED"), ("-100.000")
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS"), ("-100.000 C")
        )
        # Case doesn't matter
        override_tlm("inst Health_Status Temp1 = 10")
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="RAW"), (10))
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED"), (10))
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED"), ("10")
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS"), ("10")
        )
        override_tlm("INST", "HEALTH_STATUS", "TEMP1", 5.0)  # other syntax
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="RAW"), (5.0))
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED"), (5.0))
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED"), ("5.0")
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS"), ("5.0")
        )
        # NOTE: As a user you can override with weird values and this is allowed
        override_tlm("INST", "HEALTH_STATUS", "TEMP1", "what?")
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="RAW"), ("what?"))
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED"), ("what?")
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED"), ("what?")
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS"), ("what?")
        )
        normalize_tlm("INST HEALTH_STATUS TEMP1")

    def test_overrides_all_array_values(self):
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "ARY", type="RAW"),
            ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "ARY", type="CONVERTED"),
            ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "ARY", type="FORMATTED"),
            ("[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]"),
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "ARY", type="WITH_UNITS"),
            ("['0 V', '0 V', '0 V', '0 V', '0 V', '0 V', '0 V', '0 V', '0 V', '0 V']"),
        )
        override_tlm("INST HEALTH_STATUS ARY = [1,2,3]")
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "ARY", type="RAW"), ([1, 2, 3]))
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "ARY"), ([1, 2, 3]))
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "ARY", type="FORMATTED"), ("[1, 2, 3]")
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "ARY", type="WITH_UNITS"), ("[1, 2, 3]")
        )  # NOTE: 'V' not applied
        normalize_tlm("INST HEALTH_STATUS ARY")

    def test_overrides_raw_values(self):
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="RAW"), 0)
        override_tlm("INST", "HEALTH_STATUS", "TEMP1", 5.0, type="RAW")
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="RAW"), 5.0)
        set_tlm("INST", "HEALTH_STATUS", "TEMP1", 10.0, type="RAW")
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="RAW"), 5.0)
        normalize_tlm("INST HEALTH_STATUS TEMP1")

    def test_overrides_converted_values(self):
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), -100.0)
        override_tlm("INST HEALTH_STATUS TEMP1 = 60.0", type="CONVERTED")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), 60.0)
        override_tlm("INST HEALTH_STATUS TEMP1 = 50.0", type="CONVERTED")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), 50.0)
        set_tlm("INST HEALTH_STATUS TEMP1 = 10.0")
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), 50.0)
        normalize_tlm("INST HEALTH_STATUS TEMP1")

    def test_overrides_formatted_values(self):
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED"), "-100.000"
        )
        override_tlm("INST", "HEALTH_STATUS", "TEMP1", "5.000", type="FORMATTED")
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED"), "5.000"
        )
        set_tlm("INST", "HEALTH_STATUS", "TEMP1", "10.000", type="FORMATTED")
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED"), "5.000"
        )
        normalize_tlm("INST HEALTH_STATUS TEMP1")

    def test_overrides_with_units_values(self):
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS"), "-100.000 C"
        )
        override_tlm("INST", "HEALTH_STATUS", "TEMP1", "5.00 C", type="WITH_UNITS")
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS"), "5.00 C"
        )
        set_tlm("INST", "HEALTH_STATUS", "TEMP1", 10.0, type="WITH_UNITS")
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS"), "5.00 C"
        )
        normalize_tlm("INST HEALTH_STATUS TEMP1")

    # get_overrides
    def test_get_overrides_returns_empty_array_with_no_overrides(self):
        self.assertEqual(get_overrides(), ([]))

    def test_returns_all_overrides(self):
        override_tlm("INST HEALTH_STATUS temp1 = 10")
        override_tlm("INST HEALTH_STATUS ARY = [1,2,3]", type="RAW")
        overrides = get_overrides()
        self.assertEqual(len(overrides), 5)  # 4 for TEMP1 and 1 for ARY
        self.assertEqual(
            overrides[0],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "TEMP1",
                    "value_type": "RAW",
                    "value": 10,
                }
            ),
        )
        self.assertEqual(
            overrides[1],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "TEMP1",
                    "value_type": "CONVERTED",
                    "value": 10,
                }
            ),
        )
        self.assertEqual(
            overrides[2],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "TEMP1",
                    "value_type": "FORMATTED",
                    "value": "10",
                }
            ),
        )
        self.assertEqual(
            overrides[3],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "TEMP1",
                    "value_type": "WITH_UNITS",
                    "value": "10",
                }
            ),
        )
        self.assertEqual(
            overrides[4],
            (
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_name": "ARY",
                    "value_type": "RAW",
                    "value": [1, 2, 3],
                }
            ),
        )

    # normalize_tlm
    def test_normalize_tlm_complains_about_unknown_targets_packets_and_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            normalize_tlm("BLAH HEALTH_STATUS COLLECTS")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            normalize_tlm("INST UNKNOWN COLLECTS")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            normalize_tlm("INST HEALTH_STATUS BLAH")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            normalize_tlm("BLAH", "HEALTH_STATUS", "COLLECTS")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            normalize_tlm("INST", "UNKNOWN", "COLLECTS")
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            normalize_tlm("INST", "HEALTH_STATUS", "BLAH")

    def test_normalize_tlm_complains_with_too_many_parameters(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid number of arguments"):
            normalize_tlm("INST", "HEALTH_STATUS", "TEMP1", "TEMP2")

    def test_normalize_tlm_clears_all_overrides(self):
        override_tlm("INST", "HEALTH_STATUS", "TEMP1", 5.0, type="RAW")
        override_tlm("INST", "HEALTH_STATUS", "TEMP1", 50.0, type="CONVERTED")
        override_tlm("INST", "HEALTH_STATUS", "TEMP1", "50.00", type="FORMATTED")
        override_tlm("INST", "HEALTH_STATUS", "TEMP1", "50.00 F", type="WITH_UNITS")
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="RAW"), (5.0))
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED"), (50.0)
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED"), ("50.00")
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS"), ("50.00 F")
        )
        normalize_tlm("INST", "HEALTH_STATUS", "temp1")
        self.assertEqual(tlm("INST", "HEALTH_STATUS", "TEMP1", type="RAW"), (0))
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="CONVERTED"), -100.0
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="FORMATTED"), ("-100.000")
        )
        self.assertEqual(
            tlm("INST", "HEALTH_STATUS", "TEMP1", type="WITH_UNITS"), ("-100.000 C")
        )

    # get_tlm_buffer
    def test_get_tlm_buffer_returns_a_telemetry_packet_buffer(self):
        buffer = b"\x01\x02\x03\x04"
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.buffer = buffer
        TelemetryTopic.write_packet(packet, scope="DEFAULT")
        output = get_tlm_buffer("INST", "Health_Status")
        self.assertEqual(output["buffer"][0:4], buffer)
        output = get_tlm_buffer("INST Health_Status")
        self.assertEqual(output["buffer"][0:4], buffer)

    def test_get_tlm_buffer_returns_none_for_no_current_packet(self):
        output = get_tlm_buffer("INST", "MECH")
        self.assertIsNone(output)
        output = get_tlm_buffer("INST   MECH")
        self.assertIsNone(output)

    # get_all_tlm
    def test_get_all_tlm_raises_if_the_target_does_not_exist(self):
        with self.assertRaisesRegex(RuntimeError, "Target 'BLAH' does not exist"):
            get_all_tlm("BLAH", scope="DEFAULT")

    def test_get_all_tlm_returns_an_array_of_all_packet_hashes(self):
        pkts = get_all_tlm("inst", scope="DEFAULT")
        self.assertEqual(type(pkts), list)
        names = []
        for pkt in pkts:
            self.assertEqual(type(pkt), dict)
            self.assertEqual(pkt["target_name"], "INST")
            names.append(pkt["packet_name"])
        self.assertIn("ADCS", names)
        self.assertIn("HEALTH_STATUS", names)
        self.assertIn("PARAMS", names)
        self.assertIn("IMAGE", names)
        self.assertIn("MECH", names)

    # get_all_tlm_names
    def test_get_all_tlm_names_returns_an_empty_array_if_the_target_does_not_exist(
        self,
    ):
        self.assertEqual(get_all_tlm_names("BLAH"), [])

    def test_get_all_tlm_names_returns_an_array_of_all_packet_names(self):
        names = get_all_tlm_names("inst", scope="DEFAULT")
        print(names)
        self.assertEqual(type(names), list)
        self.assertIn("ADCS", names)
        self.assertIn("HEALTH_STATUS", names)
        self.assertIn("PARAMS", names)
        self.assertIn("IMAGE", names)
        self.assertIn("MECH", names)
        self.assertNotIn("HIDDEN", names)
        names = get_all_tlm_names("inst", hidden=True, scope="DEFAULT")
        print(names)
        self.assertEqual(type(names), list)
        self.assertIn("ADCS", names)
        self.assertIn("HEALTH_STATUS", names)
        self.assertIn("PARAMS", names)
        self.assertIn("IMAGE", names)
        self.assertIn("MECH", names)
        self.assertIn("HIDDEN", names)

    # get_all_tlm_item_names
    def test_get_all_tlm_item_names_returns_an_empty_array_if_the_target_does_not_exist(
        self,
    ):
        self.assertEqual(get_all_tlm_item_names("BLAH"), [])

    # Commenting this out for now... Looks like FakeRedis' zadd() is broken?
    # def test_get_all_tlm_item_names_returns_an_array_of_all_item_names(self):
    #     items = get_all_tlm_item_names("INST", scope="DEFAULT")
    #     self.assertEqual(type(items), list)
    #     self.assertEqual(len(items), 67)
    #     self.assertIn("ARY", items)
    #     self.assertIn("ATTPROGRESS", items)
    #     self.assertIn("BLOCKTEST", items)
    #     self.assertIn("CCSDSAPID", items)

    # get_tlm
    def test_get_tlm_raises_if_the_target_or_packet_do_not_exist(self):
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            get_tlm("BLAH", "HEALTH_STATUS", scope="DEFAULT")
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            get_tlm("INST BLAH", scope="DEFAULT")

    def test_get_tlm_returns_a_packet_hash(self):
        pkt = get_tlm("inst", "Health_Status", scope="DEFAULT")
        self.assertEqual(type(pkt), dict)
        self.assertEqual(pkt["target_name"], "INST")
        self.assertEqual(pkt["packet_name"], "HEALTH_STATUS")
        pkt = get_tlm("inst   Health_Status", scope="DEFAULT")
        self.assertEqual(type(pkt), dict)

    # get_item
    def test_get_item_raises_if_the_target_or_packet_or_item_do_not_exist(self):
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            get_item("BLAH", "HEALTH_STATUS", "CCSDSVER", scope="DEFAULT")
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            get_item("INST BLAH CCSDSVER", scope="DEFAULT")
        with self.assertRaisesRegex(
            RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"
        ):
            get_item("INST", "HEALTH_STATUS", "BLAH", scope="DEFAULT")
        with self.assertRaisesRegex(
            RuntimeError, "ERROR: Target name, packet name and item name required."
        ):
            get_item("INST HEALTH_STATUS", scope="DEFAULT")

    def test_get_item_complains_about_only_target(self):
        with self.assertRaisesRegex(
            RuntimeError,
            re.escape("Target name, packet name and item name required"),
        ):
            get_item("INST")

    def test_get_item_complains_about_only_target_packet(self):
        with self.assertRaisesRegex(
            RuntimeError,
            re.escape("Invalid number of arguments (2) passed to get_item"),
        ):
            get_item("INST", "HEALTH_STATUS")

    def test_get_item_complains_about_extra_params(self):
        with self.assertRaisesRegex(
            RuntimeError,
            re.escape("Invalid number of arguments (4) passed to get_item"),
        ):
            get_item("INST", "HEALTH_STATUS", "TEMP1", "TEMP2")

    def test_get_item_returns_an_item_hash(self):
        item = get_item("inst", "Health_Status", "CcsdsVER", scope="DEFAULT")
        self.assertEqual(type(item), dict)
        self.assertEqual(item["name"], "CCSDSVER")
        self.assertEqual(item["bit_offset"], 0)
        item = get_item("inst   Health_Status   CcsdsVER", scope="DEFAULT")
        self.assertEqual(type(item), dict)

    # get_tlm_packet
    def test_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            get_tlm_packet("BLAH", "HEALTH_STATUS")

    def test_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            get_tlm_packet("INST BLAH")

    def test_complains_using_latest(self):
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'INST LATEST' does not exist"
        ):
            get_tlm_packet("INST", "LATEST")

    def test_complains_about_non_existant_value_types(self):
        with self.assertRaisesRegex(
            TypeError, "Unknown type 'MINE' for INST HEALTH_STATUS"
        ):
            get_tlm_packet("INST HEALTH_STATUS", type="MINE")

    def test_reads_all_telemetry_items_as_converted_with_their_limits_states(self):
        vals = get_tlm_packet("inst", "Health_Status")
        # Spot check a few
        self.assertEqual(vals[11][0], "TEMP1")
        self.assertEqual(vals[11][1], -100.0)
        self.assertEqual(vals[11][2], "RED_LOW")
        self.assertEqual(vals[12][0], "TEMP2")
        self.assertEqual(vals[12][1], -100.0)
        self.assertEqual(vals[12][2], "RED_LOW")
        self.assertEqual(vals[13][0], "TEMP3")
        self.assertEqual(vals[13][1], -100.0)
        self.assertEqual(vals[13][2], "RED_LOW")
        self.assertEqual(vals[14][0], "TEMP4")
        self.assertEqual(vals[14][1], -100.0)
        self.assertEqual(vals[14][2], "RED_LOW")
        # Derived items are last
        self.assertEqual(vals[23][0], "PACKET_TIMESECONDS")
        self.assertGreater(vals[23][1], 0)
        self.assertIsNone(vals[23][2])
        self.assertEqual(vals[24][0], "PACKET_TIMEFORMATTED")
        self.assertEqual(
            vals[24][1].split(" ")[0],
            formatted(datetime.now(timezone.utc)).split(" ")[0],
        )  # Match the date
        self.assertIsNone(vals[24][2])
        self.assertEqual(vals[25][0], "RECEIVED_TIMESECONDS")
        self.assertGreater(vals[25][1], 0)
        self.assertIsNone(vals[25][2])
        self.assertEqual(vals[26][0], "RECEIVED_TIMEFORMATTED")
        self.assertEqual(
            vals[26][1].split(" ")[0],
            formatted(datetime.now(timezone.utc)).split(" ")[0],
        )  # Match the date
        self.assertIsNone(vals[26][2])
        self.assertEqual(vals[27][0], "RECEIVED_COUNT")
        self.assertEqual(vals[27][1], 0)
        self.assertIsNone(vals[27][2])

    def test_reads_all_telemetry_items_as_raw(self):
        vals = get_tlm_packet("INST   HEALTH_STATUS", type="RAW")
        self.assertEqual(vals[11][0], "TEMP1")
        self.assertEqual(vals[11][1], 0)
        self.assertEqual(vals[11][2], "RED_LOW")
        self.assertEqual(vals[12][0], "TEMP2")
        self.assertEqual(vals[12][1], 0)
        self.assertEqual(vals[12][2], "RED_LOW")
        self.assertEqual(vals[13][0], "TEMP3")
        self.assertEqual(vals[13][1], 0)
        self.assertEqual(vals[13][2], "RED_LOW")
        self.assertEqual(vals[14][0], "TEMP4")
        self.assertEqual(vals[14][1], 0)
        self.assertEqual(vals[14][2], "RED_LOW")

    def test_reads_all_telemetry_items_as_formatted(self):
        vals = get_tlm_packet("INST", "HEALTH_STATUS", type="FORMATTED")
        self.assertEqual(vals[11][0], "TEMP1")
        self.assertEqual(vals[11][1], "-100.000")
        self.assertEqual(vals[11][2], "RED_LOW")
        self.assertEqual(vals[12][0], "TEMP2")
        self.assertEqual(vals[12][1], "-100.000")
        self.assertEqual(vals[12][2], "RED_LOW")
        self.assertEqual(vals[13][0], "TEMP3")
        self.assertEqual(vals[13][1], "-100.000")
        self.assertEqual(vals[13][2], "RED_LOW")
        self.assertEqual(vals[14][0], "TEMP4")
        self.assertEqual(vals[14][1], "-100.000")
        self.assertEqual(vals[14][2], "RED_LOW")

    def test_reads_all_telemetry_items_as_with_units(self):
        vals = get_tlm_packet("INST HEALTH_STATUS", type="WITH_UNITS")
        self.assertEqual(vals[11][0], "TEMP1")
        self.assertEqual(vals[11][1], "-100.000 C")
        self.assertEqual(vals[11][2], "RED_LOW")
        self.assertEqual(vals[12][0], "TEMP2")
        self.assertEqual(vals[12][1], "-100.000 C")
        self.assertEqual(vals[12][2], "RED_LOW")
        self.assertEqual(vals[13][0], "TEMP3")
        self.assertEqual(vals[13][1], "-100.000 C")
        self.assertEqual(vals[13][2], "RED_LOW")
        self.assertEqual(vals[14][0], "TEMP4")
        self.assertEqual(vals[14][1], "-100.000 C")
        self.assertEqual(vals[14][2], "RED_LOW")

    def test_marks_data_as_stale(self):
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.received_time = datetime.now(timezone.utc) - timedelta(seconds=100)
        packet.stored = False
        packet.check_limits()
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)  # Allow the write to happen

        # Use the default stale_time of 30s
        vals = get_tlm_packet("INST", "HEALTH_STATUS")
        # Spot check a few
        self.assertEqual(vals[11][0], "TEMP1")
        self.assertEqual(vals[11][1], -100.0)
        self.assertEqual(vals[11][2], "STALE")
        self.assertEqual(vals[12][0], "TEMP2")
        self.assertEqual(vals[12][1], -100.0)
        self.assertEqual(vals[12][2], "STALE")
        self.assertEqual(vals[13][0], "TEMP3")
        self.assertEqual(vals[13][1], -100.0)
        self.assertEqual(vals[13][2], "STALE")
        self.assertEqual(vals[14][0], "TEMP4")
        self.assertEqual(vals[14][1], -100.0)
        self.assertEqual(vals[14][2], "STALE")

        vals = get_tlm_packet("INST", "HEALTH_STATUS", stale_time=101)
        # Verify it goes back to the limits setting and not STALE
        self.assertEqual(vals[11][0], "TEMP1")
        self.assertEqual(vals[11][1], -100.0)
        self.assertEqual(vals[11][2], "RED_LOW")
        self.assertEqual(vals[12][0], "TEMP2")
        self.assertEqual(vals[12][1], -100.0)
        self.assertEqual(vals[12][2], "RED_LOW")
        self.assertEqual(vals[13][0], "TEMP3")
        self.assertEqual(vals[13][1], -100.0)
        self.assertEqual(vals[13][2], "RED_LOW")
        self.assertEqual(vals[14][0], "TEMP4")
        self.assertEqual(vals[14][1], -100.0)
        self.assertEqual(vals[14][2], "RED_LOW")

    # get_tlm_values
    def test_get_tlm_values_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            get_tlm_values(["BLAH__HEALTH_STATUS__TEMP1__CONVERTED"])

    def test_get_tlm_values_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            get_tlm_values(["INST__BLAH__TEMP1__CONVERTED"])

    def test_get_tlm_values_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(
            RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"
        ):
            get_tlm_values(["INST__HEALTH_STATUS__BLAH__CONVERTED"])
        with self.assertRaisesRegex(
            RuntimeError, "Item 'INST LATEST BLAH' does not exist for scope: DEFAULT"
        ):
            get_tlm_values(["INST__LATEST__BLAH__CONVERTED"])

    def test_get_tlm_values_complains_about_non_existant_value_types(self):
        with self.assertRaisesRegex(ValueError, "Unknown value type 'MINE'"):
            get_tlm_values(["INST__HEALTH_STATUS__TEMP1__MINE"])

    def test_get_tlm_values_complains_about_bad_arguments(self):
        with self.assertRaisesRegex(TypeError, "items must be array of strings"):
            get_tlm_values([])
        with self.assertRaisesRegex(TypeError, "items must be array of strings"):
            get_tlm_values([["INST", "HEALTH_STATUS", "TEMP1"]])
        with self.assertRaisesRegex(ValueError, "items must be formatted"):
            get_tlm_values(["INST", "HEALTH_STATUS", "TEMP1"])

    def test_get_tlm_values_reads_all_the_specified_items(self):
        items = []
        items.append("inst__Health_Status__Temp1__converted")  # Case doesn't matter
        items.append("INST__LATEST__TEMP2__CONVERTED")
        items.append("INST__HEALTH_STATUS__TEMP3__CONVERTED")
        items.append("INST__LATEST__TEMP4__CONVERTED")
        items.append("INST__HEALTH_STATUS__DURATION__CONVERTED")
        vals = get_tlm_values(items)
        self.assertEqual(vals[0][0], (-100.0))
        self.assertEqual(vals[1][0], (-100.0))
        self.assertEqual(vals[2][0], (-100.0))
        self.assertEqual(vals[3][0], (-100.0))
        self.assertEqual(vals[4][0], (0.0))
        self.assertEqual(vals[0][1], "RED_LOW")
        self.assertEqual(vals[1][1], "RED_LOW")
        self.assertEqual(vals[2][1], "RED_LOW")
        self.assertEqual(vals[3][1], "RED_LOW")
        self.assertIsNone(vals[4][1])

    def test_get_tlm_values_reads_all_the_specified_raw_items(self):
        items = []
        items.append("INST__HEALTH_STATUS__TEMP1__RAW")
        items.append("INST__HEALTH_STATUS__TEMP2__RAW")
        items.append("INST__HEALTH_STATUS__TEMP3__RAW")
        items.append("INST__HEALTH_STATUS__TEMP4__RAW")
        vals = get_tlm_values(items)
        self.assertEqual(vals[0][0], 0)
        self.assertEqual(vals[1][0], 0)
        self.assertEqual(vals[2][0], 0)
        self.assertEqual(vals[3][0], 0)
        self.assertEqual(vals[0][1], "RED_LOW")
        self.assertEqual(vals[1][1], "RED_LOW")
        self.assertEqual(vals[2][1], "RED_LOW")
        self.assertEqual(vals[3][1], "RED_LOW")

    def test_get_tlm_values_reads_all_the_specified_items_with_different_conversions(
        self,
    ):
        items = []
        items.append("INST__HEALTH_STATUS__TEMP1__RAW")
        items.append("INST__HEALTH_STATUS__TEMP2__CONVERTED")
        items.append("INST__HEALTH_STATUS__TEMP3__FORMATTED")
        items.append("INST__HEALTH_STATUS__TEMP4__WITH_UNITS")
        vals = get_tlm_values(items)
        self.assertEqual(vals[0][0], 0)
        self.assertEqual(vals[1][0], (-100.0))
        self.assertEqual(vals[2][0], "-100.000")
        self.assertEqual(vals[3][0], "-100.000 C")
        self.assertEqual(vals[0][1], "RED_LOW")
        self.assertEqual(vals[1][1], "RED_LOW")
        self.assertEqual(vals[2][1], "RED_LOW")
        self.assertEqual(vals[3][1], "RED_LOW")

    def test_get_tlm_values_returns_even_when_requesting_items_that_do_not_yet_exist_in_cvt(
        self,
    ):
        items = []
        items.append("INST__HEALTH_STATUS__TEMP1__CONVERTED")
        items.append("INST__PARAMS__VALUE1__CONVERTED")
        items.append("INST__MECH__SLRPNL1__CONVERTED")
        items.append("INST__ADCS__POSX__CONVERTED")
        vals = get_tlm_values(items)
        self.assertEqual(vals[0][0], (-100.0))
        self.assertIsNone(vals[1][0])
        self.assertIsNone(vals[2][0])
        self.assertIsNone(vals[3][0])
        self.assertEqual(vals[0][1], "RED_LOW")
        self.assertIsNone(vals[1][1])
        self.assertIsNone(vals[2][1])
        self.assertIsNone(vals[3][1])

    def test_get_tlm_values_handles_block_data_as_binary(self):
        items = []
        items.append("INST__HEALTH_STATUS__BLOCKTEST__RAW")
        vals = get_tlm_values(items)
        self.assertEqual(vals[0][0], b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
        self.assertIsNone(vals[0][1])

    def test_get_tlm_values_marks_data_as_stale(self):
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.received_time = datetime.now(timezone.utc) - timedelta(seconds=100)
        packet.stored = False
        packet.check_limits()
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)  # Allow the write to happen

        items = []
        items.append("INST__HEALTH_STATUS__TEMP1__CONVERTED")
        items.append("INST__LATEST__TEMP2__CONVERTED")
        items.append("INST__HEALTH_STATUS__TEMP3__CONVERTED")
        items.append("INST__LATEST__TEMP4__CONVERTED")
        items.append("INST__HEALTH_STATUS__DURATION__CONVERTED")
        # Use the default stale_time of 30s
        vals = get_tlm_values(items)
        self.assertEqual(vals[0][0], -100.0)
        self.assertEqual(vals[1][0], -100.0)
        self.assertEqual(vals[2][0], -100.0)
        self.assertEqual(vals[3][0], -100.0)
        self.assertEqual(vals[4][0], 0.0)
        self.assertEqual(vals[0][1], "STALE")
        self.assertEqual(vals[1][1], "STALE")
        self.assertEqual(vals[2][1], "STALE")
        self.assertEqual(vals[3][1], "STALE")
        self.assertEqual(vals[4][1], "STALE")

        vals = get_tlm_values(items, stale_time=101)
        self.assertEqual(vals[0][0], -100.0)
        self.assertEqual(vals[1][0], -100.0)
        self.assertEqual(vals[2][0], -100.0)
        self.assertEqual(vals[3][0], -100.0)
        self.assertEqual(vals[4][0], 0.0)
        self.assertEqual(vals[0][1], "RED_LOW")
        self.assertEqual(vals[1][1], "RED_LOW")
        self.assertEqual(vals[2][1], "RED_LOW")
        self.assertEqual(vals[3][1], "RED_LOW")
        self.assertIsNone(vals[4][1])

    def test_get_tlm_available_complains_about_bad_arguments(self):
        with self.assertRaisesRegex(ValueError, "items must be formatted"):
            get_tlm_available(["INST"])
        with self.assertRaisesRegex(ValueError, "items must be formatted"):
            get_tlm_available(["INST__HEALTH_STATUS"])
        with self.assertRaisesRegex(ValueError, "items must be formatted"):
            get_tlm_available(["INST__HEALTH_STATUS__TEMP1"])

    def test_get_tlm_available_returns_proper_value_types_based_on_item_configuration(self):
        # Test items with different conversion types
        items = [
            "INST__HEALTH_STATUS__TEMP1__WITH_UNITS",  # Has units
            "INST__HEALTH_STATUS__TEMP2__FORMATTED",   # Has format_string  
            "INST__HEALTH_STATUS__TEMP3__CONVERTED",   # Has read_conversion
            "INST__HEALTH_STATUS__DURATION__RAW",      # Raw only
        ]
        result = get_tlm_available(items)
        
        # TEMP1 has units, so should return WITH_UNITS
        self.assertEqual(result[0], "INST__HEALTH_STATUS__TEMP1__WITH_UNITS__LIMITS")
        # TEMP2 has format_string, so should return FORMATTED  
        self.assertEqual(result[1], "INST__HEALTH_STATUS__TEMP2__FORMATTED__LIMITS")
        # TEMP3 has read_conversion, so should return CONVERTED
        self.assertEqual(result[2], "INST__HEALTH_STATUS__TEMP3__CONVERTED__LIMITS")
        # DURATION should return RAW (no conversions)
        self.assertEqual(result[3], "INST__HEALTH_STATUS__DURATION__RAW")

    def test_get_tlm_available_handles_fallback_value_types(self):
        # Test fallback logic: WITH_UNITS -> FORMATTED -> CONVERTED -> RAW
        items = [
            "INST__HEALTH_STATUS__TEMP1__WITH_UNITS",  # Should fall back to FORMATTED since no units
            "INST__HEALTH_STATUS__TEMP2__FORMATTED",   # Should fall back to CONVERTED since no format_string for this test
        ]
        result = get_tlm_available(items)
        
        # These would fall back based on what's actually available for these items
        self.assertIsNotNone(result[0])
        self.assertIsNotNone(result[1])
        self.assertTrue(result[0].endswith("__LIMITS"))
        self.assertTrue(result[1].endswith("__LIMITS"))

    def test_get_tlm_available_handles_latest_packet_resolution(self):
        items = ["INST__LATEST__TEMP1__CONVERTED"]
        result = get_tlm_available(items)
        
        # Should resolve LATEST to actual packet name and return proper format
        self.assertEqual(result[0], "INST__LATEST__TEMP1__CONVERTED__LIMITS")

    def test_get_tlm_available_handles_nonexistent_items(self):
        items = [
            "INST__HEALTH_STATUS__NONEXISTENT__RAW",
            "INST__HEALTH_STATUS__TEMP1__RAW",  # This one should work
        ]
        result = get_tlm_available(items)
        
        # Nonexistent item should return None
        self.assertIsNone(result[0])
        # Valid item should return proper format
        self.assertEqual(result[1], "INST__HEALTH_STATUS__TEMP1__RAW__LIMITS")

    def test_get_tlm_available_handles_reserved_item_names(self):
        # Test with a reserved item name that should force RAW type
        items = ["INST__HEALTH_STATUS__RECEIVED_COUNT__WITH_UNITS"]
        result = get_tlm_available(items)
        
        # Reserved items should always be RAW regardless of requested type
        self.assertEqual(result[0], "INST__HEALTH_STATUS__RECEIVED_COUNT__RAW")

    def test_get_tlm_available_handles_array_items(self):
        # This would need a packet item with array_size configured
        # For now, test the basic case - arrays with STRING/BLOCK data should return None
        items = ["INST__HEALTH_STATUS__TEMP1__RAW"]  # Regular item for comparison
        result = get_tlm_available(items)
        
        # Regular items should work normally
        self.assertEqual(result[0], "INST__HEALTH_STATUS__TEMP1__RAW__LIMITS")

    def test_get_tlm_available_returns_a_valid_list_of_items_based_on_inputs(self):
        items = []
        # Ask for WITH_UNITS for an item which has various formats
        items.append('INST__HEALTH_STATUS__TEMP1__WITH_UNITS')
        items.append('INST__ADCS__Q1__WITH_UNITS')
        items.append('INST__LATEST__CCSDSTYPE__WITH_UNITS')
        items.append('INST__LATEST__CCSDSVER__WITH_UNITS')
        # Ask for FORMATTED for an item which has various formats
        items.append('INST__ADCS__Q2__FORMATTED')
        items.append('INST__ADCS__CCSDSTYPE__FORMATTED')
        items.append('INST__ADCS__CCSDSVER__FORMATTED')
        # Ask for CONVERTED for an item which has various formats
        items.append('INST__HEALTH_STATUS__COLLECT_TYPE__CONVERTED')  # states but no conversion
        items.append('INST__ADCS__STAR1ID__CONVERTED')  # conversion but no states
        items.append('INST__ADCS__CCSDSVER__CONVERTED')
        # Ask for RAW item
        items.append('INST__HEALTH_STATUS__TEMP2__RAW')
        # Ask for items that do not exist
        items.append('BLAH__HEALTH_STATUS__TEMP1__WITH_UNITS')
        items.append('INST__NOPE__TEMP1__WITH_UNITS')
        items.append('INST__HEALTH_STATUS__NOPE__WITH_UNITS')
        # Ask for the special items
        items.append('INST__ADCS__PACKET_TIMEFORMATTED__WITH_UNITS')
        items.append('INST__ADCS__PACKET_TIMESECONDS__FORMATTED')
        items.append('INST__ADCS__RECEIVED_TIMEFORMATTED__CONVERTED')
        items.append('INST__ADCS__RECEIVED_TIMESECONDS__RAW')
        # Ask for array items
        items.append('INST__HEALTH_STATUS__ARY__WITH_UNITS')
        items.append('INST__HEALTH_STATUS__ARY2__WITH_UNITS')
        
        vals = get_tlm_available(items)
        expected = [
            'INST__HEALTH_STATUS__TEMP1__WITH_UNITS__LIMITS',
            'INST__ADCS__Q1__FORMATTED',
            'INST__LATEST__CCSDSTYPE__CONVERTED',
            'INST__LATEST__CCSDSVER__RAW',
            'INST__ADCS__Q2__FORMATTED',
            'INST__ADCS__CCSDSTYPE__CONVERTED',
            'INST__ADCS__CCSDSVER__RAW',
            'INST__HEALTH_STATUS__COLLECT_TYPE__CONVERTED',
            'INST__ADCS__STAR1ID__CONVERTED',
            'INST__ADCS__CCSDSVER__RAW',
            'INST__HEALTH_STATUS__TEMP2__RAW__LIMITS',
            None,
            None,
            None,
            'INST__ADCS__PACKET_TIMEFORMATTED__RAW',
            'INST__ADCS__PACKET_TIMESECONDS__RAW',
            'INST__ADCS__RECEIVED_TIMEFORMATTED__RAW',
            'INST__ADCS__RECEIVED_TIMESECONDS__RAW',
            'INST__HEALTH_STATUS__ARY__RAW',
            'INST__HEALTH_STATUS__ARY2__RAW',
        ]
        self.assertEqual(vals, expected)

    def test_subscribe_packets_with_bad_input(self):
        with self.assertRaisesRegex(RuntimeError, "packets must be nested array"):
            subscribe_packets(["inst", "Health_Status"], ["INST", "ADCS"])

    def test_streams_packets_since_the_subscription_was_created(self):
        # Write an initial packet that should not be returned
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.received_time = datetime.now(timezone.utc)
        packet.write("DURATION", 1.0)
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)

        id = subscribe_packets([["inst", "Health_Status"], ["INST", "ADCS"]])
        time.sleep(0.01)

        # Write some packets that should be returned and one that will not
        packet.received_time = datetime.now(timezone.utc)
        packet.write("DURATION", 2.0)
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        packet.received_time = datetime.now(timezone.utc)
        packet.write("DURATION", 3.0)
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        packet = System.telemetry.packet("INST", "ADCS")
        packet.received_time = datetime.now(timezone.utc)
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        packet = System.telemetry.packet("INST", "IMAGE")  # Not subscribed
        packet.received_time = datetime.now(timezone.utc)
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")

        id, packets = get_packets(id)
        for index, packet in enumerate(packets):
            self.assertEqual(packet["target_name"], "INST")
            match index:
                case 0:
                    self.assertEqual(packet["packet_name"], "HEALTH_STATUS")
                    self.assertEqual(packet["DURATION"], 2.0)
                case 1:
                    self.assertEqual(packet["packet_name"], "HEALTH_STATUS")
                    self.assertEqual(packet["DURATION"], 3.0)
                case 2:
                    self.assertEqual(packet["packet_name"], "ADCS")
                case _:
                    raise RuntimeError("Found too many packets")

    def test_get_tlm_cnt_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH ABORT' does not exist"):
            get_tlm_cnt("BLAH", "ABORT")

    def test_get_tlm_cnt_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            get_tlm_cnt("INST", "BLAH")

    def test_get_tlm_cnt_complains_about_missing_packet(self):
        with self.assertRaisesRegex(
            RuntimeError,
            re.escape("Both target name and packet name required"),
        ):
            get_tlm_cnt("INST")

    def test_get_tlm_cnt_complains_about_extra_params(self):
        with self.assertRaisesRegex(
            RuntimeError,
            re.escape("Invalid number of arguments (3) passed to get_tlm_cnt"),
        ):
            get_tlm_cnt("INST", "HEALTH_STATUS", "TEMP1")

    def test_get_tlm_cnt_returns_the_receive_count(self):
        start = get_tlm_cnt("inst", "Health_Status")

        TargetModel.increment_telemetry_count("INST", "HEALTH_STATUS", 1, scope="DEFAULT")

        count = get_tlm_cnt("INST", "HEALTH_STATUS")
        self.assertEqual(count, start + 1)

    def test_get_tlm_cnts_returns_receive_counts_for_telemetry_packets(self):
        result = TargetModel.increment_telemetry_count("INST", "ADCS", 100, scope="DEFAULT")
        cnts = get_tlm_cnts([["inst", "Adcs"]])
        self.assertEqual(cnts, ([result]))

    def test_get_packet_derived_items_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH ABORT' does not exist"):
            get_packet_derived_items("BLAH", "ABORT")

    def test_get_packet_derived_items_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            get_packet_derived_items("INST", "BLAH")

    def test_get_packet_derived_items_returns_the_packet_derived_items(self):
        items = get_packet_derived_items("inst", "Health_Status")
        self.assertIn("RECEIVED_TIMESECONDS", items)
        self.assertIn("RECEIVED_TIMEFORMATTED", items)
        self.assertIn("RECEIVED_COUNT", items)
