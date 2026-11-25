# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.

import asyncio
import io
import threading
import unittest
from unittest.mock import patch

from openc3.microservices.host_interface_microservice import HostInterfaceMicroservice, _PipeSafeStream


class TestHostInterfaceMicroservice(unittest.IsolatedAsyncioTestCase):
    async def test_device_operation_times_out_without_blocking_event_loop(self):
        service = HostInterfaceMicroservice.__new__(HostInterfaceMicroservice)
        service.name = "HOST"
        release = threading.Event()
        timer_fired = False

        async def mark_timer():
            nonlocal timer_fired
            await asyncio.sleep(0)
            timer_fired = True

        timer = asyncio.create_task(mark_timer())
        try:
            with (
                patch("openc3.microservices.host_interface_microservice.DEVICE_OPERATION_TIMEOUT", 0.01),
                self.assertRaisesRegex(TimeoutError, "device connect timed out"),
            ):
                await service._run_device_operation(release.wait, "connect")
        finally:
            release.set()
        await timer
        self.assertTrue(timer_fired)

    def _control_service(self):
        service = HostInterfaceMicroservice.__new__(HostInterfaceMicroservice)
        service.name = "HOST"
        service.channel = "HOST"
        service.shutdown = False
        service._interface = None
        service._desired_connected = False
        service._status_ping = asyncio.Event()
        return service

    @staticmethod
    def _endpoint(read):
        class Recv:
            reads = 0

            async def read(self, size):
                self.reads += 1
                if self.reads == 1:
                    return b"\0"  # the hub's prime
                return await read()

        class Send:
            async def write_all(self, data):
                pass

        class Bi:
            def send(self):
                return Send()

            def recv(self):
                return Recv()

        class Connection:
            async def accept_bi(self):
                return Bi()

            def close(self):
                pass

        class Endpoint:
            async def connect(self, addr, alpn):
                return Connection()

        return Endpoint()

    async def test_control_channel_dropped_at_shutdown_is_not_an_error(self):
        service = self._control_service()

        async def read():
            # Shutting down closes the connection under the pending read
            service.shutdown = True
            raise RuntimeError("ConnectionLost(LocallyClosed)")

        with patch("openc3.microservices.host_interface_microservice.Logger") as logger:
            await asyncio.wait_for(service._control_loop(self._endpoint(read), "addr"), 2)
        logger.warn.assert_not_called()
        self.assertEqual(asyncio.all_tasks(), {asyncio.current_task()})

    async def test_cancelled_control_channel_leaves_no_tasks_running(self):
        service = self._control_service()
        reading = asyncio.Event()

        async def read():
            reading.set()
            await asyncio.Event().wait()

        control = asyncio.create_task(service._control_loop(self._endpoint(read), "addr"))
        await asyncio.wait_for(reading.wait(), 2)
        control.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await control
        # The reader and status writer are stopped with it, rather than left to
        # fail unobserved when the connection closes
        self.assertEqual(asyncio.all_tasks(), {asyncio.current_task()})


class TestStdinLifeline(unittest.TestCase):
    def test_eof_requests_stop_and_arms_exit_backstop(self):
        service = HostInterfaceMicroservice.__new__(HostInterfaceMicroservice)
        service.name = "HOST"
        stopped = threading.Event()
        exited = threading.Event()
        with (
            patch("openc3.microservices.host_interface_microservice.STOP_GRACE", 0.01),
            patch(
                "openc3.microservices.host_interface_microservice.os._exit",
                side_effect=lambda code: exited.set(),
            ),
        ):
            # Data before EOF is ignored; EOF triggers the stop.
            service._watch_stdin(io.BytesIO(b"ignored"), stopped.set)
            self.assertTrue(stopped.is_set())
            self.assertTrue(exited.wait(2), "backstop should force an exit after STOP_GRACE")

    def test_pipe_safe_stream_swallows_broken_pipe(self):
        class Broken:
            def write(self, data):
                raise BrokenPipeError()

            def flush(self):
                raise BrokenPipeError()

        stream = _PipeSafeStream(Broken())
        self.assertEqual(stream.write("x"), 1)
        stream.flush()
        self.assertEqual(stream.write("more"), 4)

    def test_pipe_safe_stream_passes_through(self):
        target = io.StringIO()
        stream = _PipeSafeStream(target)
        stream.write("hello")
        stream.flush()
        self.assertEqual(target.getvalue(), "hello")


if __name__ == "__main__":
    unittest.main()
