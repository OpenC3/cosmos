//! Iroh client to the COSMOS `bridge_microservice` hub.
//!
//! openc3-app does not run its own Iroh server. It is a **client** of the
//! COSMOS-side `bridge_microservice` (the hub), dialing it with a configured
//! bridge ticket, and uses control APIs over dedicated ALPNs:
//!
//! * `api/host_microservices` — poll the list of host microservices to spawn.
//! * `api/log` — forward host microservice stdout up so COSMOS logs it too.
//!
//! The raw interface data path does NOT flow through openc3-app: each spawned
//! host interface dials the hub directly on `stream/<name>` and is paired there
//! with the matching COSMOS `bridge_interface`.

use anyhow::{bail, Context as _, Result};
use iroh::endpoint::presets;
use iroh::{Endpoint, EndpointAddr, SecretKey};
use iroh_tickets::endpoint::EndpointTicket;
use serde::Deserialize;
use std::collections::BTreeMap;
use tokio::runtime::Runtime;
use tokio::sync::mpsc;

/// ALPN for the host-microservice list API.
const API_HOST_MICROSERVICES: &[u8] = b"api/host_microservices";
/// ALPN for the log-forwarding API.
const API_LOG: &[u8] = b"api/log";
/// Bootstrap ALPN for manual enrollment (redeeming a one-time code).
const API_ENROLL: &[u8] = b"api/enroll";
/// ALPN for publishing the authorized host-microservice identities.
const API_AUTHORIZE: &[u8] = b"api/authorize";
/// ALPN for syncing the scope's plugin files (lib/, requirements, pyproject).
const API_FILES: &[u8] = b"api/files";
/// Upper bound on a small API response we will read.
const MAX_RESPONSE: usize = 16 * 1024 * 1024;
/// Upper bound on a file-sync payload (plugin files can be larger).
const MAX_FILES: usize = 512 * 1024 * 1024;

/// One file in a plugin-file sync delta. `content` is base64 (standard). The
/// hub also sends a `sha256` (ignored here — openc3-app re-hashes from disk on
/// the next sync to build its manifest).
#[derive(Debug, Deserialize)]
pub struct FileEntry {
    pub path: String,
    pub content: String,
}

/// The hub's response to a file sync: changed/new files + paths to delete.
#[derive(Debug, Default, Deserialize)]
pub struct FilesDelta {
    #[serde(default)]
    pub files: Vec<FileEntry>,
    #[serde(default)]
    pub deletions: Vec<String>,
}

/// Mint a fresh Iroh identity for a host microservice. Returns
/// `(secret_key_hex, public_key_hex)`. openc3-app hands the secret to the child
/// and never persists it; the public key is authorized with the hub.
pub fn generate_host_key() -> (String, String) {
    let secret = SecretKey::generate();
    let hex = |bytes: &[u8]| -> String {
        use std::fmt::Write;
        let mut s = String::with_capacity(bytes.len() * 2);
        for b in bytes {
            let _ = write!(s, "{b:02x}");
        }
        s
    };
    (hex(&secret.to_bytes()), hex(secret.public().as_bytes()))
}

/// Redeem a manual enrollment `code` with the hub over the `api/enroll` ALPN,
/// using `secret_key` as openc3-app's identity — which the hub records as the
/// authorized control key on success. One-shot; binds a temporary endpoint.
pub fn enroll(secret_key: SecretKey, bridge_ticket: &str, code: &str) -> Result<()> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .context("building tokio runtime for enrollment")?;
    let ticket: EndpointTicket = bridge_ticket.parse().context("parsing bridge ticket")?;
    let addr = ticket.endpoint_addr().clone();
    runtime.block_on(async move {
        let endpoint = Endpoint::builder(presets::N0)
            .secret_key(secret_key)
            .bind()
            .await?;
        let conn = endpoint
            .connect(addr, API_ENROLL)
            .await
            .map_err(|e| anyhow::anyhow!("connect api/enroll: {e}"))?;
        let (mut send, mut recv) = conn
            .open_bi()
            .await
            .map_err(|e| anyhow::anyhow!("open_bi: {e}"))?;
        let request = serde_json::json!({ "code": code }).to_string();
        send.write_all(request.as_bytes())
            .await
            .map_err(|e| anyhow::anyhow!("write request: {e}"))?;
        let _ = send.finish();
        let data = recv
            .read_to_end(MAX_RESPONSE)
            .await
            .map_err(|e| anyhow::anyhow!("read response: {e}"))?;
        let response: serde_json::Value =
            serde_json::from_slice(&data).context("parsing enroll response")?;
        endpoint.close().await;
        if response.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
            Ok(())
        } else {
            let err = response
                .get("error")
                .and_then(|v| v.as_str())
                .unwrap_or("enrollment rejected");
            bail!("{err}")
        }
    })
}

/// One host microservice openc3-app should spawn, as described by COSMOS via the
/// `api/host_microservices` API. Only the fields the launcher needs are typed;
/// `config_params`/`options` are forwarded to the host runner as opaque JSON.
#[derive(Debug, Clone, Deserialize)]
pub struct HostSpec {
    pub name: String,
    #[serde(default)]
    pub stream: String,
    #[serde(default)]
    pub config_params: Vec<serde_json::Value>,
    #[serde(default)]
    pub options: Vec<serde_json::Value>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    #[serde(default)]
    pub needs_dependencies: bool,
}

/// Client connection to the COSMOS `bridge_microservice` hub.
pub struct BridgeClient {
    runtime: Runtime,
    endpoint: Endpoint,
    addr: EndpointAddr,
    log_tx: mpsc::UnboundedSender<String>,
}

impl BridgeClient {
    /// Connect to the hub identified by `bridge_ticket` (its `EndpointTicket`),
    /// using `secret_key` as openc3-app's control identity so the hub can verify
    /// it. Binds a local Iroh endpoint and starts the background log forwarder.
    pub fn connect(secret_key: SecretKey, bridge_ticket: &str) -> Result<Self> {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .context("building tokio runtime for the bridge client")?;
        let ticket: EndpointTicket = bridge_ticket.parse().context("parsing bridge ticket")?;
        let addr = ticket.endpoint_addr().clone();
        let endpoint = runtime
            .block_on(async { Endpoint::builder(presets::N0).secret_key(secret_key).bind().await })?;

        let (log_tx, log_rx) = mpsc::unbounded_channel::<String>();
        runtime.spawn(log_forwarder(endpoint.clone(), addr.clone(), log_rx));

        Ok(Self {
            runtime,
            endpoint,
            addr,
            log_tx,
        })
    }

    /// Poll the hub for the list of host microservices this bridge should run.
    pub fn fetch_host_microservices(&self) -> Result<Vec<HostSpec>> {
        self.runtime.block_on(async {
            let conn = self
                .endpoint
                .connect(self.addr.clone(), API_HOST_MICROSERVICES)
                .await
                .map_err(|e| anyhow::anyhow!("connect api/host_microservices: {e}"))?;
            let (mut send, mut recv) = conn
                .open_bi()
                .await
                .map_err(|e| anyhow::anyhow!("open_bi: {e}"))?;
            // The client speaks first (the request); this surfaces the hub's
            // accept_bi. The request content is ignored by the hub.
            send.write_all(b"host_microservices")
                .await
                .map_err(|e| anyhow::anyhow!("write request: {e}"))?;
            let _ = send.finish();
            let data = recv
                .read_to_end(MAX_RESPONSE)
                .await
                .map_err(|e| anyhow::anyhow!("read response: {e}"))?;
            let specs: Vec<HostSpec> =
                serde_json::from_slice(&data).context("parsing host_microservices response")?;
            Ok(specs)
        })
    }

    /// Publish the set of authorized host-microservice public keys to the hub.
    /// The hub only lets these identities onto the `host/<name>` data path.
    /// Sent each operator cycle so the hub's (in-memory) set stays current.
    pub fn authorize(&self, keys: Vec<String>) -> Result<()> {
        self.runtime.block_on(async {
            let conn = self
                .endpoint
                .connect(self.addr.clone(), API_AUTHORIZE)
                .await
                .map_err(|e| anyhow::anyhow!("connect api/authorize: {e}"))?;
            let (mut send, mut recv) = conn
                .open_bi()
                .await
                .map_err(|e| anyhow::anyhow!("open_bi: {e}"))?;
            let request = serde_json::json!({ "keys": keys }).to_string();
            send.write_all(request.as_bytes())
                .await
                .map_err(|e| anyhow::anyhow!("write request: {e}"))?;
            let _ = send.finish();
            // Drain the small ack so the hub sees a clean close.
            let _ = recv.read_to_end(MAX_RESPONSE).await;
            Ok(())
        })
    }

    /// Sync the scope's plugin files. Sends the local manifest (`path → sha256`);
    /// the hub replies with only changed/new files + a deletion list, so
    /// unchanged files are never re-sent. This is how host interfaces get plugin
    /// code (the host has no bucket/gem access).
    pub fn sync_files(&self, have: BTreeMap<String, String>) -> Result<FilesDelta> {
        self.runtime.block_on(async {
            let conn = self
                .endpoint
                .connect(self.addr.clone(), API_FILES)
                .await
                .map_err(|e| anyhow::anyhow!("connect api/files: {e}"))?;
            let (mut send, mut recv) = conn
                .open_bi()
                .await
                .map_err(|e| anyhow::anyhow!("open_bi: {e}"))?;
            let request = serde_json::json!({ "have": have }).to_string();
            send.write_all(request.as_bytes())
                .await
                .map_err(|e| anyhow::anyhow!("write request: {e}"))?;
            let _ = send.finish();
            let data = recv
                .read_to_end(MAX_FILES)
                .await
                .map_err(|e| anyhow::anyhow!("read response: {e}"))?;
            let delta: FilesDelta =
                serde_json::from_slice(&data).context("parsing files response")?;
            Ok(delta)
        })
    }

    /// A cloneable sender for forwarding host stdout lines up to COSMOS.
    pub fn log_sender(&self) -> mpsc::UnboundedSender<String> {
        self.log_tx.clone()
    }
}

/// Maintain an `api/log` connection and forward queued log lines to the hub,
/// reconnecting on failure. Log delivery is best effort: a line may be dropped
/// when a connection is being (re)established.
async fn log_forwarder(
    endpoint: Endpoint,
    addr: EndpointAddr,
    mut rx: mpsc::UnboundedReceiver<String>,
) {
    // Block until there is a line to send, then (re)establish the connection.
    while let Some(mut line) = rx.recv().await {
        let Ok(conn) = endpoint.connect(addr.clone(), API_LOG).await else {
            continue; // couldn't connect; retry when the next line arrives
        };
        let Ok((mut send, _recv)) = conn.open_bi().await else {
            continue;
        };
        loop {
            let mut buf = line.into_bytes();
            buf.push(b'\n');
            if send.write_all(&buf).await.is_err() {
                break; // connection dropped; reconnect on the next line
            }
            match rx.recv().await {
                Some(next) => line = next,
                None => {
                    let _ = send.finish();
                    return; // channel closed: app shutting down
                }
            }
        }
    }
}
