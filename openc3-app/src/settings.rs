//! Persisted application settings (the COSMOS URL and the run-locally toggle),
//! stored as JSON under the app root so they survive between runs.

use crate::context::Context;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// The default COSMOS web UI URL.
pub const DEFAULT_COSMOS_URL: &str = "http://localhost:2900";

/// Which edition of COSMOS to install and manage.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Edition {
    Core,
    Enterprise,
}

impl Edition {
    /// All editions, for the settings/setup selector.
    pub const ALL: [Edition; 2] = [Edition::Core, Edition::Enterprise];

    pub fn is_enterprise(self) -> bool {
        matches!(self, Edition::Enterprise)
    }
}

impl std::fmt::Display for Edition {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Edition::Core => "COSMOS Core",
            Edition::Enterprise => "COSMOS Enterprise",
        })
    }
}

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
    /// Which COSMOS edition to install/manage.
    pub edition: Edition,
    /// Access token for the private COSMOS Enterprise repo (repos.openc3.com).
    /// Only used when `edition` is Enterprise.
    pub enterprise_token: String,
    /// Development mode: force OPENC3_TAG / OPENC3_ENTERPRISE_TAG to "latest"
    /// and drive COSMOS from a local source checkout's `openc3.sh`.
    pub dev_mode: bool,
    /// The local source checkout used in development mode (contains `openc3.sh`).
    pub dev_folder: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            cosmos_url: DEFAULT_COSMOS_URL.to_string(),
            run_locally: true,
            edition: Edition::Core,
            enterprise_token: String::new(),
            dev_mode: false,
            dev_folder: String::new(),
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
