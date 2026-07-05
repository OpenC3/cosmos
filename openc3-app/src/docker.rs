//! Thin wrapper around `docker compose` for the COSMOS environment, plus a few
//! raw engine helpers used by the util commands.

use crate::context::{Context, Runtime};
use crate::process;
use anyhow::{bail, Result};
use std::process::Command;

/// The COSMOS service container images managed by the util commands.
pub const IMAGES: &[&str] = &[
    "openc3-buckets",
    "openc3-cosmos-cmd-tlm-api",
    "openc3-cosmos-init",
    "openc3-cosmos-script-runner-api",
    "openc3-operator",
    "openc3-redis",
    "openc3-traefik",
    "openc3-tsdb",
];

/// Build a `Command` for the engine itself (e.g. `docker ...`).
pub fn engine_cmd(rt: &Runtime) -> Command {
    Command::new(&rt.engine)
}

/// Build a base `docker compose -f <cosmos>/compose.yaml` command running with
/// the COSMOS directory as the working directory (so the bundled `.env` and
/// relative volume paths resolve correctly).
pub fn compose(ctx: &Context) -> Result<Command> {
    let rt = ctx.runtime()?;
    if !ctx.paths.cosmos_installed() {
        bail!(
            "COSMOS environment not installed at {}. Run `openc3 install cosmos`.",
            ctx.paths.cosmos.display()
        );
    }
    let mut cmd = Command::new(&rt.compose[0]);
    for part in &rt.compose[1..] {
        cmd.arg(part);
    }
    cmd.arg("-f").arg(ctx.paths.compose_file());
    cmd.current_dir(&ctx.paths.cosmos);
    apply_runtime_env(&mut cmd, rt);
    Ok(cmd)
}

/// Like [`compose`] but also includes the build overlay (development installs).
pub fn compose_with_build(ctx: &Context) -> Result<Command> {
    let mut cmd = compose(ctx)?;
    cmd.arg("-f").arg(ctx.paths.compose_build_file());
    Ok(cmd)
}

/// Apply the user/rootless environment variables that compose.yaml expects.
fn apply_runtime_env(cmd: &mut Command, rt: &Runtime) {
    cmd.env("OPENC3_USER_ID", rt.user_id.to_string());
    cmd.env("OPENC3_GROUP_ID", rt.group_id.to_string());
    if rt.rootless {
        cmd.env("OPENC3_ROOTLESS", "1");
    } else {
        cmd.env("OPENC3_ROOTFUL", "1");
    }
}

/// `docker compose up -d`
pub fn up(ctx: &Context) -> Result<()> {
    let mut cmd = compose(ctx)?;
    cmd.args(["up", "-d"]);
    process::run(&mut cmd)
}

/// Gracefully stop the COSMOS services, then `down`.
pub fn stop(ctx: &Context) -> Result<()> {
    // Stop the active services first so they shut down cleanly.
    let mut graceful = vec![
        "openc3-operator",
        "openc3-cosmos-script-runner-api",
        "openc3-cosmos-cmd-tlm-api",
    ];
    if ctx.enterprise {
        graceful.push("openc3-metrics");
    }
    for svc in graceful {
        let mut cmd = compose(ctx)?;
        cmd.args(["stop", svc]);
        // Ignore errors for services that may not exist in this edition.
        let _ = process::run(&mut cmd);
    }
    std::thread::sleep(std::time::Duration::from_secs(5));
    let mut down = compose(ctx)?;
    down.args(["down", "-t", "30"]);
    process::run(&mut down)
}

/// `docker compose down -t 30 -v` (used by cleanup).
pub fn down_volumes(ctx: &Context) -> Result<()> {
    let mut cmd = compose(ctx)?;
    cmd.args(["down", "-t", "30", "-v"]);
    process::run(&mut cmd)
}

/// `docker compose ps` passthrough.
pub fn ps(ctx: &Context) -> Result<()> {
    let mut cmd = compose(ctx)?;
    cmd.arg("ps");
    process::run(&mut cmd)
}

/// `docker compose logs [-f] [service]`.
pub fn logs(ctx: &Context, service: Option<&str>, follow: bool) -> Result<()> {
    let mut cmd = compose(ctx)?;
    cmd.arg("logs");
    if follow {
        cmd.arg("-f");
    }
    if let Some(svc) = service {
        cmd.arg(svc);
    }
    process::run(&mut cmd)
}

/// Capture the last `tail` log lines for a service (used by the GUI logs panel).
#[cfg(feature = "gui")]
pub fn capture_logs(ctx: &Context, service: &str, tail: u32) -> Result<String> {
    let mut cmd = compose(ctx)?;
    cmd.args(["logs", "--no-color", "--tail", &tail.to_string(), service]);
    let out = process::capture(&mut cmd)?;
    let mut text = String::from_utf8_lossy(&out.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !stderr.trim().is_empty() {
        if !text.is_empty() {
            text.push('\n');
        }
        text.push_str(&stderr);
    }
    if text.trim().is_empty() {
        text = "No logs available".to_string();
    }
    Ok(text)
}
