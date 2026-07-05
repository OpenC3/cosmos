//! Container status monitoring. Parses `docker compose ps --format json` into
//! a structured snapshot consumed by the headless monitor loop and the GUI.

use crate::context::Context;
use crate::docker;
use crate::process;
use anyhow::Result;
use serde::Deserialize;

/// A published port mapping as reported by compose ps.
#[allow(dead_code)]
#[derive(Clone, Debug, Default, Deserialize)]
pub struct Publisher {
    #[serde(default, rename = "PublishedPort")]
    pub published_port: u32,
}

/// One container's status as reported by compose. This is a deserialization
/// DTO; not every field is read in every code path.
#[allow(dead_code)]
#[derive(Clone, Debug, Deserialize)]
pub struct ContainerStatus {
    #[serde(default, rename = "Service")]
    pub service: String,
    #[serde(default, rename = "Name")]
    pub name: String,
    #[serde(default, rename = "State")]
    pub state: String,
    #[serde(default, rename = "Status")]
    pub status: String,
    #[serde(default, rename = "Health")]
    pub health: String,
    #[serde(default, rename = "Publishers")]
    pub publishers: Vec<Publisher>,
    /// CPU percentage from `docker stats` (populated by [`snapshot`], not ps).
    #[serde(default)]
    pub cpu: String,
    /// Memory usage from `docker stats` (used portion, e.g. "25.6MiB").
    #[serde(default)]
    pub mem: String,
}

/// One row of `docker stats --format json`.
#[derive(Debug, Deserialize)]
struct DockerStat {
    #[serde(default, rename = "Name")]
    name: String,
    #[serde(default, rename = "CPUPerc")]
    cpu_perc: String,
    #[serde(default, rename = "MemUsage")]
    mem_usage: String,
}

/// A coarse lifecycle classification used to color the GUI status table.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RunState {
    Running,
    ExitedSuccess,
    ExitedFailure,
    Restarting,
    Paused,
    Unknown,
}

impl ContainerStatus {
    /// True when the container is up (and healthy if a healthcheck exists).
    pub fn is_healthy(&self) -> bool {
        let running = self.state.eq_ignore_ascii_case("running");
        let health_ok = self.health.is_empty()
            || self.health.eq_ignore_ascii_case("healthy")
            || self.health.eq_ignore_ascii_case("none");
        running && health_ok
    }

    /// Classify the container's lifecycle state from the `State`/`Status` fields.
    pub fn run_state(&self) -> RunState {
        let state = self.state.to_lowercase();
        let status = self.status.to_lowercase();
        if state.contains("restart") || status.contains("restart") {
            RunState::Restarting
        } else if state.contains("paused") || status.contains("paused") {
            RunState::Paused
        } else if state == "running" || status.contains("up") {
            RunState::Running
        } else if state.contains("exited") || status.contains("exited") {
            if self.status.contains("(0)") {
                RunState::ExitedSuccess
            } else {
                RunState::ExitedFailure
            }
        } else {
            RunState::Unknown
        }
    }

    /// True when the container is in the running state.
    pub fn is_running(&self) -> bool {
        self.run_state() == RunState::Running
    }

    /// A human display string preferring the descriptive `Status` field.
    pub fn display_status(&self) -> String {
        let base = if self.status.is_empty() {
            self.state.clone()
        } else {
            self.status.clone()
        };
        // Fold in health when it isn't already part of the status text.
        if !self.health.is_empty()
            && !self.health.eq_ignore_ascii_case("none")
            && !base.to_lowercase().contains(&self.health.to_lowercase())
        {
            format!("{base} ({})", self.health)
        } else {
            base
        }
    }

    /// CPU usage for display, or "-" when unavailable (e.g. not running).
    pub fn cpu_display(&self) -> &str {
        if self.cpu.is_empty() {
            "-"
        } else {
            &self.cpu
        }
    }

    /// Memory usage for display, or "-" when unavailable.
    pub fn mem_display(&self) -> &str {
        if self.mem.is_empty() {
            "-"
        } else {
            &self.mem
        }
    }

    /// Comma-separated list of published host ports, or "-" when none.
    pub fn ports_summary(&self) -> String {
        let mut ports: Vec<u32> = self
            .publishers
            .iter()
            .map(|p| p.published_port)
            .filter(|&p| p != 0)
            .collect();
        ports.sort_unstable();
        ports.dedup();
        if ports.is_empty() {
            "-".to_string()
        } else {
            ports
                .iter()
                .map(|p| p.to_string())
                .collect::<Vec<_>>()
                .join(", ")
        }
    }
}

/// Query the current status of all COSMOS containers.
///
/// `docker compose ps --format json` emits either a JSON array or one JSON
/// object per line depending on the version, so we handle both.
pub fn snapshot(ctx: &Context) -> Result<Vec<ContainerStatus>> {
    let mut cmd = docker::compose(ctx)?;
    cmd.args(["ps", "--all", "--format", "json"]);
    let out = process::capture(&mut cmd)?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        anyhow::bail!("docker compose ps failed: {stderr}");
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut statuses = parse_ps(&text);

    // Enrich with CPU/memory utilization from `docker stats` (best effort).
    let stats = fetch_stats(ctx);
    for s in &mut statuses {
        if let Some((cpu, mem)) = stats.get(&s.name) {
            s.cpu = cpu.clone();
            s.mem = mem.clone();
        }
    }
    Ok(statuses)
}

/// Fetch a one-shot CPU/memory snapshot via `docker stats`, keyed by container
/// name. Best effort: returns an empty map on any error.
fn fetch_stats(ctx: &Context) -> std::collections::HashMap<String, (String, String)> {
    let mut map = std::collections::HashMap::new();
    let Ok(rt) = ctx.runtime() else {
        return map;
    };
    let mut cmd = docker::engine_cmd(rt);
    cmd.args(["stats", "--no-stream", "--format", "{{json .}}"]);
    let Ok(out) = process::capture(&mut cmd) else {
        return map;
    };
    if !out.status.success() {
        return map;
    }
    for line in String::from_utf8_lossy(&out.stdout).lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if let Ok(stat) = serde_json::from_str::<DockerStat>(line) {
            // MemUsage looks like "25.6MiB / 7.667GiB"; keep the used portion.
            let mem = stat
                .mem_usage
                .split('/')
                .next()
                .unwrap_or("")
                .trim()
                .to_string();
            map.insert(stat.name, (stat.cpu_perc, mem));
        }
    }
    map
}

fn parse_ps(text: &str) -> Vec<ContainerStatus> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }
    // Newer compose: a single JSON array.
    if trimmed.starts_with('[') {
        if let Ok(v) = serde_json::from_str::<Vec<ContainerStatus>>(trimmed) {
            return v;
        }
    }
    // Older compose: newline-delimited JSON objects.
    let mut result = Vec::new();
    for line in trimmed.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if let Ok(c) = serde_json::from_str::<ContainerStatus>(line) {
            result.push(c);
        }
    }
    result
}

/// Render a one-line human summary of a snapshot.
pub fn summarize(statuses: &[ContainerStatus]) -> String {
    if statuses.is_empty() {
        return "No COSMOS containers are running.".to_string();
    }
    let healthy = statuses.iter().filter(|c| c.is_healthy()).count();
    format!("{}/{} containers healthy", healthy, statuses.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_array_form() {
        let json = r#"[{"Service":"openc3-redis","State":"running","Health":"healthy"}]"#;
        let v = parse_ps(json);
        assert_eq!(v.len(), 1);
        assert!(v[0].is_healthy());
    }

    #[test]
    fn parses_ndjson_form() {
        let json = "{\"Service\":\"a\",\"State\":\"running\"}\n{\"Service\":\"b\",\"State\":\"exited\"}";
        let v = parse_ps(json);
        assert_eq!(v.len(), 2);
        assert!(v[0].is_healthy());
        assert!(!v[1].is_healthy());
    }
}
