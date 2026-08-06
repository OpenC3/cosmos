//! Single-instance guard for the GUI, with "show the existing window" signaling.
//!
//! Launching the app again should not spin up a second copy (another tray icon,
//! another operator); instead it should surface the already-running window. The
//! token is an **advisory lock** on a per-user file (`<root>/openc3-app.lock`):
//!
//! * The first instance takes an exclusive lock and holds it for its lifetime.
//! * A later launch fails to take the lock, drops a one-byte "show request"
//!   marker file next to it, and exits. The primary polls for that marker and
//!   raises its window.
//!
//! Why a lock file rather than a TCP port: there is no globally-shared resource
//! to collide with (the path is private to this app and user), so it can't clash
//! with an unrelated program the way a fixed port can.
//!
//! Crash-resilient by construction: an advisory lock is released by the OS when
//! the holding process dies (even on a hard crash), so the next launch takes it
//! and runs — the lock file may linger on disk but carries no stale state. And it
//! never blocks a valid launch: contention can only come from *our* own instance
//! (unique path), and if the lock can't be taken for any other reason we fail
//! open and run without the guard rather than refuse to start.

use fs4::fs_std::FileExt;
use std::fs::{File, OpenOptions};
use std::path::{Path, PathBuf};

const LOCK_FILE: &str = "openc3-app.lock";
const SHOW_FILE: &str = "openc3-app.show";

/// Outcome of trying to become the single instance.
pub enum Acquire {
    /// This process should run; holds the lock and the show-request marker path.
    Primary(Guard),
    /// Another live instance was found and asked to show itself; exit quietly.
    Secondary,
}

/// Held by the running instance for its whole lifetime. Dropping it releases the
/// OS advisory lock. Also knows the marker path so the app can poll for a later
/// launch's "please show your window" request.
pub struct Guard {
    // Held only to keep the advisory lock engaged; `None` if we failed open.
    _lock: Option<File>,
    marker: PathBuf,
}

impl Guard {
    /// True (once) if a later launch asked us to surface our window. Consuming:
    /// clears the request so it fires a single show.
    pub fn take_show_request(&self) -> bool {
        if self.marker.exists() {
            let _ = std::fs::remove_file(&self.marker);
            true
        } else {
            false
        }
    }
}

/// Acquire the singleton for the app rooted at `root`. See the module docs for
/// the crash-resilience and don't-block-valid-launches guarantees.
pub fn acquire(root: &Path) -> Acquire {
    let _ = std::fs::create_dir_all(root);
    let lock_path = root.join(LOCK_FILE);
    let marker = root.join(SHOW_FILE);

    let file = match OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false) // it's just a lock token; content is irrelevant
        .open(&lock_path)
    {
        Ok(f) => f,
        Err(e) => {
            // Can't even open the lock file — fail open (run) rather than block.
            crate::logging::warn(
                "openc3-app",
                &format!("single-instance lock unavailable ({e}); launching without the guard"),
            );
            return Acquire::Primary(Guard { _lock: None, marker });
        }
    };

    match file.try_lock_exclusive() {
        Ok(true) => {
            // We're the primary. Clear any stale marker left by a crash.
            let _ = std::fs::remove_file(&marker);
            Acquire::Primary(Guard { _lock: Some(file), marker })
        }
        Ok(false) => {
            // Another instance holds the lock: ask it to show, then exit.
            let _ = std::fs::write(&marker, b"show");
            Acquire::Secondary
        }
        Err(e) => {
            // Locking errored (e.g. a filesystem that doesn't support it) — fail
            // open so we still launch.
            crate::logging::warn(
                "openc3-app",
                &format!("single-instance lock error ({e}); launching without the guard"),
            );
            Acquire::Primary(Guard { _lock: Some(file), marker })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_root() -> PathBuf {
        // A unique dir per test run so parallel tests don't share the lock file.
        let mut dir = std::env::temp_dir();
        dir.push(format!("openc3-si-test-{}-{:?}", std::process::id(), std::thread::current().id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn second_acquire_is_secondary_and_requests_show() {
        let root = temp_root();
        let first = acquire(&root);
        assert!(matches!(first, Acquire::Primary(_)), "first launch is primary");

        // While the first still holds the lock, a second acquire is a duplicate.
        match acquire(&root) {
            Acquire::Secondary => {}
            Acquire::Primary(_) => panic!("second launch should be a duplicate"),
        }
        // ...and it left a show request the primary can consume exactly once.
        if let Acquire::Primary(guard) = first {
            assert!(guard.take_show_request(), "primary should see the show request");
            assert!(!guard.take_show_request(), "the request is consumed once");
        }
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn lock_is_released_when_primary_drops() {
        let root = temp_root();
        // A dead/exited primary (guard dropped) must not block the next launch —
        // dropping releases the advisory lock, mirroring process exit/crash.
        match acquire(&root) {
            Acquire::Primary(guard) => drop(guard),
            Acquire::Secondary => panic!("first launch is primary"),
        }
        assert!(
            matches!(acquire(&root), Acquire::Primary(_)),
            "a relaunch after the primary exits must become primary again"
        );
        let _ = std::fs::remove_dir_all(&root);
    }
}
