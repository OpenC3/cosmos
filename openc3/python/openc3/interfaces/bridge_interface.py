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
import inspect
import json
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

# Control-channel ALPN (JSON status up / connect-disconnect commands down),
# distinct from the raw-byte data path (stream/<name>).
CTRL_ALPN_PREFIX = "ctrl/"

# Delay before retrying the (persistent) control channel after it drops.
CTRL_RECONNECT_DELAY = 5.0

# Data-channel readiness handshake (MUST match host_interface_microservice.py).
# The hub primes and pairs the data legs, but that alone is not proof the host is
# ready (the hub primes each leg the instant it arrives). So once the tunnel is
# paired the host sends READY (it is up, paired, and ready); only then does this
# interface report connected and reply GO, at which point the host connects its
# device. This guarantees (1) COSMOS never "connects" before the host is ready
# and (2) the host never touches hardware before COSMOS is connected. The bytes
# are consumed before raw device data flows, so they never mix with it.
BRIDGE_READY = b"\x01"
BRIDGE_GO = b"\x02"


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

        # asyncio machinery, owned by a dedicated background thread. The loop,
        # thread, endpoint, and control channel are started once and persist for
        # the interface's life so COSMOS can (re)connect the host and keep
        # receiving status even while the data tunnel is disconnected.
        self._loop = None
        self._thread = None
        self._endpoint = None
        self._started = False
        self._addr = None
        # Data path (per connect/disconnect).
        self._connection = None
        self._send_stream = None
        self._reader_task = None
        # Thread-safe hand-off of received bytes to read_interface().
        self._read_queue = None
        self._connected = False
        # Control path (persistent): the host's latest reported status and the
        # current send stream for connect/disconnect commands.
        self._ctrl_task = None
        self._ctrl_send = None
        self._host_status = None
        self._host_status_lock = threading.Lock()
        # Whether COSMOS wants the host connected; re-asserted to the host each
        # time the control channel (re)establishes, so the desired state survives
        # a control drop and can't be lost to a startup race.
        self._want_connected = False

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
        # Start the persistent loop/thread/endpoint/control once.
        if not self._started:
            self._loop = asyncio.new_event_loop()
            self._thread = threading.Thread(target=self._run_loop, daemon=True)
            self._thread.start()
            asyncio.run_coroutine_threadsafe(self._startup(), self._loop).result(self.connect_timeout)
            self._ctrl_task = asyncio.run_coroutine_threadsafe(self._start_control(), self._loop).result(5)
            self._started = True
        # Ask the host to (re)connect, then bring up the data tunnel. connect()
        # only returns once the host is up, paired, and ready (see the READY/GO
        # handshake in _establish_data); until then it raises so the normal
        # reconnect logic retries. The +5 lets the inner handshake timeout fire
        # (and clean up the tunnel) before this outer wait gives up.
        self._want_connected = True
        self._send_command("connect")
        asyncio.run_coroutine_threadsafe(self._establish_data(), self._loop).result(self.connect_timeout + 5)

    def _run_loop(self):
        asyncio.set_event_loop(self._loop)
        self._loop.run_forever()

    async def _startup(self):
        """One-time setup on the loop: identity, registration, and the endpoint."""
        import iroh

        # Bind a stable per-process identity and register its public key so the
        # hub authorizes this COSMOS leg.
        if self._secret_key_hex is None:
            self._secret_key_hex = bytes(iroh.SecretKey.generate().to_bytes()).hex()
        secret_key = iroh.SecretKey.from_bytes(bytes.fromhex(self._secret_key_hex))
        public_key = bytes(secret_key.public().to_bytes()).hex()
        BridgeInterfaceModel(name=self.name, scope=self._scope, public_key=public_key).create(force=True)
        self._endpoint = await iroh.Endpoint.bind(
            iroh.EndpointOptions(preset=iroh.preset_n0(), secret_key=bytes.fromhex(self._secret_key_hex))
        )

    async def _start_control(self):
        """Launch the persistent control-channel task on the loop."""
        return self._loop.create_task(self._control_loop())

    async def _establish_data(self):
        import iroh

        addr = iroh.EndpointTicket.from_string(self.ticket).endpoint_addr()
        self._addr = addr
        # Route by ALPN: stream/<INTERFACE_NAME>. openc3-app pairs this with the
        # host microservice serving the same stream. Raw device bytes only; this
        # flows transparently through bridge_microservice.
        alpn = f"stream/{self.name}".encode()
        try:
            self._connection = await self._endpoint.connect(addr, alpn)
            # bridge_microservice is the server: it opens+primes the bi-stream, so
            # we accept it and discard the primer byte.
            bi = await self._connection.accept_bi()
            self._send_stream = bi.send()
            recv = bi.recv()
            await recv.read(1)
            # Do NOT report connected yet. Wait for the host's READY, which only
            # arrives once the host has connected and paired its own data leg and
            # is ready — so a successful connect() proves the host is up. (req 1)
            ready = await asyncio.wait_for(self._read_exact(recv, len(BRIDGE_READY)), timeout=self.connect_timeout)
            if ready != BRIDGE_READY:
                raise RuntimeError(f"{self.name}: unexpected bridge handshake {ready!r}")
            # Tell the host it may now connect its device and start reading. (req 2)
            await self._send(BRIDGE_GO)
            self._connected = True
            self._reader_task = self._loop.create_task(self._reader(recv))
        except BaseException:
            # A failed/timed-out handshake must leave no half-open tunnel behind,
            # so the InterfaceMicroservice's retry starts clean.
            await self._close_data()
            raise

    async def _read_exact(self, recv, n):
        """Read exactly n bytes from an Iroh recv stream (for the fixed-size
        handshake). read(k) returns at most k bytes, so this never over-reads
        into the raw device data that follows."""
        buf = b""
        while len(buf) < n:
            chunk = await recv.read(n - len(buf))
            if not chunk:
                raise RuntimeError(f"{self.name}: bridge stream closed during handshake")
            buf += bytes(chunk)
        return buf

    async def _reader(self, recv):
        """Pump raw bytes from the Iroh stream into the read queue."""
        try:
            while self._connected:
                data = await recv.read(READ_CHUNK_BYTES)
                if not data:  # peer finished/closed the stream
                    break
                self._read_queue.put(bytes(data))
        except asyncio.CancelledError:
            # Expected on disconnect/shutdown: the reader task is cancelled.
            # Exit cleanly; the finally block signals the disconnect downstream.
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

    # Note: we intentionally do NOT override as_json(). The base Interface
    # reports state (authoritative to this side — the InterfaceMicroservice
    # drives it from connect/disconnect) plus byte/packet counts off the tunnel,
    # which carries the same bytes the host device sees. Injecting host-reported
    # fields here both lagged the state after a Disconnect and pushed keys
    # (connection_string) that InterfaceStatusModel doesn't accept. The host's
    # live status is surfaced separately to openc3-app via the hub control tap.

    # ------------------------------------------------------------------ control
    async def _control_loop(self):
        """Persistent control channel: read the host's status, hold the send
        stream for commands. Reconnects on drop; independent of the data tunnel."""
        alpn = f"{CTRL_ALPN_PREFIX}{self.name}".encode()
        while True:
            connection = None
            try:
                connection = await self._endpoint.connect(self._addr or await self._resolve_addr(), alpn)
                bi = await connection.accept_bi()  # hub opens+primes
                self._ctrl_send = bi.send()
                recv = bi.recv()
                await recv.read(1)
                # (Re)assert the desired state so it survives control drops and a
                # startup race where connect()'s command was sent before pairing.
                await self._write_command("connect" if self._want_connected else "disconnect")
                await self._ctrl_read_status(recv)
            except asyncio.CancelledError:
                break
            except Exception as error:
                Logger.info(f"{self.name}: control channel error: {type(error).__name__}: {error}")
            finally:
                self._ctrl_send = None
                if connection is not None:
                    with contextlib.suppress(Exception):
                        result = connection.close()
                        if inspect.isawaitable(result):
                            await result
            await asyncio.sleep(CTRL_RECONNECT_DELAY)

    async def _resolve_addr(self):
        import iroh

        return iroh.EndpointTicket.from_string(self.ticket).endpoint_addr()

    async def _ctrl_read_status(self, recv):
        """Read newline-delimited status JSON from the host into `_host_status`."""
        buffer = b""
        while True:
            data = await recv.read(READ_CHUNK_BYTES)
            if not data:  # control stream closed
                break
            buffer += bytes(data)
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("type") == "status" and isinstance(msg.get("status"), dict):
                    with self._host_status_lock:
                        self._host_status = msg["status"]

    def _send_command(self, cmd):
        """Send a connect/disconnect command to the host over the control channel
        (best effort — the host also follows the data tunnel's presence)."""
        if self._loop is None or not self._loop.is_running():
            return
        with contextlib.suppress(Exception):
            asyncio.run_coroutine_threadsafe(self._write_command(cmd), self._loop).result(5)

    async def _write_command(self, cmd):
        if self._ctrl_send is None:
            return
        await self._ctrl_send.write_all((json.dumps({"type": "cmd", "cmd": cmd}) + "\n").encode())

    def disconnect(self):
        # Tell the host to disconnect its device, then tear down the DATA tunnel.
        # The persistent loop/endpoint/control stay up so status keeps flowing and
        # a later connect() can reconnect the host.
        self._want_connected = False
        self._send_command("disconnect")
        self._connected = False
        if self._loop is not None and self._loop.is_running():
            with contextlib.suppress(Exception):
                asyncio.run_coroutine_threadsafe(self._close_data(), self._loop).result(5)
        # Unblock read_interface if it's waiting.
        if self._read_queue is not None:
            self._read_queue.put(None)
        super().disconnect()

    async def _close_data(self):
        if self._reader_task is not None:
            self._reader_task.cancel()
            self._reader_task = None
        with contextlib.suppress(Exception):
            if self._send_stream is not None:
                await self._send_stream.finish()
        self._send_stream = None
        with contextlib.suppress(Exception):
            if self._connection is not None:
                result = self._connection.close()
                if inspect.isawaitable(result):
                    await result
        self._connection = None
