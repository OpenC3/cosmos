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

/// Run a docker-derived command.
pub fn run(mut cmd: Command) -> Result<()> {
    process::run(&mut cmd)
}

/// Like [`run`] but captures output regardless of exit status.
pub fn capture(mut cmd: Command) -> Result<std::process::Output> {
    process::capture(&mut cmd)
}

/// If the installer just added the user to the `docker` group but this process
/// doesn't have that group yet (it predates the change), re-exec the whole app
/// through `sg docker` so it — and all of its docker calls — gain socket access
/// without a full logout. A process can't change its own supplementary groups,
/// so re-execing is the only in-place way. No-op elsewhere or when already
/// usable; guarded against re-exec loops.
pub fn relaunch_in_docker_group_if_needed() {
    group::relaunch_if_needed();
}

mod group {
    /// Env guard so a re-exec (or a failed one) never loops.
    #[cfg(target_os = "linux")]
    const GUARD: &str = "OPENC3_DOCKER_REGROUP";

    #[cfg(target_os = "linux")]
    pub fn relaunch_if_needed() {
        use std::os::unix::process::CommandExt;
        use std::process::Command;

        if std::env::var_os(GUARD).is_some() || !should_join() {
            return;
        }
        let Ok(exe) = std::env::current_exe() else {
            return;
        };
        // Re-run the exact same invocation inside `sg docker`.
        let mut inner = shell_quote(&exe.to_string_lossy());
        for arg in std::env::args().skip(1) {
            inner.push(' ');
            inner.push_str(&shell_quote(&arg));
        }
        // Set the guard on this process first so a failed exec doesn't retry.
        std::env::set_var(GUARD, "1");
        crate::logging::info(
            "docker",
            "Joining the 'docker' group (re-launching) so Docker works without a re-login…",
        );
        // Replaces this process image; only returns on error.
        let err = Command::new("sg")
            .arg("docker")
            .arg("-c")
            .arg(format!("exec {inner}"))
            .exec();
        crate::logging::warn(
            "docker",
            &format!("could not join the docker group ({err}); log out and back in to use Docker"),
        );
    }

    #[cfg(not(target_os = "linux"))]
    pub fn relaunch_if_needed() {}

    /// True when we should re-exec into the docker group: not root, `sg` is
    /// available, this process isn't in the group yet, but the user is a member
    /// per the group database (e.g. after the installer's `usermod`).
    #[cfg(target_os = "linux")]
    fn should_join() -> bool {
        if id_field(&["-u"]).as_deref() == Some("0") || !crate::process::which("sg") {
            return false;
        }
        if id_groups(None).iter().any(|g| g == "docker") {
            return false;
        }
        username()
            .map(|u| id_groups(Some(&u)).iter().any(|g| g == "docker"))
            .unwrap_or(false)
    }

    /// POSIX single-quote escaping so arbitrary paths/args survive `sh -c`.
    #[cfg(target_os = "linux")]
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

    /// Group names for `user` (or the current process when `None`).
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
        let mut cmd = std::process::Command::new("id");
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
