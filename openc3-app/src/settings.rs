//! Persisted application settings (the COSMOS URL and the run-locally toggle),
//! stored as JSON under the app root so they survive between runs.

use crate::context::Context;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// The default COSMOS web UI URL.
pub const DEFAULT_COSMOS_URL: &str = "http://localhost:2900";

#[derive(Debug, Clone, Serialize, Deserialize)]
// Fill any missing field from `Default` so older/newer settings files stay
// readable as fields are added.
#[serde(default)]
pub struct Settings {
    /// The COSMOS web UI URL used by "Open COSMOS in Browser" (and the readiness
    /// probe when running locally).
    pub cosmos_url: String,
    /// Whether COSMOS runs locally, managed by this app via Docker. When false
    /// the app doesn't offer Docker/COSMOS installs or start/stop controls and
    /// simply opens the configured (remote) URL.
    pub run_locally: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            cosmos_url: DEFAULT_COSMOS_URL.to_string(),
            run_locally: true,
        }
    }
}

impl Settings {
    fn path(ctx: &Context) -> PathBuf {
        ctx.paths.root.join("openc3-app-settings.json")
    }

    /// Load settings from disk, falling back to defaults on any error.
    pub fn load(ctx: &Context) -> Self {
        std::fs::read_to_string(Self::path(ctx))
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    /// Persist settings to disk (best effort; warns on failure).
    pub fn save(&self, ctx: &Context) {
        let path = Self::path(ctx);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        match serde_json::to_string_pretty(self) {
            Ok(json) => {
                if let Err(e) = std::fs::write(&path, json) {
                    crate::logging::warn("openc3-app", &format!("could not save settings: {e}"));
                }
            }
            Err(e) => {
                crate::logging::warn("openc3-app", &format!("could not serialize settings: {e}"));
            }
        }
    }

    /// The COSMOS URL to actually use, substituting the default when the stored
    /// value is blank.
    pub fn effective_cosmos_url(&self) -> &str {
        let trimmed = self.cosmos_url.trim();
        if trimmed.is_empty() {
            DEFAULT_COSMOS_URL
        } else {
            trimmed
        }
    }
}
