//! High-level command implementations corresponding to the CLI subcommands.
//! Together these reproduce the functionality of `openc3.sh`.

use crate::context::Context;
use crate::{docker, env_file, install, monitor, process};
use anyhow::{bail, Context as _, Result};
use std::io::Write;
use std::path::Path;
use std::process::Command;

/// In development mode, run the source checkout's `openc3.sh` (or `openc3.bat`
/// on Windows) with `subcommand`, from that directory. OPENC3_TAG /
/// OPENC3_ENTERPRISE_TAG overrides are inherited from the process environment
/// (the GUI sets them when dev mode is on).
fn run_dev(dev: &Path, subcommand: &str, args: &[String]) -> Result<()> {
    let (script_name, launcher): (&str, Option<&str>) = if cfg!(windows) {
        ("openc3.bat", None)
    } else {
        ("openc3.sh", Some("bash"))
    };
    let script = dev.join(script_name);
    if !script.exists() {
        bail!(
            "Development folder '{}' does not contain {}.",
            dev.display(),
            script_name
        );
    }
    let mut cmd = match launcher {
        Some(sh) => {
            let mut c = Command::new(sh);
            c.arg(&script);
            c
        }
        None => Command::new(&script),
    };
    cmd.arg(subcommand);
    for a in args {
        cmd.arg(a);
    }
    cmd.current_dir(dev);
    process::run(&mut cmd)
}

/// `build` — build all COSMOS containers from source (dev installs only).
pub fn build(ctx: &Context, flags: &[String]) -> Result<()> {
    if let Some(dev) = &ctx.dev_folder {
        return run_dev(dev, "build", flags);
    }
    if !ctx.paths.is_devel() {
        bail!("'build' is only available for development installs (no compose-build.yaml found).");
    }
    install::setup_cosmos(ctx)?;
    let mut cmd = docker::compose_with_build(ctx)?;
    cmd.arg("build");
    for f in flags {
        cmd.arg(f);
    }
    docker::run(cmd)
}

/// `run` — start the containers detached.
pub fn run(ctx: &Context) -> Result<()> {
    if let Some(dev) = &ctx.dev_folder {
        return run_dev(dev, "run", &[]);
    }
    check_not_root();
    install::setup_cosmos(ctx)?;
    // On first run Docker downloads all the container images, which can take
    // several minutes. Stream compose's progress through the notifier so the GUI
    // (and CLI) show what's happening instead of appearing hung.
    install::progress("Starting COSMOS containers (first run downloads images — this can take several minutes)…");
    docker::up(ctx, |line| install::progress(line))?;
    install::progress("COSMOS is starting. Access it at http://localhost:2900");
    Ok(())
}

/// `start` — build (dev) then run.
pub fn start(ctx: &Context, flags: &[String]) -> Result<()> {
    if let Some(dev) = &ctx.dev_folder {
        return run_dev(dev, "start", flags);
    }
    if ctx.paths.is_devel() {
        build(ctx, flags)?;
    }
    run(ctx)
}

/// `stop` — gracefully stop and tear down.
pub fn stop(ctx: &Context) -> Result<()> {
    if let Some(dev) = &ctx.dev_folder {
        return run_dev(dev, "stop", &[]);
    }
    docker::stop(ctx)
}

/// `restart` — stop then run.
pub fn restart(ctx: &Context) -> Result<()> {
    stop(ctx)?;
    run(ctx)
}

/// Open `url` in the host's default web browser.
#[cfg(feature = "gui")]
pub fn open_browser(url: &str) -> Result<()> {
    let mut cmd = if cfg!(target_os = "macos") {
        let mut c = Command::new("open");
        c.arg(url);
        c
    } else if cfg!(target_os = "windows") {
        // `start` is a cmd builtin; the empty "" is the window title argument.
        let mut c = Command::new("cmd");
        c.args(["/C", "start", "", url]);
        c
    } else {
        let mut c = Command::new("xdg-open");
        c.arg(url);
        c
    };
    process::run(&mut cmd)
}

/// `status` — show a color-coded-style container status table.
pub fn status(ctx: &Context) -> Result<()> {
    use crate::monitor::RunState;
    match monitor::snapshot(ctx, true) {
        Ok(statuses) => {
            let running = statuses.iter().filter(|c| c.is_running()).count();
            println!("{} of {} containers running", running, statuses.len());
            for c in &statuses {
                let glyph = match c.run_state() {
                    RunState::Running => "●",
                    RunState::ExitedSuccess => "○",
                    RunState::ExitedFailure => "○",
                    RunState::Restarting => "↻",
                    RunState::Paused => "❚",
                    RunState::Unknown => "?",
                };
                println!(
                    "  {glyph} {:<34} {:<14} {:<24} {:>7} {:>12}  {}",
                    c.service,
                    c.tag_display(),
                    c.display_status(),
                    c.cpu_display(),
                    c.mem_display(),
                    c.ports_summary()
                );
            }
            if !statuses.is_empty() {
                let (cpu_total, mem_total) = monitor::totals(&statuses);
                let (label, blank) = ("Total", "");
                println!(
                    "    {label:<34} {blank:<14} {blank:<24} {cpu_total:>7} {mem_total:>12}"
                );
            }
            Ok(())
        }
        // Fall back to a raw `ps` if JSON parsing isn't available.
        Err(_) => docker::ps(ctx),
    }
}

/// `logs` — show (optionally follow) container logs.
pub fn logs(ctx: &Context, service: Option<&str>, follow: bool) -> Result<()> {
    docker::logs(ctx, service, follow)
}

/// `monitor` — headless loop printing health every few seconds.
pub fn monitor_loop(ctx: &Context) -> Result<()> {
    println!("Monitoring COSMOS containers (Ctrl-C to stop)...");
    loop {
        // Health only — no per-container CPU/mem stats needed here.
        match monitor::snapshot(ctx, false) {
            Ok(statuses) => {
                let unhealthy: Vec<_> = statuses.iter().filter(|c| !c.is_healthy()).collect();
                let summary = monitor::summarize(&statuses);
                if unhealthy.is_empty() {
                    println!("[ok] {summary}");
                } else {
                    let names: Vec<&str> =
                        unhealthy.iter().map(|c| c.service.as_str()).collect();
                    println!("[warn] {summary} — unhealthy: {}", names.join(", "));
                }
            }
            Err(e) => println!("[error] {e}"),
        }
        std::thread::sleep(std::time::Duration::from_secs(5));
    }
}

/// `cleanup` — remove docker volumes and (optionally) local plugins.
pub fn cleanup(ctx: &Context, local: bool, force: bool) -> Result<()> {
    if !force {
        print!("Are you sure? Cleanup removes ALL docker volumes and COSMOS data! [y/N] ");
        std::io::stdout().flush().ok();
        let mut answer = String::new();
        std::io::stdin().read_line(&mut answer).ok();
        if !answer.trim().eq_ignore_ascii_case("y") {
            println!("Aborted.");
            return Ok(());
        }
    }
    if let Some(dev) = &ctx.dev_folder {
        // Already confirmed above; pass `force` so openc3.sh doesn't re-prompt.
        let mut args = Vec::new();
        if local {
            args.push("local".to_string());
        }
        args.push("force".to_string());
        return run_dev(dev, "cleanup", &args);
    }
    docker::down_volumes(ctx)?;
    if local {
        let default_dir = ctx.paths.cosmos.join("plugins").join("DEFAULT");
        if default_dir.is_dir() {
            for entry in std::fs::read_dir(&default_dir)? {
                let entry = entry?;
                if entry.file_name() == "README.md" {
                    continue;
                }
                let path = entry.path();
                if path.is_dir() {
                    std::fs::remove_dir_all(&path).ok();
                } else {
                    std::fs::remove_file(&path).ok();
                }
            }
        }
    }
    Ok(())
}

/// `cli` / `cliroot` — run the Ruby CLI inside a one-off container.
pub fn cli(ctx: &Context, args: &[String], as_root: bool) -> Result<()> {
    let env = env_file::parse(&ctx.paths.env_file())
        .with_context(|| "reading the COSMOS .env file (is COSMOS installed?)")?;
    let cwd = std::env::current_dir()?;

    let mut cmd = docker::compose(ctx)?;
    cmd.arg("run").arg("-it").arg("--rm");
    if as_root {
        cmd.arg("--user=root");
    }
    cmd.arg("-v").arg(format!("{}:/openc3/local:z", cwd.display()));
    cmd.arg("-w").arg("/openc3/local");
    if ctx.enterprise {
        if let Some(user) = env.get("OPENC3_API_USER") {
            cmd.arg("-e").arg(format!("OPENC3_API_USER={user}"));
        }
    }
    if let Some(pw) = env.get("OPENC3_API_PASSWORD") {
        cmd.arg("-e").arg(format!("OPENC3_API_PASSWORD={pw}"));
    }
    cmd.arg("--no-deps")
        .arg("openc3-cosmos-cmd-tlm-api")
        .arg("ruby")
        .arg("/openc3/bin/openc3cli");
    for a in args {
        cmd.arg(a);
    }
    docker::run(cmd)
}

/// `test` — build then run a test suite (development installs only).
pub fn test(ctx: &Context, args: &[String]) -> Result<()> {
    if !ctx.paths.is_devel() {
        bail!("'test' requires a development install with the COSMOS source tree.");
    }
    install::setup_cosmos(ctx)?;
    let mut build = docker::compose_with_build(ctx)?;
    build.arg("build");
    docker::run(build)?;

    // Delegate to the repository's test script when present.
    let script = ctx
        .paths
        .cosmos
        .join("scripts")
        .join("linux")
        .join("openc3_test.sh");
    if script.exists() {
        let mut cmd = Command::new("bash");
        cmd.arg(&script).args(args).current_dir(&ctx.paths.cosmos);
        process::run(&mut cmd)
    } else {
        bail!(
            "test script not found at {}. Available in a full source checkout only.",
            script.display()
        );
    }
}

/// `upgrade` — apply a COSMOS release via git (mirrors openc3_upgrade.sh).
pub fn upgrade(ctx: &Context, tag: &str, preview: bool) -> Result<()> {
    if !process::which("git") {
        bail!("git is required for upgrade but was not found.");
    }
    let dir = &ctx.paths.cosmos;
    if !dir.join(".git").exists() {
        bail!(
            "The COSMOS install at {} is not a git checkout; upgrade requires git-based installs.",
            dir.display()
        );
    }

    let enterprise = ctx.enterprise
        || dir.join("openc3-enterprise-traefik").is_dir()
        || tag.to_lowercase().contains("enterprise");
    let url = if enterprise {
        // Enterprise now lives in the private Forgejo repo (repos.openc3.com).
        "https://repos.openc3.com/OpenC3/cosmos-enterprise-project.git"
    } else {
        "https://github.com/OpenC3/cosmos-project.git"
    };

    // Enterprise fetches authenticate with a repos.openc3.com access token
    // (Forgejo accepts it as an Authorization header). For the CLI it comes from
    // OPENC3_ENTERPRISE_TOKEN.
    let token = crate::install::enterprise_token_from_env();
    if enterprise && token.trim().is_empty() {
        bail!(
            "COSMOS Enterprise upgrades require a repos.openc3.com access token.\n\
             Set OPENC3_ENTERPRISE_TOKEN and try again."
        );
    }
    let token_opt: Option<&str> = if enterprise { Some(&token) } else { None };

    let real_tag = tag.strip_prefix("enterprise-").unwrap_or(tag).to_string();

    // Configure the 'cosmos' remote.
    let remotes = process::stdout_string(git(dir).args(["remote"]))?;
    if remotes.lines().any(|r| r.trim() == "cosmos") {
        process::run(git(dir).args(["remote", "set-url", "cosmos", url]))?;
    } else {
        process::run(git(dir).args(["remote", "add", "cosmos", url]))?;
    }

    println!("Fetching latest changes from the 'cosmos' remote...");
    process::run(git_net(dir, token_opt).args(["fetch", "cosmos"]))?;

    let hash = process::stdout_string(
        git_net(dir, token_opt).args(["ls-remote", "cosmos", &format!("refs/tags/{real_tag}")]),
    )?;
    let hash = hash
        .split_whitespace()
        .next()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow::anyhow!("tag '{real_tag}' not found on remote"))?
        .to_string();

    if preview {
        return process::run(git(dir).args(["diff", "-R", &hash]));
    }

    // git diff -R <hash> --binary | git apply --whitespace=fix --exclude=plugins/*
    let diff = process::stdout_string(git(dir).args(["diff", "-R", &hash, "--binary"]))?;
    let mut apply = git(dir);
    apply.args(["apply", "--whitespace=fix", "--exclude=plugins/*"]);
    apply.stdin(std::process::Stdio::piped());
    // No flashing console window on Windows (the GUI has no console of its own).
    process::no_window(&mut apply);
    let mut child = apply.spawn().context("spawning git apply")?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(diff.as_bytes())?;
    }
    let st = child.wait()?;
    if !st.success() {
        bail!("git apply failed");
    }
    println!("Applied changes for tag '{tag}'. Run `openc3 run` to start the upgraded environment.");
    Ok(())
}

fn git(dir: &std::path::Path) -> Command {
    let mut cmd = Command::new("git");
    cmd.current_dir(dir);
    cmd
}

/// A git command in `dir` for network operations, optionally authenticating to a
/// private Forgejo repo with an access token. The token is supplied via git's
/// `GIT_CONFIG_*` environment variables (an `http.extraHeader`), so it never
/// lands in the process argv or in `.git/config`.
fn git_net(dir: &std::path::Path, token: Option<&str>) -> Command {
    let mut cmd = git(dir);
    if let Some(t) = token {
        cmd.env("GIT_CONFIG_COUNT", "1")
            .env("GIT_CONFIG_KEY_0", "http.extraHeader")
            .env("GIT_CONFIG_VALUE_0", format!("Authorization: token {t}"));
    }
    cmd
}

fn check_not_root() {
    #[cfg(unix)]
    {
        let is_root = std::process::Command::new("id")
            .arg("-u")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim() == "0")
            .unwrap_or(false);
        if is_root {
            eprintln!(
                "WARNING: COSMOS should not be run as root; Local Mode file permissions will be affected."
            );
        }
    }
}
