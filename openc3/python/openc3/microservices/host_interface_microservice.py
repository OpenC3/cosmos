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

"""Host side of a bridged COSMOS interface, launched by openc3-app.

This runs on the host computer (outside Docker) so it can reach hardware such
as serial ports. It builds the real interface, opens the device, and tunnels
**raw bytes** over Iroh to the COSMOS bridge_microservice hub, which pairs it
with the matching COSMOS ``bridge_interface`` by the ``stream/<name>`` ALPN:

    host interface  <--stream/NAME-->  bridge_microservice  <--stream/NAME-->  bridge_interface (COSMOS)

Only raw data transfer happens here; protocols and target definitions stay on
the Docker side of COSMOS (applied by the bridge_interface). There is no Redis
access on the host.

The host uses the normal COSMOS ``Logger`` API, but configured so it only writes
its JSON records to **stdout** (no Redis). openc3-app captures that stdout and
forwards it up to the bridge_microservice, which re-emits it into COSMOS, so log
messages appear in the main system as well.

Configuration is passed by openc3-app via environment variables:

* ``OPENC3_BRIDGE_TICKET``  — the bridge_microservice's Iroh ticket to dial.
* ``OPENC3_BRIDGE_CHANNEL`` — the stream/interface name (the ``stream/<name>`` ALPN).
* ``OPENC3_HOST_INTERFACE`` — JSON ``{"config_params": [...], "options": [...]}``.
* ``OPENC3_MICROSERVICE_NAME`` — name used for logging.
"""

import asyncio
import contextlib
import json
import os
import traceback

from openc3.top_level import get_class_from_module
from openc3.utilities.logger import Logger
from openc3.utilities.string import filename_to_class_name, filename_to_module


# Host interfaces dial the hub on host/<name> (distinct from the COSMOS
# bridge_interface's stream/<name>) so the hub can enforce host-side identity.
HOST_ALPN_PREFIX = "host/"

# One-byte stream primer written by the bridge_microservice (server); we strip it.
PRIME_BYTES = 1

# Size of each raw read when pumping bytes.
PUMP_CHUNK_BYTES = 65536

# Delay between reconnect attempts.
RECONNECT_DELAY = 5.0


class HostInterfaceMicroservice:
    def __init__(self):
        self.name = os.environ.get("OPENC3_MICROSERVICE_NAME", "host_interface")
        self.ticket = os.environ.get("OPENC3_BRIDGE_TICKET")
        self.channel = os.environ.get("OPENC3_BRIDGE_CHANNEL")
        # openc3-app mints this identity and hands it over (never persisted). The
        # hub authorizes its public key, so only microservices openc3-app spawned
        # may use the data path.
        self.secret_key = os.environ.get("OPENC3_BRIDGE_PRIVATE_KEY")
        config = json.loads(os.environ.get("OPENC3_HOST_INTERFACE") or "{}")
        self.config_params = config.get("config_params") or []
        self.options = config.get("options") or []
        self.shutdown = False
        # Use the real COSMOS Logger, but only to stdout (openc3-app forwards it
        # up to COSMOS). Never write to a (nonexistent) host Redis.
        Logger.no_store = True
        Logger.microservice_name = self.name

    def build_interface(self):
        """Instantiate the real interface and apply its (already secret-resolved)
        connection options. No protocols/targets are applied on the host."""
        klass = get_class_from_module(
            filename_to_module(self.config_params[0]),
            filename_to_class_name(self.config_params[0]),
        )
        if len(self.config_params) > 1:
            interface = klass(*self.config_params[1:])
        else:
            interface = klass()
        for option in self.options:
            interface.set_option(option[0], option[1:])
        return interface

    def run(self):
        if not self.ticket or not self.channel:
            Logger.error(f"{self.name}: OPENC3_BRIDGE_TICKET and OPENC3_BRIDGE_CHANNEL are required; exiting")
            return
        try:
            import iroh  # noqa: F401
        except ImportError as error:
            Logger.error(f"{self.name}: iroh package not installed ({error}); exiting")
            return
        try:
            asyncio.run(self._serve())
        except Exception:
            Logger.error(f"{self.name}: host interface crashed:\n{traceback.format_exc()}")

    async def _serve(self):
        import iroh

        # Bind with the openc3-app-provided identity so the hub can verify us.
        options = iroh.EndpointOptions(preset=iroh.preset_n0())
        if self.secret_key:
            options = iroh.EndpointOptions(
                preset=iroh.preset_n0(), secret_key=bytes.fromhex(self.secret_key)
            )
        endpoint = await iroh.Endpoint.bind(options)
        addr = iroh.EndpointTicket.from_string(self.ticket).endpoint_addr()
        alpn = f"{HOST_ALPN_PREFIX}{self.channel}".encode()
        while not self.shutdown:
            interface = None
            connection = None
            try:
                interface = self.build_interface()
                interface.connect()
                Logger.info(f"{self.name}: connected {interface.connection_string()}")

                connection = await endpoint.connect(addr, alpn)
                # bridge_microservice (server) opens+primes the bi-stream; accept
                # it and strip the primer, then it is raw device bytes.
                bi = await connection.accept_bi()
                send = bi.send()
                recv = bi.recv()
                await recv.read(PRIME_BYTES)
                Logger.info(f"{self.name}: bridged to COSMOS on {alpn.decode()}")

                loop = asyncio.get_event_loop()
                up = asyncio.create_task(self._device_to_bridge(loop, interface, send))
                down = asyncio.create_task(self._bridge_to_device(loop, interface, recv))
                await asyncio.wait({up, down}, return_when=asyncio.FIRST_COMPLETED)
                up.cancel()
                down.cancel()
            except Exception as error:
                Logger.error(f"{self.name}: bridge error: {type(error).__name__}: {error}")
            finally:
                if interface is not None:
                    with contextlib.suppress(Exception):
                        interface.disconnect()
                if connection is not None:
                    with contextlib.suppress(Exception):
                        result = connection.close()
                        if asyncio.iscoroutine(result):
                            await result
            if not self.shutdown:
                Logger.info(f"{self.name}: reconnecting in {RECONNECT_DELAY}s")
                await asyncio.sleep(RECONNECT_DELAY)

    async def _device_to_bridge(self, loop, interface, send):
        """Read raw bytes from the device and forward them to COSMOS."""
        while not self.shutdown:
            data, _extra = await loop.run_in_executor(None, interface.read_interface)
            if data is None:  # interface requested disconnect
                break
            await send.write_all(bytes(data))
        with contextlib.suppress(Exception):
            await send.finish()

    async def _bridge_to_device(self, loop, interface, recv):
        """Read raw bytes from COSMOS and write them to the device."""
        while not self.shutdown:
            data = await recv.read(PUMP_CHUNK_BYTES)
            if not data:  # stream closed
                break
            await loop.run_in_executor(None, interface.write_interface, bytes(data))


if __name__ == "__main__":
    HostInterfaceMicroservice().run()
