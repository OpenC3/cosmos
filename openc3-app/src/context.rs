//! Application context: resolved filesystem layout and detected container
//! runtime. Built once at startup and shared by the CLI and GUI.

use anyhow::{Context as _, Result};
use std::path::{Path, PathBuf};

/// Where installed components live, all relative to a single application root
/// so the install is self-contained and relocatable.
#[derive(Clone, Debug)]
pub struct Paths {
    /// Application root (defaults to the directory containing the executable).
    pub root: PathBuf,
    /// Isolated Python runtime (requirement #2).
    pub python: PathBuf,
    /// COSMOS environment: compose.yaml, .env and support dirs (requirement #3).
    pub cosmos: PathBuf,
    /// Downloaded helper tools (uv, portable docker, etc.).
    pub bin: PathBuf,
    /// Per-microservice working directories (`microservices/<name>/`).
    pub microservices: PathBuf,
}

impl Paths {
    pub fn resolve(root_override: Option<PathBuf>) -> Result<Self> {
        let root = match root_override {
            Some(r) => r,
            None => match std::env::var_os("OPENC3_APP_HOME") {
                Some(v) => PathBuf::from(v),
                None => default_root()?,
            },
        };
        let root = absolute(&root);
        Ok(Self {
            python: root.join("python"),
            cosmos: root.join("cosmos"),
            bin: root.join("bin"),
            microservices: root.join("microservices"),
            root,
        })
    }

    /// Path to the COSMOS compose file.
    pub fn compose_file(&self) -> PathBuf {
        self.cosmos.join("compose.yaml")
    }

    pub fn compose_build_file(&self) -> PathBuf {
        self.cosmos.join("compose-build.yaml")
    }

    pub fn env_file(&self) -> PathBuf {
        self.cosmos.join(".env")
    }

    /// True if the COSMOS environment appears to be installed.
    pub fn cosmos_installed(&self) -> bool {
        self.compose_file().exists()
    }

    /// True if the isolated Python runtime has been installed under `python/`.
    pub fn python_installed(&self) -> bool {
        self.python.join("venv").is_dir() || self.python.join("runtimes").is_dir()
    }

    /// True if this is a development install (has a build compose file).
    pub fn is_devel(&self) -> bool {
        self.compose_build_file().exists()
    }
}

/// Determine the default application root.
///
/// Resolution order:
///   1. Cargo dev build (exe under `target/`) → the current working directory,
///      so installs don't litter the build tree.
///   2. Packaged/installed app (inside a macOS `.app` bundle, or anywhere the
///      executable's directory isn't writable, e.g. `/Applications`,
///      `Program Files`, `/usr`) → a per-user data directory. This avoids
///      writing into a code-signed/read-only bundle or a system path.
///   3. Otherwise (a portable install in a writable folder) → the directory
///      containing the executable, keeping components beside the binary.
fn default_root() -> Result<PathBuf> {
    let exe = std::env::current_exe().context("locating current executable")?;
    let dir = exe
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."));

    let is_target = dir
        .components()
        .any(|c| c.as_os_str() == "target" || c.as_os_str() == "deps");
    if is_target {
        return Ok(std::env::current_dir().unwrap_or(dir));
    }

    if in_app_bundle(&dir) || !dir_writable(&dir) {
        let data = user_data_dir();
        std::fs::create_dir_all(&data).ok();
        return Ok(data);
    }

    Ok(dir)
}

/// True if `dir` is inside a macOS application bundle (`.../Foo.app/...`).
fn in_app_bundle(dir: &Path) -> bool {
    dir.components()
        .any(|c| c.as_os_str().to_string_lossy().ends_with(".app"))
}

/// Probe whether `dir` is writable by creating and removing a temp file.
fn dir_writable(dir: &Path) -> bool {
    let probe = dir.join(".openc3-write-test");
    match std::fs::File::create(&probe) {
        Ok(_) => {
            let _ = std::fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

/// Per-user, writable data directory for an installed app:
///   macOS:   ~/Library/Application Support/OpenC3
///   Windows: %APPDATA%\OpenC3
///   Linux:   $XDG_DATA_HOME/openc3 (or ~/.local/share/openc3)
fn user_data_dir() -> PathBuf {
    if cfg!(target_os = "macos") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join("Library/Application Support/OpenC3");
        }
    } else if cfg!(target_os = "windows") {
        if let Some(appdata) = std::env::var_os("APPDATA") {
            return PathBuf::from(appdata).join("OpenC3");
        }
    } else {
        if let Some(xdg) = std::env::var_os("XDG_DATA_HOME") {
            return PathBuf::from(xdg).join("openc3");
        }
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(".local/share/openc3");
        }
    }
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn absolute(p: &Path) -> PathBuf {
    if p.is_absolute() {
        p.to_path_buf()
    } else {
        std::env::current_dir()
            .map(|c| c.join(p))
            .unwrap_or_else(|_| p.to_path_buf())
    }
}

/// The container runtime in use (Docker or Podman) and how to invoke compose.
#[derive(Clone, Debug)]
pub struct Runtime {
    /// Base container command, e.g. "docker" or "podman".
    pub engine: String,
    /// Compose invocation, e.g. ["docker", "compose"] or ["docker-compose"].
    pub compose: Vec<String>,
    /// Whether the engine is running rootless (affects user mapping).
    pub rootless: bool,
    /// Effective user id to pass to containers (rootful only).
    pub user_id: u32,
    /// Effective group id to pass to containers (rootful only).
    pub group_id: u32,
}

impl Runtime {
    /// Detect the available container runtime. Returns None if neither docker
    /// nor podman is installed (the install step can fix that).
    pub fn detect() -> Option<Self> {
        let engine = if crate::process::which("docker") {
            "docker".to_string()
        } else if crate::process::which("podman") {
            "podman".to_string()
        } else {
            return None;
        };

        let compose = detect_compose(&engine);
        let rootless = detect_rootless(&engine);
        let (user_id, group_id) = if rootless { (0, 0) } else { effective_ids() };

        Some(Self {
            engine,
            compose,
            rootless,
            user_id,
            group_id,
        })
    }
}

fn detect_compose(engine: &str) -> Vec<String> {
    // Prefer the `docker compose` plugin; fall back to standalone docker-compose.
    let plugin_ok = std::process::Command::new(engine)
        .args(["compose", "version"])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if plugin_ok {
        vec![engine.to_string(), "compose".to_string()]
    } else if crate::process::which("docker-compose") {
        vec!["docker-compose".to_string()]
    } else {
        // Best guess; commands will surface a clear error if unusable.
        vec![engine.to_string(), "compose".to_string()]
    }
}

fn detect_rootless(engine: &str) -> bool {
    let out = std::process::Command::new(engine)
        .arg("info")
        .output();
    match out {
        Ok(o) => {
            let text = String::from_utf8_lossy(&o.stdout);
            text.lines().any(|l| {
                let l = l.trim();
                l.ends_with("rootless") || l.contains("rootless: true")
            })
        }
        Err(_) => false,
    }
}

/// True when a container engine (docker or podman) is installed *and its daemon
/// is reachable*, verified with a successful `info` call. This is a stronger
/// check than mere binary presence: an installed-but-stopped engine returns
/// false (so callers can treat it as "not ready"). Note: `info` can take a
/// moment, so call this off the UI thread.
pub fn container_engine_running() -> bool {
    engine_info_ok("docker") || engine_info_ok("podman")
}

fn engine_info_ok(engine: &str) -> bool {
    if !crate::process::which(engine) {
        return false;
    }
    std::process::Command::new(engine)
        .arg("info")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

#[cfg(unix)]
fn effective_ids() -> (u32, u32) {
    // Avoid pulling in libc: shell out to id, default to 1000 on failure.
    let uid = std::process::Command::new("id")
        .arg("-u")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(1000);
    let gid = std::process::Command::new("id")
        .arg("-g")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(1000);
    (uid, gid)
}

#[cfg(not(unix))]
fn effective_ids() -> (u32, u32) {
    // Windows containers / Docker Desktop manage user mapping themselves.
    (1000, 1000)
}

/// Bundle of everything a command needs.
#[derive(Clone)]
pub struct Context {
    pub paths: Paths,
    pub runtime: Option<Runtime>,
    pub enterprise: bool,
}

impl Context {
    pub fn new(root_override: Option<PathBuf>, enterprise: bool) -> Result<Self> {
        Ok(Self {
            paths: Paths::resolve(root_override)?,
            runtime: Runtime::detect(),
            enterprise,
        })
    }

    /// Get the runtime or a helpful error pointing at `install docker`.
    pub fn runtime(&self) -> Result<&Runtime> {
        self.runtime.as_ref().ok_or_else(|| {
            anyhow::anyhow!(
                "No container runtime found. Run `openc3 install docker` to install one."
            )
        })
    }
}
