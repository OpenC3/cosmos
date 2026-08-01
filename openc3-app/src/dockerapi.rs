//! Direct Docker Engine API access over the daemon socket / named pipe for the
//! status + stats poll, so the app doesn't spawn a `docker` subprocess on every
//! tick (which on Windows also flashes a console window). [`snapshot`] is tried
//! first by [`crate::monitor::snapshot`], which falls back to the `docker` CLI
//! when the socket isn't reachable (e.g. podman without its API socket enabled).

use crate::context::Context;
use crate::monitor::{ContainerStatus, Publisher};
use anyhow::{Context as _, Result};
use bollard::models::{ContainerCpuStats, ContainerStatsResponse, ContainerSummary};
use bollard::query_parameters::{ListContainersOptionsBuilder, StatsOptionsBuilder};
use bollard::Docker;
use futures_util::StreamExt;
use std::collections::HashMap;

/// Compose labels. `working_dir` scopes the container list to *our* stack the
/// same way `docker compose` (run from that directory) does; `service` gives the
/// compose service name shown in the status table.
const WORKDIR_LABEL: &str = "com.docker.compose.project.working_dir";
const SERVICE_LABEL: &str = "com.docker.compose.service";

/// Query all COSMOS containers via the Docker Engine API. When `with_stats` is
/// false, only the container list/status is fetched (fast); when true, each
/// running container is additionally polled for CPU/memory, which is slow
/// (`docker stats` double-samples ~1-2s per container). Errors if the daemon
/// socket can't be reached, so the caller can fall back to the CLI path.
pub fn snapshot(ctx: &Context, with_stats: bool) -> Result<Vec<ContainerStatus>> {
    // Compose records the absolute working directory it was launched from. In
    // development mode COSMOS is launched from the source checkout, so scope the
    // status to that folder; otherwise our (absolute) cosmos install path.
    // Trim a trailing slash so e.g. ".../cosmos/" still matches the label
    // ".../cosmos" that compose stored.
    let workdir = ctx
        .dev_folder
        .as_ref()
        .unwrap_or(&ctx.paths.cosmos)
        .to_string_lossy()
        .trim_end_matches('/')
        .to_string();
    let docker = Docker::connect_with_defaults().context("connecting to the Docker Engine API")?;
    // A current-thread runtime spawns no background threads and is cheap to
    // build per poll; the per-container stats calls are IO-bound and overlap
    // cooperatively while it's driven by `block_on`.
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .context("building tokio runtime for the Docker API")?;
    rt.block_on(collect(&docker, &workdir, with_stats))
}

async fn collect(docker: &Docker, workdir: &str, with_stats: bool) -> Result<Vec<ContainerStatus>> {
    let mut filters = HashMap::new();
    filters.insert(
        "label".to_string(),
        vec![format!("{WORKDIR_LABEL}={workdir}")],
    );
    let options = ListContainersOptionsBuilder::default()
        .all(true)
        .filters(&filters)
        .build();
    let list = docker
        .list_containers(Some(options))
        .await
        .context("listing COSMOS containers")?;

    // Status is quick; the per-container stats call blocks ~1s (Docker samples
    // twice to compute a delta), so fan them out concurrently.
    let mut set = tokio::task::JoinSet::new();
    for summary in list {
        let docker = docker.clone();
        set.spawn(async move { build_status(&docker, summary, with_stats).await });
    }
    let mut out = Vec::new();
    while let Some(joined) = set.join_next().await {
        if let Ok(status) = joined {
            out.push(status);
        }
    }
    Ok(out)
}

async fn build_status(docker: &Docker, c: ContainerSummary, with_stats: bool) -> ContainerStatus {
    let labels = c.labels.unwrap_or_default();
    let service = labels.get(SERVICE_LABEL).cloned().unwrap_or_default();
    let name = c
        .names
        .and_then(|names| names.into_iter().next())
        .map(|n| n.trim_start_matches('/').to_string())
        .unwrap_or_default();
    let state = c.state.map(|s| s.to_string()).unwrap_or_default();
    let status = c.status.unwrap_or_default();
    let image = c.image.unwrap_or_default();
    let health = parse_health(&status);
    let publishers = c
        .ports
        .unwrap_or_default()
        .into_iter()
        .filter_map(|p| p.public_port)
        .map(|port| Publisher {
            published_port: port as u32,
        })
        .collect();

    let mut cs = ContainerStatus {
        service,
        name,
        state,
        status,
        health,
        image,
        publishers,
        cpu: String::new(),
        mem: String::new(),
    };

    if with_stats && cs.state.eq_ignore_ascii_case("running") {
        if let Some(id) = c.id.as_deref() {
            if let Some((cpu, mem)) = fetch_stats(docker, id).await {
                cs.cpu = cpu;
                cs.mem = mem;
            }
        }
    }
    cs
}

/// One-shot CPU% + memory usage for a container, computed from the raw counters
/// the same way the `docker stats` CLI does. Best effort: `None` on any error.
async fn fetch_stats(docker: &Docker, id: &str) -> Option<(String, String)> {
    let options = StatsOptionsBuilder::default().stream(false).build();
    let stat = docker.stats(id, Some(options)).take(1).next().await?.ok()?;
    Some((cpu_percent(&stat), mem_used(&stat)))
}

/// CPU percentage across all cores, mirroring the docker CLI formula:
/// `(cpu_delta / system_delta) * online_cpus * 100`.
fn cpu_percent(s: &ContainerStatsResponse) -> String {
    let total = |c: Option<&ContainerCpuStats>| {
        c.and_then(|c| c.cpu_usage.as_ref())
            .and_then(|u| u.total_usage)
    };
    let cur = s.cpu_stats.as_ref();
    let pre = s.precpu_stats.as_ref();
    let online = cur
        .and_then(|c| c.online_cpus)
        .or_else(|| {
            cur.and_then(|c| c.cpu_usage.as_ref())
                .and_then(|u| u.percpu_usage.as_ref())
                .map(|v| v.len() as u32)
        })
        .unwrap_or(1)
        .max(1);
    let (Some(total), Some(pretotal), Some(sys), Some(presys)) = (
        total(cur),
        total(pre),
        cur.and_then(|c| c.system_cpu_usage),
        pre.and_then(|c| c.system_cpu_usage),
    ) else {
        return String::new();
    };
    let cpu_delta = total.saturating_sub(pretotal) as f64;
    let sys_delta = sys.saturating_sub(presys) as f64;
    if sys_delta > 0.0 && cpu_delta > 0.0 {
        format!("{:.2}%", (cpu_delta / sys_delta) * online as f64 * 100.0)
    } else {
        "0.00%".to_string()
    }
}

/// Memory working set, mirroring `docker stats`: usage minus page cache
/// (cgroup v2 reports it as `inactive_file`, v1 as `total_inactive_file`).
fn mem_used(s: &ContainerStatsResponse) -> String {
    let Some(mem) = s.memory_stats.as_ref() else {
        return String::new();
    };
    let Some(usage) = mem.usage else {
        return String::new();
    };
    let cache = mem
        .stats
        .as_ref()
        .and_then(|m| {
            m.get("inactive_file")
                .or_else(|| m.get("total_inactive_file"))
                .copied()
        })
        .unwrap_or(0);
    crate::monitor::human_bytes(usage.saturating_sub(cache))
}

/// Derive the health from the compose/docker status text (e.g. "Up 2 minutes
/// (healthy)"), matching what `docker compose ps` reports in its Health field.
fn parse_health(status: &str) -> String {
    let s = status.to_lowercase();
    if s.contains("(healthy)") {
        "healthy".to_string()
    } else if s.contains("(unhealthy)") {
        "unhealthy".to_string()
    } else if s.contains("health: starting") || s.contains("(starting)") {
        "starting".to_string()
    } else {
        String::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn health_parsed_from_status_text() {
        assert_eq!(parse_health("Up 2 minutes (healthy)"), "healthy");
        assert_eq!(parse_health("Up 5 seconds (health: starting)"), "starting");
        assert_eq!(parse_health("Up 1 minute (unhealthy)"), "unhealthy");
        assert_eq!(parse_health("Up 3 minutes"), "");
        assert_eq!(parse_health("Exited (0) 1 minute ago"), "");
    }
}
