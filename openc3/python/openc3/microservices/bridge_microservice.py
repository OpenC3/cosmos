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

"""COSMOS side of the Iroh bridge: the single Iroh server/hub.

This microservice runs an Iroh endpoint inside COSMOS that everything else
dials. It is the hub of the bridge:

    bridge_interface (COSMOS) ->\\
                                 bridge_microservice (hub) -> host interface (openc3-app)
    openc3-app (api/*)       ->/

Two kinds of ALPN are served:

* ``stream/<interface-name>`` — the raw device data path. Both the COSMOS
  ``bridge_interface`` and the host-side interface dial in with the same ALPN;
  the hub rendezvous-pairs the two connections and pumps raw bytes between them
  (no framing). openc3-app is NOT in this data path.
* ``api/*`` — control APIs that openc3-app (the host launcher) dials:
  * ``api/host_microservices`` returns the JSON list of host microservices this
    bridge should run (from HostInterfaceMicroserviceModel); openc3-app polls it.
  * ``api/log`` receives host microservice stdout lines from openc3-app and
    re-emits them through the real COSMOS Logger.

The bridge keeps a stable Iroh identity across restarts: the private key lives
in the secrets store and the public key + current ticket are published in the
BridgeModel so peers can look the bridge up by name.
"""

import asyncio
import base64
import contextlib
import hashlib
import inspect
import io
import json
import os
import tarfile
import time
import traceback

from openc3.microservices.microservice import Microservice
from openc3.models.bridge_interface_model import BridgeInterfaceModel
from openc3.models.bridge_model import BridgeModel
from openc3.models.host_interface_microservice_model import HostInterfaceMicroserviceModel
from openc3.models.model import Model
from openc3.models.scope_model import ScopeModel
from openc3.topics.config_topic import ConfigTopic
from openc3.topics.topic import Topic
from openc3.utilities.store_queued import EphemeralStoreQueued


# Data path routing is by ALPN. The COSMOS bridge_interface (trusted, in-COSMOS)
# dials stream/<name>; the host-side interface dials host/<name>. The hub pairs
# the two legs on the same <name> and enforces identity only on the host leg.
STREAM_ALPN_PREFIX = "stream/"
HOST_ALPN_PREFIX = "host/"

# Control path: a second paired channel per interface carrying newline-delimited
# JSON (not raw bytes) — the host pushes its live InterfaceStatus up, and COSMOS
# sends connect/disconnect down. COSMOS dials ctrl/<name>; the host dials
# hostctrl/<name>. Paired on a distinct channel key so it never mixes with the
# data path.
CTRL_ALPN_PREFIX = "ctrl/"
HOSTCTRL_ALPN_PREFIX = "hostctrl/"
# Prefix for the rendezvous channel key of a control pair (keeps it disjoint from
# the data path's bare <name> key).
CTRL_CHANNEL_PREFIX = b"ctrl/"

# Control API ALPNs dialed by openc3-app.
API_HOST_MICROSERVICES = b"api/host_microservices"
API_LOG = b"api/log"
# Publishes the set of authorized host-microservice identities (openc3-app-minted
# public keys) that may use the host/<name> data path.
API_AUTHORIZE = b"api/authorize"
# Serves the scope's plugin lib/ files (hash-delta) so host interfaces can use
# plugin code. The host has no bucket/gem access, so the hub reads and ships it.
API_FILES = b"api/files"
# Returns the latest host InterfaceStatus per interface (tapped from the control
# channel), so openc3-app can display host interface status in its bridge section.
API_INTERFACE_STATUS = b"api/interface_status"

# The /gems volume (present in all deployments) holds the plugin gem cache.
GEM_HOME = os.environ.get("GEM_HOME") or "/gems"
# Bootstrap ALPN for manual enrollment (validated by a one-time code, not by
# the authorized app identity — this is how that identity gets established).
API_ENROLL = b"api/enroll"

# How often the relay re-queries its streams (from the HostInterfaceMicroserviceModels)
# and re-advertises ALPNs, so newly-deployed bridged interfaces are picked up
# without the operator having to respawn the relay.
STREAM_REFRESH_INTERVAL = 5.0

# One-byte stream primer. QUIC only surfaces a bi-stream to the peer's accept_bi
# once the opener writes, so on the data path the hub (server) opens+primes and
# the clients accept+strip this byte. All subsequent bytes are raw device data.
PRIME = b"\x00"

# Fixed UDP port range for bridge hubs. Each hub binds one port in this range and
# advertises 127.0.0.1:<port> in its ticket so the host reaches it locally (no
# relay). The SAME range MUST be published from the operator container in
# compose.yaml (127.0.0.1:BASE-LAST:BASE-LAST/udp). One port per bridge, assigned
# from the pool and reused across restarts; the pool size caps concurrent bridges.
BRIDGE_PORT_BASE = int(os.environ.get("OPENC3_BRIDGE_PORT_BASE") or 7799)
BRIDGE_PORT_COUNT = int(os.environ.get("OPENC3_BRIDGE_PORT_COUNT") or 16)

# Size of each raw read when pumping bytes.
PUMP_CHUNK_BYTES = 65536

# How long a lone data-path peer waits for its partner before giving up.
PAIR_TIMEOUT = 300

# How long a request/response handler waits for the client to finish reading and
# close before tearing the connection down (avoids a close race that truncates
# the response with "connection lost" over real networking).
CLOSE_DRAIN_TIMEOUT = 10


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
            pass
    return f"{type(error).__name__}: {error}"


class BridgeMicroservice(Microservice):
    """The Iroh hub: rendezvous for the data path plus control APIs.

    On startup it ensures a BridgeModel exists for this named bridge, generating
    an Iroh keypair if one isn't already stored, so the bridge keeps a stable
    identity across restarts. The private key is held in the secrets store; the
    public key and current connection ticket are written to the BridgeModel so
    bridge_interfaces (and openc3-app) can look the bridge up by name.
    """

    def __init__(self, name):
        super().__init__(name)
        self.bridge_name = self._bridge_name()
        # Interface/stream names this bridge relays, discovered live by querying
        # the HostInterfaceMicroserviceModels for this bridge (NOT passed as static
        # OPTIONs). Their stream/<name> ALPNs are advertised so the QUIC handshake
        # accepts data-path connections for them; _stream_watcher re-advertises as
        # the set changes so new interfaces are picked up without a relay restart.
        self.streams = self._streams()
        # channel (name bytes) -> (send, recv, connection, future, is_host) for
        # the first arrival on a data/control channel, awaiting its partner.
        self._waiting = {}
        # Latest host InterfaceStatus per interface name, tapped from the control
        # channel as it flows host -> COSMOS. Served to openc3-app over
        # api/interface_status so it can show host interface status too.
        self._interface_status = {}
        # Authorized host-microservice identities (Iroh EndpointId hex strings)
        # allowed on the host/<name> data path. Published by openc3-app over
        # api/authorize each cycle; held in memory only (matches the ephemeral,
        # never-persisted host keys).
        self._authorized_hosts = set()
        # Cache of extracted plugin-gem files so we only unzip+hash a gem when it
        # is new or its file has changed. gem_path -> (mtime, size, files) where
        # files is {relative_path: (content_bytes, sha256_hex)}. Survives across
        # connections (the hub process is long-lived), so only a genuine gem
        # change (or a hub restart) does the expensive work.
        self._gem_file_cache = {}

    def _streams(self):
        """The stream (interface) names this bridge relays, from the
        HostInterfaceMicroserviceModels whose bridge_name matches ours. Queried live (not
        read from static OPTIONs) so adding/removing a bridged interface does not
        change this relay's MicroserviceModel — which would make the operator
        respawn it. Sorted so an unchanged set never looks changed to
        _stream_watcher."""
        streams = []
        for _name, data in HostInterfaceMicroserviceModel.all(self.scope).items():
            if isinstance(data, str):
                data = json.loads(data)
            if data.get("bridge_name") != self.bridge_name:
                continue
            stream = data.get("stream")
            if stream and stream not in streams:
                streams.append(stream)
        return sorted(streams)

    def _build_alpns(self):
        """Full ALPN set to advertise: a stream/host/ctrl/hostctrl quad per
        relayed stream, plus the fixed control-API ALPNs."""
        alpns = []
        for s in self.streams:
            alpns.append(f"{STREAM_ALPN_PREFIX}{s}".encode())
            alpns.append(f"{HOST_ALPN_PREFIX}{s}".encode())
            alpns.append(f"{CTRL_ALPN_PREFIX}{s}".encode())
            alpns.append(f"{HOSTCTRL_ALPN_PREFIX}{s}".encode())
        alpns += [API_HOST_MICROSERVICES, API_LOG, API_AUTHORIZE, API_ENROLL, API_FILES, API_INTERFACE_STATUS]
        return alpns

    def _bridge_name(self):
        """This bridge's name (microservice OPTION BRIDGE_NAME, else the NAME
        segment of the SCOPE__TYPE__NAME microservice name)."""
        for option in self.config.get("options") or []:
            if isinstance(option, list | tuple) and len(option) >= 2 and str(option[0]).upper() == "BRIDGE_NAME":
                return option[1]
        return self.name.split("__")[-1]

    # --- Microservice entry point -------------------------------------------

    def run(self):
        try:
            import iroh  # noqa: F401
        except ImportError as error:
            self.logger.error(f"iroh package not installed ({error}); cannot bridge; idling")
            self._idle_until_shutdown()
            return

        try:
            asyncio.run(self._serve())
        except Exception as error:
            # iroh's IrohError carries its detail in .message(); str()/traceback
            # render only the class name ("IrohError"), so pull the real message
            # out explicitly — otherwise the crash log is useless for diagnosis.
            self.logger.error(f"Bridge hub crashed ({_iroh_error_detail(error)}):\n{traceback.format_exc()}")

    def _idle_until_shutdown(self):
        while not self.cancel_thread:
            time.sleep(1)

    # --- Iroh hub -----------------------------------------------------------

    async def _serve(self):
        import iroh

        model, private_key = self._ensure_keys(iroh)
        secret_key = bytes.fromhex(private_key)
        port = self._ensure_port(model)
        # Advertise a stream/<name> ALPN quad for each relayed stream (data +
        # control paths) plus the fixed control API ALPNs (always available for
        # openc3-app). _stream_watcher re-advertises this set as streams change.
        alpns = self._build_alpns()
        # Bind a fixed UDP port (published to the host from the operator
        # container). By default there is NO relay: co-located peers reach the hub
        # directly via 127.0.0.1. To allow REMOTE peers (across the internet/NAT),
        # set OPENC3_BRIDGE_RELAY to a relay URL (n0's public relay or a
        # self-hosted one); the hub then advertises that relay in its ticket.
        relay = os.environ.get("OPENC3_BRIDGE_RELAY")
        if relay:
            options = {
                "preset": iroh.preset_n0(),
                "relay_mode": iroh.RelayMode.custom_from_urls([relay]),
                "bind_addr": f"0.0.0.0:{port}",
                "alpns": alpns,
                "secret_key": secret_key,
            }
        else:
            options = {
                "preset": iroh.preset_n0_disable_relay(),
                "bind_addr": f"0.0.0.0:{port}",
                "alpns": alpns,
                "secret_key": secret_key,
            }
        endpoint = await iroh.Endpoint.bind(iroh.EndpointOptions(**options))
        # Advertise a host-reachable local address: Docker publishes
        # 127.0.0.1:<port>/udp on the host straight through to this container port,
        # so a co-located host dials 127.0.0.1:<port> directly (the bind's own
        # 172.x address keeps in-container peers working).
        local_addr = f"127.0.0.1:{port}"
        await endpoint.add_external_addr(local_addr)
        # With a relay, wait until online so the ticket carries the relay URL and
        # discovered public address that remote peers need (bounded so the hub
        # still starts if the relay is unreachable).
        if relay:
            try:
                await asyncio.wait_for(endpoint.online(), timeout=15)
            except Exception:
                self.logger.warn(
                    f"Bridge '{self.bridge_name}': not online within timeout; ticket may lack a "
                    "relay/public address (remote pairing needs one)"
                )
        # add_external_addr is eventually-consistent; make sure the local address
        # is present before minting the ticket.
        for _ in range(50):
            if local_addr in endpoint.addr().direct_addresses():
                break
            await asyncio.sleep(0.1)
        # Refresh and store this bridge's current ticket so peers can find it by
        # bridge name (the identity is stable via the persisted keypair).
        ticket = str(iroh.EndpointTicket.from_addr(endpoint.addr()))
        model.ticket = ticket
        model.create(force=True)
        self.logger.info(f"Bridge '{self.bridge_name}' hub listening on port {port}; ticket: {ticket}")

        watcher = asyncio.create_task(self._shutdown_watcher(endpoint))
        streams = asyncio.create_task(self._stream_watcher(endpoint))
        # Hold strong references to the per-connection handler tasks: asyncio
        # keeps only weak references, so an un-stored task can be garbage
        # collected mid-flight. Discard each when it finishes.
        handlers = set()
        try:
            while not self.cancel_thread:
                incoming = await endpoint.accept_next()
                if incoming is None:
                    break  # endpoint closed
                self.count += 1
                task = asyncio.create_task(self._handle(incoming))
                handlers.add(task)
                task.add_done_callback(handlers.discard)
        finally:
            watcher.cancel()
            streams.cancel()

    async def _shutdown_watcher(self, endpoint):
        """Close the endpoint on shutdown so the accept loop wakes and exits."""
        while not self.cancel_thread:
            await asyncio.sleep(0.5)
        with contextlib.suppress(Exception):
            result = endpoint.close()
            if inspect.isawaitable(result):
                await result

    def _read_config_changes(self, topic, offset, timeout_ms):
        """Block (in an executor thread) until a config change is published on the
        ConfigTopic or timeout_ms elapses, returning the message ids read. Fully
        drains the read_topics generator here since its blocking xread only runs
        while iterating. Offsets are passed in explicitly (not left to the store's
        thread-local tracking) so this is correct across executor threads."""
        ids = []
        with contextlib.suppress(Exception):
            for _topic, msg_id, _msg_hash, _redis in Topic.read_topics([topic], [offset], timeout_ms):
                ids.append(msg_id)
        return ids

    async def _stream_watcher(self, endpoint):
        """Keep the endpoint's advertised ALPNs in sync with the set of streams
        this bridge relays. Because the relay discovers streams by querying the
        HostInterfaceMicroserviceModels (not static OPTIONs), a newly-deployed or removed
        bridged interface never mutates this relay's MicroserviceModel — so the
        operator does not respawn it; instead we adapt the live ALPN set here,
        keeping the same identity/ticket.

        Wakes immediately on ConfigTopic changes (interface created/deleted, ...)
        and also re-checks every STREAM_REFRESH_INTERVAL as a fallback (covers a
        missed message or a bridge created before this watcher started)."""
        loop = asyncio.get_event_loop()
        config_topic = f"{self.scope}{ConfigTopic.PRIMARY_KEY}"
        timeout_ms = int(STREAM_REFRESH_INTERVAL * 1000)
        # Start at the current end of the topic so we only wake on NEW changes.
        try:
            offset = await loop.run_in_executor(None, Topic.get_last_offset, config_topic)
        except Exception:
            offset = "0-0"
        while not self.cancel_thread:
            # Block until a config change arrives or the fallback interval elapses.
            ids = await loop.run_in_executor(None, self._read_config_changes, config_topic, offset, timeout_ms)
            if ids:
                offset = ids[-1]
            if self.cancel_thread:
                break
            try:
                streams = self._streams()
            except Exception as error:
                self.logger.warn(f"Bridge '{self.bridge_name}': stream refresh error: {_iroh_error_detail(error)}")
                continue
            if streams == self.streams:
                continue
            added = sorted(set(streams) - set(self.streams))
            removed = sorted(set(self.streams) - set(streams))
            self.streams = streams
            with contextlib.suppress(Exception):
                endpoint.set_alpns(self._build_alpns())
            self.logger.info(f"Bridge '{self.bridge_name}': streams updated (added={added}, removed={removed})")

    async def _handle(self, incoming):
        """Accept one connection and dispatch it by negotiated ALPN."""
        try:
            accepting = await incoming.accept()
            alpn = await accepting.alpn()
            conn = await accepting.connect()
        except Exception as error:
            # Routine noise on an open UDP port: anything that isn't a real iroh
            # peer dialing our ticket fails ALPN/TLS negotiation here (port
            # scanners, health checks, stray QUIC/HTTP3 clients -> "no known
            # protocol" / WebPKI "UnknownIssuer"). A legitimate bridge peer pins
            # our node key via the ticket and never hits this. Log at debug so it
            # doesn't spam; a genuinely misconfigured peer surfaces later as an
            # authorization rejection (logged at warn) once it does negotiate.
            self.logger.debug(f"Bridge accept error (ignored): {_iroh_error_detail(error)}")
            return
        try:
            if alpn == API_ENROLL:
                # Bootstrap: gated by a one-time code, not the app identity.
                await self._serve_enroll(conn)
            elif alpn in (API_HOST_MICROSERVICES, API_LOG, API_AUTHORIZE, API_FILES, API_INTERFACE_STATUS):
                # Control APIs are restricted to the enrolled openc3-app identity.
                if not self._authorized(conn):
                    self.logger.warn(f"Rejected unauthorized control connection from {conn.remote_id()} on {alpn!r}")
                    await self._close(conn)
                    return
                if alpn == API_HOST_MICROSERVICES:
                    await self._serve_host_microservices(conn)
                elif alpn == API_AUTHORIZE:
                    await self._serve_authorize(conn)
                elif alpn == API_FILES:
                    await self._serve_files(conn)
                elif alpn == API_INTERFACE_STATUS:
                    await self._serve_interface_status(conn)
                else:
                    await self._serve_log(conn)
            elif alpn.startswith(HOST_ALPN_PREFIX.encode()):
                # Host-side data leg: must be an openc3-app-authorized identity.
                if str(conn.remote_id()) not in self._authorized_hosts:
                    self.logger.warn(f"Rejected unauthorized host data connection from {conn.remote_id()}")
                    await self._close(conn)
                    return
                await self._rendezvous(alpn[len(HOST_ALPN_PREFIX) :], conn)
            elif alpn.startswith(STREAM_ALPN_PREFIX.encode()):
                # COSMOS bridge_interface leg: verify its registered identity.
                name = alpn[len(STREAM_ALPN_PREFIX) :]
                if not self._authorized_interface(conn, name.decode("utf-8", "replace")):
                    self.logger.warn(f"Rejected unauthorized COSMOS interface connection from {conn.remote_id()}")
                    await self._close(conn)
                    return
                await self._rendezvous(name, conn)
            elif alpn.startswith(HOSTCTRL_ALPN_PREFIX.encode()):
                # Host-side control leg (status up / commands down): same identity
                # rule as the host data leg. Paired on a distinct control channel.
                if str(conn.remote_id()) not in self._authorized_hosts:
                    self.logger.warn(f"Rejected unauthorized host control connection from {conn.remote_id()}")
                    await self._close(conn)
                    return
                await self._rendezvous(CTRL_CHANNEL_PREFIX + alpn[len(HOSTCTRL_ALPN_PREFIX) :], conn, is_host=True)
            elif alpn.startswith(CTRL_ALPN_PREFIX.encode()):
                # COSMOS-side control leg: same identity rule as the COSMOS data leg.
                name = alpn[len(CTRL_ALPN_PREFIX) :]
                if not self._authorized_interface(conn, name.decode("utf-8", "replace")):
                    self.logger.warn(f"Rejected unauthorized COSMOS control connection from {conn.remote_id()}")
                    await self._close(conn)
                    return
                await self._rendezvous(CTRL_CHANNEL_PREFIX + name, conn, is_host=False)
            else:
                self.logger.warn(f"Bridge received unknown ALPN {alpn!r}")
                await self._close(conn)
        except Exception as error:
            self.logger.warn(f"Bridge handler error: {_iroh_error_detail(error)}")
            await self._close(conn)

    async def _read_request(self, recv):
        """Read a full request from a bi-stream until the peer finishes writing.
        A single `read()` can return only a partial payload (especially over a
        relay, where data arrives in smaller chunks), so loop to EOF to avoid
        truncated/undecodable JSON."""
        data = b""
        with contextlib.suppress(Exception):
            while not self.cancel_thread:
                chunk = await recv.read(PUMP_CHUNK_BYTES)
                if not chunk:
                    break
                data += bytes(chunk)
        return data

    async def _serve_enroll(self, conn):
        """Redeem a one-time manual-enrollment code (Phase 2 remote pairing).

        openc3-app opens the bi-stream and sends a JSON request ``{"code": ...}``.
        The connector's identity is taken cryptographically from the connection
        (not a claimed value). If the code matches the bridge's pending
        ``enroll_code``, that identity becomes the authorized app key and the code
        is cleared (one-time). Responds with JSON ``{"ok": bool, ...}``.
        """
        bi = await conn.accept_bi()
        send = bi.send()
        recv = bi.recv()
        request = await self._read_request(recv)
        response = {"ok": False, "error": "invalid enrollment code"}
        try:
            code = json.loads(request or b"{}").get("code")
            model = BridgeModel.get_model(self.bridge_name, scope=self.scope)
            if model and model.enroll_code and code and code == model.enroll_code:
                model.app_public_key = str(conn.remote_id())
                model.enroll_code = None  # one-time
                model.create(force=True)
                response = {"ok": True, "app_public_key": model.app_public_key}
                self.logger.info(f"Enrolled openc3-app identity {model.app_public_key} for '{self.bridge_name}'")
            else:
                self.logger.warn(f"Rejected enrollment attempt from {conn.remote_id()} (bad/absent code)")
        except Exception as error:
            response = {"ok": False, "error": _iroh_error_detail(error)}
        with contextlib.suppress(Exception):
            await send.write_all(json.dumps(response).encode())
            await send.finish()
        await self._drain_close(conn)

    def _authorized_interface(self, conn, name):
        """True if `conn`'s remote identity matches the COSMOS bridge_interface
        registered (in BridgeInterfaceModel) for `name`. Read fresh each time."""
        model = BridgeInterfaceModel.get_model(name, scope=self.scope)
        expected = model.public_key if model else None
        if not expected:
            return False
        return str(conn.remote_id()) == expected

    def _authorized(self, conn):
        """True if `conn`'s remote Iroh identity is the enrolled openc3-app key.

        The authorized key is read fresh from the BridgeModel each time so
        enrollment (which sets app_public_key out of band) takes effect without
        restarting the hub. If no app identity is enrolled yet, control access
        is denied.
        """
        model = BridgeModel.get_model(self.bridge_name, scope=self.scope)
        authorized = model.app_public_key if model else None
        if not authorized:
            return False
        return str(conn.remote_id()) == authorized

    # --- Data path (rendezvous) ---------------------------------------------

    async def _rendezvous(self, channel, conn, is_host=False):
        """Pair two connections sharing a channel and pump bytes between them.

        The hub is the server, so it opens+primes each connection's bi-stream
        (the clients accept+strip the primer). The first arrival parks; the
        second pumps bytes between the pair in both directions. For a control
        channel (``ctrl/<name>`` key), the host->COSMOS direction is tapped to
        capture the host's InterfaceStatus for api/interface_status.
        """
        bi = await conn.open_bi()
        send = bi.send()
        recv = bi.recv()
        await send.write_all(PRIME)

        # Control channels are keyed ctrl/<name>; tap the host leg's status.
        ctrl_name = None
        if channel.startswith(CTRL_CHANNEL_PREFIX):
            ctrl_name = channel[len(CTRL_CHANNEL_PREFIX) :].decode("utf-8", "replace")

        partner = self._waiting.pop(channel, None)
        if partner is not None:
            p_send, p_recv, _p_conn, p_future, _p_is_host = partner
            self.logger.info(f"Paired {channel.decode('utf-8', 'replace')}")
            if ctrl_name is not None:
                # Identify the host leg so we tap host->COSMOS (status) and pump
                # COSMOS->host (commands) plainly.
                if is_host:
                    host_recv, cosmos_send = recv, p_send
                    cosmos_recv, host_send = p_recv, send
                else:
                    host_recv, cosmos_send = p_recv, send
                    cosmos_recv, host_send = recv, p_send
                up = asyncio.create_task(self._pump_status(host_recv, cosmos_send, ctrl_name))
                down = asyncio.create_task(self._pump(cosmos_recv, host_send))
            else:
                up = asyncio.create_task(self._pump(p_recv, send))
                down = asyncio.create_task(self._pump(recv, p_send))
            try:
                await asyncio.wait({up, down}, return_when=asyncio.FIRST_COMPLETED)
            finally:
                up.cancel()
                down.cancel()
                if not p_future.done():
                    p_future.set_result(True)  # release the parked partner
                await self._close(conn)
        else:
            future = asyncio.get_event_loop().create_future()
            self._waiting[channel] = (send, recv, conn, future, is_host)
            try:
                await asyncio.wait_for(future, timeout=PAIR_TIMEOUT)
            except asyncio.TimeoutError:
                self._waiting.pop(channel, None)
                self.logger.warn(f"No partner for {channel.decode('utf-8', 'replace')} within timeout")
            finally:
                await self._close(conn)

    async def _pump(self, recv, send):
        """Copy raw bytes from one stream to another until it closes."""
        with contextlib.suppress(asyncio.CancelledError):
            while not self.cancel_thread:
                data = await recv.read(PUMP_CHUNK_BYTES)
                if not data:  # peer finished/closed
                    break
                await send.write_all(bytes(data))
            with contextlib.suppress(Exception):
                await send.finish()

    async def _pump_status(self, recv, send, name):
        """Like _pump, but for the control channel host->COSMOS direction: forward
        the bytes and tap newline-delimited status JSON into `_interface_status`."""
        buffer = b""
        with contextlib.suppress(asyncio.CancelledError):
            while not self.cancel_thread:
                data = await recv.read(PUMP_CHUNK_BYTES)
                if not data:  # peer finished/closed
                    break
                await send.write_all(bytes(data))
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
                        self._interface_status[name] = msg["status"]
            with contextlib.suppress(Exception):
                await send.finish()

    async def _serve_interface_status(self, conn):
        """Return the latest host InterfaceStatus per interface as JSON."""
        bi = await conn.accept_bi()
        send = bi.send()
        recv = bi.recv()
        with contextlib.suppress(Exception):
            await recv.read(PUMP_CHUNK_BYTES)  # consume the request
        payload = json.dumps(self._interface_status).encode()
        await send.write_all(payload)
        with contextlib.suppress(Exception):
            await send.finish()
        await self._drain_close(conn)

    # --- Control APIs -------------------------------------------------------

    async def _serve_host_microservices(self, conn):
        """Return the JSON list of host microservices for this bridge.

        openc3-app opens the bi-stream and writes a (content-ignored) request;
        we reply with the JSON payload and finish.
        """
        bi = await conn.accept_bi()
        send = bi.send()
        recv = bi.recv()
        with contextlib.suppress(Exception):
            await recv.read(PUMP_CHUNK_BYTES)  # consume the request
        payload = self._host_microservices_payload()
        await send.write_all(payload)
        with contextlib.suppress(Exception):
            await send.finish()
        await self._drain_close(conn)

    def _host_microservices_payload(self):
        """Build the JSON spawn list for this bridge, resolving secret_options
        into concrete options (the host has no COSMOS secrets access)."""
        entries = []
        for _name, data in HostInterfaceMicroserviceModel.all(self.scope).items():
            if isinstance(data, str):
                data = json.loads(data)
            if data.get("bridge_name") != self.bridge_name:
                continue
            options = [list(option) for option in (data.get("options") or [])]
            for secret_option in data.get("secret_options") or []:
                if len(secret_option) >= 2:
                    value = self.secrets.get(secret_option[1], scope=self.scope)
                    options.append([secret_option[0], value])
            entries.append(
                {
                    "name": data.get("name"),
                    "stream": data.get("stream"),
                    "config_params": data.get("config_params") or [],
                    "options": options,
                    # BRIDGE_PROTOCOLs run on the host next to the device.
                    "protocols": data.get("protocols") or [],
                    "work_dir": data.get("work_dir"),
                    "env": data.get("env") or {},
                    "container": data.get("container"),
                    "needs_dependencies": data.get("needs_dependencies", False),
                }
            )
        return json.dumps(entries).encode()

    async def _serve_authorize(self, conn):
        """Record the set of authorized host-microservice identities that may use
        the host/<name> data path. openc3-app opens the bi-stream and sends
        ``{"keys": ["<pubkey_hex>", ...]}``; the set replaces the previous one."""
        bi = await conn.accept_bi()
        send = bi.send()
        recv = bi.recv()
        request = await self._read_request(recv)
        try:
            keys = json.loads(request or b"{}").get("keys") or []
            self._authorized_hosts = {str(key) for key in keys}
        except (ValueError, TypeError) as error:
            self.logger.warn(f"Bad api/authorize request: {error}")
        with contextlib.suppress(Exception):
            await send.write_all(b'{"ok":true}')
            await send.finish()
        await self._drain_close(conn)

    async def _serve_files(self, conn):
        """Ship the scope's plugin lib/ files to openc3-app as a hash-delta.

        openc3-app opens the bi-stream and sends ``{"have": {path: sha256}}``.
        We reply with only files whose hash differs (base64 content) plus a list
        of paths to delete, so unchanged files are never resent. The host has no
        bucket/gem access, so all plugin code routes through here over Iroh.
        """
        bi = await conn.accept_bi()
        send = bi.send()
        recv = bi.recv()
        request = await self._read_request(recv)
        have = {}
        with contextlib.suppress(ValueError, TypeError):
            have = json.loads(request or b"{}").get("have") or {}
        # Reading/untarring the plugin gems and hashing+encoding their files is
        # slow and fully synchronous. Running it on the event loop would stall the
        # data-path _pump tasks for the duration, so a client that polls this API
        # (openc3-app, every operator cycle) causes periodic latency bursts in the
        # bridged stream. The plugin list is a fast Redis read done on the loop;
        # the heavy disk/CPU work runs in a thread so byte pumping keeps going.
        gems = self._plugin_gem_names()
        loop = asyncio.get_event_loop()
        payload = await loop.run_in_executor(None, self._build_files_payload, gems, have)
        with contextlib.suppress(Exception):
            await send.write_all(payload)
            await send.finish()
        await self._drain_close(conn)

    def _plugin_gem_names(self):
        """The set of plugin gem filenames installed in this scope (Redis read)."""
        plugins = Model.all(f"{self.scope}__openc3_plugins")
        return {str(name).split("__")[0] for name in plugins}

    def _build_files_payload(self, gems, have):
        """Build the api/files hash-delta JSON (changed/new files + deletions) for
        `gems` vs the client's `have` manifest. Pure disk/CPU work (no Redis) so it
        runs in a thread off the event loop — see `_serve_files`."""
        current = self._collect_plugin_files(gems)
        files = []
        for path, (content, digest) in current.items():
            if have.get(path) != digest:
                files.append({"path": path, "sha256": digest, "content": base64.b64encode(content).decode()})
        deletions = [path for path in have if path not in current]
        return json.dumps({"files": files, "deletions": deletions}).encode()

    def _collect_plugin_files(self, gems):
        """Return {relative_path: (content_bytes, sha256_hex)} of the files host
        interfaces may need from the given plugin `gems`: everything under
        ``lib/`` plus any ``requirements.txt`` / ``pyproject.toml`` (used to
        provision the host venv). Read from the .gem files cached on the /gems
        volume.

        A gem is only opened/unzipped/hashed when it is new or its file has
        changed (by mtime + size); otherwise the cached result is reused, so
        repeated syncs of unchanged plugins do no work. Paths are prefixed by the
        gem's stem (``<gem>/lib/...``) so files from different plugins don't
        collide and openc3-app can put each lib dir on PYTHONPATH / install each
        gem's Python requirements.
        """
        files = {}
        seen_paths = set()
        for gem in gems:
            gem_path = self._find_gem(gem)
            if not gem_path:
                self.logger.warn(f"Plugin gem {gem} not found under {GEM_HOME}; skipping file sync")
                continue
            seen_paths.add(gem_path)
            try:
                stat = os.stat(gem_path)
                stamp = (stat.st_mtime_ns, stat.st_size)
            except OSError as error:
                self.logger.warn(f"Failed to stat {gem}: {type(error).__name__}: {error}")
                continue
            cached = self._gem_file_cache.get(gem_path)
            if cached is not None and cached[0] == stamp[0] and cached[1] == stamp[1]:
                files.update(cached[2])  # unchanged: reuse (no unzip, no hash)
                continue
            gem_files = self._extract_gem_files(gem, gem_path)
            if gem_files is None:
                continue  # read failed; leave any prior cache entry in place
            self._gem_file_cache[gem_path] = (stamp[0], stamp[1], gem_files)
            files.update(gem_files)
        # Drop cache entries for gems no longer installed so it can't grow forever.
        for stale in [path for path in self._gem_file_cache if path not in seen_paths]:
            del self._gem_file_cache[stale]
        return files

    def _extract_gem_files(self, gem, gem_path):
        """Unzip a single plugin gem and hash its host-relevant files. Returns
        {relative_path: (content_bytes, sha256_hex)}, or None if the gem couldn't
        be read (so the caller keeps any previously cached copy)."""
        stem = gem[:-4] if gem.endswith(".gem") else gem
        gem_files = {}
        try:
            # A .gem is an (uncompressed) tar containing data.tar.gz.
            with tarfile.open(gem_path, "r") as outer:
                data_member = outer.extractfile("data.tar.gz")
                if data_member is None:
                    return gem_files
                with tarfile.open(fileobj=io.BytesIO(data_member.read()), mode="r:gz") as data:
                    for member in data.getmembers():
                        if not member.isfile():
                            continue
                        if member.name.startswith("lib/") or member.name in ("requirements.txt", "pyproject.toml"):
                            extracted = data.extractfile(member)
                            if extracted is not None:
                                content = extracted.read()
                                gem_files[f"{stem}/{member.name}"] = (content, hashlib.sha256(content).hexdigest())
        except Exception as error:
            self.logger.warn(f"Failed reading files from {gem}: {type(error).__name__}: {error}")
            return None
        return gem_files

    def _find_gem(self, gem):
        for sub in ("cosmoscache", "cache"):
            path = os.path.join(GEM_HOME, sub, gem)
            if os.path.exists(path):
                return path
        return None

    async def _serve_log(self, conn):
        """Ingest host microservice log lines from openc3-app and re-emit them
        through the real COSMOS Logger. openc3-app opens the bi-stream and
        streams newline-delimited lines."""
        bi = await conn.accept_bi()
        recv = bi.recv()
        buffer = b""
        with contextlib.suppress(Exception):
            while not self.cancel_thread:
                data = await recv.read(PUMP_CHUNK_BYTES)
                if not data:
                    break
                buffer += bytes(data)
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    self._emit_host_log(line.decode("utf-8", "replace"))
        await self._close(conn)

    def _emit_host_log(self, line):
        """Re-emit one host stdout line into COSMOS.

        The host runs the real COSMOS Logger (no_store), which prints a JSON log
        record per line; we write that record straight to the scope's log topic
        so it appears in COSMOS with its original level/microservice_name. Any
        non-JSON stdout line is logged as INFO.
        """
        line = line.strip()
        if not line:
            return
        record = None
        with contextlib.suppress(ValueError, TypeError):
            record = json.loads(line)
        if isinstance(record, dict) and "level" in record:
            EphemeralStoreQueued.write_topic(f"{self.scope}__openc3_log_messages", record)
        else:
            self.logger.info(line, scope=self.scope)

    # --- Iroh identity ------------------------------------------------------

    async def _close(self, conn):
        with contextlib.suppress(Exception):
            result = conn.close()
            if inspect.isawaitable(result):
                await result

    async def _drain_close(self, conn):
        """Close a request/response connection only after the client has finished
        reading the response and closed its side. Closing immediately after
        ``send.finish()`` can send CONNECTION_CLOSE before the response is
        delivered, which the client sees as "connection lost"."""
        with contextlib.suppress(Exception):
            await asyncio.wait_for(conn.closed(), timeout=CLOSE_DRAIN_TIMEOUT)
        await self._close(conn)

    def _secret_name(self):
        """Secrets-store key holding this bridge's private key."""
        return f"BRIDGE_{self.bridge_name}_PRIVATE_KEY"

    def _ensure_keys(self, iroh):
        """Ensure this bridge has an Iroh keypair: the public key/ticket live in
        the BridgeModel, the private key in the secrets store. Generates and
        persists a new keypair if either piece is missing. Returns
        ``(model, private_key_hex)``."""
        model = BridgeModel.get_model(self.bridge_name, scope=self.scope)
        private_key = self.secrets.get(self._secret_name(), scope=self.scope)

        if model is None or not model.public_key or not private_key:
            secret = iroh.SecretKey.generate()
            private_key = bytes(secret.to_bytes()).hex()
            public_key = bytes(secret.public().to_bytes()).hex()
            # Private key -> secrets store; public key -> model.
            self.secrets.set(self._secret_name(), private_key, scope=self.scope)
            if model is None:
                model = BridgeModel(name=self.bridge_name, scope=self.scope, public_key=public_key)
            else:
                model.public_key = public_key
            model.create(force=True)
            self.logger.info(f"Generated Iroh keypair for bridge '{self.bridge_name}'")
        return model, private_key

    def _ensure_port(self, model):
        """Return this bridge's fixed UDP port, assigning one from the published
        range if it doesn't have one yet. The port is persisted on the model and
        reused across restarts so the host can always reach the hub at
        127.0.0.1:<port>. Ports must be unique across every bridge sharing this
        operator container, so the lowest port not claimed by any other bridge
        (in any scope) is chosen and persisted immediately."""
        if getattr(model, "port", None):
            return int(model.port)

        used = set()
        for scope in ScopeModel.names():
            for name in BridgeModel.names(scope):
                if scope == self.scope and name == self.bridge_name:
                    continue
                other = BridgeModel.get_model(name, scope=scope)
                if other and getattr(other, "port", None):
                    used.add(int(other.port))

        for candidate in range(BRIDGE_PORT_BASE, BRIDGE_PORT_BASE + BRIDGE_PORT_COUNT):
            if candidate not in used:
                model.port = candidate
                model.create(force=True)
                return candidate

        raise RuntimeError(
            f"No free bridge port in {BRIDGE_PORT_BASE}-{BRIDGE_PORT_BASE + BRIDGE_PORT_COUNT - 1}; "
            "increase OPENC3_BRIDGE_PORT_COUNT and the published range in compose.yaml"
        )


if __name__ == "__main__":
    BridgeMicroservice.class_run()
