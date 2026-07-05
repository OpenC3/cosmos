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

"""COSMOS interface that tunnels raw bytes over Iroh to bridge_microservice.

This completes the processing chain:

    bridge_interface  ->  bridge_microservice  ->  openc3-app  ->  host microservice

It lets COSMOS (running in Docker) drive host-side interfaces such as serial
ports that aren't reachable from inside the container. The host microservice
(spawned by openc3-app) talks to the real device; openc3-app relays over Iroh to
bridge_microservice; and this interface is the COSMOS end of that pipe.

The Iroh stream carries **raw device bytes** (no framing), so this behaves like
any other byte-stream interface and normal COSMOS PROTOCOLs (BURST, LENGTH,
TERMINATED, ...) can be layered on top via the interface configuration.

The interface takes the BRIDGE_NAME (its first parameter, or the
``OPENC3_BRIDGE_NAME`` environment variable) and looks up that bridge's current
ticket from its ``BridgeModel`` at connect time, so multiple named bridges are
supported. The ALPN must match bridge_microservice / openc3-app.
"""

import asyncio
import contextlib
import os
import queue
import threading

from openc3.config.config_parser import ConfigParser
from openc3.interfaces.interface import Interface
from openc3.models.bridge_interface_model import BridgeInterfaceModel
from openc3.models.bridge_model import BridgeModel
from openc3.utilities.logger import Logger


# Size of each raw read from the Iroh stream.
READ_CHUNK_BYTES = 65536


class BridgeInterface(Interface):
    """Streams raw bytes to/from bridge_microservice over an Iroh connection.

    Routing is by ALPN: the connection uses ALPN ``stream/<INTERFACE_NAME>`` so
    openc3-app routes it to the host microservice serving that stream.
    """

    def __init__(self, bridge_name=None):
        super().__init__()
        # The bridge to connect through, by name. Its ticket is looked up from
        # the BridgeModel at connect time (published by its BridgeMicroservice).
        self.bridge_name = ConfigParser.handle_none(bridge_name)
        if self.bridge_name is None:
            self.bridge_name = os.environ.get("OPENC3_BRIDGE_NAME")
        # Resolved from the BridgeModel during connect().
        self.ticket = None
        self.connect_timeout = 30.0
        self.write_timeout = 10.0
        # Scope + per-process Iroh identity (generated once) whose public key is
        # registered so the hub authorizes this COSMOS leg.
        self._scope = "DEFAULT"
        self._secret_key_hex = None

        # asyncio machinery, owned by a dedicated background thread.
        self._loop = None
        self._thread = None
        self._endpoint = None
        self._connection = None
        self._send_stream = None
        self._reader_task = None
        # Thread-safe hand-off of received bytes to read_interface().
        self._read_queue = None
        self._connected = False

    def connection_string(self):
        return "Iroh bridge to bridge_microservice"

    def connect(self):
        super().connect()  # reset protocols
        if not self.bridge_name:
            raise RuntimeError(
                f"{self.name}: no BRIDGE_NAME configured (interface parameter or "
                "OPENC3_BRIDGE_NAME environment variable)"
            )
        # Look up the named bridge's current ticket (published by its
        # BridgeMicroservice). Raises if the bridge isn't up yet so the
        # interface's normal reconnect logic retries.
        scope = os.environ.get("OPENC3_SCOPE", "DEFAULT")
        self._scope = scope
        model = BridgeModel.get_model(self.bridge_name, scope=scope)
        if model is None or not model.ticket:
            raise RuntimeError(
                f"{self.name}: bridge '{self.bridge_name}' not found (or no ticket) in scope "
                f"{scope}; is its bridge_microservice running?"
            )
        self.ticket = model.ticket
        self._read_queue = queue.Queue()
        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()
        # Establish the Iroh connection and wait for it (raises on failure).
        asyncio.run_coroutine_threadsafe(self._establish(), self._loop).result(self.connect_timeout)

    def _run_loop(self):
        asyncio.set_event_loop(self._loop)
        self._loop.run_forever()

    async def _establish(self):
        import iroh

        # Bind a stable per-process identity and register its public key so the
        # hub authorizes this COSMOS leg (re-registered each connect; idempotent).
        if self._secret_key_hex is None:
            self._secret_key_hex = bytes(iroh.SecretKey.generate().to_bytes()).hex()
        secret_key = iroh.SecretKey.from_bytes(bytes.fromhex(self._secret_key_hex))
        public_key = bytes(secret_key.public().to_bytes()).hex()
        BridgeInterfaceModel(name=self.name, scope=self._scope, public_key=public_key).create(force=True)

        self._endpoint = await iroh.Endpoint.bind(
            iroh.EndpointOptions(preset=iroh.preset_n0(), secret_key=bytes.fromhex(self._secret_key_hex))
        )
        addr = iroh.EndpointTicket.from_string(self.ticket).endpoint_addr()
        # Route by ALPN: stream/<INTERFACE_NAME>. openc3-app pairs this with the
        # host microservice serving the same stream. Raw device bytes only; this
        # flows transparently through bridge_microservice.
        alpn = f"stream/{self.name}".encode()
        self._connection = await self._endpoint.connect(addr, alpn)
        # bridge_microservice is the server: it opens+primes the bi-stream, so we
        # accept it and discard the primer byte before pumping raw bytes.
        bi = await self._connection.accept_bi()
        self._send_stream = bi.send()
        recv = bi.recv()
        await recv.read(1)
        self._connected = True
        self._reader_task = self._loop.create_task(self._reader(recv))

    async def _reader(self, recv):
        """Pump raw bytes from the Iroh stream into the read queue."""
        try:
            while self._connected:
                data = await recv.read(READ_CHUNK_BYTES)
                if not data:  # peer finished/closed the stream
                    break
                self._read_queue.put(bytes(data))
        except asyncio.CancelledError:
            pass
        except Exception as error:
            Logger.info(f"{self.name}: bridge reader stopped: {type(error).__name__}: {error}")
        finally:
            self._connected = False
            self._read_queue.put(None)  # sentinel -> read_interface signals disconnect

    def connected(self):
        return self._connected

    def read_interface(self):
        data = self._read_queue.get()  # blocks until data or the disconnect sentinel
        if data is None:
            return None, None
        extra = None
        self.read_interface_base(data, extra)
        return data, extra

    def write_interface(self, data, extra=None):
        if not self._connected:
            raise RuntimeError(f"{self.name}: interface not connected for write")
        self.write_interface_base(data, extra)
        asyncio.run_coroutine_threadsafe(self._send(bytes(data)), self._loop).result(self.write_timeout)
        return data, extra

    async def _send(self, data):
        await self._send_stream.write_all(data)

    def disconnect(self):
        self._connected = False
        if self._loop is not None and self._loop.is_running():
            with contextlib.suppress(Exception):
                asyncio.run_coroutine_threadsafe(self._close(), self._loop).result(5)
            self._loop.call_soon_threadsafe(self._loop.stop)
        if self._thread is not None:
            self._thread.join(timeout=5)
            self._thread = None
        # Unblock read_interface if it's waiting.
        if self._read_queue is not None:
            self._read_queue.put(None)
        super().disconnect()

    async def _close(self):
        if self._reader_task is not None:
            self._reader_task.cancel()
        with contextlib.suppress(Exception):
            if self._send_stream is not None:
                await self._send_stream.finish()
        with contextlib.suppress(Exception):
            if self._connection is not None:
                result = self._connection.close()
                if asyncio.iscoroutine(result):
                    await result
