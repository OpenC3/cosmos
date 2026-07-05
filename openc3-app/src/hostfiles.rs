//! Local cache of the COSMOS scope's plugin files, synced from the hub.
//!
//! Host interfaces may `require`/import plugin code (custom interfaces,
//! protocols, helpers in a plugin's top-level `lib/`). The host has no bucket or
//! gem access, so the hub ships those files over Iroh (`api/files`). This module
//! keeps a local mirror under `<root>/host_files/`, syncing by per-file sha256
//! so unchanged files are never re-fetched, and reports what the host runner
//! needs: the `lib` dirs for `PYTHONPATH` and any `requirements.txt` /
//! `pyproject.toml` for provisioning the host venv.

use anyhow::{Context as _, Result};
use base64::Engine as _;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::bridge::BridgeClient;

/// What the host runner needs after a sync.
#[derive(Debug, Default, Clone)]
pub struct SyncResult {
    /// `lib` dirs to place on the host runner's PYTHONPATH.
    pub lib_dirs: Vec<PathBuf>,
    /// `requirements.txt` files to install into the host venv.
    pub requirements: Vec<PathBuf>,
    /// Directories containing a `pyproject.toml` to install into the host venv.
    pub projects: Vec<PathBuf>,
    /// Hash of the venv-affecting inputs (requirements/pyproject contents). When
    /// this changes (e.g. a plugin upgrade), host venvs are re-installed.
    pub pip_fingerprint: String,
}

/// Sync `<root>/host_files/` against the hub and return the host runner inputs.
pub fn sync(client: &BridgeClient, host_files_dir: &Path) -> Result<SyncResult> {
    std::fs::create_dir_all(host_files_dir).ok();
    let have = current_manifest(host_files_dir)?;
    let delta = client.sync_files(have)?;

    for entry in &delta.files {
        let dest = resolve(host_files_dir, &entry.path);
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let content = base64::engine::general_purpose::STANDARD
            .decode(entry.content.as_bytes())
            .with_context(|| format!("decoding {}", entry.path))?;
        std::fs::write(&dest, content).with_context(|| format!("writing {}", dest.display()))?;
    }
    for path in &delta.deletions {
        let _ = std::fs::remove_file(resolve(host_files_dir, path));
    }

    let mut result = scan(host_files_dir);
    result.pip_fingerprint = pip_fingerprint(&result);
    Ok(result)
}

/// Fingerprint the venv-affecting inputs (requirements.txt + pyproject.toml
/// contents), sorted, so a plugin upgrade that changes them updates the venv.
fn pip_fingerprint(result: &SyncResult) -> String {
    let mut inputs: Vec<PathBuf> = result.requirements.clone();
    for project in &result.projects {
        inputs.push(project.join("pyproject.toml"));
    }
    inputs.sort();
    let mut hasher = Sha256::new();
    for path in inputs {
        if let Ok(bytes) = std::fs::read(&path) {
            hasher.update(path.to_string_lossy().as_bytes());
            hasher.update([0u8]);
            hasher.update(&bytes);
            hasher.update([0u8]);
        }
    }
    hex(&hasher.finalize())
}

/// Join a `/`-separated relative path onto the base, component by component
/// (so it's correct cross-platform and can't escape the base).
fn resolve(base: &Path, rel: &str) -> PathBuf {
    let mut path = base.to_path_buf();
    for component in rel.split('/') {
        if component.is_empty() || component == "." || component == ".." {
            continue;
        }
        path.push(component);
    }
    path
}

/// Build the current on-disk manifest: `<relative/path> -> sha256 hex`.
fn current_manifest(dir: &Path) -> Result<BTreeMap<String, String>> {
    let mut manifest = BTreeMap::new();
    walk(dir, dir, &mut manifest)?;
    Ok(manifest)
}

fn walk(base: &Path, dir: &Path, manifest: &mut BTreeMap<String, String>) -> Result<()> {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return Ok(()),
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk(base, &path, manifest)?;
        } else if path.is_file() {
            let rel = path
                .strip_prefix(base)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            let bytes = std::fs::read(&path)?;
            manifest.insert(rel, sha256_hex(&bytes));
        }
    }
    Ok(())
}

fn sha256_hex(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        let _ = write!(s, "{b:02x}");
    }
    s
}

/// Scan the synced tree for host runner inputs: `<gem>/lib` dirs, and any
/// `<gem>/requirements.txt` / `<gem>/pyproject.toml`.
fn scan(host_files_dir: &Path) -> SyncResult {
    let mut result = SyncResult::default();
    let gem_dirs = match std::fs::read_dir(host_files_dir) {
        Ok(e) => e,
        Err(_) => return result,
    };
    for gem in gem_dirs.flatten() {
        let gem_path = gem.path();
        if !gem_path.is_dir() {
            continue;
        }
        let lib = gem_path.join("lib");
        if lib.is_dir() {
            result.lib_dirs.push(lib);
        }
        if gem_path.join("requirements.txt").is_file() {
            result.requirements.push(gem_path.join("requirements.txt"));
        }
        if gem_path.join("pyproject.toml").is_file() {
            result.projects.push(gem_path);
        }
    }
    result
}
