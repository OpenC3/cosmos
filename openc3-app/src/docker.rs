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

/// Run a docker-derived command, transparently applying the `docker` group via
/// `sg` on Linux when this process isn't in that group yet (see
/// [`group::needs_wrap`]). This is what lets docker work right after the
/// installer adds the user to the group — no app restart required. On other
/// platforms (and when unneeded) it runs the command unchanged.
pub fn run(cmd: Command) -> Result<()> {
    process::run(&mut group::wrap(cmd))
}

/// Like [`run`] but captures output regardless of exit status.
pub fn capture(cmd: Command) -> Result<std::process::Output> {
    process::capture(&mut group::wrap(cmd))
}

/// Transparently run docker commands under the `docker` group via `sg` when the
/// current process was started before the user was added to the group. A running
/// process can't change its own supplementary groups, but each docker command is
/// a fresh child, so `sg docker -c '<cmd>'` (which re-reads group membership)
/// gives it access — no logout / app restart needed.
mod group {
    use std::process::Command;

    /// Wrap `cmd` as `sg docker -c '<program args…>'` when needed; otherwise
    /// return it unchanged. Env overrides and the working directory are set on
    /// the `sg` command and inherited by the shell it runs.
    pub fn wrap(cmd: Command) -> Command {
        if !needs_wrap() {
            return cmd;
        }
        let mut shell = shell_quote(&cmd.get_program().to_string_lossy());
        for arg in cmd.get_args() {
            shell.push(' ');
            shell.push_str(&shell_quote(&arg.to_string_lossy()));
        }
        let mut sg = Command::new("sg");
        sg.arg("docker").arg("-c").arg(shell);
        for (key, val) in cmd.get_envs() {
            match val {
                Some(v) => {
                    sg.env(key, v);
                }
                None => {
                    sg.env_remove(key);
                }
            }
        }
        if let Some(dir) = cmd.get_current_dir() {
            sg.current_dir(dir);
        }
        sg
    }

    /// POSIX single-quote escaping so arbitrary args survive `sh -c`.
    fn shell_quote(s: &str) -> String {
        let mut out = String::with_capacity(s.len() + 2);
        out.push('\'');
        for ch in s.chars() {
            if ch == '\'' {
                out.push_str("'\\''");
            } else {
                out.push(ch);
            }
        }
        out.push('\'');
        out
    }

    #[cfg(target_os = "linux")]
    pub fn needs_wrap() -> bool {
        use std::sync::atomic::{AtomicBool, Ordering};
        // Once wrapping becomes possible (user added to the group) it stays so;
        // cache to avoid re-running `id` on every docker command afterward.
        static ACTIVE: AtomicBool = AtomicBool::new(false);
        if ACTIVE.load(Ordering::Relaxed) {
            return true;
        }
        // Root already has socket access; sg must exist to switch groups.
        if id_field(&["-u"]).as_deref() == Some("0") || !crate::process::which("sg") {
            return false;
        }
        // If this process already has the docker group, nothing to do.
        if session_groups().iter().any(|g| g == "docker") {
            return false;
        }
        // Wrap only once the user is a member per the group database (e.g. after
        // the installer's `usermod`), so `sg docker` succeeds without a password.
        let configured = username()
            .map(|u| id_groups(Some(&u)).iter().any(|g| g == "docker"))
            .unwrap_or(false);
        if configured {
            ACTIVE.store(true, Ordering::Relaxed);
        }
        configured
    }

    #[cfg(not(target_os = "linux"))]
    pub fn needs_wrap() -> bool {
        false
    }

    #[cfg(target_os = "linux")]
    fn session_groups() -> Vec<String> {
        id_groups(None)
    }

    #[cfg(target_os = "linux")]
    fn id_groups(user: Option<&str>) -> Vec<String> {
        let mut args = vec!["-nG"];
        if let Some(u) = user {
            args.push(u);
        }
        id_field(&args)
            .map(|s| s.split_whitespace().map(|g| g.to_string()).collect())
            .unwrap_or_default()
    }

    #[cfg(target_os = "linux")]
    fn id_field(args: &[&str]) -> Option<String> {
        let mut cmd = Command::new("id");
        cmd.args(args);
        crate::process::stdout_string(&mut cmd).ok().map(|s| s.trim().to_string())
    }

    #[cfg(target_os = "linux")]
    fn username() -> Option<String> {
        for key in ["USER", "LOGNAME"] {
            if let Ok(v) = std::env::var(key) {
                if !v.is_empty() {
                    return Some(v);
                }
            }
        }
        id_field(&["-un"]).filter(|s| !s.is_empty())
    }
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
    run(cmd)
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
        let _ = run(cmd);
    }
    std::thread::sleep(std::time::Duration::from_secs(5));
    let mut down = compose(ctx)?;
    down.args(["down", "-t", "30"]);
    run(down)
}

/// `docker compose down -t 30 -v` (used by cleanup).
pub fn down_volumes(ctx: &Context) -> Result<()> {
    let mut cmd = compose(ctx)?;
    cmd.args(["down", "-t", "30", "-v"]);
    run(cmd)
}

/// `docker compose ps` passthrough.
pub fn ps(ctx: &Context) -> Result<()> {
    let mut cmd = compose(ctx)?;
    cmd.arg("ps");
    run(cmd)
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
    run(cmd)
}

/// Capture the last `tail` log lines for a service (used by the GUI logs panel).
#[cfg(feature = "gui")]
pub fn capture_logs(ctx: &Context, service: &str, tail: u32) -> Result<String> {
    let mut cmd = compose(ctx)?;
    cmd.args(["logs", "--no-color", "--tail", &tail.to_string(), service]);
    let out = capture(cmd)?;
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
