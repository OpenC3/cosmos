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
import base64
import io
import json
import os
import tarfile
import tempfile
import time
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


class FakeAcceptConnection(FakeConnection):
    """A connection whose peer opens the bi-stream (as openc3-app does)."""

    async def accept_bi(self):
        return self.bi


class TestBridgeDiscovery(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.service = BridgeMicroservice.__new__(BridgeMicroservice)
        self.service.cancel_thread = False
        self.service.logger = Mock()
        self.service.bridge_name = "BRIDGE"
        self.service.scope = "DEFAULT"
        self.service._discovery_requests = []
        self.service._discovery_event = asyncio.Event()

    def response(self, connection):
        return json.loads(b"".join(connection.bi.send().data))

    async def test_discovery_returns_pending_requests_and_drops_expired(self):
        self.service._discovery_requests = [
            {"id": "1", "discovery": ["openc3/discovery/serial_discovery.py"], "expires_at": time.time() + 10},
            {"id": "2", "discovery": ["old.py"], "expires_at": time.time() - 1},
        ]
        connection = FakeAcceptConnection([b"discovery", b""])
        connection.disconnect()  # client closes after reading
        await asyncio.wait_for(self.service._serve_discovery(connection), timeout=1)
        self.assertEqual(
            self.response(connection), [{"id": "1", "discovery": ["openc3/discovery/serial_discovery.py"]}]
        )
        self.assertEqual(self.service._discovery_requests, [])

    async def test_discovery_long_polls_until_a_request_arrives(self):
        connection = FakeAcceptConnection([b"discovery", b""])
        connection.disconnect()
        task = asyncio.create_task(self.service._serve_discovery(connection))
        await asyncio.sleep(0.05)
        self.assertFalse(task.done())
        self.service._discovery_requests.append({"id": "3", "discovery": ["x.py", "1"], "expires_at": time.time() + 10})
        self.service._discovery_event.set()
        await asyncio.wait_for(task, timeout=1)
        self.assertEqual(self.response(connection), [{"id": "3", "discovery": ["x.py", "1"]}])

    async def test_discovery_returns_empty_list_after_timeout(self):
        connection = FakeAcceptConnection([b"discovery", b""])
        connection.disconnect()
        with patch("openc3.microservices.bridge_microservice.DISCOVERY_POLL_TIMEOUT", 0.01):
            await asyncio.wait_for(self.service._serve_discovery(connection), timeout=1)
        self.assertEqual(self.response(connection), [])

    async def test_discovery_result_is_published(self):
        body = json.dumps({"id": "1", "results": [{"value": "/dev/ttyUSB0", "text": "USB"}]}).encode()
        connection = FakeAcceptConnection([body, b""])
        connection.disconnect()
        with patch("openc3.microservices.bridge_microservice.DiscoveryTopic.write_result") as write_result:
            await asyncio.wait_for(self.service._serve_discovery_result(connection), timeout=1)
        write_result.assert_called_once_with(
            "BRIDGE", "1", {"results": [{"value": "/dev/ttyUSB0", "text": "USB"}]}, scope="DEFAULT"
        )

    async def test_scan_requests_carry_the_scan(self):
        scan = {"matchers": [{"id": "1", "class": "openc3.discovery.hid_discovery", "params": ["0x054C"]}]}
        self.service._discovery_requests = [
            {"id": "4", "discovery": [], "scan": scan, "expires_at": time.time() + 10},
        ]
        connection = FakeAcceptConnection([b"discovery", b""])
        connection.disconnect()
        await asyncio.wait_for(self.service._serve_discovery(connection), timeout=1)
        self.assertEqual(self.response(connection), [{"id": "4", "discovery": [], "scan": scan}])

    async def test_scan_result_is_published(self):
        scan = {"devices": [{"class": "x", "value": "abc", "matches": ["1"]}], "errors": {}, "skipped": {}}
        connection = FakeAcceptConnection([json.dumps({"id": "4", "scan": scan}).encode(), b""])
        connection.disconnect()
        with patch("openc3.microservices.bridge_microservice.DiscoveryTopic.write_result") as write_result:
            await asyncio.wait_for(self.service._serve_discovery_result(connection), timeout=1)
        write_result.assert_called_once_with("BRIDGE", "4", {"scan": scan}, scope="DEFAULT")

    async def test_discovery_error_is_published(self):
        connection = FakeAcceptConnection([json.dumps({"id": "1", "error": "boom"}).encode(), b""])
        connection.disconnect()
        with patch("openc3.microservices.bridge_microservice.DiscoveryTopic.write_result") as write_result:
            await asyncio.wait_for(self.service._serve_discovery_result(connection), timeout=1)
        write_result.assert_called_once_with("BRIDGE", "1", {"error": "boom"}, scope="DEFAULT")


class TestBridgeFiles(unittest.TestCase):
    def setUp(self):
        self.service = BridgeMicroservice.__new__(BridgeMicroservice)
        self.service.logger = Mock()
        self.service._gem_file_cache = {}
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def make_gem(self, files):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w:gz") as tar:
            for name, content in files.items():
                info = tarfile.TarInfo(name)
                info.size = len(content)
                tar.addfile(info, io.BytesIO(content))
        path = os.path.join(self.tmp.name, "plugin-1.0.0.gem")
        with tarfile.open(path, "w") as gem:
            info = tarfile.TarInfo("data.tar.gz")
            info.size = len(data.getvalue())
            gem.addfile(info, io.BytesIO(data.getvalue()))
        return path

    def test_ships_host_files(self):
        path = self.make_gem(
            {
                "lib/plugin.py": b"gem lib",
                "targets/HA/lib/interface.py": b"target lib",
                "targets/HA/cmd_tlm/cmd.txt": b"not needed",
                "requirements.txt": b"-c constraints.txt\n--requirement=more/extra.txt\n-r https://x/y.txt\nrequests\n",
                "constraints.txt": b"requests<3",
                "more/extra.txt": b"six",
                "README.md": b"not needed",
            }
        )
        with patch.object(self.service, "_find_gem", return_value=path):
            payload = json.loads(
                self.service._build_files_payload(
                    {"plugin-1.0.0.gem"}, {}, {"plugin-1.0.0": "rendered\n", "other-1.0.0": "ignored"}
                )
            )
        files = {entry["path"]: base64.b64decode(entry["content"]) for entry in payload["files"]}
        self.assertEqual(
            files,
            {
                "plugin-1.0.0/lib/plugin.py": b"gem lib",
                "plugin-1.0.0/targets/HA/lib/interface.py": b"target lib",
                # The installed (e.g. ERB rendered) requirements replace the gem's
                "plugin-1.0.0/requirements.txt": b"rendered\n",
                "plugin-1.0.0/constraints.txt": b"requests<3",
                "plugin-1.0.0/more/extra.txt": b"six",
            },
        )

    def test_installed_requirements(self):
        plugins = {
            "plugin-1.0.0.gem__0": {"python_requirements": "requests\n"},
            "other-1.0.0.gem__0": {"python_requirements": None},
        }
        with patch("openc3.microservices.bridge_microservice.Model.all", return_value=plugins):
            self.service.scope = "DEFAULT"
            self.assertEqual(self.service._installed_requirements(), {"plugin-1.0.0": "requests\n"})

    def test_host_microservices_name_their_plugin_files(self):
        self.service.scope = "DEFAULT"
        self.service.bridge_name = "BRIDGE"
        models = {
            "INT": {"name": "INT", "bridge_name": "BRIDGE", "plugin": "my-plugin-1.0.0.gem__0"},
            "OTHER": {"name": "OTHER", "bridge_name": "ELSEWHERE", "plugin": "x.gem__0"},
        }
        with patch("openc3.microservices.bridge_microservice.HostInterfaceMicroserviceModel.all", return_value=models):
            payload = json.loads(self.service._host_microservices_payload())
        self.assertEqual([(entry["name"], entry["plugin_files"]) for entry in payload], [("INT", "my-plugin-1.0.0")])
