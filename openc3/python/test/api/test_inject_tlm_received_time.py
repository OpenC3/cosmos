# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

import json
import unittest
from datetime import datetime, timezone
from unittest.mock import Mock, patch

from openc3.api.tlm_api import inject_tlm
from openc3.microservices.interface_decom_common import handle_inject_tlm
from openc3.script.telemetry import inject_tlm as script_inject_tlm


class TestInjectTlmReceivedTime(unittest.TestCase):
    @patch("openc3.api.tlm_api.DecomInterfaceTopic.inject_tlm")
    @patch("openc3.api.tlm_api.InterfaceModel.all", return_value={})
    @patch("openc3.api.tlm_api.TargetModel.packet")
    @patch("openc3.api.tlm_api.authorize")
    def test_api_passes_received_time_without_interface(self, _authorize, _packet, _interfaces, decom_inject):
        received_time = 1_609_459_200_123_456_000

        inject_tlm("INST", "HEALTH_STATUS", received_time=received_time)

        decom_inject.assert_called_once_with(
            "INST",
            "HEALTH_STATUS",
            None,
            type="CONVERTED",
            stored=False,
            scope="DEFAULT",
            received_time=received_time,
        )

    @patch("openc3.api.tlm_api.InterfaceTopic.inject_tlm")
    @patch(
        "openc3.api.tlm_api.InterfaceModel.all",
        return_value={
            "INST_INT": {
                "name": "INST_INT",
                "tlm_target_names": ["INST"],
            }
        },
    )
    @patch("openc3.api.tlm_api.TargetModel.packet")
    @patch("openc3.api.tlm_api.authorize")
    def test_api_passes_received_time_with_interface(self, _authorize, _packet, _interfaces, interface_inject):
        received_time = 1_609_459_200_123_456_000

        inject_tlm("INST", "HEALTH_STATUS", received_time=received_time)

        interface_inject.assert_called_once_with(
            "INST_INT",
            "INST",
            "HEALTH_STATUS",
            None,
            type="CONVERTED",
            stored=False,
            scope="DEFAULT",
            received_time=received_time,
        )

    @patch("openc3.microservices.interface_decom_common.TelemetryTopic.write_packet")
    @patch(
        "openc3.microservices.interface_decom_common.TargetModel.increment_telemetry_count",
        return_value=1,
    )
    @patch("openc3.microservices.interface_decom_common.System")
    def test_handler_uses_historical_received_time(self, system, _increment, write_packet):
        packet = Mock()
        packet.target_name = "INST"
        packet.packet_name = "HEALTH_STATUS"
        system.telemetry.packet.return_value = packet
        received_time = 1_609_459_200_123_456_000

        handle_inject_tlm(
            json.dumps(
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_hash": None,
                    "type": "CONVERTED",
                    "stored": False,
                    "received_time": received_time,
                }
            ),
            "DEFAULT",
        )

        self.assertEqual(
            packet.received_time,
            datetime(2021, 1, 1, 0, 0, 0, 123456, tzinfo=timezone.utc),
        )
        write_packet.assert_called_once_with(packet, "DEFAULT")

    @patch("openc3.microservices.interface_decom_common.TelemetryTopic.write_packet")
    @patch(
        "openc3.microservices.interface_decom_common.TargetModel.increment_telemetry_count",
        return_value=1,
    )
    @patch("openc3.microservices.interface_decom_common.System")
    def test_handler_accepts_unix_epoch_zero(self, system, _increment, _write_packet):
        packet = Mock()
        packet.target_name = "INST"
        packet.packet_name = "HEALTH_STATUS"
        system.telemetry.packet.return_value = packet

        handle_inject_tlm(
            json.dumps(
                {
                    "target_name": "INST",
                    "packet_name": "HEALTH_STATUS",
                    "item_hash": None,
                    "type": "CONVERTED",
                    "stored": False,
                    "received_time": 0,
                }
            ),
            "DEFAULT",
        )

        self.assertEqual(packet.received_time, datetime(1970, 1, 1, tzinfo=timezone.utc))

    @patch("openc3.script.telemetry.openc3.script.API_SERVER")
    def test_script_wrapper_forwards_received_time(self, api_server):
        received_time = 1_609_459_200_123_456_000

        script_inject_tlm("INST", "HEALTH_STATUS", received_time=received_time)

        api_server.inject_tlm.assert_called_once_with(
            "INST",
            "HEALTH_STATUS",
            None,
            type="CONVERTED",
            stored=False,
            scope="DEFAULT",
            received_time=received_time,
        )


if __name__ == "__main__":
    unittest.main()
