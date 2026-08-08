//! Container status monitoring. Parses `docker compose ps --format json` into
//! a structured snapshot consumed by the headless monitor loop and the GUI.

use crate::context::Context;
use crate::docker;
use anyhow::Result;
use serde::Deserialize;
use std::time::Duration;

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
#[derive(Clone, Debug, Default, Deserialize)]
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
    /// Full image reference, e.g. "openc3inc/openc3-cosmos-cmd-tlm-api:6.9.0".
    #[serde(default, rename = "Image")]
    pub image: String,
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
        // A one-shot container (e.g. openc3-cosmos-init) that ran and exited 0 has
        // done its job — that's a healthy outcome, not a problem to warn about.
        if self.run_state() == RunState::ExitedSuccess {
            return true;
        }
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

    /// Best-effort uptime parsed from the compose `Status` string (e.g. "Up 5
    /// minutes", "Up 45 seconds", "Up About a minute"). `None` when not running.
    /// Coarse by design — it's only used against a warm-up threshold.
    pub fn uptime(&self) -> Option<Duration> {
        if !self.is_running() {
            return None;
        }
        let status = self.status.to_lowercase();
        // Strip the "up " prefix and any trailing "(healthy)" annotation.
        let phrase = match status.strip_prefix("up ") {
            Some(rest) => rest.split('(').next().unwrap_or("").trim(),
            // Running but an unrecognized status: treat as long-up (don't stall).
            None => return Some(Duration::from_secs(u64::MAX / 2)),
        };
        if phrase.contains("less than a second") {
            return Some(Duration::ZERO);
        }
        // Leading count ("2 minutes"); "about a minute"/"an hour" imply 1 unit.
        let n: u64 = phrase
            .split_whitespace()
            .next()
            .and_then(|t| t.parse().ok())
            .unwrap_or(1);
        let secs = if phrase.contains("second") {
            n
        } else if phrase.contains("minute") {
            n * 60
        } else if phrase.contains("hour") {
            n * 3600
        } else if phrase.contains("day") {
            n * 86_400
        } else if phrase.contains("week") {
            n * 604_800
        } else if phrase.contains("month") {
            n * 2_592_000
        } else {
            u64::MAX / 2 // running but unparseable unit: treat as long-up
        };
        Some(Duration::from_secs(secs))
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

    /// The image tag (version) for display, e.g. "6.9.0" or "latest", or "-"
    /// when there's no image.
    pub fn tag_display(&self) -> &str {
        image_tag(&self.image)
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
/// `with_stats` controls whether per-container CPU/memory is collected — that's
/// the slow part (`docker stats` double-samples ~1-2s per container), so callers
/// that only need presence/health/uptime (readiness checks, the collapsed status
/// summary) should pass `false`.
///
/// Prefers the Docker Engine API over the daemon socket (no subprocess per
/// poll; see [`crate::dockerapi`]). Falls back to the `docker` CLI when the
/// socket isn't reachable — e.g. podman without its API socket enabled, or an
/// unusual `DOCKER_HOST` bollard can't connect to.
pub fn snapshot(ctx: &Context, with_stats: bool) -> Result<Vec<ContainerStatus>> {
    let mut statuses = match crate::dockerapi::snapshot(ctx, with_stats) {
        Ok(statuses) => statuses,
        Err(err) => {
            crate::logging::debug(
                "monitor",
                &format!("Docker API poll unavailable ({err:#}); using the docker CLI"),
            );
            snapshot_via_cli(ctx, with_stats)?
        }
    };
    // Present containers alphabetically (by compose service, then container
    // name) so the list order is stable and easy to scan.
    statuses.sort_by(|a, b| {
        a.service
            .to_lowercase()
            .cmp(&b.service.to_lowercase())
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(statuses)
}

/// COSMOS container readiness for bridge enrollment, derived from a compose
/// snapshot. Distinguishes the reasons enrollment can't proceed so the GUI can
/// explain *why* instead of always claiming COSMOS hasn't started.
#[derive(Debug, Clone)]
pub enum CosmosReadiness {
    /// Docker itself isn't reachable (daemon stopped / socket error). Carries a
    /// short reason.
    DockerUnavailable(String),
    /// Docker is reachable but no COSMOS containers exist for the compose context
    /// openc3-app is pointed at (wrong project, Development-mode folder, or a
    /// remote COSMOS that needs manual token pairing).
    NoContainers,
    /// COSMOS containers exist but none are running (stopped / exited / restarting).
    NotRunning,
    /// COSMOS is running; carries the smallest container uptime (for warm-up gating).
    Up(Duration),
}

/// Classify COSMOS's container state for the bridge-enrollment gate. `with_stats`
/// is passed through to [`snapshot`] (keep it false here — this is polled often
/// and only needs states/uptimes, not CPU/mem).
pub fn cosmos_readiness(ctx: &Context, with_stats: bool) -> CosmosReadiness {
    match snapshot(ctx, with_stats) {
        Err(err) => CosmosReadiness::DockerUnavailable(format!("{err:#}")),
        Ok(statuses) if statuses.is_empty() => CosmosReadiness::NoContainers,
        Ok(statuses) => match statuses.iter().filter_map(|c| c.uptime()).min() {
            Some(uptime) => CosmosReadiness::Up(uptime),
            None => CosmosReadiness::NotRunning,
        },
    }
}

/// Extract the image tag (version) from a full image reference. Handles
/// `@sha256:` digests and registry-port colons (`host:5000/img:tag`). Returns
/// the implicit "latest" when an image has no tag, or "-" when there's none.
fn image_tag(image: &str) -> &str {
    if image.is_empty() {
        return "-";
    }
    // Drop any digest suffix ("name@sha256:...").
    let reference = image.split('@').next().unwrap_or(image);
    // The tag follows the last ':' — but only when that ':' isn't the registry
    // port separator (which is followed by '/').
    if let Some(idx) = reference.rfind(':') {
        let candidate = &reference[idx + 1..];
        if !candidate.is_empty() && !candidate.contains('/') {
            return candidate;
        }
    }
    "latest"
}

/// CLI fallback: parse `docker compose ps --format json` (which emits either a
/// JSON array or one JSON object per line depending on the version) and enrich
/// with `docker stats`.
fn snapshot_via_cli(ctx: &Context, with_stats: bool) -> Result<Vec<ContainerStatus>> {
    let mut cmd = docker::compose(ctx)?;
    cmd.args(["ps", "--all", "--format", "json"]);
    let out = docker::capture(cmd)?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        anyhow::bail!("docker compose ps failed: {stderr}");
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut statuses = parse_ps(&text);

    // Enrich with CPU/memory utilization from `docker stats` (best effort) only
    // when the caller wants it — `docker stats` is the slow part.
    if with_stats {
        let stats = fetch_stats(ctx);
        for s in &mut statuses {
            if let Some((cpu, mem)) = stats.get(&s.name) {
                s.cpu = cpu.clone();
                s.mem = mem.clone();
            }
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
    let Ok(out) = docker::capture(cmd) else {
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

/// Sum CPU% and memory usage across the given containers, returned as display
/// strings (e.g. "12.34%", "1.2GiB") for a totals row. Containers without
/// stats (not running) contribute nothing.
pub fn totals<'a>(statuses: impl IntoIterator<Item = &'a ContainerStatus>) -> (String, String) {
    let mut cpu = 0.0_f64;
    let mut mem = 0.0_f64;
    for c in statuses {
        if let Some(v) = parse_cpu(&c.cpu) {
            cpu += v;
        }
        if let Some(v) = parse_mem_bytes(&c.mem) {
            mem += v;
        }
    }
    (format!("{cpu:.2}%"), human_bytes(mem.round() as u64))
}

/// Parse a CPU percentage display string ("12.34%") back to a number.
fn parse_cpu(s: &str) -> Option<f64> {
    let t = s.trim().trim_end_matches('%').trim();
    if t.is_empty() {
        return None;
    }
    t.parse().ok()
}

/// Parse a memory display string ("25.6MiB") back to bytes. Handles the IEC
/// units `docker stats` emits, plus decimal units defensively.
fn parse_mem_bytes(s: &str) -> Option<f64> {
    let t = s.trim();
    if t.is_empty() || t == "-" {
        return None;
    }
    let split = t.find(|c: char| c.is_ascii_alphabetic())?;
    let (num, unit) = t.split_at(split);
    let value: f64 = num.trim().parse().ok()?;
    let mult = match unit.trim().to_ascii_lowercase().as_str() {
        "b" => 1.0,
        "kib" => 1024.0,
        "mib" => 1024f64.powi(2),
        "gib" => 1024f64.powi(3),
        "tib" => 1024f64.powi(4),
        "pib" => 1024f64.powi(5),
        "kb" => 1000.0,
        "mb" => 1000f64.powi(2),
        "gb" => 1000f64.powi(3),
        "tb" => 1000f64.powi(4),
        _ => return None,
    };
    Some(value * mult)
}

/// Format bytes in IEC units similar to `docker stats` (e.g. "25.6MiB").
pub(crate) fn human_bytes(bytes: u64) -> String {
    const UNITS: [&str; 6] = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes}B")
    } else {
        format!("{value:.1}{}", UNITS[unit])
    }
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
    fn exited_zero_is_healthy_but_nonzero_is_not() {
        // A one-shot init container that completed (exit 0) is healthy...
        let ok = parse_ps(
            r#"[{"Service":"openc3-cosmos-init","State":"exited","Status":"Exited (0) 2 minutes ago"}]"#,
        );
        assert!(ok[0].is_healthy());
        // ...but a non-zero exit is still unhealthy.
        let bad = parse_ps(
            r#"[{"Service":"openc3-cosmos-init","State":"exited","Status":"Exited (1) 2 minutes ago"}]"#,
        );
        assert!(!bad[0].is_healthy());
    }

    #[test]
    fn extracts_image_tag() {
        assert_eq!(image_tag("openc3inc/openc3-cosmos-cmd-tlm-api:6.9.0"), "6.9.0");
        assert_eq!(image_tag("openc3inc/foo:latest"), "latest");
        assert_eq!(image_tag("openc3inc/foo"), "latest"); // implicit tag
        assert_eq!(image_tag("localhost:5000/openc3/foo:1.2"), "1.2");
        assert_eq!(image_tag("localhost:5000/openc3/foo"), "latest"); // port, no tag
        assert_eq!(image_tag("foo:1.0@sha256:abc123"), "1.0"); // digest stripped
        assert_eq!(image_tag(""), "-");
    }

    #[test]
    fn human_bytes_uses_iec_units() {
        assert_eq!(human_bytes(512), "512B");
        assert_eq!(human_bytes(1024), "1.0KiB");
        assert_eq!(human_bytes(26_843_546), "25.6MiB");
    }

    #[test]
    fn totals_sum_cpu_and_memory() {
        let a = ContainerStatus {
            cpu: "10.50%".to_string(),
            mem: "100.0MiB".to_string(),
            ..Default::default()
        };
        let b = ContainerStatus {
            cpu: "5.25%".to_string(),
            mem: "1.0GiB".to_string(),
            ..Default::default()
        };
        // Not running: no stats, contributes nothing.
        let c = ContainerStatus::default();
        let (cpu, mem) = totals([&a, &b, &c]);
        assert_eq!(cpu, "15.75%");
        assert_eq!(mem, "1.1GiB"); // 100MiB + 1024MiB = 1124MiB ≈ 1.1GiB
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
