# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.

import asyncio
import threading
import unittest
from unittest.mock import patch

from openc3.microservices.host_interface_microservice import HostInterfaceMicroservice


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


if __name__ == "__main__":
    unittest.main()
