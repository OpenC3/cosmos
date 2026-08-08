//! Installers for the three environment components described in the
//! requirements:
//!   1. a working Docker / docker compose engine,
//!   2. an isolated Python runtime under the `python/` subfolder,
//!   3. the OpenC3 COSMOS environment under the `cosmos/` subfolder.

use crate::context::Context;
use crate::download;
use crate::process;
use anyhow::{bail, Context as _, Result};
use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::process::Command;

/// A sink for user-facing install messages.
type Notifier = Box<dyn Fn(String)>;

thread_local! {
    /// Optional sink for user-facing install messages on the current thread.
    static NOTIFIER: RefCell<Option<Notifier>> = const { RefCell::new(None) };
}

/// Route user-facing install messages emitted by [`notify`] to `sink` on the
/// current thread. The GUI uses this to mirror messages into its activity log;
/// when no sink is set (the CLI), messages are printed to stdout.
#[cfg(feature = "gui")]
pub fn set_notifier(sink: Notifier) {
    NOTIFIER.with(|n| *n.borrow_mut() = Some(sink));
}

/// Remove any notifier set for the current thread.
#[cfg(feature = "gui")]
pub fn clear_notifier() {
    NOTIFIER.with(|n| *n.borrow_mut() = None);
}

thread_local! {
    /// Optional sink for important instructions ([`notify_dialog`]) to surface as
    /// a dismissible GUI popup (e.g. Docker's post-install NEXT STEPS).
    static DIALOG: RefCell<Option<Notifier>> = const { RefCell::new(None) };
}

/// Route dialog-worthy messages to `sink`; the GUI shows them as a popup with an
/// OK button. When unset (the CLI) they only go to the normal message log.
#[cfg(feature = "gui")]
pub fn set_dialog_notifier(sink: Notifier) {
    DIALOG.with(|d| *d.borrow_mut() = Some(sink));
}

/// Remove any dialog notifier set for the current thread.
#[cfg(feature = "gui")]
pub fn clear_dialog_notifier() {
    DIALOG.with(|d| *d.borrow_mut() = None);
}

/// Public entry point for other modules (e.g. `commands`) to emit a user-facing
/// progress line through the same GUI-log / stdout routing as install messages.
pub fn progress(msg: impl Into<String>) {
    notify(msg);
}

/// Emit a user-facing message: to the thread's notifier if set, else stdout.
fn notify(msg: impl Into<String>) {
    let msg = msg.into();
    NOTIFIER.with(|n| match n.borrow().as_ref() {
        Some(sink) => sink(msg),
        None => println!("{msg}"),
    });
}

/// Emit an important instruction that goes to the normal message log AND, in the
/// GUI, pops up in a dismissible dialog (used for post-install NEXT STEPS).
fn notify_dialog(msg: impl Into<String>) {
    let msg = msg.into();
    notify(msg.clone()); // still record it in the activity log / stdout
    DIALOG.with(|d| {
        if let Some(sink) = d.borrow().as_ref() {
            sink(msg);
        }
    });
}

/// Docker Desktop licensing caveat, surfaced wherever Docker Desktop is offered.
pub const DOCKER_DESKTOP_LICENSE: &str = "Note: Docker Desktop requires a paid Docker subscription \
for organizations with more than 250 employees OR more than $10 million in annual revenue. \
Free alternatives (colima on macOS; Podman or Rancher Desktop on Windows) avoid this and can be \
installed manually if needed.";

const UV_VERSION_URL_BASE: &str = "https://github.com/astral-sh/uv/releases/latest/download";
const CACERT_URL: &str = "https://curl.se/ca/cacert.pem";
const COSMOS_PROJECT_REPO: &str = "https://github.com/OpenC3/cosmos-project";
/// COSMOS Enterprise lives in a private Forgejo repo; its tag/branch source
/// archives are fetched from the Gitea-compatible API with a token.
const ENTERPRISE_ARCHIVE_BASE: &str =
    "https://repos.openc3.com/api/v1/repos/OpenC3/cosmos-enterprise-project/archive";
const DEFAULT_PYTHON: &str = "3.12";

/// Install everything in dependency order.
pub fn all(ctx: &Context) -> Result<()> {
    prerequisites(ctx)?;
    docker(ctx)?;
    python(ctx)?;
    cosmos(ctx, "latest", ctx.enterprise, &enterprise_token_from_env())?;
    Ok(())
}

/// The COSMOS Enterprise access token for CLI installs, taken from the
/// `OPENC3_ENTERPRISE_TOKEN` environment variable. (The GUI stores it in
/// settings.)
pub fn enterprise_token_from_env() -> String {
    std::env::var("OPENC3_ENTERPRISE_TOKEN").unwrap_or_default()
}

/// Install OS-level prerequisites the other installers rely on so the app can
/// run from a fresh OS: a downloader (curl/wget). macOS and Windows ship curl,
/// so this is only meaningful on Linux.
pub fn prerequisites(_ctx: &Context) -> Result<()> {
    ensure_downloader()?;
    Ok(())
}

// ---------------------------------------------------------------------------
// 1. Docker engine
// ---------------------------------------------------------------------------

/// Install a container runtime appropriate for the host platform. This is a
/// best-effort, guided installer: where a fully automated install is unsafe
/// (it usually needs elevated privileges) we run the platform-standard
/// installer and surface clear instructions.
pub fn docker(_ctx: &Context) -> Result<()> {
    if process::which("docker") || process::which("podman") {
        notify("A container runtime is already installed.");
        return Ok(());
    }

    if cfg!(target_os = "macos") {
        install_docker_macos()
    } else if cfg!(target_os = "linux") {
        install_docker_linux()
    } else if cfg!(target_os = "windows") {
        install_docker_windows()
    } else {
        bail!("Automated Docker install is not supported on this platform; install Docker manually.")
    }
}

/// Install Docker Desktop on macOS from Docker's official disk image.
///
/// We deliberately avoid Homebrew here: `brew` shells out to `sudo`, which
/// prompts on a TTY the GUI doesn't have, and the Docker cask fails when its
/// credential-helper binaries already exist (e.g. "already a Binary at
/// /usr/local/bin/docker-credential-osxkeychain").
///
/// Instead we copy Docker.app into /Applications and launch it, letting Docker
/// Desktop perform its own privileged setup on first launch. That setup shows
/// Docker's own branded "Docker Desktop needs privileged access" prompt — much
/// clearer than a generic `osascript` password dialog — and Docker handles any
/// pre-existing credential helpers itself.
pub fn install_docker_macos() -> Result<()> {
    notify(DOCKER_DESKTOP_LICENSE);
    let arch = if cfg!(target_arch = "aarch64") {
        "arm64"
    } else {
        "amd64"
    };
    let url = format!("https://desktop.docker.com/mac/main/{arch}/Docker.dmg");

    let dmg = std::env::temp_dir().join("openc3-Docker.dmg");
    notify("Downloading Docker Desktop (this is a large download)...");
    download::to_file(&url, &dmg)?;

    // Mount the image (no admin needed). Clear any stale mount from a prior
    // attempt first so `attach` doesn't fail on a busy mountpoint.
    let mount = std::env::temp_dir().join("openc3-docker-mount");
    let _ = process::run(Command::new("hdiutil").arg("detach").arg(&mount).arg("-force"));
    notify("Mounting the Docker Desktop image...");
    process::run(
        Command::new("hdiutil")
            .arg("attach")
            .arg("-nobrowse")
            .arg("-mountpoint")
            .arg(&mount)
            .arg(&dmg),
    )?;

    let src = mount.join("Docker.app");
    let dest = "/Applications/Docker.app";
    notify("Installing Docker Desktop into /Applications...");
    let result = copy_app_to_applications(&src, dest);

    // Always unmount and clean up, even if the copy failed.
    let _ = process::run(Command::new("hdiutil").arg("detach").arg(&mount).arg("-force"));
    let _ = std::fs::remove_file(&dmg);
    result?;

    // Clear the download quarantine so Gatekeeper doesn't add an extra prompt.
    let _ = process::run(Command::new("xattr").args(["-dr", "com.apple.quarantine", dest]));

    notify("Launching Docker Desktop...");
    let _ = process::run(Command::new("open").args(["-a", "Docker"]));
    notify_dialog(
        "Docker Desktop installed and launching.\n\
         NEXT STEP: complete Docker's first-run setup (Docker will ask for your password to \
         finish installing), then start COSMOS.",
    );
    Ok(())
}

/// Copy a `.app` bundle into /Applications. Tries a plain copy first — that
/// works for admin users (the common case) with no password prompt at all —
/// and only falls back to an authenticated copy when the user can't write to
/// /Applications. `ditto` preserves the bundle's code signature and metadata.
fn copy_app_to_applications(src: &Path, dest: &str) -> Result<()> {
    let _ = std::fs::remove_dir_all(dest);
    if process::run(Command::new("ditto").arg(src).arg(dest)).is_ok() {
        return Ok(());
    }
    notify("Administrator access is needed to install into /Applications...");
    let cmd = format!("rm -rf '{dest}' && /usr/bin/ditto '{}' '{dest}'", src.display());
    run_with_admin(&cmd)
}

/// Run a shell command as root via a native macOS authentication dialog, so the
/// GUI doesn't need a terminal for the password (unlike `sudo`). Only used as a
/// fallback when the user lacks write access to /Applications.
fn run_with_admin(shell_command: &str) -> Result<()> {
    // Escape for embedding inside the AppleScript double-quoted string.
    let escaped = shell_command.replace('\\', "\\\\").replace('"', "\\\"");
    let script = format!("do shell script \"{escaped}\" with administrator privileges");
    process::run(Command::new("osascript").arg("-e").arg(script))
}

/// Start an already-installed container engine (Docker is installed but its
/// daemon isn't running). On macOS/Windows this launches Docker Desktop; on
/// Linux it starts the docker service. GUI-only (the Setup page's Start Docker).
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn start_docker() -> Result<()> {
    if cfg!(target_os = "macos") {
        notify("Starting Docker Desktop...");
        process::run(Command::new("open").args(["-a", "Docker"]))?;
        notify("Docker Desktop is starting. Wait until it reports it is running.");
        Ok(())
    } else if cfg!(target_os = "windows") {
        // Update WSL before Docker starts — Docker Desktop's WSL2 backend needs
        // a current WSL. Best-effort: ignore the result (WSL absent, already
        // current, offline, etc.) and don't pop a console.
        notify("Updating WSL (if needed)...");
        let mut wsl = Command::new("wsl");
        wsl.arg("--update");
        let _ = process::capture(&mut wsl);
        notify("Starting Docker Desktop...");
        let pf = std::env::var("ProgramFiles").unwrap_or_else(|_| r"C:\Program Files".to_string());
        let exe = format!(r"{pf}\Docker\Docker\Docker Desktop.exe");
        // `start` returns immediately instead of blocking on the GUI app.
        process::run(Command::new("cmd").args(["/C", "start", "", &exe]))?;
        notify("Docker Desktop is starting. Wait until it reports it is running.");
        Ok(())
    } else {
        start_docker_linux_service()
    }
}

/// Start the Docker service on Linux. Prefers a GUI polkit prompt (`pkexec`)
/// so a GUI launch needs no terminal; falls back to sudo, then to instructions.
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
fn start_docker_linux_service() -> Result<()> {
    notify("Starting the Docker service...");
    let mut cmd = if is_root() {
        let mut c = Command::new("systemctl");
        c.args(["start", "docker"]);
        c
    } else if process::which("pkexec") {
        let mut c = Command::new("pkexec");
        c.args(["systemctl", "start", "docker"]);
        c
    } else if process::which("sudo") {
        let mut c = Command::new("sudo");
        c.args(["systemctl", "start", "docker"]);
        c
    } else {
        bail!(
            "Docker is installed but not running.\n\
             MANUAL STEP: start it with  sudo systemctl start docker  then try again."
        );
    };
    process::run(&mut cmd)?;
    notify("Docker service started.");
    Ok(())
}

fn install_docker_linux() -> Result<()> {
    // Use Docker's official convenience script. Requires root; use sudo when
    // not already root.
    ensure_downloader()?;
    let script = download::to_bytes("https://get.docker.com")?;
    let tmp = std::env::temp_dir().join("get-docker.sh");
    std::fs::write(&tmp, &script)?;

    let is_root = is_root();
    let mut cmd = if is_root {
        let mut c = Command::new("sh");
        c.arg(&tmp);
        c
    } else if process::which("sudo") {
        let mut c = Command::new("sudo");
        c.arg("sh").arg(&tmp);
        c
    } else {
        bail!(
            "Installing Docker requires administrator (root) privileges, but 'sudo' was not found.\n\
             MANUAL STEPS: re-run this as the root user, or install Docker Engine manually \
             following https://docs.docker.com/engine/install/ then re-run this installation."
        );
    };
    notify("Running the official Docker install script...");
    process::run(&mut cmd)?;
    add_user_to_docker_group();
    Ok(())
}

/// Add the invoking user to the `docker` group so Docker can be used without
/// sudo. openc3-app itself then reaches Docker via `sg docker` (see
/// docker.rs::group) so it works in this session without an app restart; a
/// plain login shell picks up the group on next login (or `newgrp docker`).
fn add_user_to_docker_group() {
    // The real user — sudo preserves it in SUDO_USER; fall back to USER.
    let user = std::env::var("SUDO_USER")
        .ok()
        .filter(|u| !u.is_empty())
        .or_else(|| std::env::var("USER").ok())
        .unwrap_or_default();
    if user.is_empty() || user == "root" {
        notify("Docker installed. (Running as root — no docker group change needed.)");
        return;
    }
    // Create the group and add the user in a single privileged step (one prompt).
    let script = format!("groupadd -f docker && usermod -aG docker {}", shell_single_quote(&user));
    match run_root_shell(&script) {
        Ok(()) => notify(format!(
            "Docker installed and '{user}' added to the docker group. openc3-app will try to use \
             Docker in this session automatically. For a plain terminal, run `newgrp docker` or \
             start a new login session.",
        )),
        Err(error) => {
            // Common in a GUI launch: no terminal for a sudo password prompt.
            // Give the user the exact commands to run themselves, in a popup.
            crate::logging::warn("install", &format!("docker group add failed: {error:#}"));
            notify_dialog(
                "Docker is installed, but adding you to the 'docker' group needs administrator \
                 rights and couldn't be done automatically.\n\n\
                 Run these in a terminal, then start COSMOS:\n\n  \
                 sudo groupadd docker\n  \
                 sudo usermod -aG docker $USER\n  \
                 newgrp docker\n\n\
                 (Instead of `newgrp docker` you can log out and back in.)",
            );
        }
    }
}

/// Run `shell_cmd` as root suitably for a GUI (windowed) launch: prefer pkexec,
/// whose graphical polkit prompt works without a controlling terminal; then fall
/// back to a NON-interactive sudo (`-n`), which succeeds only with cached or
/// passwordless sudo — a GUI has no terminal to type a password into, so we must
/// not let sudo hang waiting for one. Errors if neither is usable.
fn run_root_shell(shell_cmd: &str) -> Result<()> {
    if is_root() {
        process::run(Command::new("sh").arg("-c").arg(shell_cmd))
    } else if process::which("pkexec") {
        process::run(Command::new("pkexec").arg("sh").arg("-c").arg(shell_cmd))
    } else if process::which("sudo") {
        process::run(Command::new("sudo").arg("-n").arg("sh").arg("-c").arg(shell_cmd))
    } else {
        bail!("neither pkexec nor sudo is available to gain root")
    }
}

/// POSIX single-quote a string so it's safe to embed in a `sh -c` command.
fn shell_single_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

const WINGET_MANUAL: &str = "winget (the Windows Package Manager) was not found, so Docker Desktop \
can't be installed automatically.\n\
MANUAL STEPS:\n  \
1. Install 'App Installer' from the Microsoft Store (it provides winget), or\n  \
2. Install Docker Desktop manually from https://www.docker.com/products/docker-desktop/\n  \
then re-run this installation.";

/// Install Docker Desktop on Windows via winget. Windows offers Docker Desktop
/// only (the simplest turnkey option); users who need a free alternative can
/// install Podman or Rancher Desktop manually.
pub fn install_docker_windows() -> Result<()> {
    if !process::which("winget") {
        bail!("{WINGET_MANUAL}");
    }
    notify(DOCKER_DESKTOP_LICENSE);
    notify("Installing Docker Desktop via winget...");
    winget_install("Docker.DockerDesktop")?;
    notify_dialog(
        "Docker Desktop installed.\n\
         NEXT STEPS:\n  \
         1. Reboot if Windows prompts you to.\n  \
         2. Launch Docker Desktop and complete first-run setup (enable WSL2 if asked).\n  \
         3. Wait until Docker reports it is running, then start COSMOS.",
    );
    Ok(())
}

/// `winget install -e --id <id>` accepting agreements.
fn winget_install(id: &str) -> Result<()> {
    process::run(Command::new("winget").args([
        "install",
        "-e",
        "--id",
        id,
        "--accept-package-agreements",
        "--accept-source-agreements",
    ]))
}

// ---------------------------------------------------------------------------
// Windows optional features (the WSL2 / virtualization stack Docker needs)
// ---------------------------------------------------------------------------

/// Windows optional features Docker Desktop's WSL2 backend and virtualization
/// depend on. The first element is the DISM / Win32_OptionalFeature name; the
/// second is a human label for the UI.
#[cfg(windows)]
const WINDOWS_FEATURES: [(&str, &str); 3] = [
    ("VirtualMachinePlatform", "Virtual Machine Platform"),
    ("HypervisorPlatform", "Windows Hypervisor Platform"),
    ("Microsoft-Windows-Subsystem-Linux", "Windows Subsystem for Linux"),
];

/// The required Windows features that are not currently enabled, as (name,
/// label) pairs. Queried via the `Win32_OptionalFeature` WMI class, which
/// standard users can read without elevation (no UAC prompt), so it's safe to
/// call on every launch. Always empty off Windows.
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn missing_windows_features() -> Vec<&'static str> {
    #[cfg(windows)]
    {
        // Iterate the array by value (each item is (&'static str, &'static str)).
        let mut missing = Vec::new();
        for (name, label) in WINDOWS_FEATURES {
            if !feature_enabled(name) {
                missing.push(label);
            }
        }
        missing
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}

/// True if a Win32_OptionalFeature is Enabled (InstallState 1). Read-only WMI
/// query — no elevation needed.
#[cfg(windows)]
fn feature_enabled(name: &str) -> bool {
    let mut cmd = Command::new("powershell");
    cmd.args([
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        &format!(
            "(Get-CimInstance -ClassName Win32_OptionalFeature -Filter \"Name='{name}'\").InstallState"
        ),
    ]);
    match process::capture(&mut cmd) {
        // InstallState: 1 = Enabled, 2 = Disabled, 3 = Absent.
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).trim() == "1",
        _ => false,
    }
}

/// Enable the required Windows features (Virtual Machine Platform, Windows
/// Hypervisor Platform, WSL). Enabling needs administrator rights, so this
/// elevates a PowerShell that runs `Enable-WindowsOptionalFeature` for each
/// (idempotent — already-enabled features are a no-op). A restart is required
/// afterward for the changes to take effect. No-op off Windows.
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn enable_windows_features() -> Result<()> {
    #[cfg(windows)]
    {
        notify("Enabling required Windows features (Virtual Machine Platform, Windows Hypervisor Platform, WSL)...");
        notify("Windows will ask for administrator permission.");
        // Write a small script and run it elevated. A file avoids fragile nested
        // PowerShell quoting through Start-Process -Verb RunAs.
        let script = "\
$ErrorActionPreference = 'Stop'\r\n\
$features = @('VirtualMachinePlatform','HypervisorPlatform','Microsoft-Windows-Subsystem-Linux')\r\n\
foreach ($f in $features) {\r\n\
    Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart | Out-Null\r\n\
}\r\n";
        let path = std::env::temp_dir().join("openc3_enable_features.ps1");
        std::fs::write(&path, script).context("writing feature-enable script")?;
        let path_str = path.to_string_lossy().replace('\'', "''");
        // Elevate: launch the script with RunAs, wait, and propagate its exit
        // code so a cancelled UAC prompt surfaces as an error.
        let outer = format!(
            "$p = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList \
             '-NoProfile','-ExecutionPolicy','Bypass','-File','{path_str}'; exit $p.ExitCode"
        );
        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-Command", &outer]);
        let result = process::run(&mut cmd);
        let _ = std::fs::remove_file(&path);
        result.context(
            "enabling Windows features (administrator permission is required; the prompt may have been declined)",
        )?;
        notify(
            "Windows features enabled.\n\
             IMPORTANT: RESTART Windows for the changes to take effect, then launch Docker Desktop \
             and complete its first-run setup.",
        );
        Ok(())
    }
    #[cfg(not(windows))]
    {
        Ok(())
    }
}

/// Restart Windows (`shutdown /r /t 0`) so newly-enabled optional features take
/// effect. Interactive users can restart without elevation. No-op off Windows.
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn restart_windows() -> Result<()> {
    #[cfg(windows)]
    {
        notify("Restarting Windows...");
        process::run(Command::new("shutdown").args(["/r", "/t", "0"]))?;
        Ok(())
    }
    #[cfg(not(windows))]
    {
        Ok(())
    }
}

/// Whether hardware virtualization (Intel VT-x / AMD-V/SVM) is enabled in the
/// BIOS/UEFI — a hard requirement for Docker's WSL2/Hyper-V backend that the app
/// cannot turn on itself (it's a firmware setting). `Some(true)` = enabled (or a
/// hypervisor is already running on it), `Some(false)` = present but disabled in
/// firmware, `None` = unknown/not determinable. Read-only WMI (no elevation).
/// Always `None` off Windows.
#[cfg_attr(not(feature = "gui"), allow(dead_code))]
pub fn virtualization_enabled() -> Option<bool> {
    #[cfg(windows)]
    {
        // If a hypervisor is already present, virtualization is clearly on (and
        // Win32_Processor.VirtualizationFirmwareEnabled becomes unreliable once
        // Hyper-V owns the CPU), so check that first. Otherwise fall back to the
        // per-processor firmware flag: true -> enabled, false -> disabled in
        // BIOS, neither -> unknown (property not populated).
        let mut cmd = Command::new("powershell");
        cmd.args([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "$cs=Get-CimInstance Win32_ComputerSystem; \
             if($cs.HypervisorPresent){'enabled'} \
             else { $v=@(Get-CimInstance Win32_Processor | ForEach-Object { $_.VirtualizationFirmwareEnabled }); \
             if($v -contains $true){'enabled'} elseif($v -contains $false){'disabled'} else {'unknown'} }",
        ]);
        match process::capture(&mut cmd) {
            Ok(out) if out.status.success() => match String::from_utf8_lossy(&out.stdout).trim() {
                "enabled" => Some(true),
                "disabled" => Some(false),
                _ => None,
            },
            _ => None,
        }
    }
    #[cfg(not(windows))]
    {
        None
    }
}

// ---------------------------------------------------------------------------
// Prerequisite bootstrapping
// ---------------------------------------------------------------------------

/// Ensure a downloader (curl or wget) is available, since every install step
/// fetches something. macOS and Windows ship curl; on Linux we install it with
/// the system package manager if it's missing.
fn ensure_downloader() -> Result<()> {
    if process::which("curl") || process::which("wget") {
        return Ok(());
    }
    if cfg!(target_os = "linux") {
        notify("Installing curl (required to download components)...");
        install_linux_package("curl")?;
        if process::which("curl") || process::which("wget") {
            return Ok(());
        }
    }
    bail!(
        "A downloader (curl or wget) is required but isn't installed and couldn't be added \
         automatically.\n\
         MANUAL STEP: install curl with your package manager, e.g.\n  \
         sudo apt-get install -y curl     (Debian/Ubuntu)\n  \
         sudo dnf install -y curl         (Fedora/RHEL)\n\
         then re-run this installation."
    )
}

/// Install a package using whichever Linux package manager is present, using
/// sudo when not already root.
fn install_linux_package(pkg: &str) -> Result<()> {
    let use_sudo = !is_root() && process::which("sudo");
    let run_pm = |args: &[&str]| -> Result<()> {
        let mut cmd = if use_sudo {
            let mut c = Command::new("sudo");
            c.args(args);
            c
        } else {
            let mut c = Command::new(args[0]);
            c.args(&args[1..]);
            c
        };
        process::run(&mut cmd)
    };

    if process::which("apt-get") {
        let _ = run_pm(&["apt-get", "update"]);
        run_pm(&["apt-get", "install", "-y", pkg, "ca-certificates"])
    } else if process::which("dnf") {
        run_pm(&["dnf", "install", "-y", pkg])
    } else if process::which("yum") {
        run_pm(&["yum", "install", "-y", pkg])
    } else if process::which("pacman") {
        run_pm(&["pacman", "-Sy", "--noconfirm", pkg])
    } else if process::which("zypper") {
        run_pm(&["zypper", "--non-interactive", "install", pkg])
    } else if process::which("apk") {
        run_pm(&["apk", "add", pkg])
    } else {
        bail!(
            "Could not find a supported package manager to install '{pkg}'.\n\
             MANUAL STEP: install '{pkg}' using your distribution's package manager, then re-run."
        )
    }
}

// ---------------------------------------------------------------------------
// 2. Isolated Python runtime
// ---------------------------------------------------------------------------

/// Install an isolated Python runtime under `<root>/python` using the `uv`
/// package manager (matching the COSMOS project's tooling). The uv binary is
/// downloaded into `<root>/bin`, the interpreter is installed under
/// `<root>/python/runtimes`, and a ready-to-use virtual environment is created
/// at `<root>/python/venv`.
pub fn python(ctx: &Context) -> Result<()> {
    ensure_downloader()?;
    let uv = ensure_uv(ctx)?;
    let runtimes = ctx.paths.python.join("runtimes");
    let venv = ctx.paths.python.join("venv");
    std::fs::create_dir_all(&runtimes).ok();

    // Keep everything self-contained within the app's python/ subfolder.
    let install_dir = runtimes.clone();
    let cache = ctx.paths.python.join("cache");

    notify(format!("Installing Python {DEFAULT_PYTHON} into {}", runtimes.display()));
    let mut install = Command::new(&uv);
    install
        .args(["python", "install", DEFAULT_PYTHON])
        .env("UV_PYTHON_INSTALL_DIR", &install_dir)
        .env("UV_CACHE_DIR", &cache);
    process::run(&mut install)?;

    notify(format!("Creating virtual environment at {}", venv.display()));
    let mut mkvenv = Command::new(&uv);
    mkvenv
        .args(["venv", "--python", DEFAULT_PYTHON])
        .arg(&venv)
        .env("UV_PYTHON_INSTALL_DIR", &install_dir)
        .env("UV_CACHE_DIR", &cache);
    process::run(&mut mkvenv)?;

    // Note: the bridge `iroh` package is installed per-microservice into each
    // service's own venv by the operator, not into this base venv.

    notify(format!(
        "Isolated Python environment ready at {}",
        ctx.paths.python.display()
    ));
    Ok(())
}

/// Ensure the `uv` binary exists under `<root>/bin`, downloading the standalone
/// build for this platform if necessary. Returns the path to the binary.
pub fn ensure_uv(ctx: &Context) -> Result<PathBuf> {
    let bin_name = if cfg!(windows) { "uv.exe" } else { "uv" };
    let dest = ctx.paths.bin.join(bin_name);
    if dest.exists() {
        return Ok(dest);
    }
    std::fs::create_dir_all(&ctx.paths.bin).ok();

    let target = uv_target()?;
    let (asset, is_zip) = if cfg!(windows) {
        (format!("uv-{target}.zip"), true)
    } else {
        (format!("uv-{target}.tar.gz"), false)
    };
    let url = format!("{UV_VERSION_URL_BASE}/{asset}");
    let bytes = download::to_bytes(&url)?;

    let stage = ctx.paths.bin.join(".uv-stage");
    let _ = std::fs::remove_dir_all(&stage);
    if is_zip {
        download::extract_zip(&bytes, &stage)?;
    } else {
        download::extract_tar_gz(&bytes, &stage)?;
    }

    // Archives contain a `uv-<target>/` directory with the binaries inside.
    let inner = stage.join(format!("uv-{target}"));
    let search_dir = if inner.is_dir() { inner } else { stage.clone() };
    for name in [bin_name, if cfg!(windows) { "uvx.exe" } else { "uvx" }] {
        let src = search_dir.join(name);
        if src.exists() {
            std::fs::rename(&src, ctx.paths.bin.join(name))
                .or_else(|_| std::fs::copy(&src, ctx.paths.bin.join(name)).map(|_| ()))?;
        }
    }
    let _ = std::fs::remove_dir_all(&stage);

    if !dest.exists() {
        bail!("failed to install uv from {url}");
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755)).ok();
    }
    Ok(dest)
}

fn uv_target() -> Result<String> {
    let arch = if cfg!(target_arch = "x86_64") {
        "x86_64"
    } else if cfg!(target_arch = "aarch64") {
        "aarch64"
    } else {
        bail!("unsupported CPU architecture for uv download");
    };
    let triple = if cfg!(target_os = "macos") {
        format!("{arch}-apple-darwin")
    } else if cfg!(target_os = "windows") {
        format!("{arch}-pc-windows-msvc")
    } else if cfg!(target_os = "linux") {
        format!("{arch}-unknown-linux-gnu")
    } else {
        bail!("unsupported OS for uv download");
    };
    Ok(triple)
}

// ---------------------------------------------------------------------------
// 3. COSMOS environment
// ---------------------------------------------------------------------------

/// Download and lay out the OpenC3 COSMOS environment under `<root>/cosmos`.
///
/// `enterprise` selects COSMOS Enterprise (a private Forgejo repo), which
/// requires `token` (a repos.openc3.com access token); Core downloads from the
/// public GitHub `cosmos-project`.
pub fn cosmos(ctx: &Context, tag: &str, enterprise: bool, token: &str) -> Result<()> {
    ensure_downloader()?;
    if ctx.paths.cosmos_installed() {
        notify(format!(
            "COSMOS already installed at {}. Skipping download.",
            ctx.paths.cosmos.display()
        ));
        return setup_cosmos(ctx);
    }

    let bytes = if enterprise {
        if token.trim().is_empty() {
            bail!(
                "COSMOS Enterprise requires a repos.openc3.com access token.\n\
                 Enter it in Settings (or the Setup page) and try again."
            );
        }
        // The Gitea API archive endpoint takes a branch or tag as the ref.
        let git_ref = if tag == "latest" { "main" } else { tag };
        let url = format!("{ENTERPRISE_ARCHIVE_BASE}/{git_ref}.tar.gz");
        notify("Downloading COSMOS Enterprise...");
        download::to_bytes_auth(&url, token).context(
            "downloading COSMOS Enterprise (check your access token has read access to the repo)",
        )?
    } else {
        let url = if tag == "latest" {
            format!("{COSMOS_PROJECT_REPO}/archive/refs/heads/main.tar.gz")
        } else {
            format!("{COSMOS_PROJECT_REPO}/archive/refs/tags/{tag}.tar.gz")
        };
        notify("Downloading COSMOS Core...");
        download::to_bytes(&url)?
    };

    let stage = ctx.paths.root.join(".cosmos-stage");
    let _ = std::fs::remove_dir_all(&stage);
    download::extract_tar_gz(&bytes, &stage)?;
    let inner = download::single_subdir(&stage)
        .context("locating extracted cosmos-project directory")?;

    std::fs::create_dir_all(&ctx.paths.cosmos).ok();
    move_dir_contents(&inner, &ctx.paths.cosmos)?;
    let _ = std::fs::remove_dir_all(&stage);

    notify(format!(
        "COSMOS environment installed at {}",
        ctx.paths.cosmos.display()
    ));
    setup_cosmos(ctx)
}

/// Equivalent of `openc3_setup.sh`: ensure cacert.pem exists and is copied into
/// each service directory that expects it.
pub fn setup_cosmos(ctx: &Context) -> Result<()> {
    let cacert = ctx.paths.cosmos.join("cacert.pem");
    if !cacert.exists() {
        if let Some(ssl_file) = std::env::var_os("SSL_CERT_FILE") {
            std::fs::copy(&ssl_file, &cacert).with_context(|| {
                format!("copying SSL_CERT_FILE to {}", cacert.display())
            })?;
        } else {
            download::to_file(CACERT_URL, &cacert)?;
        }
    }
    for sub in [
        "openc3-ruby",
        "openc3-redis",
        "openc3-traefik",
        "openc3-buckets",
        "openc3-tsdb",
    ] {
        let dir = ctx.paths.cosmos.join(sub);
        if dir.is_dir() {
            std::fs::copy(&cacert, dir.join("cacert.pem")).ok();
        }
    }
    Ok(())
}

fn move_dir_contents(from: &Path, to: &Path) -> Result<()> {
    for entry in std::fs::read_dir(from)? {
        let entry = entry?;
        let target = to.join(entry.file_name());
        // rename is atomic when on the same filesystem; fall back to copy.
        if std::fs::rename(entry.path(), &target).is_err() {
            copy_recursive(&entry.path(), &target)?;
        }
    }
    Ok(())
}

fn copy_recursive(from: &Path, to: &Path) -> Result<()> {
    if from.is_dir() {
        std::fs::create_dir_all(to).ok();
        for entry in std::fs::read_dir(from)? {
            let entry = entry?;
            copy_recursive(&entry.path(), &to.join(entry.file_name()))?;
        }
    } else {
        if let Some(parent) = to.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        std::fs::copy(from, to)?;
    }
    Ok(())
}

#[cfg(unix)]
fn is_root() -> bool {
    std::process::Command::new("id")
        .arg("-u")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim() == "0")
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_root() -> bool {
    false
}
