# COSMOS Bridge Architecture

How COSMOS interfaces that must run on a **host machine** (to reach hardware
such as serial ports, USB HID devices, or local TCP servers not visible inside
Docker) are driven from a COSMOS deployment. The bridge tunnels **raw device
bytes** over [Iroh](https://www.iroh.computer/) (QUIC-based P2P) between the
container world and the host, with a separate control plane for spawning host
processes, authorizing identities, forwarding logs, and shipping plugin code.

---

## 1. The four components

```
   ┌─────────────────────── COSMOS (Docker) ───────────────────────┐        ┌──────────── Host machine ────────────┐
   │                                                                │        │                                       │
   │   bridge_interface ──stream/<name>──┐                          │        │   openc3-app (Rust launcher)          │
   │   (a normal COSMOS Interface)       │                          │        │     • control-plane client of the hub │
   │                                     ▼                          │        │     • spawns + supervises host procs  │
   │                          bridge_microservice  ◀───api/*────────┼────────┼──▶  │                                  │
   │                          (the Iroh "hub")                      │        │     └─ host_interface_microservice    │
   │                                     ▲                          │        │          (Python, one per interface)  │
   │                                     └──host/<name>─────────────┼────────┼──────┘         │                       │
   │                                                                │        │                ▼                      │
   └────────────────────────────────────────────────────────────────┘      │          real device (serial/USB/...) │
                                                                            └───────────────────────────────────────┘
```

| Component | Where | Language | Role |
|-----------|-------|----------|------|
| **`bridge_interface`** | COSMOS container | Ruby / Python | A regular COSMOS `Interface`. The COSMOS end of the byte pipe. |
| **`bridge_microservice`** | COSMOS container | Python | The **single Iroh server** ("hub"). Rendezvous for the data path + all control APIs. |
| **`openc3-app`** | Host | Rust | Native launcher/manager. Control-plane **client** of the hub; spawns and supervises host microservices. |
| **`host_interface_microservice`** | Host | Python | One per bridged interface. Opens the real device and tunnels raw bytes to the hub. |

Key design decision: **openc3-app is not in the data path.** It only runs the
control plane (spawn list, authorization, logs, file sync). The actual device
bytes flow `host_interface_microservice → bridge_microservice → bridge_interface`
directly over Iroh, paired inside the hub.

---

## 2. Iroh addressing: identities, tickets, and ALPNs

Everything is built on three Iroh primitives:

- **Identity** — an Ed25519 keypair. The public key is the `EndpointId`
  (a.k.a. `remote_id()`), used for authorization. Iroh authenticates the QUIC
  peer cryptographically, so a claimed identity cannot be spoofed.
- **Ticket** (`EndpointTicket`) — a serialized dialable address for an endpoint
  (its `EndpointId` + reachability hints). The hub publishes its ticket; clients
  dial it.
- **ALPN** — the QUIC application protocol string, used here as a **router**.
  The hub advertises a set of ALPNs and dispatches each incoming connection by
  the one negotiated.

### ALPNs served by the hub

| ALPN | Dialed by | Purpose |
|------|-----------|---------|
| `stream/<name>` | COSMOS `bridge_interface` | Data path — COSMOS leg |
| `host/<name>` | host `host_interface_microservice` | Data path — host leg |
| `api/host_microservices` | openc3-app | Poll the list of host processes to spawn |
| `api/authorize` | openc3-app | Publish the set of authorized host identities |
| `api/files` | openc3-app | Hash-delta sync of the scope's plugin `lib/` files |
| `api/log` | openc3-app | Forward host stdout up into COSMOS logging |
| `api/enroll` | openc3-app | Redeem a one-time manual-enrollment code (remote pairing) |

The data path deliberately uses **two different ALPN prefixes** for the same
`<name>`: `stream/<name>` (the trusted in-COSMOS leg) and `host/<name>` (the
host leg). The hub pairs the two legs by `<name>` but enforces identity
separately on each (see §5).

### The one-byte primer (`PRIME`)

QUIC only surfaces a bi-directional stream to the peer's `accept_bi()` once the
*opener* writes something. On the data path the hub is the server: it
`open_bi()`s and writes a single `\x00` primer byte; both clients `accept_bi()`
and strip that byte. Everything after it is raw device data.

### Connectivity: local vs. remote (the relay)

How a peer actually reaches the hub depends on what addresses the ticket carries:

- **Local (default).** The hub binds a fixed UDP port
  (`OPENC3_BRIDGE_PORT_BASE`, default 7799, one per bridge) that the operator
  container publishes on the host's loopback (see `compose.yaml`), and advertises
  `127.0.0.1:<port>` in its ticket (plus its `172.x` container address for
  in-COSMOS peers). A **co-located** openc3-app dials `127.0.0.1:<port>` directly.
  No relay, no exposed ports, works offline.
- **Remote (opt-in).** A `127.0.0.1`/`172.x` ticket is useless to an openc3-app
  on another machine. To pair across the internet/NAT, set **`OPENC3_BRIDGE_RELAY`**
  to a relay URL. The hub then enables that relay, waits to come online, and
  advertises the relay URL (and its discovered public address) in the ticket, so
  a remote peer reaches it via the relay — **no inbound ports on the COSMOS host
  required** (both sides connect *outbound* to the relay).

`OPENC3_BRIDGE_RELAY` must be set on **both** ends and match:

- COSMOS side (the hub + any host interfaces): set it in the environment of the
  operator container, e.g. uncomment the line in `.env`. This affects
  `bridge_microservice` and `host_interface_microservice`.
- openc3-app side (the host running the launcher): set it in openc3-app's own
  environment before launching.

The value is a relay URL — an [n0 public relay][n0-relays] (e.g.
`https://use1-1.relay.n0.iroh.link.`, or a nearer region) or a **self-hosted**
Iroh relay. A relay co-located on the COSMOS host still needs its own inbound
ports open (TCP 443 + UDP 3478); only a relay that lives elsewhere (n0's, or a
separate host) keeps the COSMOS host free of inbound ports. When set, the relay
is used for reachability/NAT hole-punching but co-located peers still connect
directly over `127.0.0.1`, so local pairing stays direct and offline-capable.

[n0-relays]: https://www.iroh.computer/docs/concepts/relay

---

## 3. Persistent state (COSMOS models & secrets)

Stored in Redis/Valkey via COSMOS models, scoped per-scope:

- **`BridgeModel`** (`name`, `public_key`, `ticket`, `app_public_key`,
  `enroll_code`) — one per named bridge. Holds the hub's stable **public** key,
  its **current ticket** (refreshed each hub start), the enrolled **openc3-app
  public key** authorized for control APIs, and a pending one-time
  **enrollment code** for manual pairing.
- **`BridgeInterfaceModel`** (`name`, `public_key`) — the public key of each
  COSMOS-side `bridge_interface`, so the hub can authorize the `stream/<name>`
  leg.
- **`HostMicroserviceModel`** — the declarative spawn list: `name`, `bridge_name`,
  `stream`, `config_params`, `options`, `secret_options`, `env`, `container`,
  `needs_dependencies`, etc. Created from plugin definitions.
- **Secrets store** — the bridge's **private** key, under
  `BRIDGE_<name>_PRIVATE_KEY`. Never leaves COSMOS.

The hub keeps a **stable identity across restarts**: private key in the secrets
store, public key + ticket in the `BridgeModel`. On each start it re-binds,
regenerates the ticket (address hints change), and rewrites `model.ticket`.

---

## 4. Enrollment: how openc3-app gets trusted

openc3-app authenticates to the hub with its **own persistent Iroh identity**
(`<root>/bridge/identity.key`, 0600). Only its public key ever leaves the host.
Enrollment yields the hub ticket, persisted in `<root>/bridge/current.json`.
Two paths:

### Auto-enroll (co-located COSMOS, the default)

The trust anchor is **local Docker access**. openc3-app runs the CLI inside the
cmd-tlm-api container:

```
docker compose run --rm --no-deps openc3-cosmos-cmd-tlm-api \
    ruby /openc3/bin/openc3cli bridgeenroll <BRIDGE_NAME> <APP_PUBLIC_KEY>
```

`bridgeenroll` sets `BridgeModel.app_public_key = <APP_PUBLIC_KEY>` and prints
**only the ticket** on stdout. Being able to run a command in the container is
itself proof of authorization, so this is zero-touch and secure. Bridge name
defaults to `DEFAULT` (every scope has a `DEFAULT` bridge); `OPENC3_BRIDGE_NAME`
overrides it.

### Manual enroll (remote COSMOS)

The COSMOS Admin → Bridges page (or `bridgetoken` CLI) generates a base64url
token `{bridge, ticket, code}`. The user pastes it into openc3-app, which
redeems the one-time `code` over the `api/enroll` ALPN using its own identity.
On success the hub records that identity as `app_public_key` and clears the code
(one-time). See `enroll.rs::enroll_with_token` and `bridge.rs::enroll`.

Remote enrollment only works if the token's ticket is reachable from the
enrolling host — i.e. the bridge must be running with `OPENC3_BRIDGE_RELAY` set
(and the same relay set for openc3-app), otherwise the ticket only carries
`127.0.0.1`/`172.x` addresses and the redeem times out. See
[§2 Connectivity](#connectivity-local-vs-remote-the-relay). Generate the token
*after* enabling the relay so it embeds the relay URL.

`resolve_ticket` precedence: `OPENC3_BRIDGE_TICKET` env override → existing
`current.json` → auto-enroll.

---

## 5. Authorization model

Three independent authorization checks, all read **fresh** on each connection so
changes take effect without restarting the hub:

1. **Control APIs (`api/*`, except `api/enroll`)** — the connection's Iroh
   `remote_id()` must equal `BridgeModel.app_public_key`. Only the enrolled
   openc3-app may poll the spawn list, authorize hosts, sync files, or forward
   logs. (`bridge_microservice._authorized`)
2. **COSMOS data leg (`stream/<name>`)** — `remote_id()` must equal
   `BridgeInterfaceModel(name).public_key`. Each `bridge_interface` registers
   its per-process public key at connect time.
   (`bridge_microservice._authorized_interface`)
3. **Host data leg (`host/<name>`)** — `remote_id()` must be in the in-memory
   `_authorized_hosts` set, which openc3-app publishes each cycle via
   `api/authorize`.

### Ephemeral host identities

openc3-app **mints a fresh Iroh keypair per host microservice**
(`generate_host_key`). The **secret** is handed to the child via
`OPENC3_BRIDGE_PRIVATE_KEY` and **never persisted**; the **public** key is sent
to the hub via `api/authorize` before the child connects. So only processes
openc3-app actually spawned can use the data path, and nothing on the host holds
a long-lived data-path secret.

---

## 6. The data path (rendezvous)

1. COSMOS `bridge_interface.connect()` looks up `BridgeModel.ticket` by
   `bridge_name`, binds its identity, registers its public key, dials
   `stream/<name>`, `accept_bi()`, strips the primer, and pumps bytes on a
   background asyncio thread ↔ a thread-safe queue that `read_interface` /
   `write_interface` drain.
2. `host_interface_microservice` builds the **real** interface
   (`config_params`/`options` forwarded from COSMOS), opens the device, binds
   the openc3-app-provided identity, dials `host/<name>`, `accept_bi()`, strips
   the primer, and pumps device bytes ↔ Iroh.
3. The hub's `_rendezvous` pairs the two connections by `<name>`: the first
   arrival parks (up to `PAIR_TIMEOUT = 300s`); the second wires
   `_pump(a.recv → b.send)` both directions until either side closes.

Because the stream carries raw bytes with **no framing**, normal COSMOS
PROTOCOLs (BURST, LENGTH, TERMINATED, …) layer on top in the `bridge_interface`
config exactly as for any byte-stream interface. Protocols and target
definitions stay entirely on the COSMOS side; the host only moves bytes.

---

## 7. openc3-app: control-plane client & supervisor

openc3-app is a single cross-platform binary (Iced GUI + headless CLI). Its
`MicroserviceOperator` runs a supervision loop that, each cycle:

1. **`maybe_connect()`** — establishes/re-establishes the bridge connection.
   Auto-enroll is gated on real COSMOS **container uptime** (via
   `ContainerStatus::uptime()`): it waits `BRIDGE_WARMUP = 30s` after the
   containers come up, then retries up to `BRIDGE_MAX_ATTEMPTS = 3`, re-armed on
   each COSMOS restart, so it never cycles forever.
2. **`fetch()`** — `api/host_microservices` → the desired `HostSpec` list for
   this bridge, resolving `secret_options` into concrete option values (the host
   has no secrets access).
3. **File sync** — `hostfiles::sync` sends the local `path→sha256` manifest to
   `api/files`; the hub returns only changed files (+ deletions). Files land
   under `<root>/host_files/<gem>/…`. The scan reports each gem's `lib/` dir
   (→ `PYTHONPATH`) and any `requirements.txt` / `pyproject.toml` (→ host venv
   pip inputs), plus a `pip_fingerprint`.
4. **Identity minting + `api/authorize`** — mint/reuse a per-service key, inject
   the secret into the child's env, publish the public-key set to the hub.
5. **Diff & supervise** — diff desired vs running; start new, restart changed,
   stop removed. Each Python microservice gets a **per-service venv**
   (`ensure_venv`, prefers `uv`), rebuilt when `pip_fingerprint` changes.

The GUI shows a **bridge status** line ("Connected to COSMOS" / "Not paired…" /
"COSMOS unreachable…") and a collapsible **Container Status** section.

### Log forwarding

Each host process runs the real COSMOS `Logger` with `no_store=True`, printing a
JSON log record per line to **stdout**. openc3-app captures stdout and streams
it to the hub over `api/log`; `bridge_microservice._emit_host_log` writes each
JSON record straight to the scope's `openc3_log_messages` topic, so host logs
appear in COSMOS with their original level/microservice name.

---

## 8. host_interface_microservice

Launched by openc3-app as `python -u -m
openc3.microservices.host_interface_microservice` inside the per-service venv,
with configuration passed via environment:

| Env var | Meaning |
|---------|---------|
| `OPENC3_BRIDGE_TICKET` | Hub ticket to dial |
| `OPENC3_BRIDGE_CHANNEL` | Stream/interface `<name>` (→ `host/<name>` ALPN) |
| `OPENC3_HOST_INTERFACE` | JSON `{config_params, options}` for the real interface |
| `OPENC3_BRIDGE_PRIVATE_KEY` | Ephemeral, openc3-app-minted identity (never persisted) |
| `OPENC3_MICROSERVICE_NAME` | Name used for logging |
| `PYTHONPATH` | Synced plugin `lib/` dirs |

`build_interface()` resolves the real interface class from
`config_params[0]` (a filename → module) via `get_class_from_module`, which
imports through `sys.path`. Because inherited `PYTHONPATH` isn't dependable for
a GUI-launched process, the microservice calls **`add_lib_dirs_to_path()`**
first, folding every `PYTHONPATH` entry into `sys.path` explicitly so imports of
custom interface/protocol code resolve deterministically.

The service loop reconnects every `RECONNECT_DELAY = 5s` on failure, running two
pumps: device→bridge (`read_interface` → `send`) and bridge→device (`recv` →
`write_interface`).

> **Note:** `config_params[0]` must match the actual synced filename. A name
> mismatch (e.g. a typo in the plugin's `INTERFACE` line) surfaces as
> `ModuleNotFoundError` even when the search path is correct — the search path
> makes the file *findable*, it can't correct the requested name.

---

## 9. Robustness details

- **QUIC close race (`_drain_close`)** — closing a request/response connection
  right after `send.finish()` can send `CONNECTION_CLOSE` ahead of the in-flight
  response, which the client sees as "connection lost" (masked on loopback,
  fatal over real networks). The hub's control-API handlers await
  `conn.closed()` (up to `CLOSE_DRAIN_TIMEOUT = 10s`) before closing.
- **Transient poll failures** — if `fetch()` fails, the previous spawn set is
  kept so running host processes aren't torn down.
- **Graceful hub shutdown** — a watcher closes the endpoint on `cancel_thread`
  so the accept loop wakes and exits.
- **Plugin code delivery** — the host has no bucket or gem access; all plugin
  `lib/`, `requirements.txt`, and `pyproject.toml` files are read by the hub
  from the cached `.gem` files on the `/gems` volume and shipped over
  `api/files` (hash-delta, so unchanged files are never re-sent).

---

## 10. End-to-end sequence (first launch)

```
openc3-app start
  └─ load/create control identity  (<root>/bridge/identity.key)
  └─ auto-enroll: docker compose run … bridgeenroll DEFAULT <app_pubkey>
        └─ COSMOS: BridgeModel.app_public_key = <app_pubkey>; prints ticket
  └─ persist ticket -> current.json; BridgeClient.connect(ticket)
  ── operator loop ──
     ├─ api/host_microservices  -> [HostSpec…]
     ├─ api/files               -> sync plugin lib/ to <root>/host_files
     ├─ mint per-service key; api/authorize [pubkeys…]
     └─ spawn host_interface_microservice (venv, PYTHONPATH, env)
           └─ build real interface, open device
           └─ dial host/<name>  ─┐
                                 ├─ hub rendezvous pairs the two legs
   COSMOS bridge_interface dial ─┘   and pumps raw bytes both ways
```

---

## 11. Source map

| Concern | File |
|---------|------|
| Hub (server, all ALPNs, rendezvous, control APIs) | `openc3/python/openc3/microservices/bridge_microservice.py` |
| COSMOS data leg (Python) | `openc3/python/openc3/interfaces/bridge_interface.py` |
| COSMOS data leg (Ruby) | `openc3/lib/openc3/bridge/bridge_interface_thread.rb` |
| Host runner | `openc3/python/openc3/microservices/host_interface_microservice.py` |
| Persistent models | `openc3/python/openc3/models/{bridge_model,bridge_interface_model,host_microservice_model}.py` |
| Enroll CLI (`bridgeenroll`) | `openc3/bin/openc3cli` |
| App: enrollment & identity | `openc3-app/src/enroll.rs` |
| App: hub client (ALPNs, APIs) | `openc3-app/src/bridge.rs` |
| App: supervision loop | `openc3-app/src/operator.rs` |
| App: plugin file cache | `openc3-app/src/hostfiles.rs` |
| App: container status/uptime | `openc3-app/src/monitor.rs` |
