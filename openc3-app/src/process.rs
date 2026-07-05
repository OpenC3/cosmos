//! Small helpers for spawning child processes.

use anyhow::{bail, Context, Result};
use std::path::Path;
use std::process::{Command, Output, Stdio};

/// Run a command, inheriting stdio so the user sees live output. Returns an
/// error if the command exits non-zero.
pub fn run(cmd: &mut Command) -> Result<()> {
    let display = describe(cmd);
    let status = cmd
        .status()
        .with_context(|| format!("failed to spawn: {display}"))?;
    if !status.success() {
        bail!("command failed ({}): {display}", status);
    }
    Ok(())
}

/// Run a command capturing stdout/stderr. Returns the captured output
/// regardless of exit status (caller decides what to do).
pub fn capture(cmd: &mut Command) -> Result<Output> {
    let display = describe(cmd);
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    cmd.output()
        .with_context(|| format!("failed to spawn: {display}"))
}

/// Run a command and return trimmed stdout, erroring on non-zero exit.
pub fn stdout_string(cmd: &mut Command) -> Result<String> {
    let display = describe(cmd);
    let out = capture(cmd)?;
    if !out.status.success() {
        bail!(
            "command failed ({}): {display}\n{}",
            out.status,
            String::from_utf8_lossy(&out.stderr)
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// True if `program` is found on PATH.
pub fn which(program: &str) -> bool {
    which_path(program).is_some()
}

/// Locate a program on PATH, returning its full path if found.
pub fn which_path(program: &str) -> Option<std::path::PathBuf> {
    let path = std::env::var_os("PATH")?;
    let exts: Vec<String> = if cfg!(windows) {
        std::env::var("PATHEXT")
            .unwrap_or_else(|_| ".EXE;.CMD;.BAT;.COM".into())
            .split(';')
            .map(|s| s.to_string())
            .collect()
    } else {
        vec![String::new()]
    };
    for dir in std::env::split_paths(&path) {
        for ext in &exts {
            let candidate = dir.join(format!("{program}{ext}"));
            if is_executable(&candidate) {
                return Some(candidate);
            }
        }
    }
    None
}

fn is_executable(path: &Path) -> bool {
    path.is_file()
}

fn describe(cmd: &Command) -> String {
    let prog = cmd.get_program().to_string_lossy().to_string();
    let args: Vec<String> = cmd
        .get_args()
        .map(|a| a.to_string_lossy().to_string())
        .collect();
    if args.is_empty() {
        prog
    } else {
        format!("{prog} {}", args.join(" "))
    }
}
