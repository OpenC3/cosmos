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
    bridge should run (from HostMicroserviceModel); openc3-app polls it.
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
import io
import json
import os
import tarfile
import time
import traceback

from openc3.microservices.microservice import Microservice
from openc3.models.bridge_interface_model import BridgeInterfaceModel
from openc3.models.bridge_model import BridgeModel
from openc3.models.host_microservice_model import HostMicroserviceModel
from openc3.models.model import Model
from openc3.utilities.store_queued import EphemeralStoreQueued


# Data path routing is by ALPN. The COSMOS bridge_interface (trusted, in-COSMOS)
# dials stream/<name>; the host-side interface dials host/<name>. The hub pairs
# the two legs on the same <name> and enforces identity only on the host leg.
STREAM_ALPN_PREFIX = "stream/"
HOST_ALPN_PREFIX = "host/"

# Control API ALPNs dialed by openc3-app.
API_HOST_MICROSERVICES = b"api/host_microservices"
API_LOG = b"api/log"
# Publishes the set of authorized host-microservice identities (openc3-app-minted
# public keys) that may use the host/<name> data path.
API_AUTHORIZE = b"api/authorize"
# Serves the scope's plugin lib/ files (hash-delta) so host interfaces can use
# plugin code. The host has no bucket/gem access, so the hub reads and ships it.
API_FILES = b"api/files"

# The /gems volume (present in all deployments) holds the plugin gem cache.
GEM_HOME = os.environ.get("GEM_HOME") or "/gems"
# Bootstrap ALPN for manual enrollment (validated by a one-time code, not by
# the authorized app identity — this is how that identity gets established).
API_ENROLL = b"api/enroll"

# One-byte stream primer. QUIC only surfaces a bi-stream to the peer's accept_bi
# once the opener writes, so on the data path the hub (server) opens+primes and
# the clients accept+strip this byte. All subsequent bytes are raw device data.
PRIME = b"\x00"

# Size of each raw read when pumping bytes.
PUMP_CHUNK_BYTES = 65536

# How long a lone data-path peer waits for its partner before giving up.
PAIR_TIMEOUT = 300


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
        # Interface/stream names this bridge relays (microservice OPTION STREAM
        # <name>, repeatable). Their stream/<name> ALPNs are advertised so the
        # QUIC handshake accepts data-path connections for them.
        self.streams = self._streams()
        # channel (name bytes) -> (send, recv, connection, future) for the first
        # arrival on a data-path channel, awaiting its partner.
        self._waiting = {}
        # Authorized host-microservice identities (Iroh EndpointId hex strings)
        # allowed on the host/<name> data path. Published by openc3-app over
        # api/authorize each cycle; held in memory only (matches the ephemeral,
        # never-persisted host keys).
        self._authorized_hosts = set()

    def _streams(self):
        streams = []
        for option in self.config.get("options") or []:
            if isinstance(option, list | tuple) and len(option) >= 2 and str(option[0]).upper() == "STREAM":
                streams.append(option[1])
        return streams

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
        except Exception:
            self.logger.error(f"Bridge hub crashed:\n{traceback.format_exc()}")

    def _idle_until_shutdown(self):
        while not self.cancel_thread:
            time.sleep(1)

    # --- Iroh hub -----------------------------------------------------------

    async def _serve(self):
        import iroh

        model, private_key = self._ensure_keys(iroh)
        secret_key = bytes.fromhex(private_key)
        # Advertise a stream/<name> ALPN for each configured stream (the data
        # path) plus the control API ALPNs (always available for openc3-app).
        alpns = [f"{STREAM_ALPN_PREFIX}{s}".encode() for s in self.streams]
        alpns += [f"{HOST_ALPN_PREFIX}{s}".encode() for s in self.streams]
        alpns += [API_HOST_MICROSERVICES, API_LOG, API_AUTHORIZE, API_ENROLL, API_FILES]
        endpoint = await iroh.Endpoint.bind(
            iroh.EndpointOptions(preset=iroh.preset_n0(), alpns=alpns, secret_key=secret_key)
        )
        # Refresh and store this bridge's current ticket so peers can find it by
        # bridge name (the identity is stable via the persisted keypair).
        ticket = str(iroh.EndpointTicket.from_addr(endpoint.addr()))
        model.ticket = ticket
        model.create(force=True)
        self.logger.info(f"Bridge '{self.bridge_name}' hub listening; ticket: {ticket}")

        watcher = asyncio.create_task(self._shutdown_watcher(endpoint))
        try:
            while not self.cancel_thread:
                incoming = await endpoint.accept_next()
                if incoming is None:
                    break  # endpoint closed
                self.count += 1
                asyncio.create_task(self._handle(incoming))
        finally:
            watcher.cancel()

    async def _shutdown_watcher(self, endpoint):
        """Close the endpoint on shutdown so the accept loop wakes and exits."""
        while not self.cancel_thread:
            await asyncio.sleep(0.5)
        with contextlib.suppress(Exception):
            result = endpoint.close()
            if asyncio.iscoroutine(result):
                await result

    async def _handle(self, incoming):
        """Accept one connection and dispatch it by negotiated ALPN."""
        try:
            accepting = await incoming.accept()
            alpn = await accepting.alpn()
            conn = await accepting.connect()
        except Exception as error:
            self.logger.warn(f"Bridge accept error: {type(error).__name__}: {error}")
            return
        try:
            if alpn == API_ENROLL:
                # Bootstrap: gated by a one-time code, not the app identity.
                await self._serve_enroll(conn)
            elif alpn in (API_HOST_MICROSERVICES, API_LOG, API_AUTHORIZE, API_FILES):
                # Control APIs are restricted to the enrolled openc3-app identity.
                if not self._authorized(conn):
                    self.logger.warn(
                        f"Rejected unauthorized control connection from {conn.remote_id()} on {alpn!r}"
                    )
                    await self._close(conn)
                    return
                if alpn == API_HOST_MICROSERVICES:
                    await self._serve_host_microservices(conn)
                elif alpn == API_AUTHORIZE:
                    await self._serve_authorize(conn)
                elif alpn == API_FILES:
                    await self._serve_files(conn)
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
                    self.logger.warn(
                        f"Rejected unauthorized COSMOS interface connection from {conn.remote_id()}"
                    )
                    await self._close(conn)
                    return
                await self._rendezvous(name, conn)
            else:
                self.logger.warn(f"Bridge received unknown ALPN {alpn!r}")
                await self._close(conn)
        except Exception as error:
            self.logger.warn(f"Bridge handler error: {type(error).__name__}: {error}")
            await self._close(conn)

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
        request = b""
        with contextlib.suppress(Exception):
            request = bytes(await recv.read(PUMP_CHUNK_BYTES))
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
            response = {"ok": False, "error": f"{type(error).__name__}: {error}"}
        with contextlib.suppress(Exception):
            await send.write_all(json.dumps(response).encode())
            await send.finish()
        await self._close(conn)

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

    async def _rendezvous(self, channel, conn):
        """Pair two connections sharing a stream/<name> ALPN and pump bytes.

        The hub is the server, so it opens+primes each connection's bi-stream
        (the clients accept+strip the primer). The first arrival parks; the
        second pumps raw bytes between the pair in both directions.
        """
        bi = await conn.open_bi()
        send = bi.send()
        recv = bi.recv()
        await send.write_all(PRIME)

        partner = self._waiting.pop(channel, None)
        if partner is not None:
            p_send, p_recv, _p_conn, p_future = partner
            self.logger.info(f"Paired {channel.decode('utf-8', 'replace')}")
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
            self._waiting[channel] = (send, recv, conn, future)
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
        await self._close(conn)

    def _host_microservices_payload(self):
        """Build the JSON spawn list for this bridge, resolving secret_options
        into concrete options (the host has no COSMOS secrets access)."""
        entries = []
        for _name, data in HostMicroserviceModel.all(self.scope).items():
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
        request = b""
        with contextlib.suppress(Exception):
            request = bytes(await recv.read(PUMP_CHUNK_BYTES))
        try:
            keys = json.loads(request or b"{}").get("keys") or []
            self._authorized_hosts = {str(key) for key in keys}
        except (ValueError, TypeError) as error:
            self.logger.warn(f"Bad api/authorize request: {error}")
        with contextlib.suppress(Exception):
            await send.write_all(b'{"ok":true}')
            await send.finish()
        await self._close(conn)

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
        request = b""
        with contextlib.suppress(Exception):
            while not self.cancel_thread:
                chunk = await recv.read(PUMP_CHUNK_BYTES)
                if not chunk:
                    break
                request += bytes(chunk)
        have = {}
        with contextlib.suppress(ValueError, TypeError):
            have = json.loads(request or b"{}").get("have") or {}
        current = self._collect_plugin_files()
        files = []
        for path, content in current.items():
            digest = hashlib.sha256(content).hexdigest()
            if have.get(path) != digest:
                files.append({"path": path, "sha256": digest, "content": base64.b64encode(content).decode()})
        deletions = [path for path in have if path not in current]
        payload = json.dumps({"files": files, "deletions": deletions}).encode()
        with contextlib.suppress(Exception):
            await send.write_all(payload)
            await send.finish()
        await self._close(conn)

    def _collect_plugin_files(self):
        """Return {relative_path: bytes} of the files host interfaces may need
        from this scope's plugin gems: everything under ``lib/`` plus any
        ``requirements.txt`` / ``pyproject.toml`` (used to provision the host
        venv). Read from the .gem files cached on the /gems volume.

        Paths are prefixed by the gem's stem (``<gem>/lib/...``) so files from
        different plugins don't collide and openc3-app can put each lib dir on
        PYTHONPATH / install each gem's Python requirements.
        """
        files = {}
        plugins = Model.all(f"{self.scope}__openc3_plugins")
        gems = {str(name).split("__")[0] for name in plugins}
        for gem in gems:
            gem_path = self._find_gem(gem)
            if not gem_path:
                self.logger.warn(f"Plugin gem {gem} not found under {GEM_HOME}; skipping file sync")
                continue
            stem = gem[:-4] if gem.endswith(".gem") else gem
            try:
                # A .gem is an (uncompressed) tar containing data.tar.gz.
                with tarfile.open(gem_path, "r") as outer:
                    data_member = outer.extractfile("data.tar.gz")
                    if data_member is None:
                        continue
                    with tarfile.open(fileobj=io.BytesIO(data_member.read()), mode="r:gz") as data:
                        for member in data.getmembers():
                            if not member.isfile():
                                continue
                            if member.name.startswith("lib/") or member.name in ("requirements.txt", "pyproject.toml"):
                                extracted = data.extractfile(member)
                                if extracted is not None:
                                    files[f"{stem}/{member.name}"] = extracted.read()
            except Exception as error:
                self.logger.warn(f"Failed reading files from {gem}: {type(error).__name__}: {error}")
        return files

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
            if asyncio.iscoroutine(result):
                await result

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


if __name__ == "__main__":
    BridgeMicroservice.class_run()
