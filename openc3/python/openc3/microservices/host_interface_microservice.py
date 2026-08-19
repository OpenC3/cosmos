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

By default only raw data transfer happens here; target definitions and any
regular ``PROTOCOL``s stay on the Docker side of COSMOS (applied by the
bridge_interface). Protocols declared with ``BRIDGE_PROTOCOL`` are the exception:
they are handed down in the host config and run **here**, next to the device, so
protocol processing that must live near the hardware (framing, timing-sensitive
handshakes, CRC, ...) happens before bytes ever cross the Iroh tunnel. There is
no Redis access on the host.

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
import inspect
import json
import os
import signal
import sys
import traceback

from openc3.packets.packet import Packet
from openc3.top_level import get_class_from_module
from openc3.utilities.logger import Logger
from openc3.utilities.string import filename_to_class_name, filename_to_module


def add_lib_dirs_to_path():
    """Put the synced plugin ``lib`` directories on ``sys.path``.

    openc3-app mirrors the scope's plugin files to the host and passes the
    ``lib`` directories in ``PYTHONPATH`` so host interfaces can import custom
    interface/protocol code (e.g. a plugin's ``lib/my_interface.py``). We fold
    those directories into ``sys.path`` explicitly rather than relying on the
    interpreter picking up the inherited ``PYTHONPATH`` — that inheritance is
    not dependable when the process is launched by the GUI app, so
    ``importlib.import_module`` in :func:`build_interface` would otherwise raise
    ``ModuleNotFoundError``.
    """
    pythonpath = os.environ.get("PYTHONPATH", "")
    for entry in pythonpath.split(os.pathsep):
        if entry and entry not in sys.path:
            sys.path.insert(0, entry)


# Host interfaces dial the hub on host/<name> (distinct from the COSMOS
# bridge_interface's stream/<name>) so the hub can enforce host-side identity.
HOST_ALPN_PREFIX = "host/"

# Control channel: the host dials hostctrl/<name> to push its live InterfaceStatus
# up to COSMOS (so it shows in CmdTlmServer) and to receive connect/disconnect
# commands. Carries newline-delimited JSON, not raw device bytes.
HOSTCTRL_ALPN_PREFIX = "hostctrl/"

# How often the host pushes its status up the control channel.
STATUS_INTERVAL = 1.0

# One-byte stream primer written by the bridge_microservice (server); we strip it.
PRIME_BYTES = 1

# Size of each raw read when pumping bytes.
PUMP_CHUNK_BYTES = 65536

# Delay between reconnect attempts.
RECONNECT_DELAY = 5.0

# Data-channel readiness handshake (MUST match bridge_interface.py). After the
# data legs pair, the host sends READY (up, paired, ready) and waits for the
# COSMOS bridge_interface to reply GO before it connects the device — so we never
# touch hardware until COSMOS is connected. The bytes are consumed before raw
# device data flows, so they never mix with it.
BRIDGE_READY = b"\x01"
BRIDGE_GO = b"\x02"

# Max wait for COSMOS's GO after we send READY before giving up and parking.
HANDSHAKE_TIMEOUT = 30.0

# Device/plugin connect and disconnect methods are arbitrary synchronous code;
# bound how long the async control loop waits for either operation.
DEVICE_OPERATION_TIMEOUT = 30.0


def _iroh_error_detail(error):
    """Human-readable detail for an exception. iroh's IrohError keeps its message
    behind a .message() method (its str()/repr() is just the class name), so call
    it when present; otherwise fall back to str()."""
    message = getattr(error, "message", None)
    if callable(message):
        try:
            detail = message()
            if detail:
                return f"{type(error).__name__}: {detail}"
        except Exception:
            # Error-detail extraction is best effort; use str(error) below.
            pass
    return f"{type(error).__name__}: {error}"


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
        # BRIDGE_PROTOCOLs to run on the host next to the device. Each entry is
        # [READ|WRITE|READ_WRITE, protocol filename/classname, params...].
        self.protocols = config.get("protocols") or []
        self.shutdown = False
        # Desired connection state, driven by COSMOS connect/disconnect commands
        # over the control channel. Starts disconnected: COSMOS is authoritative
        # and issues "connect" when its bridge_interface connects (including on
        # startup). `_connect_event`/`_disconnect_event` wake the data loop.
        self._desired_connected = False
        self._connect_event = None
        self._disconnect_event = None
        # Set to push a status line to COSMOS immediately on a state change
        # (rather than waiting up to STATUS_INTERVAL), so a park propagates fast.
        self._status_ping = None
        # The currently-connected interface, read (thread-safely enough for a
        # snapshot) by the status publisher.
        self._interface = None
        # Use the real COSMOS Logger, but only to stdout (openc3-app forwards it
        # up to COSMOS). Never write to a (nonexistent) host Redis.
        Logger.no_store = True
        Logger.microservice_name = self.name

    def build_interface(self):
        """Instantiate the real interface, apply its (already secret-resolved)
        connection options, and add any BRIDGE_PROTOCOLs so they run on the host
        next to the device. Target definitions and regular PROTOCOLs are not
        applied here; those stay on the COSMOS bridge_interface."""
        # Ensure the synced plugin lib dirs are importable before we resolve the
        # interface (and protocol) classes from their modules.
        add_lib_dirs_to_path()
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
        # Add BRIDGE_PROTOCOLs exactly as InterfaceModel#build does for regular
        # PROTOCOLs: [READ|WRITE|READ_WRITE, filename/classname, params...].
        for protocol in self.protocols:
            protocol_class = get_class_from_module(
                filename_to_module(protocol[1]),
                filename_to_class_name(protocol[1]),
            )
            interface.add_protocol(protocol_class, protocol[2:], protocol[0].upper())
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
        except KeyboardInterrupt:
            # SIGINT delivered before our async handler was installed (or on a
            # loop that can't install one) — still a clean shutdown, not a crash.
            Logger.info(f"{self.name}: shutting down (interrupt)")
        except Exception:
            Logger.error(f"{self.name}: host interface crashed:\n{traceback.format_exc()}")

    async def _serve(self):
        import iroh

        loop = asyncio.get_running_loop()
        self._connect_event = asyncio.Event()
        self._disconnect_event = asyncio.Event()
        self._disconnect_event.set()  # start disconnected; COSMOS drives connect
        self._status_ping = asyncio.Event()

        # Shut down cleanly on SIGINT/SIGTERM. openc3-app soft-stops us with
        # SIGINT when it closes; without this the default handler raises
        # KeyboardInterrupt and dumps a traceback. Instead: flip `shutdown`, wake
        # any parked loop, and set `stop` so the run loop below cancels the tasks
        # and lets their finally blocks disconnect the device / close connections.
        stop = asyncio.Event()

        def _request_stop():
            self.shutdown = True
            self._connect_event.set()
            self._disconnect_event.set()
            stop.set()

        for sig in (signal.SIGINT, signal.SIGTERM):
            # add_signal_handler is unsupported on some loops (e.g. Windows
            # Proactor); there the process is hard-stopped instead.
            with contextlib.suppress(NotImplementedError, ValueError, RuntimeError):
                loop.add_signal_handler(sig, _request_stop)

        # Bind with the openc3-app-provided identity so the hub can verify us.
        # No relay by default (co-located); set OPENC3_BRIDGE_RELAY to the same
        # relay the hub uses to reach it remotely.
        relay = os.environ.get("OPENC3_BRIDGE_RELAY")
        if relay:
            opts = {"preset": iroh.preset_n0(), "relay_mode": iroh.RelayMode.custom_from_urls([relay])}
        else:
            opts = {"preset": iroh.preset_n0_disable_relay()}
        if self.secret_key:
            opts["secret_key"] = bytes.fromhex(self.secret_key)
        endpoint = await iroh.Endpoint.bind(iroh.EndpointOptions(**opts))
        addr = iroh.EndpointTicket.from_string(self.ticket).endpoint_addr()

        # Run the persistent control channel and the (gated) data channel until a
        # shutdown signal arrives (or a task exits on its own), then cancel both
        # and await them so their finally blocks run before we close the endpoint.
        control = asyncio.create_task(self._control_loop(endpoint, addr))
        data = asyncio.create_task(self._data_loop(endpoint, addr))
        stopper = asyncio.create_task(stop.wait())
        try:
            await asyncio.wait({control, data, stopper}, return_when=asyncio.FIRST_COMPLETED)
        finally:
            self.shutdown = True
            for task in (control, data, stopper):
                task.cancel()
            await asyncio.gather(control, data, stopper, return_exceptions=True)
            with contextlib.suppress(Exception):
                result = endpoint.close()
                if inspect.isawaitable(result):
                    _ = await result
        Logger.info(f"{self.name}: shut down")

    def _set_desired(self, connected):
        if connected == self._desired_connected:
            return
        self._desired_connected = connected
        if connected:
            self._connect_event.set()
            self._disconnect_event.clear()
        else:
            self._disconnect_event.set()
            self._connect_event.clear()
        # Report the new desired state to COSMOS right away. This is what lets a
        # park (e.g. the device failed to open, as with a missing USB HID device)
        # reach the bridge_interface even though the device never connected.
        if self._status_ping is not None:
            self._status_ping.set()

    # ------------------------------------------------------------------ control
    async def _control_loop(self, endpoint, addr):
        """Persistent control channel: push status up, receive commands down.

        Independent of the data connection so COSMOS can (re)connect the host
        device at any time. Reconnects on drop."""
        alpn = f"{HOSTCTRL_ALPN_PREFIX}{self.channel}".encode()
        while not self.shutdown:
            connection = None
            try:
                connection = await endpoint.connect(addr, alpn)
                bi = await connection.accept_bi()  # hub opens+primes
                send = bi.send()
                recv = bi.recv()
                await recv.read(PRIME_BYTES)
                reader = asyncio.create_task(self._read_commands(recv))
                writer = asyncio.create_task(self._send_status(send))
                await asyncio.wait({reader, writer}, return_when=asyncio.FIRST_COMPLETED)
                reader.cancel()
                writer.cancel()
            except Exception as error:
                Logger.warn(f"{self.name}: control channel error: {_iroh_error_detail(error)}")
            finally:
                if connection is not None:
                    with contextlib.suppress(Exception):
                        result = connection.close()
                        if inspect.isawaitable(result):
                            _ = await result
            if not self.shutdown:
                await asyncio.sleep(RECONNECT_DELAY)

    async def _read_commands(self, recv):
        """Read newline-delimited JSON commands (connect/disconnect) from COSMOS.

        Each read is coalesced to its NET final desired state: on reconnect after
        the app has been closed a while, COSMOS's cycling can leave a backlog of
        stale connect/disconnect commands buffered on the (parked) control channel
        that all flush at once. Acting on each would thrash the device and spam the
        log, so we apply only the last command in the batch, and only when it
        actually changes our desired state."""
        buffer = b""
        while not self.shutdown:
            data = await recv.read(PUMP_CHUNK_BYTES)
            if not data:  # control stream closed
                break
            buffer += bytes(data)
            desired = None
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                cmd = msg.get("cmd")
                if cmd == "connect":
                    desired = True
                elif cmd == "disconnect":
                    desired = False
            if desired is not None and desired != self._desired_connected:
                Logger.info(f"{self.name}: COSMOS requested {'connect' if desired else 'disconnect'}")
                self._set_desired(desired)

    async def _send_status(self, send):
        """Push the interface's live status up to COSMOS: immediately on a state
        change (via `_status_ping`) and at least every STATUS_INTERVAL as a
        heartbeat."""
        while not self.shutdown:
            self._status_ping.clear()
            line = (json.dumps({"type": "status", "status": self._status_snapshot()}) + "\n").encode()
            await send.write_all(line)
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(self._status_ping.wait(), timeout=STATUS_INTERVAL)

    def _status_snapshot(self):
        """A JSON-able snapshot of the host interface's status. `desired` is the
        state the host is driving toward (True once it accepts COSMOS's connect,
        False once it parks) — COSMOS uses the True->False transition to detect a
        host self-disconnect even when the device never opened."""
        interface = self._interface
        if interface is not None:
            try:
                status = interface.as_json()
            except Exception:
                status = {}
            status["name"] = self.name
            # Reflect the desired/connection state the host is actually in.
            status["state"] = "CONNECTED" if interface.connected() else "DISCONNECTED"
            status["desired"] = self._desired_connected
            with contextlib.suppress(Exception):
                status["connection_string"] = interface.connection_string()
            return status
        return {"name": self.name, "state": "DISCONNECTED", "desired": self._desired_connected}

    # --------------------------------------------------------------------- data
    async def _data_loop(self, endpoint, addr):
        """Bridge the device to COSMOS while COSMOS wants us connected.

        Ordering matters: we pair the data tunnel and complete the READY/GO
        handshake with the COSMOS bridge_interface BEFORE connecting the device,
        so the device is only ever opened once COSMOS is connected (req 2). We do
        NOT auto-reconnect: whatever ends a session (a requested disconnect, the
        tunnel dropping, or a device error) parks us until COSMOS issues a fresh
        connect. COSMOS is authoritative — it detects the bridge_interface
        disconnect and re-commands us if it wants us back (req 5)."""
        alpn = f"{HOST_ALPN_PREFIX}{self.channel}".encode()
        while not self.shutdown:
            await self._connect_event.wait()  # wait until COSMOS requests connect
            if self.shutdown:
                break
            interface = None
            connection = None
            try:
                # 1. Pair the data tunnel first — no hardware touched yet.
                connection = await endpoint.connect(addr, alpn)
                # bridge_microservice (server) opens+primes the bi-stream; accept
                # it and strip the primer.
                bi = await connection.accept_bi()
                send = bi.send()
                recv = bi.recv()
                await recv.read(PRIME_BYTES)
                # 2. Tell COSMOS we are up, paired, and ready (req 1).
                await send.write_all(BRIDGE_READY)
                # 3. Wait for COSMOS to confirm it is connected before we open the
                #    device. COSMOS is authoritative on connection order (req 2).
                go = await asyncio.wait_for(self._read_exact(recv, len(BRIDGE_GO)), timeout=HANDSHAKE_TIMEOUT)
                if go != BRIDGE_GO:
                    raise RuntimeError(f"unexpected bridge handshake {go!r}")
                Logger.info(f"{self.name}: bridged to COSMOS on {alpn.decode()}")

                # 4. Now connect the device and start pumping raw bytes.
                interface = self.build_interface()
                await self._run_device_operation(interface.connect, "connect")
                self._interface = interface
                Logger.info(f"{self.name}: connected {interface.connection_string()}")
                self._status_ping.set()  # report CONNECTED promptly

                loop = asyncio.get_event_loop()
                up = asyncio.create_task(self._device_to_bridge(loop, interface, send))
                down = asyncio.create_task(self._bridge_to_device(loop, interface, recv))
                # Also break out promptly if COSMOS requests a disconnect.
                stop = asyncio.create_task(self._disconnect_event.wait())
                await asyncio.wait({up, down, stop}, return_when=asyncio.FIRST_COMPLETED)
                up.cancel()
                down.cancel()
                stop.cancel()
            except Exception as error:
                Logger.error(f"{self.name}: bridge error: {_iroh_error_detail(error)}")
            finally:
                self._interface = None
                if interface is not None:
                    try:
                        await self._run_device_operation(interface.disconnect, "disconnect")
                    except Exception as error:
                        Logger.warn(f"{self.name}: device disconnect failed: {_iroh_error_detail(error)}")
                if connection is not None:
                    with contextlib.suppress(Exception):
                        result = connection.close()
                        if inspect.isawaitable(result):
                            _ = await result
            # Never auto-reconnect (req 5). Park (clear the connect event) until
            # COSMOS issues a fresh connect over the control channel. This holds
            # whether the session ended from a requested disconnect, a dropped
            # tunnel, or a device error — COSMOS drives every (re)connection.
            self._set_desired(False)

    async def _run_device_operation(self, operation, name):
        """Run blocking device/plugin lifecycle code away from the event loop."""
        loop = asyncio.get_running_loop()
        try:
            return await asyncio.wait_for(
                loop.run_in_executor(None, operation),
                timeout=DEVICE_OPERATION_TIMEOUT,
            )
        except asyncio.TimeoutError as error:
            raise TimeoutError(
                f"{self.name}: device {name} timed out after {DEVICE_OPERATION_TIMEOUT:g} seconds"
            ) from error

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

    async def _device_to_bridge(self, loop, interface, send):
        """Read from the device and forward to COSMOS. With BRIDGE_PROTOCOLs the
        interface's protocol-aware read() runs here (so read protocols process
        the bytes next to the device) and the resulting packet buffer is tunneled;
        otherwise raw bytes pass through unchanged."""
        while not self.shutdown:
            if self.protocols:
                packet = await loop.run_in_executor(None, interface.read)
                if packet is None:  # interface/protocol requested disconnect
                    break
                data = packet.buffer
            else:
                data, _extra = await loop.run_in_executor(None, interface.read_interface)
                if data is None:  # interface requested disconnect
                    break
            await send.write_all(bytes(data))
        with contextlib.suppress(Exception):
            await send.finish()

    async def _bridge_to_device(self, loop, interface, recv):
        """Read bytes from COSMOS and write them to the device. With
        BRIDGE_PROTOCOLs the bytes are wrapped in a packet and sent through the
        interface's protocol-aware write() so write protocols run here; otherwise
        they are written raw."""
        while not self.shutdown:
            data = await recv.read(PUMP_CHUNK_BYTES)
            if not data:  # stream closed
                break
            if self.protocols:
                packet = Packet(None, None, "BIG_ENDIAN", None, bytes(data))
                await loop.run_in_executor(None, interface.write, packet)
            else:
                await loop.run_in_executor(None, interface.write_interface, bytes(data))


if __name__ == "__main__":
    HostInterfaceMicroservice().run()
