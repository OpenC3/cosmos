//! HTTP downloads and archive extraction helpers.
//!
//! Downloads delegate to the system `curl` (with a `wget` fallback) rather than
//! linking an in-process TLS stack. This keeps the binary free of any C/assembly
//! crypto dependency (e.g. `ring`), so every target cross-compiles as pure Rust.
//! It also matches the COSMOS project's existing reliance on `curl`.

use anyhow::{bail, Context, Result};
use std::fs::File;
use std::io;
use std::path::Path;
use std::process::Command;

use crate::process;

/// Download `url` to `dest`, creating parent directories as needed.
pub fn to_file(url: &str, dest: &Path) -> Result<()> {
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    println!("Downloading {url}");
    if process::which("curl") {
        let mut cmd = Command::new("curl");
        cmd.args(["-fSL", "--retry", "3", "-o"])
            .arg(dest)
            .arg(url);
        process::run(&mut cmd).with_context(|| format!("downloading {url}"))
    } else if process::which("wget") {
        let mut cmd = Command::new("wget");
        cmd.arg("-O").arg(dest).arg(url);
        process::run(&mut cmd).with_context(|| format!("downloading {url}"))
    } else {
        bail!("neither curl nor wget is available to download {url}");
    }
}

/// Download `url` and return the body as bytes.
pub fn to_bytes(url: &str) -> Result<Vec<u8>> {
    println!("Downloading {url}");
    let out = if process::which("curl") {
        process::capture(Command::new("curl").args(["-fSL", "--retry", "3", url]))?
    } else if process::which("wget") {
        process::capture(Command::new("wget").args(["-qO-", url]))?
    } else {
        bail!("neither curl nor wget is available to download {url}");
    };
    if !out.status.success() {
        bail!(
            "download of {url} failed ({}): {}",
            out.status,
            String::from_utf8_lossy(&out.stderr)
        );
    }
    Ok(out.stdout)
}

/// Extract a `.tar.gz` archive into `dest_dir`.
pub fn extract_tar_gz(bytes: &[u8], dest_dir: &Path) -> Result<()> {
    std::fs::create_dir_all(dest_dir).ok();
    let gz = flate2::read::GzDecoder::new(bytes);
    let mut archive = tar::Archive::new(gz);
    archive
        .unpack(dest_dir)
        .with_context(|| format!("extracting tar.gz to {}", dest_dir.display()))?;
    Ok(())
}

/// Extract a `.zip` archive into `dest_dir`.
pub fn extract_zip(bytes: &[u8], dest_dir: &Path) -> Result<()> {
    std::fs::create_dir_all(dest_dir).ok();
    let reader = io::Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(reader).context("opening zip archive")?;
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        let Some(path) = entry.enclosed_name() else {
            continue;
        };
        let outpath = dest_dir.join(path);
        if entry.is_dir() {
            std::fs::create_dir_all(&outpath).ok();
        } else {
            if let Some(parent) = outpath.parent() {
                std::fs::create_dir_all(parent).ok();
            }
            let mut outfile = File::create(&outpath)
                .with_context(|| format!("creating {}", outpath.display()))?;
            io::copy(&mut entry, &mut outfile)?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                if let Some(mode) = entry.unix_mode() {
                    std::fs::set_permissions(&outpath, std::fs::Permissions::from_mode(mode)).ok();
                }
            }
        }
    }
    Ok(())
}

/// After extracting an archive that contains a single top-level directory,
/// return that directory inside `dest_dir`.
pub fn single_subdir(dest_dir: &Path) -> Result<std::path::PathBuf> {
    let mut entries: Vec<_> = std::fs::read_dir(dest_dir)
        .with_context(|| format!("reading {}", dest_dir.display()))?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .collect();
    entries.retain(|p| p.is_dir());
    if entries.len() == 1 {
        Ok(entries.remove(0))
    } else {
        bail!(
            "expected a single top-level directory in {}, found {}",
            dest_dir.display(),
            entries.len()
        );
    }
}
