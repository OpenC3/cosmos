//! Host process spawner/monitor — a Rust port of OpenC3's
//! `microservice_operator.rb` (and its base `operator.rb`).
//!
//! It runs a periodic cycle that:
//!   1. fetches the desired set of microservices ([`fetch_microservices`] — a
//!      STUB for now; the real data-store query is added later),
//!   2. diffs against the previous set to find new / changed / removed services
//!      (including the parent-respawn rules from the Ruby implementation),
//!   3. spawns, restarts, and stops child processes accordingly, rate-limited
//!      per cycle, and
//!   4. respawns any process that has died unexpectedly.
//!
//! Each [`OperatorProcess`] captures the child's stdout/stderr on reader threads
//! into a bounded buffer (first N + last N lines) so death messages can be
//! reported without unbounded memory growth, mirroring `OperatorProcessIO`.

use crate::bridge::{BridgeClient, HostSpec};
use tokio::sync::mpsc::UnboundedSender;
use crate::process;
use std::collections::{BTreeMap, VecDeque};
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Default cycle time to check for microservice changes.
const CYCLE_TIME: Duration = Duration::from_secs(5);
/// How long to wait for a soft stop before hard-killing.
const PROCESS_SHUTDOWN: Duration = Duration::from_secs(5);
/// Default max number of new/changed processes to (re)start per cycle.
const MAX_START_PER_CYCLE: usize = 5;

// ---------------------------------------------------------------------------
// Microservice configuration
// ---------------------------------------------------------------------------

/// Configuration for a single supervised microservice. Mirrors the relevant
/// fields of the Ruby `MicroserviceModel` hash. `name` is the map key and is
/// kept out of the equality used for change detection.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MicroserviceConfig {
    /// For a non-Python service: the full command (program + args). For a Python
    /// service (`python == true`): the arguments passed to the per-service venv
    /// interpreter (e.g. `["-u", "-c", "<code>"]`).
    pub cmd: Vec<String>,
    /// Whether this is a Python microservice. If true, the operator provisions a
    /// dedicated venv in the service's working directory and runs `cmd` with
    /// that venv's interpreter.
    pub python: bool,
    /// Python packages to install into the service's venv (when `python`).
    pub python_packages: Vec<String>,
    /// `requirements.txt` files to install into the venv (plugin deps).
    pub pip_requirements: Vec<String>,
    /// Directories containing a `pyproject.toml` to install into the venv.
    pub pip_projects: Vec<String>,
    /// Hash of the venv-affecting inputs. A change (e.g. plugin upgrade) makes
    /// this config differ (triggering a respawn) and drives venv re-install.
    pub pip_fingerprint: String,
    /// Extra environment variables for the process.
    pub env: BTreeMap<String, String>,
    /// Parent microservice name; children are spawned by their parent rather
    /// than directly, so a child change respawns the parent.
    pub parent: Option<String>,
    /// Whether the microservice should run.
    pub enabled: bool,
    /// Shard this microservice belongs to (this operator only runs its shard).
    pub shard: i64,
    /// When true, changes to this config don't trigger a respawn.
    pub ignore_changes: bool,
    /// Bridge stream/interface name. When set, the operator advertises the
    /// `stream/<name>` ALPN on the bridge and passes OPENC3_BRIDGE_CHANNEL so
    /// the microservice connects on that routed ALPN.
    pub stream: Option<String>,
    /// Whether the process needs the dependency env (GEM_HOME, etc.).
    pub needs_dependencies: bool,
    /// Optional container hint (unused by the host operator).
    pub container: Option<String>,
}

impl Default for MicroserviceConfig {
    fn default() -> Self {
        Self {
            cmd: Vec::new(),
            python: false,
            python_packages: Vec::new(),
            pip_requirements: Vec::new(),
            pip_projects: Vec::new(),
            pip_fingerprint: String::new(),
            stream: None,
            env: BTreeMap::new(),
            parent: None,
            enabled: true,
            shard: 0,
            ignore_changes: false,
            needs_dependencies: false,
            container: None,
        }
    }
}

type ConfigMap = BTreeMap<String, MicroserviceConfig>;

/// A point-in-time status of one supervised microservice, published by the
/// operator for display (e.g. in the GUI). Not all fields are read in every
/// build (the headless binary doesn't render them).
#[allow(dead_code)]
#[derive(Clone, Debug)]
pub struct MicroserviceStatus {
    pub name: String,
    pub scope: String,
    pub running: bool,
    pub pid: Option<u32>,
    pub cmd: String,
}

/// Health of openc3-app's connection to the COSMOS bridge hub, published for
/// the GUI. `configured` means openc3-app is paired (has an identity + a bridge
/// ticket); `connected` means the most recent hub API call succeeded.
#[allow(dead_code)] // fields read by the GUI, not the headless binary
#[derive(Clone, Debug, Default)]
pub struct BridgeConnectionStatus {
    pub configured: bool,
    pub connected: bool,
    pub message: String,
}

/// The scope is the portion of a microservice name before the first `__`.
fn scope_of(name: &str) -> String {
    name.split("__").next().unwrap_or("DEFAULT").to_string()
}

/// Build the environment for a microservice process.
fn build_env(name: &str, config: &MicroserviceConfig) -> BTreeMap<String, String> {
    let mut env = config.env.clone();
    env.insert("OPENC3_MICROSERVICE_NAME".to_string(), name.to_string());
    env
}

/// When `OPENC3_DEVEL` points at the local openc3 gem (as in the Rails APIs'
/// `export OPENC3_DEVEL=../openc3`), the local openc3 Python source directory
/// (`$OPENC3_DEVEL/python`) to install into host venvs instead of the published
/// `openc3` package. Returns `None` when the variable is unset/empty or doesn't
/// point at the openc3 Python package (e.g. the `OPENC3_DEVEL=1` boolean form
/// used by `openc3.sh`), so normal installs are unaffected.
fn openc3_devel_source() -> Option<PathBuf> {
    let devel = std::env::var("OPENC3_DEVEL").ok().filter(|v| !v.is_empty())?;
    let path = Path::new(&devel).join("python");
    path.join("pyproject.toml").is_file().then_some(path)
}

/// Path to a venv's Python interpreter.
fn venv_interpreter(venv_dir: &Path) -> PathBuf {
    if cfg!(windows) {
        venv_dir.join("Scripts").join("python.exe")
    } else {
        venv_dir.join("bin").join("python")
    }
}

/// Locate the `uv` binary (in `<root>/bin` next to `python/`, else on PATH).
fn locate_uv(python_dir: &Path) -> Option<PathBuf> {
    let name = if cfg!(windows) { "uv.exe" } else { "uv" };
    if let Some(root) = python_dir.parent() {
        let candidate = root.join("bin").join(name);
        if candidate.exists() {
            return Some(candidate);
        }
    }
    process::which_path("uv")
}

/// Ensure a per-microservice venv exists at `venv_dir` and has `packages`
/// installed. Best-effort: failures are logged and the (possibly incomplete)
/// venv is still used. Prefers `uv`; falls back to the base interpreter's
/// stdlib `venv` + `pip`.
fn ensure_venv(python_dir: &Path, venv_dir: &Path, config: &MicroserviceConfig) {
    let interpreter = venv_interpreter(venv_dir);
    let fingerprint_file = venv_dir.join(".openc3_pip_fingerprint");
    // In OPENC3_DEVEL mode, install openc3 editable from the local checkout so
    // host microservices run the working-tree source, not the published package.
    let devel_openc3 = openc3_devel_source();
    // The devel source is part of what's installed, so fold it into the
    // fingerprint: toggling OPENC3_DEVEL (or changing its path) rebuilds the venv.
    let fingerprint = match &devel_openc3 {
        Some(src) => format!("{}|openc3-devel:{}", config.pip_fingerprint, src.display()),
        None => config.pip_fingerprint.clone(),
    };
    // Skip when the venv is present AND its installed inputs match the current
    // fingerprint. When they differ (e.g. a plugin upgrade changed requirements),
    // rebuild the venv from scratch so removed dependencies are pruned. Callers
    // ensure the process is stopped first, so deleting the venv is safe.
    if interpreter.exists() {
        let current = std::fs::read_to_string(&fingerprint_file).unwrap_or_default();
        if current == fingerprint {
            return;
        }
        log_info(
            "MicroserviceOperator",
            &format!("Rebuilding venv (dependencies changed) at {}", venv_dir.display()),
        );
        let _ = std::fs::remove_dir_all(venv_dir);
    }
    if let Some(src) = &devel_openc3 {
        log_info(
            "MicroserviceOperator",
            &format!("OPENC3_DEVEL: installing openc3 (editable) from {}", src.display()),
        );
    }
    let cache = python_dir.join("cache");
    let runtimes = python_dir.join("runtimes");
    // Add the configured packages to an install command, substituting an
    // editable install of the local openc3 source when in OPENC3_DEVEL mode.
    let add_packages = |install: &mut Command| {
        for p in &config.python_packages {
            match (p.as_str(), &devel_openc3) {
                ("openc3", Some(src)) => {
                    install.arg("-e").arg(src);
                }
                _ => {
                    install.arg(p);
                }
            }
        }
    };
    // Extra pip targets from plugin files: `-r <requirements>` and project dirs.
    let extra_targets = |install: &mut Command| {
        for req in &config.pip_requirements {
            install.arg("-r").arg(req);
        }
        for project in &config.pip_projects {
            install.arg(project);
        }
    };
    let has_installs = |packages: &[String]| {
        !packages.is_empty()
            || !config.pip_requirements.is_empty()
            || !config.pip_projects.is_empty()
    };

    if let Some(uv) = locate_uv(python_dir) {
        let mut create = Command::new(&uv);
        create
            .args(["venv", "--python", DEFAULT_PYTHON])
            .arg(venv_dir)
            .env("UV_PYTHON_INSTALL_DIR", &runtimes)
            .env("UV_CACHE_DIR", &cache);
        if process::run(&mut create).is_err() {
            log_error("MicroserviceOperator", "failed to create venv with uv");
        }
        if has_installs(&config.python_packages) {
            let mut install = Command::new(&uv);
            install.args(["pip", "install", "--python"]).arg(&interpreter);
            add_packages(&mut install);
            extra_targets(&mut install);
            install.env("UV_CACHE_DIR", &cache);
            let _ = process::run(&mut install);
        }
    } else {
        // Fall back to the base venv interpreter's stdlib venv + pip.
        let base = venv_interpreter(&python_dir.join("venv"));
        let _ = process::run(Command::new(&base).arg("-m").arg("venv").arg(venv_dir));
        if has_installs(&config.python_packages) {
            let mut install = Command::new(&interpreter);
            install.arg("-m").arg("pip").arg("install");
            add_packages(&mut install);
            extra_targets(&mut install);
            let _ = process::run(&mut install);
        }
    }
    // Record the inputs we installed so we can skip/refresh next time.
    let _ = std::fs::write(&fingerprint_file, &fingerprint);
}

/// The default Python version for provisioned venvs.
const DEFAULT_PYTHON: &str = "3.12";

// ---------------------------------------------------------------------------
// Captured output (bounded ring of first N + last N lines)
// ---------------------------------------------------------------------------

struct CapturedOutput {
    /// Lines accumulated since the last `take_pending` (for live streaming).
    pending: Vec<String>,
    /// First N lines over the process's lifetime.
    start_lines: Vec<String>,
    /// Last N lines over the process's lifetime.
    end_lines: VecDeque<String>,
    max_start: usize,
    max_end: usize,
}

impl CapturedOutput {
    fn new() -> Self {
        Self {
            pending: Vec::new(),
            start_lines: Vec::new(),
            end_lines: VecDeque::new(),
            max_start: 100,
            max_end: 100,
        }
    }

    fn push(&mut self, line: String) {
        if self.start_lines.len() < self.max_start {
            self.start_lines.push(line.clone());
        } else {
            self.end_lines.push_back(line.clone());
            if self.end_lines.len() > self.max_end {
                self.end_lines.pop_front();
            }
        }
        self.pending.push(line);
    }

    fn take_pending(&mut self) -> Vec<String> {
        std::mem::take(&mut self.pending)
    }

    /// First N lines, an ellipsis, then the last N lines (for death messages).
    fn snapshot(&self) -> String {
        let mut out = self.start_lines.join("\n");
        if !self.end_lines.is_empty() {
            out.push_str("\n...\n");
            let tail: Vec<&str> = self.end_lines.iter().map(|s| s.as_str()).collect();
            out.push_str(&tail.join("\n"));
        }
        out
    }
}

// ---------------------------------------------------------------------------
// OperatorProcess
// ---------------------------------------------------------------------------

/// A single supervised child process.
pub struct OperatorProcess {
    cmd: Vec<String>,
    /// The service's own working directory (`microservices/<name>/`).
    work_dir: PathBuf,
    env: BTreeMap<String, String>,
    scope: String,
    child: Option<Child>,
    pid: Option<u32>,
    /// "<hostname>__<pid>" assigned at start, mirroring the Ruby `@name`.
    instance_name: String,
    stdout_buf: Arc<Mutex<CapturedOutput>>,
    stderr_buf: Arc<Mutex<CapturedOutput>>,
    /// When set, each stdout line is also forwarded up to COSMOS (api/log).
    log_tx: Option<UnboundedSender<String>>,
}

impl OperatorProcess {
    fn new(name: String, cmd: Vec<String>, work_dir: PathBuf, env: BTreeMap<String, String>) -> Self {
        Self {
            scope: scope_of(&name),
            cmd,
            work_dir,
            env,
            child: None,
            pid: None,
            instance_name: String::new(),
            stdout_buf: Arc::new(Mutex::new(CapturedOutput::new())),
            stderr_buf: Arc::new(Mutex::new(CapturedOutput::new())),
            log_tx: None,
        }
    }

    /// Forward this process's stdout lines up to COSMOS via the given sender.
    fn set_log_tx(&mut self, log_tx: Option<UnboundedSender<String>>) {
        self.log_tx = log_tx;
    }

    /// Replace this process's definition (changed config). Takes effect on the
    /// next `start`.
    fn update_definition(&mut self, cmd: Vec<String>, work_dir: PathBuf, env: BTreeMap<String, String>) {
        self.cmd = cmd;
        self.work_dir = work_dir;
        self.env = env;
    }

    /// Inject (or clear) the Iroh bridge ticket into the process environment.
    fn set_bridge_ticket(&mut self, ticket: Option<&str>) {
        match ticket {
            Some(t) => {
                self.env
                    .insert("OPENC3_BRIDGE_TICKET".to_string(), t.to_string());
            }
            None => {
                self.env.remove("OPENC3_BRIDGE_TICKET");
            }
        }
    }

    fn cmd_line(&self) -> String {
        self.cmd.join(" ")
    }

    fn start(&mut self) -> std::io::Result<()> {
        log_info(&self.scope, &format!("Starting: {}", self.cmd_line()));
        if self.cmd.is_empty() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "empty command",
            ));
        }
        // Ensure the service's working directory exists, then run there.
        std::fs::create_dir_all(&self.work_dir).ok();
        let mut command = Command::new(&self.cmd[0]);
        command.args(&self.cmd[1..]);
        command.current_dir(&self.work_dir);
        for (key, value) in &self.env {
            command.env(key, value);
        }
        command.env("OPENC3_SCOPE", &self.scope);
        command.stdout(Stdio::piped());
        command.stderr(Stdio::piped());

        let mut child = command.spawn()?;
        self.pid = Some(child.id());
        self.instance_name = format!("{}__{}", hostname(), child.id());
        if let Some(out) = child.stdout.take() {
            spawn_reader(out, self.stdout_buf.clone());
        }
        if let Some(err) = child.stderr.take() {
            spawn_reader(err, self.stderr_buf.clone());
        }
        self.child = Some(child);
        Ok(())
    }

    /// True if the process is currently running. Reaps it if it has exited.
    fn alive(&mut self) -> bool {
        match self.child.as_mut() {
            Some(child) => matches!(child.try_wait(), Ok(None)),
            None => false,
        }
    }

    /// Ask the process to stop gracefully (SIGINT on Unix). On Windows there is
    /// no SIGINT, so the subsequent hard stop handles it.
    fn soft_stop(&self) {
        if let Some(pid) = self.pid {
            log_info(&self.scope, &format!("Soft stopping: {}", self.cmd_line()));
            signal_int(pid);
        }
    }

    /// Forcefully terminate the process.
    fn hard_stop(&mut self) {
        let line = self.cmd_line();
        let scope = self.scope.clone();
        if let Some(child) = self.child.as_mut() {
            log_info(&scope, &format!("Hard stopping: {line}"));
            let _ = child.kill();
            let _ = child.wait();
        }
        self.child = None;
    }

    /// Stream any new output to stdout/stderr, mirroring `output_increment`.
    fn output_increment(&self) {
        if let Ok(mut buf) = self.stdout_buf.lock() {
            for line in buf.take_pending() {
                // Host microservices log COSMOS JSON per line via their own
                // Logger; echo verbatim (keeping our stdout uniformly JSON) and
                // capture for the in-app log table.
                crate::logging::capture_line(&line, &self.instance_name, false);
                // Forward host microservice stdout up to COSMOS so its Logger
                // records are logged in the main system too.
                if let Some(tx) = &self.log_tx {
                    let _ = tx.send(line);
                }
            }
        }
        if let Ok(mut buf) = self.stderr_buf.lock() {
            for line in buf.take_pending() {
                crate::logging::capture_line(&line, &self.instance_name, true);
            }
        }
    }

    /// Bounded snapshot of captured output for death messages.
    fn extract_output(&self) -> String {
        let stdout = self
            .stdout_buf
            .lock()
            .map(|b| b.snapshot())
            .unwrap_or_default();
        let stderr = self
            .stderr_buf
            .lock()
            .map(|b| b.snapshot())
            .unwrap_or_default();
        format!("Stdout:\n{stdout}\nStderr:\n{stderr}")
    }
}

fn spawn_reader<R: Read + Send + 'static>(reader: R, buf: Arc<Mutex<CapturedOutput>>) {
    std::thread::spawn(move || {
        let buffered = BufReader::new(reader);
        for line in buffered.lines() {
            match line {
                Ok(l) => {
                    if let Ok(mut b) = buf.lock() {
                        b.push(l);
                    }
                }
                Err(_) => break,
            }
        }
    });
}

#[cfg(unix)]
fn signal_int(pid: u32) {
    // Avoid a libc dependency: shell out to `kill -INT`.
    let _ = Command::new("kill")
        .arg("-INT")
        .arg(pid.to_string())
        .status();
}

#[cfg(not(unix))]
fn signal_int(_pid: u32) {
    // No SIGINT on Windows; the hard stop will terminate the process.
}

fn hostname() -> String {
    std::env::var("HOSTNAME")
        .ok()
        .or_else(|| std::env::var("COMPUTERNAME").ok())
        .unwrap_or_else(|| "localhost".to_string())
}

// ---------------------------------------------------------------------------
// MicroserviceOperator
// ---------------------------------------------------------------------------

/// Supervises host microservice processes, mirroring `MicroserviceOperator`.
pub struct MicroserviceOperator {
    /// All supervised processes by microservice name.
    processes: BTreeMap<String, OperatorProcess>,
    /// Current and previous desired configs, for change detection.
    microservices: ConfigMap,
    previous_microservices: ConfigMap,
    /// Names queued to start / restart / remove this cycle.
    new_names: Vec<String>,
    changed_names: Vec<String>,
    removed_names: Vec<String>,
    shard: i64,
    cycle_time: Duration,
    max_start_per_cycle: usize,
    shutdown: Arc<AtomicBool>,
    /// Published status snapshot for observers (e.g. the GUI).
    status: Arc<Mutex<Vec<MicroserviceStatus>>>,
    /// The app's isolated Python directory (`<root>/python`); used as the base
    /// for provisioning each Python microservice's own venv.
    python_dir: PathBuf,
    /// Base directory holding each microservice's working directory
    /// (`<root>/microservices/<name>/`).
    microservices_dir: PathBuf,
    /// Bridge (hub) ticket passed to each host microservice via
    /// OPENC3_BRIDGE_TICKET so it can dial the COSMOS bridge_microservice.
    bridge_ticket: Option<String>,
    /// Client to the COSMOS bridge_microservice hub: source of the host
    /// microservice list and destination for forwarded host logs.
    bridge_client: Option<BridgeClient>,
    /// Sender for forwarding host stdout up to COSMOS (from the bridge client).
    log_tx: Option<UnboundedSender<String>>,
    /// Per-host-microservice Iroh identities (name -> (secret_hex, public_hex)),
    /// minted on demand and held only in memory — the secret is handed to the
    /// child and never persisted. The public keys are authorized with the hub.
    host_keys: BTreeMap<String, (String, String)>,
    /// Published health of the connection to the COSMOS bridge hub (for the GUI).
    bridge_status: Arc<Mutex<BridgeConnectionStatus>>,
    /// Short reason openc3-app isn't paired (no bridge client), shown in the GUI.
    unpaired_reason: Option<String>,
    /// Called to (re)establish the bridge connection while unpaired.
    bridge_connector: Option<BridgeConnector>,
    /// How long the COSMOS containers have been up (None if down). Uses real
    /// container uptime, so an already-running COSMOS satisfies the warm-up
    /// immediately, and a restart (uptime drops) re-arms enrollment.
    cosmos_uptime: Option<CosmosUptime>,
    /// Earliest instant to run the next COSMOS check / enroll attempt.
    next_bridge_check: Instant,
    /// Enroll attempts made during the current COSMOS up-session (bounded).
    enroll_attempts: u32,
    /// Earliest instant to run the next plugin-file sync. Syncing hits the hub's
    /// (synchronous, event-loop-blocking) gem scan, so it's throttled well below
    /// the operator cycle rather than run every cycle.
    next_file_sync: Instant,
    /// Result of the most recent successful file sync, re-applied to configs each
    /// cycle so a throttled sync still provides PYTHONPATH / pip inputs.
    last_sync: Option<crate::hostfiles::SyncResult>,
}

/// Establishes (or re-establishes) the bridge connection; returns the hub ticket
/// and client, or a short human reason for the GUI. Retried while unpaired.
type BridgeConnector = Box<dyn Fn() -> Result<(String, BridgeClient), String> + Send>;
/// Returns how long the COSMOS containers have been up (None if not running).
type CosmosUptime = Box<dyn Fn() -> Option<Duration> + Send>;

/// COSMOS must be up this long before we attempt auto-enroll (lets the bridge
/// microservice finish starting and publish its ticket).
const BRIDGE_WARMUP: Duration = Duration::from_secs(30);
/// Throttle for the COSMOS check + spacing between enroll attempts.
const BRIDGE_CHECK_INTERVAL: Duration = Duration::from_secs(15);
/// Max enroll attempts per COSMOS up-session before giving up (until it
/// restarts) — so we don't cycle forever.
const BRIDGE_MAX_ATTEMPTS: u32 = 3;
/// How often to re-sync the scope's plugin files from the hub. Plugin code only
/// changes on install/upgrade, so this is intentionally slow: each sync triggers
/// a full gem scan on the hub, and syncing every cycle caused periodic latency
/// bursts in the bridged data stream.
const FILE_SYNC_INTERVAL: Duration = Duration::from_secs(60);

impl MicroserviceOperator {
    pub fn new(python_dir: PathBuf, microservices_dir: PathBuf) -> Self {
        let cycle_time = std::env::var("OPERATOR_CYCLE_TIME")
            .ok()
            .and_then(|v| v.parse::<f64>().ok())
            .map(Duration::from_secs_f64)
            .unwrap_or(CYCLE_TIME);
        let max_start_per_cycle = std::env::var("OPENC3_OPERATOR_MAX_START_PER_CYCLE")
            .ok()
            .and_then(|v| v.parse::<usize>().ok())
            .unwrap_or(MAX_START_PER_CYCLE);
        let shard = std::env::var("OPENC3_SHARD")
            .ok()
            .and_then(|v| v.parse::<i64>().ok())
            .unwrap_or(0);
        Self {
            processes: BTreeMap::new(),
            microservices: BTreeMap::new(),
            previous_microservices: BTreeMap::new(),
            new_names: Vec::new(),
            changed_names: Vec::new(),
            removed_names: Vec::new(),
            shard,
            cycle_time,
            max_start_per_cycle,
            shutdown: Arc::new(AtomicBool::new(false)),
            status: Arc::new(Mutex::new(Vec::new())),
            python_dir,
            microservices_dir,
            bridge_ticket: None,
            bridge_client: None,
            log_tx: None,
            host_keys: BTreeMap::new(),
            bridge_status: Arc::new(Mutex::new(BridgeConnectionStatus::default())),
            unpaired_reason: None,
            bridge_connector: None,
            cosmos_uptime: None,
            next_bridge_check: Instant::now(),
            enroll_attempts: 0,
            next_file_sync: Instant::now(),
            last_sync: None,
        }
    }


    /// A shared handle to the latest bridge connection status (read by the GUI).
    #[allow(dead_code)] // used by the GUI, not the headless binary
    pub fn bridge_status_handle(&self) -> Arc<Mutex<BridgeConnectionStatus>> {
        self.bridge_status.clone()
    }

    /// Publish the current bridge connection health for observers.
    fn publish_bridge_status(&self, configured: bool, connected: bool, message: &str) {
        if let Ok(mut status) = self.bridge_status.lock() {
            *status = BridgeConnectionStatus {
                configured,
                connected,
                message: message.to_string(),
            };
        }
    }

    /// Resolve a microservice config into the actual command and working
    /// directory, provisioning a per-service venv for Python microservices.
    fn resolve(&self, name: &str, config: &MicroserviceConfig) -> (Vec<String>, PathBuf) {
        let work_dir = self.microservices_dir.join(name);
        std::fs::create_dir_all(&work_dir).ok();
        if config.python {
            // The venv is provisioned/rebuilt at start time (see
            // provision_and_start), not here — so a dependency change can rebuild
            // it while the process is stopped. We only need its interpreter path.
            let venv = work_dir.join("venv");
            let mut cmd = vec![venv_interpreter(&venv).to_string_lossy().into_owned()];
            cmd.extend(config.cmd.iter().cloned());
            (cmd, work_dir)
        } else {
            (config.cmd.clone(), work_dir)
        }
    }

    /// Provision the microservice's venv (creating it, or rebuilding it if its
    /// dependency inputs changed) and then start the process. Called only from
    /// the start paths — after any stop — so a venv rebuild never races a live
    /// process. A no-op fast path when the venv is already up to date.
    fn provision_and_start(&mut self, name: &str) {
        if let Some(config) = self.microservices.get(name) {
            if config.python {
                let venv = self.microservices_dir.join(name).join("venv");
                ensure_venv(&self.python_dir, &venv, config);
            }
        }
        if let Some(process) = self.processes.get_mut(name) {
            if let Err(e) = process.start() {
                log_error(&scope_of(name), &format!("Failed to start {name}: {e}"));
            }
        }
    }

    /// Provide the connector used to (re)establish the bridge connection and a
    /// cheap check for whether the COSMOS containers are up. The operator only
    /// attempts auto-enroll once COSMOS has been up for [`BRIDGE_WARMUP`], makes
    /// a bounded number of attempts (so it doesn't cycle forever), and re-arms
    /// each time COSMOS restarts.
    pub fn set_bridge_connector(&mut self, connector: BridgeConnector, cosmos_uptime: CosmosUptime) {
        self.bridge_connector = Some(connector);
        self.cosmos_uptime = Some(cosmos_uptime);
        self.next_bridge_check = Instant::now();
        self.enroll_attempts = 0;
    }

    /// Apply a freshly-established connection: hand its ticket to host
    /// microservices (OPENC3_BRIDGE_TICKET) and wire the log forwarder.
    fn apply_connection(&mut self, ticket: String, client: BridgeClient) {
        self.bridge_ticket = Some(ticket);
        self.log_tx = Some(client.log_sender());
        self.bridge_client = Some(client);
        self.unpaired_reason = None;
    }

    /// While unpaired, gate auto-enroll on COSMOS being up for a warm-up period,
    /// with bounded attempts per up-session (re-armed on restart). Called once
    /// per operator cycle; throttled to [`BRIDGE_CHECK_INTERVAL`].
    fn maybe_connect(&mut self) {
        if self.bridge_client.is_some()
            || self.bridge_connector.is_none()
            || self.cosmos_uptime.is_none()
        {
            return;
        }
        let now = Instant::now();
        if now < self.next_bridge_check {
            return;
        }
        self.next_bridge_check = now + BRIDGE_CHECK_INTERVAL;

        let uptime = match &self.cosmos_uptime {
            Some(check) => check(),
            None => return,
        };
        match uptime {
            None => {
                // COSMOS down: reset so attempts re-arm when it starts.
                self.enroll_attempts = 0;
                self.unpaired_reason = Some("waiting for COSMOS to start".to_string());
                return;
            }
            // Freshly (re)started: wait for the warm-up. Resetting attempts here
            // is what re-arms enrollment each time COSMOS restarts.
            Some(up) if up < BRIDGE_WARMUP => {
                self.enroll_attempts = 0;
                self.unpaired_reason = Some("COSMOS starting — auto-enroll shortly".to_string());
                return;
            }
            Some(_) => {}
        }
        if self.enroll_attempts >= BRIDGE_MAX_ATTEMPTS {
            // Gave up for this up-session; wait for a COSMOS restart to re-arm.
            return;
        }
        self.enroll_attempts += 1;
        let result = match &self.bridge_connector {
            Some(connector) => connector(),
            None => return,
        };
        match result {
            Ok((ticket, client)) => {
                self.apply_connection(ticket, client);
                log_info("bridge", "Paired with COSMOS");
            }
            Err(reason) => {
                let gave_up = self.enroll_attempts >= BRIDGE_MAX_ATTEMPTS;
                self.unpaired_reason = Some(if gave_up {
                    format!("auto-enroll failed after {BRIDGE_MAX_ATTEMPTS} tries — pair with a token ({reason})")
                } else {
                    reason
                });
            }
        }
    }

    /// Pass a host microservice's stream/interface name so it dials the hub on
    /// the routed `stream/<name>` ALPN.
    fn apply_stream(process: &mut OperatorProcess, config: &MicroserviceConfig) {
        if let Some(stream) = &config.stream {
            process
                .env
                .insert("OPENC3_BRIDGE_CHANNEL".to_string(), stream.clone());
        }
    }

    /// A shared handle to the latest microservice status snapshot. Observers
    /// (e.g. the GUI) read this; the operator refreshes it each cycle.
    #[allow(dead_code)] // used by the GUI, not the headless binary
    pub fn status_handle(&self) -> Arc<Mutex<Vec<MicroserviceStatus>>> {
        self.status.clone()
    }

    /// Refresh the published status snapshot from the current processes.
    fn publish_status(&mut self) {
        let mut list = Vec::with_capacity(self.processes.len());
        for (name, process) in self.processes.iter_mut() {
            list.push(MicroserviceStatus {
                name: name.clone(),
                scope: process.scope.clone(),
                running: process.alive(),
                pid: process.pid,
                cmd: process.cmd_line(),
            });
        }
        if let Ok(mut status) = self.status.lock() {
            *status = list;
        }
    }

    /// A handle that can be used (e.g. from a signal handler) to request a
    /// graceful shutdown of the [`run`](Self::run) loop. Wired up when the real
    /// microservice list and lifecycle integration are added.
    #[allow(dead_code)]
    pub fn shutdown_handle(&self) -> Arc<AtomicBool> {
        self.shutdown.clone()
    }

    fn is_shutdown(&self) -> bool {
        self.shutdown.load(Ordering::Relaxed)
    }

    /// Fetch the desired microservices (this shard only), diff against the
    /// previous set, and queue the resulting new/changed/removed work.
    fn update(&mut self) {
        self.maybe_connect();
        self.previous_microservices = self.microservices.clone();
        let mut all = self.fetch();
        all.retain(|_name, config| config.shard == self.shard);
        self.microservices = all;

        let (new_map, changed_map, removed_map) = self.compute_changes();
        let ticket = self.bridge_ticket.clone();
        let log_tx = self.log_tx.clone();

        for (name, config) in &new_map {
            let (cmd, work_dir) = self.resolve(name, config);
            let mut process =
                OperatorProcess::new(name.clone(), cmd, work_dir, build_env(name, config));
            process.set_bridge_ticket(ticket.as_deref());
            process.set_log_tx(log_tx.clone());
            Self::apply_stream(&mut process, config);
            self.processes.insert(name.clone(), process);
            self.new_names.push(name.clone());
        }
        for (name, config) in &changed_map {
            let (cmd, work_dir) = self.resolve(name, config);
            let env = build_env(name, config);
            if let Some(process) = self.processes.get_mut(name) {
                process.update_definition(cmd, work_dir, env);
                process.set_bridge_ticket(ticket.as_deref());
                process.set_log_tx(log_tx.clone());
                Self::apply_stream(process, config);
                self.changed_names.push(name.clone());
            } else {
                // Shouldn't happen, but handle by creating it new.
                log_error(
                    &scope_of(name),
                    &format!("Changed microservice {name} does not exist. Creating new..."),
                );
                let mut process = OperatorProcess::new(name.clone(), cmd, work_dir, env);
                process.set_bridge_ticket(ticket.as_deref());
                process.set_log_tx(log_tx.clone());
                Self::apply_stream(&mut process, config);
                self.processes.insert(name.clone(), process);
                self.new_names.push(name.clone());
            }
        }
        for name in removed_map.keys() {
            self.removed_names.push(name.clone());
        }
    }

    /// Re-sync the scope's plugin files from the hub into `<root>/host_files`,
    /// caching the result in `self.last_sync`. Throttled to [`FILE_SYNC_INTERVAL`]
    /// (but always runs once, right after pairing, when nothing is cached yet)
    /// because each sync makes the hub scan every plugin gem — doing that every
    /// operator cycle stalled the hub's event loop and made the bridged data
    /// stream bursty. On failure the previous cache is kept and a retry happens
    /// next cycle rather than after the full interval.
    fn maybe_sync_files(&mut self) {
        let due = self.last_sync.is_none() || Instant::now() >= self.next_file_sync;
        if !due {
            return;
        }
        let Some(client) = &self.bridge_client else {
            return;
        };
        let host_files_dir = self
            .microservices_dir
            .parent()
            .unwrap_or(&self.microservices_dir)
            .join("host_files");
        match crate::hostfiles::sync(client, &host_files_dir) {
            Ok(sync) => {
                self.last_sync = Some(sync);
                self.next_file_sync = Instant::now() + FILE_SYNC_INTERVAL;
            }
            Err(error) => log_error("bridge", &format!("Failed to sync plugin files: {error}")),
        }
    }

    /// Fetch the desired host microservices from the bridge hub. On a transient
    /// poll failure the previous set is kept so running processes aren't torn
    /// down; with no bridge configured the set is empty.
    fn fetch(&mut self) -> ConfigMap {
        let Some(client) = &self.bridge_client else {
            let message = match &self.unpaired_reason {
                Some(reason) => format!("Not paired with COSMOS: {reason}"),
                None => "Not paired with COSMOS".to_string(),
            };
            self.publish_bridge_status(false, false, &message);
            return ConfigMap::new();
        };
        let specs = match client.fetch_host_microservices() {
            Ok(specs) => {
                self.publish_bridge_status(true, true, "Connected to COSMOS");
                specs
            }
            Err(error) => {
                self.publish_bridge_status(true, false, &format!("COSMOS unreachable: {error}"));
                log_error("bridge", &format!("Failed to fetch host microservices: {error}"));
                return self.microservices.clone();
            }
        };

        let mut configs = host_specs_to_configs(specs);

        // Sync the scope's plugin files (lib/, requirements, pyproject) so host
        // interfaces can use plugin code, then set each host runner's PYTHONPATH
        // and its venv's pip inputs from the (possibly cached) sync result. The
        // sync itself is throttled — see maybe_sync_files.
        self.maybe_sync_files();
        if let Some(sync) = &self.last_sync {
            let pythonpath = std::env::join_paths(&sync.lib_dirs)
                .ok()
                .map(|p| p.to_string_lossy().into_owned());
            let requirements: Vec<String> =
                sync.requirements.iter().map(|p| p.to_string_lossy().into_owned()).collect();
            let projects: Vec<String> =
                sync.projects.iter().map(|p| p.to_string_lossy().into_owned()).collect();
            for config in configs.values_mut() {
                if let Some(pp) = &pythonpath {
                    config.env.insert("PYTHONPATH".to_string(), pp.clone());
                }
                config.pip_requirements = requirements.clone();
                config.pip_projects = projects.clone();
                config.pip_fingerprint = sync.pip_fingerprint.clone();
            }
        }

        // Mint (or reuse) a per-microservice Iroh identity and hand it to the
        // child via env. The secret is only ever in memory + the child's env.
        let names: std::collections::BTreeSet<String> = configs.keys().cloned().collect();
        let mut authorized = Vec::with_capacity(configs.len());
        for (name, config) in configs.iter_mut() {
            let key = self
                .host_keys
                .entry(name.clone())
                .or_insert_with(crate::bridge::generate_host_key);
            config
                .env
                .insert("OPENC3_BRIDGE_PRIVATE_KEY".to_string(), key.0.clone());
            config
                .env
                .insert("OPENC3_BRIDGE_PUBLIC_KEY".to_string(), key.1.clone());
            authorized.push(key.1.clone());
        }
        // Forget identities for microservices that are no longer present.
        self.host_keys.retain(|name, _| names.contains(name));
        // Tell the hub which host identities may use the data path (before the
        // children connect), so only microservices we spawned are accepted.
        if let Some(client) = &self.bridge_client {
            if let Err(error) = client.authorize(authorized) {
                log_error("bridge", &format!("Failed to authorize host keys: {error}"));
            }
        }
        configs
    }

    /// Compute the new / changed / removed config maps from the current and
    /// previous microservice sets. Faithful port of the Ruby `handle_*`
    /// methods including parent-respawn behavior.
    fn compute_changes(&self) -> (ConfigMap, ConfigMap, ConfigMap) {
        let mut new = ConfigMap::new();
        let mut changed = ConfigMap::new();
        let mut removed = ConfigMap::new();

        for (name, config) in &self.microservices {
            match self.previous_microservices.get(name) {
                Some(prev) => {
                    if prev != config && !config.ignore_changes {
                        self.handle_changed(name, config, &mut new, &mut changed, &mut removed);
                    }
                }
                None => self.handle_new(name, config, &mut new, &mut changed),
            }
        }
        for (name, config) in &self.previous_microservices {
            if !self.microservices.contains_key(name) {
                self.handle_removed(name, config, &mut changed, &mut removed);
            }
        }
        (new, changed, removed)
    }

    /// Queue `parent` for a respawn if it exists in both the current and
    /// previous sets.
    fn respawn_parent(&self, parent: &str, changed: &mut ConfigMap) {
        if self.microservices.contains_key(parent) && self.previous_microservices.contains_key(parent)
        {
            changed.insert(parent.to_string(), self.microservices[parent].clone());
        }
    }

    fn handle_new(
        &self,
        name: &str,
        config: &MicroserviceConfig,
        new: &mut ConfigMap,
        changed: &mut ConfigMap,
    ) {
        if !config.enabled {
            return;
        }
        match &config.parent {
            Some(parent) => self.respawn_parent(parent, changed),
            None => {
                new.insert(name.to_string(), config.clone());
            }
        }
    }

    fn handle_changed(
        &self,
        name: &str,
        config: &MicroserviceConfig,
        new: &mut ConfigMap,
        changed: &mut ConfigMap,
        removed: &mut ConfigMap,
    ) {
        let prev = &self.previous_microservices[name];
        let parent = &config.parent;
        let enabled = config.enabled;
        let previous_parent = &prev.parent;
        let previous_enabled = prev.enabled;

        if parent.is_some() || previous_parent.is_some() {
            if parent == previous_parent {
                // Same parent - respawn it.
                if let Some(p) = parent {
                    self.respawn_parent(p, changed);
                }
            } else if let (Some(p), Some(pp)) = (parent, previous_parent) {
                // Parent changed - respawn both.
                self.respawn_parent(p, changed);
                self.respawn_parent(pp, changed);
            } else if let Some(p) = parent {
                // Moved under a parent - respawn parent and kill standalone.
                self.respawn_parent(p, changed);
                if previous_enabled {
                    removed.insert(name.to_string(), config.clone());
                }
            } else if let Some(pp) = previous_parent {
                // Moved to standalone - respawn previous parent, make new.
                self.respawn_parent(pp, changed);
                if enabled {
                    new.insert(name.to_string(), config.clone());
                }
            }
        } else if previous_enabled {
            if enabled {
                changed.insert(name.to_string(), config.clone());
            } else {
                removed.insert(name.to_string(), config.clone());
            }
        } else {
            new.insert(name.to_string(), config.clone());
        }
    }

    fn handle_removed(
        &self,
        name: &str,
        config: &MicroserviceConfig,
        changed: &mut ConfigMap,
        removed: &mut ConfigMap,
    ) {
        let prev = &self.previous_microservices[name];
        match &prev.parent {
            Some(pp) => self.respawn_parent(pp, changed),
            None => {
                if prev.enabled {
                    removed.insert(name.to_string(), config.clone());
                }
            }
        }
    }

    fn start_new(&mut self) {
        if self.new_names.is_empty() {
            return;
        }
        let total = self.new_names.len();
        let count = self.cycle_count(total);
        log_info(
            "MicroserviceOperator",
            &format!("starting {count} of {total} new process(es)..."),
        );
        let to_start: Vec<String> = self.new_names.drain(0..count).collect();
        for name in to_start {
            self.provision_and_start(&name);
        }
    }

    fn respawn_changed(&mut self) {
        if self.changed_names.is_empty() {
            return;
        }
        let total = self.changed_names.len();
        let count = self.cycle_count(total);
        let cycle: Vec<String> = self.changed_names.drain(0..count).collect();
        log_info(
            "MicroserviceOperator",
            &format!("Cycling {count} of {total} changed microservices..."),
        );
        self.shutdown_processes(&cycle);
        if self.is_shutdown() {
            return;
        }
        for name in cycle {
            // Processes are stopped above, so a venv rebuild here is safe.
            self.provision_and_start(&name);
        }
    }

    fn remove_old(&mut self) {
        if self.removed_names.is_empty() {
            return;
        }
        let names = std::mem::take(&mut self.removed_names);
        log_info(
            "MicroserviceOperator",
            &format!("Shutting down {} removed microservices...", names.len()),
        );
        self.shutdown_processes(&names);
        for name in &names {
            self.processes.remove(name);
        }
    }

    fn respawn_dead(&mut self) {
        let names: Vec<String> = self.processes.keys().cloned().collect();
        for name in names {
            if self.is_shutdown() {
                break;
            }
            // Skip processes still queued by the per-cycle start limit.
            if self.new_names.contains(&name) {
                continue;
            }
            let mut needs_restart = false;
            if let Some(process) = self.processes.get_mut(&name) {
                process.output_increment();
                if !process.alive() {
                    let output = process.extract_output();
                    log_error(
                        &process.scope,
                        &format!(
                            "Unexpected process died... respawning! {}\n{output}",
                            process.cmd_line()
                        ),
                    );
                    process.hard_stop();
                    needs_restart = true;
                }
            }
            if needs_restart {
                // Process is stopped; provision (fast no-op if unchanged) + start.
                self.provision_and_start(&name);
            }
        }
    }

    /// Number of processes to (re)start this cycle, honoring the per-cycle cap.
    fn cycle_count(&self, total: usize) -> usize {
        if self.max_start_per_cycle > 0 {
            total.min(self.max_start_per_cycle)
        } else {
            total
        }
    }

    /// Soft-stop the named processes, wait up to [`PROCESS_SHUTDOWN`], then
    /// hard-stop any still alive.
    fn shutdown_processes(&mut self, names: &[String]) {
        log_info("MicroserviceOperator", "Commanding soft stops...");
        for name in names {
            if let Some(process) = self.processes.get(name) {
                process.soft_stop();
            }
        }
        let start = Instant::now();
        let mut remaining: Vec<String> = names.to_vec();
        while start.elapsed() < PROCESS_SHUTDOWN {
            remaining.retain(|name| {
                self.processes
                    .get_mut(name)
                    .map(|p| p.alive())
                    .unwrap_or(false)
            });
            if remaining.is_empty() {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        for name in names {
            if let Some(process) = self.processes.get_mut(name) {
                process.output_increment();
                let _ = process.extract_output();
                process.hard_stop();
            }
        }
    }

    /// Run the monitor loop until shutdown is requested, then stop all
    /// processes. Blocks the calling thread.
    pub fn run(&mut self) {
        log_info(
            "MicroserviceOperator",
            &format!(
                "Monitoring processes every {} sec...",
                self.cycle_time.as_secs_f64()
            ),
        );
        loop {
            self.update();
            self.remove_old();
            self.respawn_changed();
            self.start_new();
            self.respawn_dead();
            self.publish_status();
            if self.is_shutdown() {
                break;
            }
            self.interruptible_sleep(self.cycle_time);
            if self.is_shutdown() {
                break;
            }
        }
        log_info("MicroserviceOperator", "Shutting down processes...");
        let all: Vec<String> = self.processes.keys().cloned().collect();
        self.shutdown_processes(&all);
        self.publish_status();
        log_info("MicroserviceOperator", "shutdown complete");
    }

    /// Sleep for `dur`, waking early if shutdown is requested.
    fn interruptible_sleep(&self, dur: Duration) {
        let start = Instant::now();
        while start.elapsed() < dur {
            if self.is_shutdown() {
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }
}

/// The host-side interface runner module (part of the `openc3` Python package),
/// run in each host microservice's venv.
const HOST_INTERFACE_MODULE: &str = "openc3.microservices.host_interface_microservice";

/// Convert the host microservice specs from the bridge hub into supervised
/// microservice configs. Each host interface runs the host interface runner in
/// its own Python venv; the operator hands it the bridge (hub) ticket and its
/// stream name so it dials the hub directly on `stream/<name>`.
fn host_specs_to_configs(specs: Vec<HostSpec>) -> ConfigMap {
    let mut map = ConfigMap::new();
    for spec in specs {
        // The real interface's class + params and (secret-resolved) options are
        // forwarded to the runner as opaque JSON.
        let host_interface = serde_json::json!({
            "config_params": spec.config_params,
            "options": spec.options,
        })
        .to_string();
        let mut env = spec.env.clone();
        env.insert("OPENC3_HOST_INTERFACE".to_string(), host_interface);
        // The host has no COSMOS Redis; the Logger writes JSON to stdout only
        // (openc3-app forwards it up to COSMOS via api/log).
        env.insert("OPENC3_NO_STORE".to_string(), "1".to_string());
        let config = MicroserviceConfig {
            python: true,
            python_packages: vec!["iroh".to_string(), "openc3".to_string()],
            stream: Some(spec.stream.clone()),
            cmd: vec![
                "-u".to_string(),
                "-m".to_string(),
                HOST_INTERFACE_MODULE.to_string(),
            ],
            env,
            needs_dependencies: spec.needs_dependencies,
            ..Default::default()
        };
        map.insert(spec.name.clone(), config);
    }
    map
}

fn log_info(scope: &str, msg: &str) {
    crate::logging::info(scope, msg);
}

fn log_error(scope: &str, msg: &str) {
    crate::logging::error(scope, msg);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg(parent: Option<&str>, enabled: bool) -> MicroserviceConfig {
        MicroserviceConfig {
            cmd: vec!["true".to_string()],
            parent: parent.map(|s| s.to_string()),
            enabled,
            ..Default::default()
        }
    }

    fn operator_with(current: ConfigMap, previous: ConfigMap) -> MicroserviceOperator {
        let mut op = MicroserviceOperator::new("python".into(), "microservices".into());
        op.microservices = current;
        op.previous_microservices = previous;
        op
    }

    #[test]
    fn detects_new_standalone() {
        let mut current = ConfigMap::new();
        current.insert("SCOPE__A".into(), cfg(None, true));
        let op = operator_with(current, ConfigMap::new());
        let (new, changed, removed) = op.compute_changes();
        assert!(new.contains_key("SCOPE__A"));
        assert!(changed.is_empty());
        assert!(removed.is_empty());
    }

    #[test]
    fn detects_removed_standalone() {
        let mut previous = ConfigMap::new();
        previous.insert("SCOPE__A".into(), cfg(None, true));
        let op = operator_with(ConfigMap::new(), previous);
        let (new, changed, removed) = op.compute_changes();
        assert!(removed.contains_key("SCOPE__A"));
        assert!(new.is_empty());
        assert!(changed.is_empty());
    }

    #[test]
    fn detects_changed_standalone() {
        let mut previous = ConfigMap::new();
        previous.insert("SCOPE__A".into(), cfg(None, true));
        let mut current = ConfigMap::new();
        let mut changed_cfg = cfg(None, true);
        changed_cfg.cmd = vec!["false".to_string()];
        current.insert("SCOPE__A".into(), changed_cfg);
        let op = operator_with(current, previous);
        let (_new, changed, _removed) = op.compute_changes();
        assert!(changed.contains_key("SCOPE__A"));
    }

    #[test]
    fn new_child_respawns_existing_parent() {
        // Parent exists in both current and previous; a new child should
        // respawn the parent rather than start standalone.
        let mut previous = ConfigMap::new();
        previous.insert("SCOPE__PARENT".into(), cfg(None, true));
        let mut current = ConfigMap::new();
        current.insert("SCOPE__PARENT".into(), cfg(None, true));
        current.insert("SCOPE__CHILD".into(), cfg(Some("SCOPE__PARENT"), true));
        let op = operator_with(current, previous);
        let (new, changed, _removed) = op.compute_changes();
        assert!(changed.contains_key("SCOPE__PARENT"));
        assert!(!new.contains_key("SCOPE__CHILD"));
    }
}
