//! openc3-app's control-plane identity and one-time enrollment with a bridge.
//!
//! openc3-app authenticates to the COSMOS `bridge_microservice` hub with its own
//! persistent Iroh identity. Only its **public** `EndpointId` ever leaves the
//! host; the private key is stored locally under `<root>/bridge/`.
//!
//! Enrollment is one-time and yields the hub ticket, persisted in
//! `<root>/bridge/current.json` (openc3-app pairs with a single bridge). Two
//! paths:
//! * **Auto** (co-located, default): openc3-app reaches COSMOS over the trusted
//!   local Docker control plane and runs the `bridgeenroll` CLI to register its
//!   public key and read back the hub ticket. That local access is the
//!   out-of-band trust anchor that makes zero-touch pairing secure.
//! * **Manual** (remote COSMOS): the user pastes an enrollment token (generated
//!   on the COSMOS Admin → Bridges page) into openc3-app; [`enroll_with_token`]
//!   redeems its one-time code over the hub's `api/enroll` ALPN.

use anyhow::{bail, Context as _, Result};
use base64::Engine as _;
use iroh::SecretKey;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

use crate::bridge::{self, BridgeClient};
use crate::context::Context;
use crate::{docker, process};

/// The bridge openc3-app is currently paired with, persisted across launches.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct Current {
    bridge: String,
    ticket: String,
}

/// A manual enrollment token's decoded payload (base64url JSON), produced by the
/// COSMOS Admin Bridges page / `bridgetoken` CLI.
#[derive(Debug, Deserialize)]
struct EnrollToken {
    bridge: String,
    ticket: String,
    code: String,
}

fn bridge_dir(root: &Path) -> PathBuf {
    root.join("bridge")
}

fn identity_path(root: &Path) -> PathBuf {
    bridge_dir(root).join("identity.key")
}

fn current_path(root: &Path) -> PathBuf {
    bridge_dir(root).join("current.json")
}

/// Lowercase hex-encode bytes.
fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        let _ = write!(s, "{b:02x}");
    }
    s
}

/// Decode exactly 32 bytes of hex.
fn decode_key(s: &str) -> Result<[u8; 32]> {
    let s = s.trim();
    if s.len() != 64 {
        bail!("expected 64 hex chars, got {}", s.len());
    }
    let mut out = [0u8; 32];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).context("invalid hex in key")?;
    }
    Ok(out)
}

/// Load openc3-app's persisted Iroh identity, generating and saving one on first
/// use. openc3-app persists its OWN private key here (unlike the ephemeral keys
/// it later mints for host microservices).
fn load_or_create_secret(root: &Path) -> Result<SecretKey> {
    let path = identity_path(root);
    if path.exists() {
        let contents = std::fs::read_to_string(&path).context("reading bridge identity")?;
        return Ok(SecretKey::from_bytes(&decode_key(&contents)?));
    }
    let secret = SecretKey::generate();
    std::fs::create_dir_all(bridge_dir(root)).ok();
    std::fs::write(&path, hex(&secret.to_bytes())).context("writing bridge identity")?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600));
    }
    Ok(secret)
}

/// openc3-app's public identity as hex (its Iroh `EndpointId`).
fn public_key_hex(secret: &SecretKey) -> String {
    hex(secret.public().as_bytes())
}

fn read_current(root: &Path) -> Option<Current> {
    let contents = std::fs::read_to_string(current_path(root)).ok()?;
    serde_json::from_str(&contents).ok()
}

fn write_current(root: &Path, bridge: &str, ticket: &str) -> Result<()> {
    std::fs::create_dir_all(bridge_dir(root)).ok();
    let current = Current {
        bridge: bridge.to_string(),
        ticket: ticket.to_string(),
    };
    std::fs::write(current_path(root), serde_json::to_string_pretty(&current)?)
        .context("persisting current bridge")?;
    Ok(())
}

/// Resolve the hub ticket to connect with: an explicit `OPENC3_BRIDGE_TICKET`
/// (override), else a previously paired bridge (`current.json`), else auto-enroll
/// over the local Docker control plane. The bridge defaults to `DEFAULT` (every
/// scope has a DEFAULT bridge); `OPENC3_BRIDGE_NAME` overrides it. On failure
/// returns a short human reason (shown in the GUI) explaining why it isn't paired.
fn resolve_ticket(ctx: &Context, app_public_key_hex: &str) -> Result<String, String> {
    if let Ok(ticket) = std::env::var("OPENC3_BRIDGE_TICKET") {
        if !ticket.is_empty() {
            return Ok(ticket);
        }
    }
    if let Some(current) = read_current(&ctx.paths.root) {
        return Ok(current.ticket);
    }
    // Auto-enroll on first launch with the scope's DEFAULT bridge (co-located
    // COSMOS via local Docker). A remote/unmanaged COSMOS instead pairs with a
    // manual token, which lands in current.json and is picked up above.
    let name = std::env::var("OPENC3_BRIDGE_NAME")
        .ok()
        .filter(|n| !n.is_empty())
        .unwrap_or_else(|| "DEFAULT".to_string());
    let ticket = auto_enroll(ctx, &name, app_public_key_hex).map_err(|e| {
        // Full detail to the log; a short reason for the GUI.
        eprintln!("WARN  [bridge] auto-enroll with '{name}' failed: {e:#}");
        "auto-enroll failed (is COSMOS running?)".to_string()
    })?;
    let _ = write_current(&ctx.paths.root, &name, &ticket);
    println!("INFO  [bridge] auto-enrolled with '{name}'");
    Ok(ticket)
}

/// Register openc3-app's public key with COSMOS and read back the hub ticket by
/// running the `bridgeenroll` CLI in the cmd-tlm-api container (local Docker).
fn auto_enroll(ctx: &Context, bridge_name: &str, app_public_key_hex: &str) -> Result<String> {
    let mut cmd = docker::compose(ctx)?;
    cmd.arg("run")
        .arg("--rm")
        .arg("--no-deps")
        .arg("openc3-cosmos-cmd-tlm-api")
        .arg("ruby")
        .arg("/openc3/bin/openc3cli")
        .arg("bridgeenroll")
        .arg(bridge_name)
        .arg(app_public_key_hex);
    let out = process::capture(&mut cmd)?;
    if !out.status.success() {
        bail!(
            "bridgeenroll failed: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    // The CLI prints only the ticket on stdout.
    let ticket = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if ticket.is_empty() {
        bail!("bridgeenroll returned no ticket");
    }
    Ok(ticket)
}

/// Redeem a manual enrollment token (from the COSMOS Admin Bridges page) for a
/// remote COSMOS. Decodes the token, redeems its one-time code over the hub's
/// `api/enroll` ALPN using openc3-app's identity, and persists the pairing.
/// Returns the bridge name on success.
pub fn enroll_with_token(ctx: &Context, token: &str) -> Result<String> {
    let raw = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(token.trim())
        .context("enrollment token is not valid base64")?;
    let parsed: EnrollToken =
        serde_json::from_slice(&raw).context("enrollment token has an unexpected format")?;
    let secret = load_or_create_secret(&ctx.paths.root)?;
    bridge::enroll(secret, &parsed.ticket, &parsed.code).context("redeeming enrollment token")?;
    write_current(&ctx.paths.root, &parsed.bridge, &parsed.ticket)?;
    println!("INFO  [bridge] enrolled with '{}' via token", parsed.bridge);
    Ok(parsed.bridge)
}

/// Load/create openc3-app's identity, resolve the hub ticket (enrolling if
/// needed), and connect a [`BridgeClient`]. Returns `(hub_ticket, client)`, or
/// `None` if no bridge is configured or the connection fails. The returned
/// ticket is what host microservices use (via `OPENC3_BRIDGE_TICKET`) to dial
/// the hub for the data path.
/// On failure returns a short human reason (shown in the GUI) for why openc3-app
/// isn't paired with COSMOS.
pub fn connect_bridge(ctx: &Context) -> Result<(String, BridgeClient), String> {
    let secret = load_or_create_secret(&ctx.paths.root).map_err(|e| {
        eprintln!("WARN  [bridge] could not load control identity: {e:#}");
        "identity error".to_string()
    })?;
    let ticket = resolve_ticket(ctx, &public_key_hex(&secret))?;
    BridgeClient::connect(secret, &ticket)
        .map(|client| (ticket, client))
        .map_err(|e| {
            eprintln!("WARN  [bridge] failed to connect to bridge_microservice: {e:#}");
            "invalid bridge ticket".to_string()
        })
}
