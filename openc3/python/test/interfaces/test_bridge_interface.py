# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import asyncio
import sys
import unittest
from unittest.mock import AsyncMock, Mock, patch

from openc3.interfaces.bridge_interface import BridgeInterface
from test.test_helper import mock_redis


class TrackingBridgeInterface(BridgeInterface):
    def _stop_failed_startup(self):
        self.failed_thread = self._thread
        super()._stop_failed_startup()


class TestBridgeInterface(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_failed_startup_stops_its_event_loop_thread(self):
        interface = TrackingBridgeInterface("BRIDGE")
        model = Mock(ticket="ticket")

        with (
            patch("openc3.interfaces.bridge_interface.BridgeModel.get_model", return_value=model),
            patch.object(interface, "_startup", AsyncMock(side_effect=RuntimeError("bind failed"))),
            self.assertRaisesRegex(RuntimeError, "bind failed"),
        ):
            interface.connect()

        self.assertFalse(interface.failed_thread.is_alive())
        self.assertIsNone(interface._loop)
        self.assertIsNone(interface._thread)
        self.assertFalse(interface._started)

    def test_resets_host_attempt_before_sending_connect_command(self):
        interface = BridgeInterface("BRIDGE")
        interface._started = True
        interface._loop = object()
        interface._host_attempt_seen = True
        observed = []

        def send_command(_command):
            observed.append(interface._host_attempt_seen)
            # Simulate desired=True status arriving immediately after the command.
            interface._host_attempt_seen = True

        def run_coroutine(coroutine, _loop):
            self.assertTrue(interface._host_attempt_seen)
            coroutine.close()
            future = Mock()
            future.result.return_value = None
            return future

        with (
            patch("openc3.interfaces.bridge_interface.BridgeModel.get_model", return_value=Mock(ticket="ticket")),
            patch.object(interface, "_send_command", side_effect=send_command),
            patch("openc3.interfaces.bridge_interface.asyncio.run_coroutine_threadsafe", side_effect=run_coroutine),
        ):
            interface.connect()

        self.assertEqual(observed, [False])
        self.assertTrue(interface._host_attempt_seen)

    def test_startup_configures_custom_relay(self):
        interface = BridgeInterface("BRIDGE")
        interface.name = "INTERFACE"
        interface._scope = "DEFAULT"

        class FakeKey:
            @classmethod
            def generate(cls):
                return cls()

            @classmethod
            def from_bytes(cls, _value):
                return cls()

            def to_bytes(self):
                return b"s" * 32

            def public(self):
                return self

        class FakeEndpointOptions:
            def __init__(self, **options):
                self.options = options

        endpoint = object()
        fake_iroh = Mock()
        fake_iroh.SecretKey = FakeKey
        fake_iroh.EndpointOptions = FakeEndpointOptions
        fake_iroh.Endpoint.bind = AsyncMock(return_value=endpoint)
        fake_iroh.RelayMode.custom_from_urls.return_value = "custom-relay"

        with (
            patch.dict(sys.modules, {"iroh": fake_iroh}),
            patch.dict("os.environ", {"OPENC3_BRIDGE_RELAY": "https://relay.example"}),
            patch("openc3.interfaces.bridge_interface.BridgeInterfaceModel"),
        ):
            asyncio.run(interface._startup())

        options = fake_iroh.Endpoint.bind.await_args.args[0].options
        self.assertEqual(options["relay_mode"], "custom-relay")
        fake_iroh.RelayMode.custom_from_urls.assert_called_once_with(["https://relay.example"])
        self.assertIs(interface._endpoint, endpoint)


if __name__ == "__main__":
    unittest.main()
