//! Small helpers for spawning child processes.

use anyhow::{bail, Context, Result};
use std::path::Path;
use std::process::{Command, Output, Stdio};

/// On Windows, mark a command so spawning it doesn't pop a console window when
/// the app runs as the GUI (which has no console of its own — see the
/// `windows_subsystem` attribute in main.rs). Inherited stdio handles still
/// work, so CLI output is unaffected. No-op on other platforms.
pub fn no_window(cmd: &mut Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // CREATE_NO_WINDOW
        cmd.creation_flags(0x0800_0000);
    }
    #[cfg(not(windows))]
    {
        let _ = cmd;
    }
}

/// Run a command, inheriting stdio so the user sees live output. Returns an
/// error if the command exits non-zero.
pub fn run(cmd: &mut Command) -> Result<()> {
    no_window(cmd);
    let display = describe(cmd);
    let status = cmd
        .status()
        .with_context(|| format!("failed to spawn: {display}"))?;
    if !status.success() {
        bail!("command failed ({}): {display}", status);
    }
    Ok(())
}

/// Run a command, streaming each stdout/stderr line to `on_line` as it arrives,
/// and erroring on a non-zero exit. Used to surface long-running progress (e.g.
/// `docker compose up` pulling images on first run) live instead of blocking
/// silently. Both pipes are drained concurrently (via reader threads feeding a
/// channel) so a full pipe can't deadlock the child.
pub fn run_streamed(cmd: &mut Command, mut on_line: impl FnMut(&str)) -> Result<()> {
    use std::io::{BufRead, BufReader};
    use std::sync::mpsc;
    no_window(cmd);
    let display = describe(cmd);
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = cmd
        .spawn()
        .with_context(|| format!("failed to spawn: {display}"))?;
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();
    let (tx, rx) = mpsc::channel::<String>();
    let tx2 = tx.clone();
    let h1 = stdout.map(|out| {
        std::thread::spawn(move || {
            for line in BufReader::new(out).lines().map_while(std::result::Result::ok) {
                let _ = tx.send(line);
            }
        })
    });
    let h2 = stderr.map(|err| {
        std::thread::spawn(move || {
            for line in BufReader::new(err).lines().map_while(std::result::Result::ok) {
                let _ = tx2.send(line);
            }
        })
    });
    // Iteration ends once both reader threads finish (both senders dropped).
    for line in rx {
        on_line(&line);
    }
    if let Some(h) = h1 {
        let _ = h.join();
    }
    if let Some(h) = h2 {
        let _ = h.join();
    }
    let status = child
        .wait()
        .with_context(|| format!("waiting for: {display}"))?;
    if !status.success() {
        bail!("command failed ({}): {display}", status);
    }
    Ok(())
}

/// Run a command capturing stdout/stderr. Returns the captured output
/// regardless of exit status (caller decides what to do).
pub fn capture(cmd: &mut Command) -> Result<Output> {
    no_window(cmd);
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
