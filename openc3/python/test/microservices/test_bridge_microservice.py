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
import unittest
from unittest.mock import Mock, patch

from openc3.microservices.bridge_microservice import BridgeMicroservice


class FakeRecv:
    def __init__(self, chunks=None):
        self.chunks = list(chunks or [])
        self.block = asyncio.Event()

    async def read(self, _size):
        if self.chunks:
            return self.chunks.pop(0)
        await self.block.wait()
        return b""


class FakeSend:
    def __init__(self):
        self.data = []
        self.finished = False

    async def write_all(self, data):
        self.data.append(bytes(data))

    async def finish(self):
        self.finished = True


class FakeBi:
    def __init__(self, recv):
        self._send = FakeSend()
        self._recv = recv

    def send(self):
        return self._send

    def recv(self):
        return self._recv


class FakeConnection:
    def __init__(self, chunks=None):
        self.bi = FakeBi(FakeRecv(chunks))
        self.closed_event = asyncio.Event()
        self.close_count = 0

    async def open_bi(self):
        return self.bi

    async def closed(self):
        await self.closed_event.wait()

    def close(self):
        self.close_count += 1
        self.closed_event.set()

    def disconnect(self):
        self.closed_event.set()


class TestBridgeMicroservice(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.service = BridgeMicroservice.__new__(BridgeMicroservice)
        self.service._waiting = {}
        self.service.cancel_thread = False
        self.service.logger = Mock()
        self.service.bridge_name = "BRIDGE"
        self.service.scope = "DEFAULT"
        self.service.streams = ["OLD"]

    async def test_parked_connection_is_removed_when_it_disconnects(self):
        connection = FakeConnection()
        task = asyncio.create_task(self.service._rendezvous(b"CHANNEL", connection))
        await asyncio.sleep(0)
        self.assertIn(b"CHANNEL", self.service._waiting)

        connection.disconnect()
        await asyncio.wait_for(task, timeout=1)

        self.assertNotIn(b"CHANNEL", self.service._waiting)

    async def test_same_side_connections_are_not_paired_or_overwritten(self):
        first = FakeConnection()
        first_task = asyncio.create_task(self.service._rendezvous(b"CHANNEL", first, is_host=False))
        await asyncio.sleep(0)
        first_entry = self.service._waiting[b"CHANNEL"]

        duplicate = FakeConnection()
        await self.service._rendezvous(b"CHANNEL", duplicate, is_host=False)

        self.assertIs(self.service._waiting[b"CHANNEL"], first_entry)
        self.assertEqual(duplicate.close_count, 1)
        self.assertFalse(first_task.done())

        first.disconnect()
        await asyncio.wait_for(first_task, timeout=1)

    async def test_opposite_sides_pair(self):
        cosmos = FakeConnection([b""])
        cosmos_task = asyncio.create_task(self.service._rendezvous(b"CHANNEL", cosmos, is_host=False))
        await asyncio.sleep(0)

        host = FakeConnection([b""])
        await asyncio.wait_for(self.service._rendezvous(b"CHANNEL", host, is_host=True), timeout=1)
        await asyncio.wait_for(cosmos_task, timeout=1)

        self.assertNotIn(b"CHANNEL", self.service._waiting)
        self.assertGreaterEqual(cosmos.close_count, 1)
        self.assertGreaterEqual(host.close_count, 1)

    async def test_read_request_has_a_size_limit(self):
        recv = FakeRecv([b"1234"])
        with (
            patch("openc3.microservices.bridge_microservice.MAX_REQUEST_BYTES", 3),
            self.assertRaisesRegex(ValueError, "request exceeds 3 bytes"),
        ):
            await self.service._read_request(recv)

    async def test_read_request_has_a_timeout(self):
        recv = FakeRecv()
        with (
            patch("openc3.microservices.bridge_microservice.REQUEST_TIMEOUT", 0.01),
            self.assertRaises(asyncio.TimeoutError),
        ):
            await self.service._read_request(recv)

    async def test_bind_retries_address_conflicts_before_persisting(self):
        endpoint = object()

        class FakeEndpointOptions:
            def __init__(self, **options):
                self.options = options

        class FakeEndpoint:
            calls = []

            @classmethod
            async def bind(cls, options):
                cls.calls.append(options.options["bind_addr"])
                if len(cls.calls) == 1:
                    raise RuntimeError("Address already in use")
                return endpoint

        iroh = Mock(Endpoint=FakeEndpoint, EndpointOptions=FakeEndpointOptions)
        model = Mock(port=None)
        with patch.object(self.service, "_port_candidates", return_value=[7799, 7800]):
            result, port = await self.service._bind_endpoint(iroh, model, {"alpns": []})

        self.assertIs(result, endpoint)
        self.assertEqual(port, 7800)
        self.assertEqual(FakeEndpoint.calls, ["0.0.0.0:7799", "0.0.0.0:7800"])
        self.assertEqual(model.port, 7800)
        model.create.assert_called_once_with(force=True)

    def test_failed_alpn_refresh_keeps_previous_streams_for_retry(self):
        endpoint = Mock()
        endpoint.set_alpns.side_effect = RuntimeError("refresh failed")

        changed = self.service._refresh_alpns(endpoint, ["NEW"])

        self.assertFalse(changed)
        self.assertEqual(self.service.streams, ["OLD"])
        self.service.logger.warn.assert_called_once()


if __name__ == "__main__":
    unittest.main()
