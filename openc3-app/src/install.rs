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
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

thread_local! {
    /// Optional sink for user-facing install messages on the current thread.
    static NOTIFIER: RefCell<Option<Box<dyn Fn(String)>>> = const { RefCell::new(None) };
}

/// Route user-facing install messages emitted by [`notify`] to `sink` on the
/// current thread. The GUI uses this to mirror messages into its activity log;
/// when no sink is set (the CLI), messages are printed to stdout.
#[cfg(feature = "gui")]
pub fn set_notifier(sink: Box<dyn Fn(String)>) {
    NOTIFIER.with(|n| *n.borrow_mut() = Some(sink));
}

/// Remove any notifier set for the current thread.
#[cfg(feature = "gui")]
pub fn clear_notifier() {
    NOTIFIER.with(|n| *n.borrow_mut() = None);
}

/// Emit a user-facing message: to the thread's notifier if set, else stdout.
fn notify(msg: impl Into<String>) {
    let msg = msg.into();
    NOTIFIER.with(|n| match n.borrow().as_ref() {
        Some(sink) => sink(msg),
        None => println!("{msg}"),
    });
}

/// Which Docker engine to install on macOS.
#[derive(Clone, Copy, Debug)]
pub enum MacEngine {
    /// Lightweight, CLI-only engine (colima + docker CLI + docker-compose).
    Colima,
    /// Full Docker Desktop application.
    DockerDesktop,
}

/// Which container engine to install on Windows.
#[derive(Clone, Copy, Debug)]
pub enum WinEngine {
    /// Docker Desktop (turnkey; see licensing note).
    DockerDesktop,
    /// Podman (free, no Desktop; uses WSL2).
    Podman,
    /// Rancher Desktop configured with the dockerd/moby engine (free; WSL2).
    RancherDesktop,
}

/// Docker Desktop licensing caveat, surfaced wherever Docker Desktop is offered.
pub const DOCKER_DESKTOP_LICENSE: &str = "Note: Docker Desktop requires a paid Docker subscription \
for organizations with more than 250 employees OR more than $10 million in annual revenue. \
The free alternatives (colima on macOS; Podman or Rancher Desktop on Windows) avoid this.";

const UV_VERSION_URL_BASE: &str = "https://github.com/astral-sh/uv/releases/latest/download";
const CACERT_URL: &str = "https://curl.se/ca/cacert.pem";
const COSMOS_PROJECT_REPO: &str = "https://github.com/OpenC3/cosmos-project";
const DEFAULT_PYTHON: &str = "3.12";

/// Install everything in dependency order.
pub fn all(ctx: &Context) -> Result<()> {
    prerequisites(ctx)?;
    docker(ctx)?;
    python(ctx)?;
    cosmos(ctx, "latest")?;
    Ok(())
}

/// Install OS-level prerequisites the other installers rely on so the app can
/// run from a fresh OS: a downloader (curl/wget) on every platform, and
/// Homebrew on macOS (which also pulls in the Command Line Tools).
pub fn prerequisites(_ctx: &Context) -> Result<()> {
    ensure_downloader()?;
    if cfg!(target_os = "macos") {
        ensure_homebrew()?;
    }
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
        // CLI path: ask the user which engine they want.
        let engine = prompt_mac_engine()?;
        install_docker_macos(engine)
    } else if cfg!(target_os = "linux") {
        install_docker_linux()
    } else if cfg!(target_os = "windows") {
        // CLI path: ask the user which engine they want.
        let engine = prompt_win_engine()?;
        install_docker_windows(engine)
    } else {
        bail!("Automated Docker install is not supported on this platform; install Docker manually.")
    }
}

/// Prompt (on the CLI) for which macOS Docker engine to install. Defaults to
/// colima on an empty response.
fn prompt_mac_engine() -> Result<MacEngine> {
    println!("Choose a Docker engine for macOS:");
    println!("  1) colima         — lightweight, CLI-only (recommended)");
    println!("  2) Docker Desktop — full GUI application");
    println!("{DOCKER_DESKTOP_LICENSE}");
    print!("Enter 1 or 2 [1]: ");
    io::stdout().flush().ok();
    let mut line = String::new();
    io::stdin().read_line(&mut line).ok();
    match line.trim() {
        "2" => Ok(MacEngine::DockerDesktop),
        _ => Ok(MacEngine::Colima),
    }
}

/// Prompt (on the CLI) for which Windows container engine to install. Defaults
/// to Docker Desktop on an empty response.
fn prompt_win_engine() -> Result<WinEngine> {
    println!("Choose a container engine for Windows:");
    println!("  1) Docker Desktop  — turnkey GUI app (see licensing note)");
    println!("  2) Podman          — free, no Desktop (uses WSL2)");
    println!("  3) Rancher Desktop — free, dockerd/moby engine (uses WSL2)");
    println!("{DOCKER_DESKTOP_LICENSE}");
    print!("Enter 1, 2, or 3 [1]: ");
    io::stdout().flush().ok();
    let mut line = String::new();
    io::stdin().read_line(&mut line).ok();
    match line.trim() {
        "2" => Ok(WinEngine::Podman),
        "3" => Ok(WinEngine::RancherDesktop),
        _ => Ok(WinEngine::DockerDesktop),
    }
}

/// Install the chosen Docker engine on macOS via Homebrew, installing Homebrew
/// itself first if necessary.
pub fn install_docker_macos(engine: MacEngine) -> Result<()> {
    let brew = ensure_homebrew()?;
    match engine {
        MacEngine::Colima => {
            notify("Installing colima + docker via Homebrew...");
            process::run(
                Command::new(&brew).args(["install", "colima", "docker", "docker-compose"]),
            )?;
            notify("Starting colima...");
            // colima may not be on PATH yet; prefer the binary next to brew.
            let colima = brew
                .parent()
                .map(|d| d.join("colima"))
                .filter(|p| p.exists())
                .or_else(|| process::which_path("colima"))
                .unwrap_or_else(|| PathBuf::from("colima"));
            process::run(Command::new(&colima).arg("start"))?;
            notify("Docker (colima) is installed and running.");
        }
        MacEngine::DockerDesktop => {
            notify(DOCKER_DESKTOP_LICENSE);
            notify("Installing Docker Desktop via Homebrew...");
            process::run(Command::new(&brew).args(["install", "--cask", "docker"]))?;
            notify("Launching Docker Desktop...");
            // Best effort: the first launch may require completing setup in the UI.
            let _ = process::run(Command::new("open").args(["-a", "Docker"]));
            notify(
                "Docker Desktop installed and launching.\n\
                 NEXT STEP: complete first-run setup in the Docker Desktop window (you may be \
                 asked to grant privileges). Wait until Docker reports 'running' before starting \
                 COSMOS.",
            );
        }
    }
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
    // Ensure the group exists, then add the user. Both need root (use sudo when
    // we aren't already root, as the install script itself did).
    let steps: [&[&str]; 2] = [&["groupadd", "-f", "docker"], &["usermod", "-aG", "docker", &user]];
    for step in steps {
        let mut cmd = if is_root() {
            let mut c = Command::new(step[0]);
            c.args(&step[1..]);
            c
        } else {
            let mut c = Command::new("sudo");
            c.args(step);
            c
        };
        if let Err(error) = process::run(&mut cmd) {
            notify(&format!(
                "Docker installed, but adding '{user}' to the docker group failed ({error}).\n\
                 MANUAL STEP: run  sudo usermod -aG docker {user}  then log out and back in.",
            ));
            return;
        }
    }
    notify(&format!(
        "Docker installed and '{user}' added to the docker group. openc3-app will use \
         Docker in this session automatically (no restart needed). For a plain terminal, \
         run `newgrp docker` or start a new login session.",
    ));
}

const WINGET_MANUAL: &str = "winget (the Windows Package Manager) was not found, so the engine \
can't be installed automatically.\n\
MANUAL STEPS:\n  \
1. Install 'App Installer' from the Microsoft Store (it provides winget), or\n  \
2. Install your chosen engine manually:\n       \
Docker Desktop: https://www.docker.com/products/docker-desktop/\n       \
Podman: https://podman.io/\n       \
Rancher Desktop: https://rancherdesktop.io/\n  \
then re-run this installation.";

/// Install the chosen container engine on Windows via winget.
pub fn install_docker_windows(engine: WinEngine) -> Result<()> {
    if !process::which("winget") {
        bail!("{WINGET_MANUAL}");
    }
    match engine {
        WinEngine::DockerDesktop => {
            notify(DOCKER_DESKTOP_LICENSE);
            notify("Installing Docker Desktop via winget...");
            winget_install("Docker.DockerDesktop")?;
            notify(
                "Docker Desktop installed.\n\
                 NEXT STEPS:\n  \
                 1. Reboot if Windows prompts you to.\n  \
                 2. Launch Docker Desktop and complete first-run setup (enable WSL2 if asked).\n  \
                 3. Wait until Docker reports it is running, then start COSMOS.",
            );
        }
        WinEngine::Podman => {
            notify("Installing Podman via winget...");
            winget_install("RedHat.Podman")?;
            if setup_podman_machine() {
                notify(
                    "Podman installed and the Podman machine started.\n\
                     NOTE: `podman compose` needs a Compose provider. If COSMOS fails to start, \
                     install Docker Compose v2 and ensure it is on PATH.",
                );
            } else {
                notify(
                    "Podman installed.\n\
                     NEXT STEPS (open a NEW terminal so PATH picks up podman):\n  \
                     podman machine init\n  \
                     podman machine start\n\
                     Also ensure a Compose provider is available (`podman compose` uses \
                     docker-compose if present), then start COSMOS.",
                );
            }
        }
        WinEngine::RancherDesktop => {
            notify("Installing Rancher Desktop via winget...");
            winget_install("suse.RancherDesktop")?;
            if setup_rancher_moby() {
                notify(
                    "Rancher Desktop installed and started with the dockerd (moby) engine.\n\
                     NOTE: first start can take a few minutes while it provisions WSL2.",
                );
            } else {
                notify(
                    "Rancher Desktop installed.\n\
                     NEXT STEPS: launch Rancher Desktop, and in Preferences set the Container \
                     Engine to 'dockerd (moby)' (NOT containerd) so the `docker` CLI is \
                     available, then start COSMOS.",
                );
            }
        }
    }
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

/// Candidate base directories for Windows program installs.
fn windows_program_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    for var in ["ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"] {
        if let Some(v) = std::env::var_os(var) {
            dirs.push(PathBuf::from(v));
        }
    }
    dirs
}

/// Find a Windows executable on PATH or under known install locations. Needed
/// because a freshly winget-installed tool isn't on the current process's PATH.
fn find_windows_exe(name: &str, relative_candidates: &[&str]) -> Option<PathBuf> {
    if let Some(p) = process::which_path(name) {
        return Some(p);
    }
    for base in windows_program_dirs() {
        for rel in relative_candidates {
            let p = base.join(rel);
            if p.exists() {
                return Some(p);
            }
        }
    }
    None
}

/// Best-effort: initialize and start the Podman machine. Returns true on success.
fn setup_podman_machine() -> bool {
    let Some(podman) = find_windows_exe("podman", &["RedHat\\Podman\\podman.exe"]) else {
        return false;
    };
    // `machine init` fails if a machine already exists; ignore that case.
    let _ = process::run(Command::new(&podman).args(["machine", "init"]));
    process::run(Command::new(&podman).args(["machine", "start"])).is_ok()
}

/// Best-effort: start Rancher Desktop with the moby engine and Kubernetes off.
/// Returns true on success.
fn setup_rancher_moby() -> bool {
    let candidates = [
        "Rancher Desktop\\resources\\resources\\win32\\bin\\rdctl.exe",
        "Programs\\Rancher Desktop\\resources\\resources\\win32\\bin\\rdctl.exe",
    ];
    let Some(rdctl) = find_windows_exe("rdctl", &candidates) else {
        return false;
    };
    // Current releases use dotted flags; fall back to the older flag name.
    if process::run(Command::new(&rdctl).args([
        "start",
        "--container-engine.name",
        "moby",
        "--kubernetes.enabled=false",
    ]))
    .is_ok()
    {
        return true;
    }
    process::run(Command::new(&rdctl).args(["start", "--container-engine", "moby"])).is_ok()
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

/// Clear manual instructions shown when Homebrew can't be installed automatically.
const HOMEBREW_MANUAL: &str = "Homebrew is required to install Docker on macOS but could not be \
installed automatically (it needs administrator rights and the Command Line Tools).\n\
MANUAL STEPS:\n  \
1. Open the Terminal app (Applications > Utilities > Terminal).\n  \
2. Paste and run this command:\n       \
/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n  \
3. Enter your password when prompted, let it finish, then re-run this installation.\n\
Alternatively, install Docker Desktop manually from https://www.docker.com/products/docker-desktop/";

/// Return the path to the `brew` binary, installing Homebrew if it is missing.
/// If the automatic install isn't possible, returns an error containing clear
/// manual steps for the user.
fn ensure_homebrew() -> Result<PathBuf> {
    if let Some(p) = brew_path() {
        return Ok(p);
    }
    notify("Homebrew not found; attempting to install it (this can take several minutes)...");
    if bootstrap_homebrew().is_err() {
        bail!("{HOMEBREW_MANUAL}");
    }
    brew_path().ok_or_else(|| anyhow::anyhow!("{HOMEBREW_MANUAL}"))
}

/// Run Homebrew's official non-interactive installer (also installs the Command
/// Line Tools). Fetches itself with curl, which is present on macOS.
fn bootstrap_homebrew() -> Result<()> {
    let script = download::to_bytes(
        "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh",
    )?;
    let tmp = std::env::temp_dir().join("install-homebrew.sh");
    std::fs::write(&tmp, &script)?;
    let mut cmd = Command::new("/bin/bash");
    cmd.arg(&tmp).env("NONINTERACTIVE", "1");
    process::run(&mut cmd)
}

/// Locate the `brew` executable on PATH or in its standard install locations.
fn brew_path() -> Option<PathBuf> {
    if let Some(p) = process::which_path("brew") {
        return Some(p);
    }
    for candidate in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
        let p = PathBuf::from(candidate);
        if p.exists() {
            return Some(p);
        }
    }
    None
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
pub fn cosmos(ctx: &Context, tag: &str) -> Result<()> {
    ensure_downloader()?;
    if ctx.paths.cosmos_installed() {
        notify(format!(
            "COSMOS already installed at {}. Skipping download.",
            ctx.paths.cosmos.display()
        ));
        return setup_cosmos(ctx);
    }

    let url = if tag == "latest" {
        format!("{COSMOS_PROJECT_REPO}/archive/refs/heads/main.tar.gz")
    } else {
        format!("{COSMOS_PROJECT_REPO}/archive/refs/tags/{tag}.tar.gz")
    };
    let bytes = download::to_bytes(&url)?;

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
