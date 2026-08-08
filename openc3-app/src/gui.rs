//! Iced-based graphical control panel. This is the default front-end (the app
//! launches into it when run with no subcommand). It shows live container
//! health and offers buttons for the common lifecycle actions. Long-running
//! actions run on background threads so the UI stays responsive; their
//! high-level progress is mirrored into an in-app log while detailed container
//! output streams to the controlling terminal.

use crate::context::{Context, Runtime};
use crate::monitor::{self, ContainerStatus};
use crate::operator::{BridgeConnectionStatus, MicroserviceOperator, MicroserviceStatus};
use crate::{commands, install};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use iced::widget::image::Handle as ImageHandle;
use iced::widget::{
    button, checkbox, column, container, horizontal_rule, opaque, pick_list, progress_bar, row,
    scrollable, stack, text, text_editor, text_input, Image, Space,
};
use iced::{window, Center, Color, Element, Font, Length, Size, Subscription, Task, Theme};

/// The app-tile logo shown on the splash screen (embedded PNG).
const SPLASH_LOGO: &[u8] = include_bytes!("../assets/icons/512x512.png");

/// Embedded icon font (a single gear glyph at U+E900), loaded at startup. Using
/// an embedded font is the cross-platform way to get the gear: the bundled UI
/// font has no gear glyph (U+2699 renders as tofu) and the tiny-skia software
/// renderer doesn't reliably paint the svg/canvas layers, but text renders and
/// positions correctly everywhere. See build note in assets/README.
const ICON_FONT_BYTES: &[u8] = include_bytes!("../assets/openc3-icons.ttf");
/// Font family name baked into the icon TTF; how iced references it.
const ICON_FONT: Font = Font::with_name("openc3-icons");
/// The gear glyph's codepoint in [`ICON_FONT`] (Private Use Area).
const GEAR_GLYPH: &str = "\u{E900}";
/// The close (X) glyph's codepoint in [`ICON_FONT`] (Private Use Area).
const CLOSE_GLYPH: &str = "\u{E901}";
/// Disclosure carets in [`ICON_FONT`] (Private Use Area). Shipped in our own
/// font because some Windows font fallbacks lack the Unicode triangle U+25B6
/// (it rendered as tofu / a white square).
const CARET_RIGHT_GLYPH: &str = "\u{E902}";
const CARET_DOWN_GLYPH: &str = "\u{E903}";
/// Light grey that reads on the dark UI, used for the gear icon.
const GEAR_COLOR: Color = Color::from_rgb(0.81, 0.81, 0.81);

/// How long the splash screen is displayed before advancing.
const SPLASH_DURATION: Duration = Duration::from_secs(3);

/// Frames for the textual loading spinner. ASCII so they render in any font
/// (braille spinner glyphs show as missing-glyph boxes in the GUI font).
const SPINNER: [&str; 4] = ["|", "/", "-", "\\"];

/// The three top-level pages of the application.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Page {
    Splash,
    Install,
    Main,
}

/// Minimum severity shown in the log table (like LogMessages.vue's level select).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LogLevelFilter {
    Debug,
    Info,
    Warn,
    Error,
    Fatal,
}

impl LogLevelFilter {
    const ALL: [LogLevelFilter; 5] = [
        LogLevelFilter::Debug,
        LogLevelFilter::Info,
        LogLevelFilter::Warn,
        LogLevelFilter::Error,
        LogLevelFilter::Fatal,
    ];

    /// Severity rank; a record shows when its level rank >= the filter's rank.
    fn rank(self) -> u8 {
        match self {
            LogLevelFilter::Debug => 0,
            LogLevelFilter::Info => 1,
            LogLevelFilter::Warn => 2,
            LogLevelFilter::Error => 3,
            LogLevelFilter::Fatal => 4,
        }
    }
}

impl std::fmt::Display for LogLevelFilter {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            LogLevelFilter::Debug => "DEBUG",
            LogLevelFilter::Info => "INFO",
            LogLevelFilter::Warn => "WARN",
            LogLevelFilter::Error => "ERROR",
            LogLevelFilter::Fatal => "FATAL",
        };
        f.write_str(s)
    }
}

/// Severity rank of a record's level string (unknown levels sort as INFO).
fn level_rank(level: &str) -> u8 {
    match level {
        "DEBUG" => 0,
        "WARN" => 2,
        "ERROR" => 3,
        "FATAL" => 4,
        _ => 1, // INFO and anything unrecognized
    }
}

/// Display color for a log level, roughly matching the Astro status colors used
/// by the COSMOS LogMessages component.
fn level_color(level: &str) -> Color {
    match level {
        "DEBUG" => Color::from_rgb8(0x9E, 0x9E, 0x9E),
        "WARN" => Color::from_rgb8(0xFF, 0xB3, 0x00),
        "ERROR" | "FATAL" => Color::from_rgb8(0xF4, 0x43, 0x36),
        _ => Color::from_rgb8(0x4C, 0xAF, 0x50), // INFO / normal
    }
}

/// Result of the startup environment check.
#[derive(Debug, Clone, Copy)]
struct EnvCheck {
    /// A docker or podman daemon is installed *and running* (reachable).
    container_ok: bool,
    /// A docker or podman binary is installed (whether or not it's running).
    container_installed: bool,
    /// The isolated Python runtime is installed.
    python_ok: bool,
    /// The COSMOS environment (cosmos-project folder) is installed.
    cosmos_ok: bool,
    /// Windows: the optional features Docker's WSL2 backend needs (Virtual
    /// Machine Platform, Windows Hypervisor Platform, WSL) are all enabled.
    /// Always true off Windows.
    windows_features_ok: bool,
    /// Windows: hardware virtualization (VT-x/AMD-V) state from firmware.
    /// `Some(false)` means it's disabled in the BIOS/UEFI (a hard blocker the app
    /// can't fix); `Some(true)` enabled; `None` unknown. Always `None` off Windows.
    virtualization: Option<bool>,
}


/// Data produced by background worker threads, polled by the UI on each tick.
#[derive(Default)]
struct Shared {
    busy: bool,
    /// Freshly fetched container logs, consumed by the UI on the next tick.
    fetched_logs: Option<String>,
    /// A status refresh (which runs the blocking `docker ps`/`stats`) is in
    /// flight on a background thread.
    refreshing: bool,
    /// Latest status snapshot, consumed by the UI on the next tick.
    statuses: Option<Vec<ContainerStatus>>,
    /// Whether COSMOS is up and serving its web UI (index.html).
    cosmos_ready: Option<bool>,
    /// An environment re-check (which runs the blocking `docker info`) is in
    /// flight; its result lands in `env`.
    checking_env: bool,
    env: Option<EnvCheck>,
    /// Set by the enable-Windows-features task on success: the features only take
    /// effect after a reboot, so the UI should prompt the user to restart.
    restart_pending: bool,
    /// An important instruction (e.g. post-install NEXT STEPS) emitted by a task,
    /// to be shown as a dismissible popup on the next tick.
    pending_dialog: Option<String>,
    /// The most recent progress line from a running task (e.g. a `docker compose`
    /// pull line), shown live as the busy indicator's status.
    activity: Option<String>,
}

struct State {
    ctx: Context,
    /// The primary window; closing it exits the app.
    main_window: window::Id,
    /// The separate logs window, when open.
    logs_window: Option<window::Id>,
    page: Page,
    /// When the splash screen first appeared.
    splash_start: Instant,
    /// Latest environment check result (drives the install page).
    env: EnvCheck,
    shared: Arc<Mutex<Shared>>,
    statuses: Vec<ContainerStatus>,
    /// Shared status from the host microservice operator (the "bridge"), and a
    /// display copy refreshed each tick.
    operator_status: Arc<Mutex<Vec<MicroserviceStatus>>>,
    operator_shutdown: Arc<AtomicBool>,
    operator_thread: Option<JoinHandle<()>>,
    microservices: Vec<MicroserviceStatus>,
    /// Shared + display copy of the COSMOS bridge connection health.
    bridge_status_handle: Arc<Mutex<BridgeConnectionStatus>>,
    bridge_status: BridgeConnectionStatus,
    /// Whether COSMOS is up and serving its web UI; gates the Open button.
    cosmos_ready: bool,
    /// False until the first status snapshot has been received.
    status_loaded: bool,
    /// Whether the Container Status section is collapsed (starts collapsed,
    /// showing just a summary; click the header to expand the full table).
    status_collapsed: bool,
    /// Animation frame for the loading spinner.
    spinner: usize,
    /// Snapshot of captured log records (from [`crate::logging`]) for the log
    /// table, refreshed each tick unless paused.
    log_records: Vec<crate::logging::LogRecord>,
    /// Minimum level shown in the log table.
    log_level: LogLevelFilter,
    /// Case-insensitive substring filter over the log message/source.
    log_search: String,
    /// When true, the table stops refreshing so rows can be read/scrolled.
    log_paused: bool,
    busy: bool,
    /// When set, the UI shows the logs panel for this service.
    viewing_logs: Option<String>,
    /// Editable-buffer holding the fetched logs (read-only, but selectable).
    logs_content: text_editor::Content,
    /// Whether the destructive cleanup confirmation screen is showing, and the
    /// text the user has typed into its confirmation field.
    cleanup_confirm: bool,
    cleanup_input: String,
    /// Enrollment token the user is entering to pair with a remote COSMOS bridge.
    /// A multi-line editor so the long token wraps instead of overflowing.
    bridge_token_content: text_editor::Content,
    /// True while a manual pairing is running on a background thread (keeps the
    /// UI responsive and guards against re-submitting).
    bridge_pairing: Arc<AtomicBool>,
    /// Shared with the operator; the "Retry" button sets it to re-arm bridge
    /// enrollment. Persists across operator restarts (pairing).
    bridge_retry: Arc<AtomicBool>,
    /// Handles for an operator started by a background pairing task, handed back
    /// to the UI thread (swapped in on the next tick) so pairing never blocks.
    next_operator: Arc<Mutex<Option<OperatorHandles>>>,
    /// Whether the Settings dialog (cleanup + bridge pairing) is showing.
    settings_open: bool,
    /// Persisted settings (COSMOS URL, run-locally toggle).
    settings: crate::settings::Settings,
    /// The effective Development-mode context (dev folder, or None) captured when
    /// the Settings page was opened. On close we compare against the current
    /// context; if it changed we restart the operator so the bridge re-enrolls
    /// against the new compose context.
    dev_context_on_open: Option<std::path::PathBuf>,
    /// Whether the "Shutdown COSMOS?" confirmation modal is showing.
    shutdown_confirm: bool,
    /// Whether the "Quit OpenC3 COSMOS?" confirmation modal is showing. Only used
    /// where there's no tray to hide to (Linux), so the close (X) button asks
    /// before actually exiting.
    quit_confirm: bool,
    /// Whether to show the "restart Windows" prompt (a Windows feature was just
    /// enabled and only takes effect after a reboot).
    restart_pending: bool,
    /// Text of a dismissible instruction popup (post-install NEXT STEPS), if one
    /// is currently showing.
    dialog: Option<String>,
    /// Latest progress line from the running task, shown by the busy indicator.
    activity: Option<String>,
    /// Single-instance lock held for our lifetime; also lets us poll for a later
    /// launch's request to surface our window.
    singleton: crate::single_instance::Guard,
}

/// Start the host microservice operator on a background thread, wiring the
/// bridge client. openc3-app is a client of the COSMOS bridge_microservice hub;
/// [`crate::enroll::connect_bridge`] resolves its identity and the hub ticket
/// (auto-enrolling co-located, or using a previously redeemed manual token).
type OperatorHandles = (
    Arc<Mutex<Vec<MicroserviceStatus>>>,
    Arc<Mutex<BridgeConnectionStatus>>,
    Arc<AtomicBool>,
    Option<JoinHandle<()>>,
);

fn start_operator(ctx: &Context, retry: Arc<AtomicBool>) -> OperatorHandles {
    let mut operator =
        MicroserviceOperator::new(ctx.paths.python.clone(), ctx.paths.microservices.clone());
    // Auto-enroll runs in the operator loop once COSMOS has been up a while
    // (retried, bounded, re-armed on restart). Give it a connector + a cheap
    // COSMOS-up check, both capturing the context.
    let connect_ctx = ctx.clone();
    let ready_ctx = ctx.clone();
    operator.set_bridge_connector(
        Box::new(move || crate::enroll::connect_bridge(&connect_ctx)),
        // Classify COSMOS container readiness (running/uptime, or a specific
        // reason it isn't) so the unpaired status explains why. Uptime only — no
        // CPU/mem stats (the slow part).
        Box::new(move || crate::monitor::cosmos_readiness(&ready_ctx, false)),
    );
    operator.set_retry_flag(retry);
    let status = operator.status_handle();
    let bridge_status = operator.bridge_status_handle();
    let shutdown = operator.shutdown_handle();
    let thread = Some(std::thread::spawn(move || operator.run()));
    (status, bridge_status, shutdown, thread)
}

#[derive(Debug, Clone)]
enum Message {
    Tick,
    InstallDocker,
    InstallDockerMac,
    InstallDockerWin,
    /// Windows: enable the WSL2/virtualization optional features Docker needs.
    EnableWindowsFeatures,
    /// Windows: restart now to apply newly-enabled features.
    RestartWindows,
    /// Dismiss the restart prompt (restart later).
    DismissRestart,
    /// Dismiss the instruction popup (NEXT STEPS).
    DismissDialog,
    StartDocker,
    InstallPython,
    InstallCosmos,
    Skip,
    Start,
    /// Ask to shut COSMOS down — opens the confirmation modal.
    Stop,
    /// Confirm the shutdown (from the modal) and actually stop COSMOS.
    ConfirmShutdown,
    /// Dismiss the shutdown confirmation modal without stopping.
    CancelShutdown,
    /// Confirm quitting the app (from the no-tray close prompt) and exit.
    ConfirmQuit,
    /// Dismiss the quit confirmation modal and keep running.
    CancelQuit,
    OpenBrowser,
    ShowSettings,
    CloseSettings,
    CosmosUrlChanged(String),
    RunLocallyToggled(bool),
    EditionChanged(crate::settings::Edition),
    EnterpriseTokenChanged(String),
    DevModeToggled(bool),
    DevFolderChanged(String),
    BrowseDevFolder,
    DevFolderPicked(Option<std::path::PathBuf>),
    LogLevelChanged(LogLevelFilter),
    LogSearchChanged(String),
    ToggleLogPause,
    ClearLog,
    ShowCleanup,
    CleanupInputChanged(String),
    ConfirmCleanup,
    CancelCleanup,
    BridgeTokenAction(text_editor::Action),
    SubmitBridgeToken,
    /// Re-arm bridge auto-enrollment (the "Retry" button).
    RetryBridge,
    /// Expand/collapse the Container Status section.
    ToggleStatus,
    ViewLogs(String),
    RefreshLogs,
    CloseLogs,
    LogsAction(text_editor::Action),
    /// The user requested a window close (e.g. the OS X button).
    CloseRequested(window::Id),
    /// Poll the system tray for menu clicks (Show/Quit).
    PollTray,
    /// A window was actually closed/destroyed.
    WindowClosed(window::Id),
    /// No-op (used to discard the result of window::open).
    Ignore,
}

impl State {
    fn new(mut ctx: Context, main_window: window::Id, singleton: crate::single_instance::Guard) -> Self {
        let settings = crate::settings::Settings::load(&ctx);
        // The persisted edition is the source of truth in the GUI.
        ctx.enterprise = settings.edition.is_enterprise();
        // Development mode: source folder first, then env overrides derived from it.
        ctx.dev_folder = dev_folder_from_settings(&settings);
        apply_dev_env(settings.dev_mode, ctx.dev_folder.as_deref());
        let env = EnvCheck {
            container_ok: ctx.runtime.is_some(),
            container_installed: crate::context::container_engine_installed(),
            python_ok: ctx.paths.python_installed(),
            cosmos_ok: ctx.paths.cosmos_installed(),
            windows_features_ok: install::missing_windows_features().is_empty(),
            virtualization: install::virtualization_enabled(),
        };

        // Start the host microservice operator (process spawner/monitor) on a
        // background thread and keep a handle to its published status.
        let bridge_retry = Arc::new(AtomicBool::new(false));
        let (operator_status, bridge_status_handle, operator_shutdown, operator_thread) =
            start_operator(&ctx, bridge_retry.clone());

        crate::logging::info("openc3-app", "OpenC3 COSMOS control panel ready.");

        Self {
            ctx,
            main_window,
            logs_window: None,
            page: Page::Splash,
            splash_start: Instant::now(),
            env,
            shared: Arc::new(Mutex::new(Shared::default())),
            statuses: Vec::new(),
            operator_status,
            operator_shutdown,
            operator_thread,
            bridge_status_handle,
            bridge_status: BridgeConnectionStatus::default(),
            microservices: Vec::new(),
            cosmos_ready: false,
            status_loaded: false,
            status_collapsed: true,
            spinner: 0,
            log_records: Vec::new(),
            log_level: LogLevelFilter::Info,
            log_search: String::new(),
            log_paused: false,
            busy: false,
            viewing_logs: None,
            logs_content: text_editor::Content::new(),
            cleanup_confirm: false,
            cleanup_input: String::new(),
            bridge_token_content: text_editor::Content::new(),
            bridge_pairing: Arc::new(AtomicBool::new(false)),
            bridge_retry,
            next_operator: Arc::new(Mutex::new(None)),
            settings_open: false,
            settings,
            // Set when the Settings page opens; only compared on close.
            dev_context_on_open: None,
            shutdown_confirm: false,
            quit_confirm: false,
            restart_pending: false,
            dialog: None,
            activity: None,
            singleton,
        }
    }

    /// Re-detect the environment on a background thread. The container check
    /// runs `docker info` (so it reflects a *reachable* engine, not just an
    /// installed binary), which can block briefly — hence off the UI thread.
    /// The result is delivered to `self.env` via [`drain_shared`]. A
    /// `checking_env` flag prevents overlapping checks.
    fn maybe_refresh_env(&self) {
        {
            let mut s = self.shared.lock().unwrap();
            if s.checking_env {
                return;
            }
            s.checking_env = true;
        }
        let paths = self.ctx.paths.clone();
        let shared = self.shared.clone();
        std::thread::spawn(move || {
            let env = EnvCheck {
                container_ok: crate::context::container_engine_running(),
                container_installed: crate::context::container_engine_installed(),
                python_ok: paths.python_installed(),
                cosmos_ok: paths.cosmos_installed(),
                windows_features_ok: install::missing_windows_features().is_empty(),
                virtualization: install::virtualization_enabled(),
            };
            if let Ok(mut s) = shared.lock() {
                s.env = Some(env);
                s.checking_env = false;
            }
        });
    }

    /// Advance to the main page, refreshing the detected container runtime so
    /// it reflects anything installed during this session.
    fn go_main(&mut self) {
        self.ctx.runtime = Runtime::detect();
        self.page = Page::Main;
        self.maybe_refresh_status();
    }

    /// Re-apply development-mode settings: the process-env tag overrides and the
    /// context's dev source folder.
    fn apply_dev_settings(&mut self) {
        self.ctx.dev_folder = dev_folder_from_settings(&self.settings);
        apply_dev_env(self.settings.dev_mode, self.ctx.dev_folder.as_deref());
    }

    /// Restart the host-microservice operator so it picks up the current context
    /// (e.g. after a Development-mode compose-context switch). When `reenroll`,
    /// any auto-enrolled ticket is dropped first so enrollment re-runs against the
    /// new context instead of reusing a ticket for the old one; a manual token is
    /// preserved (see `forget_cached_ticket`). Runs on a background thread; the
    /// fresh handles are swapped in on the next tick via `next_operator`, so the
    /// UI never blocks and the operator's bridge closures capture the updated `ctx`.
    fn restart_operator(&mut self, reenroll: bool) {
        let ctx = self.ctx.clone();
        let shutdown = self.operator_shutdown.clone();
        let old_thread = self.operator_thread.take();
        let retry = self.bridge_retry.clone();
        let next_operator = self.next_operator.clone();
        std::thread::spawn(move || {
            if reenroll {
                crate::enroll::forget_cached_ticket(&ctx.paths.root);
            }
            // Tell the old operator to stop and wait for it, so we don't run two
            // operators (double host microservices) against the same bridge.
            shutdown.store(true, Ordering::Relaxed);
            if let Some(handle) = old_thread {
                let _ = handle.join();
            }
            let handles = start_operator(&ctx, retry);
            if let Ok(mut slot) = next_operator.lock() {
                *slot = Some(handles);
            }
        });
    }

    /// Whether the setup page should be shown. Running COSMOS locally needs
    /// Docker + Python + the COSMOS environment (plus, on Windows, the WSL2/
    /// virtualization features Docker depends on); running against a remote
    /// COSMOS only needs the host Python runtime (for the bridge microservices).
    fn needs_setup(&self) -> bool {
        if self.settings.run_locally {
            !(self.env.windows_features_ok
                && self.env.container_ok
                && self.env.python_ok
                && self.env.cosmos_ok)
        } else {
            !self.env.python_ok
        }
    }

    /// Trigger a status refresh on a background thread (the snapshot runs the
    /// blocking `docker ps`/`stats`, so it must never run on the UI thread).
    /// Results are delivered to the UI via [`drain_shared`]. A `refreshing`
    /// flag prevents overlapping refreshes from piling up.
    fn maybe_refresh_status(&self) {
        {
            let mut s = self.shared.lock().unwrap();
            if s.refreshing {
                return;
            }
            s.refreshing = true;
        }
        let ctx = self.ctx.clone();
        let shared = self.shared.clone();
        let url = self.settings.effective_cosmos_url().to_string();
        let run_locally = self.settings.run_locally;
        // The per-container CPU/mem stats are expensive; only collect them when
        // the status table is expanded to actually show them.
        let with_stats = !self.status_collapsed;
        std::thread::spawn(move || {
            // Only poll local containers when we're managing COSMOS locally.
            let statuses = if run_locally {
                monitor::snapshot(&ctx, with_stats).unwrap_or_default()
            } else {
                Vec::new()
            };
            // Probe the web UI so the Open button only enables once it serves
            // index.html.
            let ready = probe_cosmos(&url);
            if let Ok(mut s) = shared.lock() {
                s.statuses = Some(statuses);
                s.cosmos_ready = Some(ready);
                s.refreshing = false;
            }
        });
    }

    fn drain_shared(&mut self) {
        // Refresh the log table from the captured-log sink unless paused.
        if !self.log_paused {
            self.log_records = crate::logging::snapshot();
        }
        // Swap in operator handles produced by a background pairing task.
        if let Some((status, bridge_status, shutdown, thread)) =
            self.next_operator.lock().ok().and_then(|mut slot| slot.take())
        {
            self.operator_status = status;
            self.bridge_status_handle = bridge_status;
            self.operator_shutdown = shutdown;
            self.operator_thread = thread;
        }
        if let Ok(mut s) = self.shared.lock() {
            self.busy = s.busy;
            // Track the latest task progress line for the busy indicator; clear
            // it once the task finishes.
            if let Some(a) = s.activity.take() {
                self.activity = Some(a);
            }
            if !self.busy {
                self.activity = None;
            }
            if let Some(content) = s.fetched_logs.take() {
                self.logs_content = text_editor::Content::with_text(&content);
            }
            if let Some(statuses) = s.statuses.take() {
                self.statuses = statuses;
                self.status_loaded = true;
            }
            if let Some(env) = s.env.take() {
                self.env = env;
            }
            if let Some(ready) = s.cosmos_ready.take() {
                self.cosmos_ready = ready;
            }
            // One-shot: the enable-features task flagged a pending restart.
            if s.restart_pending {
                self.restart_pending = true;
                s.restart_pending = false;
            }
            // One-shot: a task emitted a dialog-worthy instruction (NEXT STEPS).
            if let Some(msg) = s.pending_dialog.take() {
                self.dialog = Some(msg);
            }
        }
    }

    /// Fetch a service's logs on a background thread; the result is picked up by
    /// the next tick via [`drain_shared`].
    fn spawn_logs(&self, service: String) {
        let ctx = self.ctx.clone();
        let shared = self.shared.clone();
        std::thread::spawn(move || {
            let content = crate::docker::capture_logs(&ctx, &service, 500)
                .unwrap_or_else(|e| format!("Failed to fetch logs: {e}"));
            if let Ok(mut s) = shared.lock() {
                s.fetched_logs = Some(content);
            }
        });
    }

    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Tick => {
                self.drain_shared();
                if let Ok(list) = self.operator_status.lock() {
                    self.microservices = list.clone();
                }
                if let Ok(status) = self.bridge_status_handle.lock() {
                    self.bridge_status = status.clone();
                }
                self.spinner = self.spinner.wrapping_add(1);
                match self.page {
                    Page::Splash => {
                        // Keep the environment check fresh while the splash shows,
                        // then route to the install page only if something is
                        // missing once the splash duration elapses.
                        self.maybe_refresh_env();
                        if self.splash_start.elapsed() >= SPLASH_DURATION {
                            if self.needs_setup() {
                                self.page = Page::Install;
                            } else {
                                self.go_main();
                            }
                        }
                    }
                    Page::Install => {
                        // Keep the install page in sync as components are added,
                        // and once everything is present, advance automatically.
                        if !self.busy {
                            // If Docker was just installed and we were added to the
                            // docker group, re-exec into it so Docker becomes usable
                            // this session (replaces the process; no-op otherwise).
                            crate::docker::relaunch_in_docker_group_if_needed();
                            self.maybe_refresh_env();
                            if !self.needs_setup() {
                                self.go_main();
                            }
                        }
                    }
                    Page::Main => {
                        if !self.busy {
                            self.maybe_refresh_status();
                        }
                    }
                }
                // A second launch may have asked us to surface our window (this
                // covers platforms without a tray poll; tray platforms also catch
                // it faster in PollTray).
                if self.singleton.take_show_request() {
                    self.show_main_window()
                } else {
                    Task::none()
                }
            }
            Message::Skip => {
                self.go_main();
                Task::none()
            }
            Message::InstallDocker => {
                let ctx = self.ctx.clone();
                self.spawn("Installing Docker", move || install::docker(&ctx));
                Task::none()
            }
            Message::InstallDockerMac => {
                self.spawn("Installing Docker Desktop", install::install_docker_macos);
                Task::none()
            }
            Message::InstallDockerWin => {
                self.spawn("Installing Docker Desktop", install::install_docker_windows);
                Task::none()
            }
            Message::EnableWindowsFeatures => {
                // Dedicated spawn so we can flag a pending restart on success.
                self.spawn_enable_windows_features();
                Task::none()
            }
            Message::RestartWindows => {
                self.restart_pending = false;
                self.spawn("Restarting Windows", install::restart_windows);
                Task::none()
            }
            Message::DismissRestart => {
                self.restart_pending = false;
                Task::none()
            }
            Message::DismissDialog => {
                self.dialog = None;
                Task::none()
            }
            Message::StartDocker => {
                self.spawn("Starting Docker", install::start_docker);
                Task::none()
            }
            Message::InstallPython => {
                let ctx = self.ctx.clone();
                self.spawn("Installing Python", move || install::python(&ctx));
                Task::none()
            }
            Message::InstallCosmos => {
                let ctx = self.ctx.clone();
                let enterprise = self.settings.edition.is_enterprise();
                let token = self.settings.enterprise_token.clone();
                let label = if enterprise {
                    "Installing COSMOS Enterprise"
                } else {
                    "Installing COSMOS Core"
                };
                self.spawn(label, move || install::cosmos(&ctx, "latest", enterprise, &token));
                Task::none()
            }
            Message::Start => {
                let ctx = self.ctx.clone();
                self.spawn("Starting COSMOS", move || commands::run(&ctx));
                Task::none()
            }
            Message::Stop => {
                // Don't stop immediately — confirm first (see the modal in view).
                self.shutdown_confirm = true;
                Task::none()
            }
            Message::CancelShutdown => {
                self.shutdown_confirm = false;
                Task::none()
            }
            Message::ConfirmQuit => {
                self.quit_confirm = false;
                self.quit()
            }
            Message::CancelQuit => {
                self.quit_confirm = false;
                Task::none()
            }
            Message::ConfirmShutdown => {
                self.shutdown_confirm = false;
                let ctx = self.ctx.clone();
                self.spawn("Stopping COSMOS", move || commands::stop(&ctx));
                Task::none()
            }
            Message::OpenBrowser => {
                let url = self.settings.effective_cosmos_url().to_string();
                if let Err(e) = commands::open_browser(&url) {
                    crate::logging::error("openc3-app", &format!("Failed to open browser: {e}"));
                }
                Task::none()
            }
            Message::CosmosUrlChanged(value) => {
                // Persisted on close (see CloseSettings) so typing doesn't hit
                // disk on every keystroke.
                self.settings.cosmos_url = value;
                Task::none()
            }
            Message::RunLocallyToggled(value) => {
                self.settings.run_locally = value;
                self.settings.save(&self.ctx);
                Task::none()
            }
            Message::EditionChanged(edition) => {
                self.settings.edition = edition;
                // The rest of the app (compose profiles, upgrade source) keys off
                // ctx.enterprise, so keep it in sync with the chosen edition.
                self.ctx.enterprise = edition.is_enterprise();
                self.settings.save(&self.ctx);
                Task::none()
            }
            Message::EnterpriseTokenChanged(value) => {
                // Persisted on close (see CloseSettings).
                self.settings.enterprise_token = value;
                Task::none()
            }
            Message::DevModeToggled(value) => {
                self.settings.dev_mode = value;
                self.apply_dev_settings();
                self.settings.save(&self.ctx);
                Task::none()
            }
            Message::DevFolderChanged(value) => {
                // Persisted on close (see CloseSettings).
                self.settings.dev_folder = value;
                self.apply_dev_settings();
                Task::none()
            }
            Message::BrowseDevFolder => Task::perform(
                async {
                    rfd::AsyncFileDialog::new()
                        .set_title("Choose the COSMOS development folder")
                        .pick_folder()
                        .await
                        .map(|handle| handle.path().to_path_buf())
                },
                Message::DevFolderPicked,
            ),
            Message::DevFolderPicked(picked) => {
                if let Some(path) = picked {
                    self.settings.dev_folder = path.to_string_lossy().into_owned();
                    self.apply_dev_settings();
                    self.settings.save(&self.ctx);
                }
                Task::none()
            }
            Message::ShowSettings => {
                self.settings_open = true;
                // Remember the effective dev context so we can tell on close
                // whether it changed (and thus whether to re-enroll the bridge).
                self.dev_context_on_open = self.ctx.dev_folder.clone();
                Task::none()
            }
            Message::CloseSettings => {
                self.settings_open = false;
                // Persist any text-field edits made while the dialog was open.
                self.settings.save(&self.ctx);
                // If Development Mode was switched on/off (or the dev folder
                // changed), the bridge's compose context changed — restart the
                // operator so enrollment re-runs against the new context.
                if self.ctx.dev_folder != self.dev_context_on_open {
                    crate::logging::info(
                        "bridge",
                        "Development context changed; re-running bridge enrollment",
                    );
                    self.dev_context_on_open = self.ctx.dev_folder.clone();
                    self.restart_operator(true);
                }
                Task::none()
            }
            Message::LogLevelChanged(level) => {
                self.log_level = level;
                Task::none()
            }
            Message::LogSearchChanged(value) => {
                self.log_search = value;
                Task::none()
            }
            Message::ToggleLogPause => {
                self.log_paused = !self.log_paused;
                // Resuming: refresh immediately so the view isn't stale.
                if !self.log_paused {
                    self.log_records = crate::logging::snapshot();
                }
                Task::none()
            }
            Message::ClearLog => {
                crate::logging::clear();
                self.log_records.clear();
                Task::none()
            }
            Message::ShowCleanup => {
                self.cleanup_input.clear();
                self.cleanup_confirm = true;
                // The cleanup confirmation takes over the whole page; close the
                // settings dialog behind it so cancelling returns to the main page.
                self.settings_open = false;
                Task::none()
            }
            Message::CleanupInputChanged(value) => {
                self.cleanup_input = value;
                Task::none()
            }
            Message::CancelCleanup => {
                self.cleanup_confirm = false;
                self.cleanup_input.clear();
                Task::none()
            }
            Message::ConfirmCleanup => {
                // Only proceed when the user has typed the confirmation word.
                if self.cleanup_input.trim() == "cleanup" {
                    self.cleanup_confirm = false;
                    self.cleanup_input.clear();
                    let ctx = self.ctx.clone();
                    // force=true (no prompt, we already confirmed), local=false.
                    self.spawn("Cleaning up (removing all data)", move || {
                        commands::cleanup(&ctx, false, true)
                    });
                }
                Task::none()
            }
            Message::ToggleStatus => {
                self.status_collapsed = !self.status_collapsed;
                // Expanding now shows CPU/mem, which the poll skips while
                // collapsed — refresh right away so they populate promptly.
                if !self.status_collapsed && !self.busy {
                    self.maybe_refresh_status();
                }
                Task::none()
            }
            Message::BridgeTokenAction(action) => {
                self.bridge_token_content.perform(action);
                Task::none()
            }
            Message::SubmitBridgeToken => {
                let token = self.bridge_token_content.text().trim().to_string();
                if token.is_empty() || self.bridge_pairing.load(Ordering::Relaxed) {
                    return Task::none();
                }
                // Pairing redeems the token over the network (Iroh) and restarts
                // the operator — both blocking — so run it on a background thread
                // to keep the UI responsive. Status is logged (and shown in the
                // log table); the new operator handles are handed back via
                // `next_operator` and swapped in on the next tick.
                self.bridge_token_content = text_editor::Content::new();
                self.settings_open = false;
                self.bridge_pairing.store(true, Ordering::Relaxed);
                crate::logging::info("bridge", "Pairing with COSMOS…");
                let ctx = self.ctx.clone();
                // Clone/take the current operator handles so the background task
                // can restart it on success or hand them back unchanged on error.
                let status = self.operator_status.clone();
                let bridge_status = self.bridge_status_handle.clone();
                let shutdown = self.operator_shutdown.clone();
                let old_thread = self.operator_thread.take();
                let pairing = self.bridge_pairing.clone();
                let retry = self.bridge_retry.clone();
                let next_operator = self.next_operator.clone();
                std::thread::spawn(move || {
                    let handles = match crate::enroll::enroll_with_token(&ctx, &token) {
                        Ok(bridge) => {
                            crate::logging::info(
                                "bridge",
                                &format!("Paired with bridge '{bridge}'. Reconnecting…"),
                            );
                            // Restart the operator so it picks up the new pairing.
                            shutdown.store(true, Ordering::Relaxed);
                            if let Some(handle) = old_thread {
                                let _ = handle.join();
                            }
                            start_operator(&ctx, retry)
                        }
                        Err(e) => {
                            crate::logging::error("bridge", &format!("Enrollment failed: {e:#}"));
                            // Old operator untouched; hand its handles back as-is.
                            (status, bridge_status, shutdown, old_thread)
                        }
                    };
                    if let Ok(mut slot) = next_operator.lock() {
                        *slot = Some(handles);
                    }
                    pairing.store(false, Ordering::Relaxed);
                });
                Task::none()
            }
            Message::RetryBridge => {
                // Re-arm the operator's bridge enrollment; it picks this up on
                // its next cycle. Optimistically reflect it in the UI.
                self.bridge_retry.store(true, Ordering::Relaxed);
                self.bridge_status.message = "Retrying…".to_string();
                crate::logging::info("bridge", "Retrying bridge connection…");
                Task::none()
            }
            Message::ViewLogs(service) => {
                self.logs_content = text_editor::Content::with_text("Loading logs...");
                self.viewing_logs = Some(service.clone());
                self.spawn_logs(service);
                if self.logs_window.is_some() {
                    // The logs window is already open; it will show the new logs.
                    Task::none()
                } else {
                    let (id, open) = window::open(window::Settings {
                        size: Size::new(820.0, 560.0),
                        ..window::Settings::default()
                    });
                    self.logs_window = Some(id);
                    open.map(|_| Message::Ignore)
                }
            }
            Message::RefreshLogs => {
                if let Some(service) = self.viewing_logs.clone() {
                    self.logs_content = text_editor::Content::with_text("Loading logs...");
                    self.spawn_logs(service);
                }
                Task::none()
            }
            Message::CloseLogs => {
                self.viewing_logs = None;
                self.logs_content = text_editor::Content::new();
                match self.logs_window.take() {
                    Some(id) => window::close(id),
                    None => Task::none(),
                }
            }
            Message::LogsAction(action) => {
                // Read-only: allow selection/copy/scroll, ignore edits.
                if !action.is_edit() {
                    self.logs_content.perform(action);
                }
                Task::none()
            }
            Message::CloseRequested(id) => {
                if id == self.main_window {
                    if crate::tray::ENABLED {
                        // With a tray (macOS/Windows), closing hides to the tray
                        // instead of quitting; the tray's Quit (or a real close)
                        // exits. Restore via the tray's Show. On macOS also drop
                        // the Dock icon so a tray-hidden app doesn't linger there.
                        crate::tray::set_dock_visible(false);
                        window::change_mode(id, window::Mode::Hidden)
                    } else {
                        // No tray (Linux): closing actually quits, so confirm
                        // first rather than exiting on a stray click.
                        self.quit_confirm = true;
                        Task::none()
                    }
                } else {
                    // Other windows (e.g. logs) close normally.
                    window::close(id)
                }
            }
            Message::PollTray => {
                // A second launch asking us to surface our window (checked here
                // too so tray platforms react within the 200ms poll).
                if self.singleton.take_show_request() {
                    return self.show_main_window();
                }
                match crate::tray::poll() {
                    Some(crate::tray::TrayAction::Show) => self.show_main_window(),
                    Some(crate::tray::TrayAction::Quit) => self.quit(),
                    None => Task::none(),
                }
            }
            Message::WindowClosed(id) => {
                if Some(id) == self.logs_window {
                    self.logs_window = None;
                    self.viewing_logs = None;
                    Task::none()
                } else if id == self.main_window {
                    // The main window was actually destroyed (not just hidden) —
                    // quit cleanly so we don't orphan spawned child processes.
                    self.quit()
                } else {
                    Task::none()
                }
            }
            Message::Ignore => Task::none(),
        }
    }

    /// Surface the main window: restore the Dock icon (macOS), un-hide from the
    /// tray, and focus it. Used by the tray's Show and by a second launch asking
    /// the running instance to come to the front.
    fn show_main_window(&self) -> Task<Message> {
        crate::tray::set_dock_visible(true);
        window::change_mode(self.main_window, window::Mode::Windowed)
            .chain(window::gain_focus(self.main_window))
    }

    /// Stop the supervised microservices cleanly, then exit — so we don't orphan
    /// spawned child processes.
    fn quit(&mut self) -> Task<Message> {
        self.operator_shutdown.store(true, Ordering::Relaxed);
        if let Some(handle) = self.operator_thread.take() {
            let _ = handle.join();
        }
        iced::exit()
    }

    /// Run `f` on a background thread, mirroring start/finish into the log and
    /// toggling the busy flag.
    fn spawn<F>(&self, label: &str, f: F)
    where
        F: FnOnce() -> anyhow::Result<()> + Send + 'static,
    {
        let label = label.to_string();
        {
            let mut s = self.shared.lock().unwrap();
            if s.busy {
                crate::logging::warn("openc3-app", "A task is already running; please wait.");
                return;
            }
            s.busy = true;
        }
        crate::logging::info("openc3-app", &format!("{label}..."));
        let shared = self.shared.clone();
        std::thread::spawn(move || {
            // Mirror install progress into the log (stdout + the in-app table)
            // and record the latest line as the live busy-indicator status.
            let activity_shared = shared.clone();
            install::set_notifier(Box::new(move |m| {
                crate::logging::info("openc3-app", &m);
                if let Ok(mut s) = activity_shared.lock() {
                    s.activity = Some(m);
                }
            }));
            // Surface dialog-worthy instructions (post-install NEXT STEPS) as a
            // popup: stash the text for the UI to show on its next tick.
            let dialog_shared = shared.clone();
            install::set_dialog_notifier(Box::new(move |m| {
                if let Ok(mut s) = dialog_shared.lock() {
                    s.pending_dialog = Some(m);
                }
            }));
            let result = f();
            install::clear_notifier();
            install::clear_dialog_notifier();
            match result {
                Ok(()) => crate::logging::info("openc3-app", &format!("{label}: done.")),
                Err(e) => crate::logging::error("openc3-app", &format!("{label}: ERROR: {e}")),
            }
            if let Ok(mut s) = shared.lock() {
                s.busy = false;
            }
        });
    }

    /// Like [`spawn`](Self::spawn), but for enabling Windows features: on success
    /// it flags a pending restart so the UI prompts the user (the features only
    /// take effect after a reboot).
    fn spawn_enable_windows_features(&self) {
        {
            let mut s = self.shared.lock().unwrap();
            if s.busy {
                crate::logging::warn("openc3-app", "A task is already running; please wait.");
                return;
            }
            s.busy = true;
        }
        crate::logging::info("openc3-app", "Enabling Windows features...");
        let shared = self.shared.clone();
        std::thread::spawn(move || {
            install::set_notifier(Box::new(|m| crate::logging::info("openc3-app", &m)));
            let dialog_shared = shared.clone();
            install::set_dialog_notifier(Box::new(move |m| {
                if let Ok(mut s) = dialog_shared.lock() {
                    s.pending_dialog = Some(m);
                }
            }));
            let result = install::enable_windows_features();
            install::clear_notifier();
            install::clear_dialog_notifier();
            match &result {
                Ok(()) => crate::logging::info("openc3-app", "Enabling Windows features: done."),
                Err(e) => crate::logging::error("openc3-app", &format!("Enabling Windows features: ERROR: {e}")),
            }
            if let Ok(mut s) = shared.lock() {
                s.busy = false;
                // Prompt for a restart only if the features were enabled cleanly.
                if result.is_ok() {
                    s.restart_pending = true;
                }
            }
        });
    }

    /// Per-window title.
    fn title(&self, window_id: window::Id) -> String {
        if Some(window_id) == self.logs_window {
            match &self.viewing_logs {
                Some(service) => format!("OpenC3 COSMOS — Logs: {service}"),
                None => "OpenC3 COSMOS — Logs".to_string(),
            }
        } else {
            "OpenC3 COSMOS".to_string()
        }
    }

    fn view(&self, window_id: window::Id) -> Element<'_, Message> {
        // The logs window draws its own content; everything else is the main window.
        if Some(window_id) == self.logs_window {
            return self.view_logs_window();
        }
        let content = match self.page {
            Page::Splash => self.view_splash(),
            Page::Install => self.view_install(),
            Page::Main => {
                if self.cleanup_confirm {
                    self.view_cleanup_confirm()
                } else if self.shutdown_confirm {
                    self.view_shutdown_confirm()
                } else {
                    self.view_main()
                }
            }
        };
        // A just-enabled Windows feature needs a reboot — overlay a restart
        // prompt over whatever page is showing until the user acts on it.
        let content = if self.restart_pending {
            self.with_restart_prompt(content)
        } else {
            content
        };
        // Post-install instructions (NEXT STEPS) pop up over everything with an OK.
        let content = if let Some(msg) = &self.dialog {
            self.with_dialog(content, msg)
        } else {
            content
        };
        // Confirm quitting where there's no tray to hide to (Linux).
        if self.quit_confirm {
            self.with_quit_prompt(content)
        } else {
            content
        }
    }

    /// Overlay a "Quit OpenC3 COSMOS?" confirmation on `base`. Shown when the
    /// close (X) button would actually exit (no tray to hide to), so a stray
    /// click doesn't tear everything down.
    fn with_quit_prompt<'a>(&self, base: Element<'a, Message>) -> Element<'a, Message> {
        fn scrim_style(_theme: &Theme) -> container::Style {
            container::Style {
                background: Some(Color::from_rgba8(0, 0, 0, 0.6).into()),
                ..container::Style::default()
            }
        }
        fn card_style(_theme: &Theme) -> container::Style {
            container::Style {
                background: Some(Color::from_rgb8(0x24, 0x24, 0x28).into()),
                border: iced::border::Border {
                    color: Color::from_rgb8(0x3A, 0x3A, 0x40),
                    width: 1.0,
                    radius: 10.0.into(),
                },
                ..container::Style::default()
            }
        }
        let card = container(
            column![
                text("Quit OpenC3 COSMOS?").size(22),
                text("This closes the app. Host interfaces it manages will stop.").size(15),
                Space::with_height(8),
                row![
                    button(text("Cancel"))
                        .padding(10)
                        .on_press(Message::CancelQuit),
                    button(text("Quit"))
                        .padding(10)
                        .style(button::danger)
                        .on_press(Message::ConfirmQuit),
                ]
                .spacing(10),
            ]
            .spacing(12),
        )
        .padding(24)
        .style(card_style);
        let overlay = container(card)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .style(scrim_style);
        stack![base, opaque(overlay)].into()
    }

    /// Overlay a dismissible instruction popup (dim scrim + centered card with an
    /// OK button) on `base` — used for post-install NEXT STEPS so they're not
    /// buried in the activity log.
    fn with_dialog<'a>(&self, base: Element<'a, Message>, message: &str) -> Element<'a, Message> {
        fn scrim_style(_theme: &Theme) -> container::Style {
            container::Style {
                background: Some(Color::from_rgba8(0, 0, 0, 0.6).into()),
                ..container::Style::default()
            }
        }
        fn card_style(_theme: &Theme) -> container::Style {
            container::Style {
                background: Some(Color::from_rgb8(0x24, 0x24, 0x28).into()),
                border: iced::border::Border {
                    color: Color::from_rgb8(0x3A, 0x3A, 0x40),
                    width: 1.0,
                    radius: 10.0.into(),
                },
                ..container::Style::default()
            }
        }
        let card = container(
            column![
                text("Next steps").size(22),
                text(message.to_string()).size(14),
                Space::with_height(8),
                row![
                    Space::with_width(Length::Fill),
                    button(text("OK"))
                        .padding(10)
                        .style(button::primary)
                        .on_press(Message::DismissDialog),
                ],
            ]
            .spacing(12),
        )
        .padding(24)
        .max_width(520.0)
        .style(card_style);
        let overlay = container(card)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .style(scrim_style);
        stack![base, opaque(overlay)].into()
    }

    /// Overlay a "restart Windows" modal (dim scrim + centered card) on `base`.
    /// Enabling Windows optional features only takes effect after a reboot, so
    /// after doing so we prompt the user to restart now or later.
    fn with_restart_prompt<'a>(&self, base: Element<'a, Message>) -> Element<'a, Message> {
        fn scrim_style(_theme: &Theme) -> container::Style {
            container::Style {
                background: Some(Color::from_rgba8(0, 0, 0, 0.6).into()),
                ..container::Style::default()
            }
        }
        fn card_style(_theme: &Theme) -> container::Style {
            container::Style {
                background: Some(Color::from_rgb8(0x24, 0x24, 0x28).into()),
                border: iced::border::Border {
                    color: Color::from_rgb8(0x3A, 0x3A, 0x40),
                    width: 1.0,
                    radius: 10.0.into(),
                },
                ..container::Style::default()
            }
        }
        let card = container(
            column![
                text("Restart required").size(22),
                text(
                    "Windows features were enabled. They only take effect after a restart. \
                     Restart now to finish setup?"
                )
                .size(15),
                Space::with_height(8),
                row![
                    button(text("Restart Later"))
                        .padding(10)
                        .on_press(Message::DismissRestart),
                    button(text("Restart Now"))
                        .padding(10)
                        .style(button::danger)
                        .on_press(Message::RestartWindows),
                ]
                .spacing(10),
            ]
            .spacing(12),
        )
        .padding(24)
        .style(card_style);
        let overlay = container(card)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .style(scrim_style);
        stack![base, opaque(overlay)].into()
    }

    /// Page 1: branded splash shown for [`SPLASH_DURATION`] while the
    /// environment is checked.
    fn view_splash(&self) -> Element<'_, Message> {
        // Fill the bar quickly (well before the splash ends), then hold full.
        const BAR_FILL_SECS: f32 = 1.0;
        let fraction = (self.splash_start.elapsed().as_secs_f32() / BAR_FILL_SECS).clamp(0.0, 1.0);
        let content = column![
            Image::new(ImageHandle::from_bytes(SPLASH_LOGO.to_vec()))
                .width(200)
                .height(200),
            Space::with_height(20),
            progress_bar(0.0..=1.0, fraction).width(320).height(12),
        ]
        .spacing(8)
        .align_x(Center);

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .into()
    }

    /// Page 2: only shown when docker/podman or the Python runtime is missing.
    /// Offers an install button per missing component plus a Skip button.
    fn view_install(&self) -> Element<'_, Message> {
        let muted = Color::from_rgb8(0x9E, 0x9E, 0x9E);
        const PANEL_WIDTH: f32 = 560.0;

        let logo = Image::new(ImageHandle::from_bytes(SPLASH_LOGO.to_vec()))
            .width(72)
            .height(72);
        let title = text("Setup").size(30);
        let subtitle = text("Install the components COSMOS needs, then continue.")
            .size(15)
            .color(muted);

        // Primary install button, disabled while a task is running.
        let action = |label: &str, msg: Message| {
            let b = button(text(label.to_string()).size(15))
                .padding(10)
                .style(button::primary);
            if self.busy {
                b
            } else {
                b.on_press(msg)
            }
        };

        // Rounded "card" panel: a dark gray so the light card text stays
        // high-contrast, with a subtle border to define the edge.
        fn card_style(_theme: &Theme) -> container::Style {
            container::Style {
                background: Some(Color::from_rgb8(0x24, 0x24, 0x28).into()),
                border: iced::border::Border {
                    color: Color::from_rgb8(0x3A, 0x3A, 0x40),
                    width: 1.0,
                    radius: 10.0.into(),
                },
                ..container::Style::default()
            }
        }

        // One card per missing component: a name + short description on the
        // left, the install button flush right.
        fn card<'a>(
            name: &str,
            desc: Element<'a, Message>,
            btn: Element<'a, Message>,
        ) -> Element<'a, Message> {
            container(
                row![
                    column![text(name.to_string()).size(17), desc]
                        .spacing(3)
                        .width(Length::Fill),
                    btn,
                ]
                .spacing(16)
                .align_y(Center),
            )
            .padding(16)
            .width(Length::Fill)
            .style(card_style)
            .into()
        }

        let mut cards = column![].spacing(12).width(Length::Fill);
        // Which edition to install. Only relevant to a local install; the same
        // choice is also available in Settings.
        if self.settings.run_locally {
            cards = cards.push(card(
                "Edition",
                text("Choose which COSMOS edition to install.")
                    .size(12)
                    .color(muted)
                    .into(),
                pick_list(
                    crate::settings::Edition::ALL,
                    Some(self.settings.edition),
                    Message::EditionChanged,
                )
                .text_size(14)
                .into(),
            ));
        }
        // Hardware virtualization must be enabled in BIOS/UEFI for Docker's
        // backend. We can only detect and inform — it's a firmware setting the
        // app can't change. Only warn when we're sure it's off (Some(false));
        // Some(true)/None (unknown, or off Windows) show nothing.
        if self.settings.run_locally && self.env.virtualization == Some(false) {
            let amber = Color::from_rgb8(0xFF, 0xB3, 0x00);
            cards = cards.push(card(
                "Virtualization disabled in BIOS",
                column![
                    text(
                        "Hardware virtualization (Intel VT-x / AMD-V) is turned off in your \
                         computer's firmware. Docker's WSL2 backend can't run until it's on — \
                         this is a BIOS/UEFI setting the app can't change for you."
                    )
                    .size(12)
                    .color(muted),
                    text(
                        "Restart, enter BIOS/UEFI setup (often F2/F10/Del at boot), enable \
                         Virtualization / VT-x / SVM (usually under CPU or Advanced), save, and \
                         reboot."
                    )
                    .size(12)
                    .color(muted),
                ]
                .spacing(4)
                .into(),
                text("⚠ BIOS setting").size(12).color(amber).into(),
            ));
        }
        // Windows needs the WSL2 / virtualization optional features enabled
        // before Docker's backend will run — offer to enable them (elevated; a
        // restart follows). Always satisfied off Windows, so the card is
        // Windows-only in practice. Shown before Docker since it's a prerequisite.
        if self.settings.run_locally && !self.env.windows_features_ok {
            cards = cards.push(card(
                "Windows features",
                column![
                    text("Docker's WSL2 backend needs these Windows features enabled:")
                        .size(12)
                        .color(muted),
                    text(
                        "• Virtual Machine Platform\n\
                         • Windows Hypervisor Platform\n\
                         • Windows Subsystem for Linux"
                    )
                    .size(12)
                    .color(muted),
                    text("Enabling requires administrator approval and a Windows restart.")
                        .size(11)
                        .color(muted),
                ]
                .spacing(4)
                .into(),
                action("Enable Windows Features", Message::EnableWindowsFeatures).into(),
            ));
        }
        // Docker and the COSMOS environment are only needed when running COSMOS
        // locally; otherwise the only local component is the Python runtime.
        if self.settings.run_locally && !self.env.container_ok {
            if self.env.container_installed {
                // Docker is present but its daemon isn't running: offer to start
                // it rather than reinstall.
                cards = cards.push(card(
                    "Docker",
                    text("Docker is installed but not running.")
                        .size(12)
                        .color(muted)
                        .into(),
                    action("Start Docker", Message::StartDocker).into(),
                ));
            } else {
                let docker_msg = if cfg!(target_os = "macos") {
                    Message::InstallDockerMac
                } else if cfg!(target_os = "windows") {
                    Message::InstallDockerWin
                } else {
                    Message::InstallDocker
                };
                // On macOS/Windows we install Docker Desktop; note its licensing.
                let mut desc = column![text("The container engine COSMOS runs in.")
                    .size(12)
                    .color(muted)]
                .spacing(3);
                if cfg!(any(target_os = "macos", target_os = "windows")) {
                    desc = desc.push(
                        text(install::DOCKER_DESKTOP_LICENSE)
                            .size(11)
                            .color(muted),
                    );
                }
                cards = cards.push(card(
                    "Docker",
                    desc.into(),
                    action("Install Docker", docker_msg).into(),
                ));
            }
        }
        if !self.env.python_ok {
            cards = cards.push(card(
                "Python runtime",
                text("An isolated interpreter for host scripts.")
                    .size(12)
                    .color(muted)
                    .into(),
                action("Install Python", Message::InstallPython).into(),
            ));
        }
        if self.settings.run_locally && !self.env.cosmos_ok {
            if self.settings.edition.is_enterprise() {
                // Enterprise needs an access token; disable install until it's set.
                let token_empty = self.settings.enterprise_token.trim().is_empty();
                let desc = column![
                    text("COSMOS Enterprise from repos.openc3.com (requires an access token).")
                        .size(12)
                        .color(muted),
                    text_input("Access token", &self.settings.enterprise_token)
                        .on_input(Message::EnterpriseTokenChanged)
                        .secure(true)
                        .size(13)
                        .padding(6)
                        .width(Length::Fill),
                ]
                .spacing(6);
                let btn = {
                    let b = button(text("Install COSMOS").size(15))
                        .padding(10)
                        .style(button::primary);
                    if self.busy || token_empty {
                        b
                    } else {
                        b.on_press(Message::InstallCosmos)
                    }
                };
                cards = cards.push(card("COSMOS environment", desc.into(), btn.into()));
            } else {
                cards = cards.push(card(
                    "COSMOS environment",
                    text("The COSMOS containers and configuration.")
                        .size(12)
                        .color(muted)
                        .into(),
                    action("Install COSMOS", Message::InstallCosmos).into(),
                ));
            }
        }

        // Scroll the cards within a bounded region so that when many components
        // need installing they don't push the activity log down to an unreadable
        // sliver — the cards and the log share the flexible height (3:2 below).
        let cards_panel = container(scrollable(cards).height(Length::Fill))
            .max_width(PANEL_WIDTH)
            .width(Length::Fill)
            .height(Length::FillPortion(3));

        let skip = button(text("Skip for now").size(14))
            .padding(10)
            .style(button::text)
            .on_press(Message::Skip);

        // Prominent, animated "installing" indicator so it's obvious work is
        // happening (installs can take minutes with no card-level feedback).
        let busy_note: Element<'_, Message> = if self.busy {
            let green = Color::from_rgb8(0x4C, 0xAF, 0x50);
            let frame = SPINNER[self.spinner % SPINNER.len()];
            container(
                row![
                    text(frame).size(24).font(Font::MONOSPACE).color(green),
                    column![
                        text("Installing…").size(16),
                        text("This can take several minutes. Live progress is shown below.")
                            .size(12)
                            .color(muted),
                    ]
                    .spacing(2),
                ]
                .spacing(14)
                .align_y(Center),
            )
            .padding(12)
            .width(Length::Fill)
            .max_width(PANEL_WIDTH)
            .style(card_style)
            .into()
        } else {
            Space::with_height(0).into()
        };

        // Recent log lines in a subtle panel so install progress is visible here.
        // Show only INFO and above: DEBUG lines (e.g. the repeated "Docker API
        // poll unavailable" CLI-fallback notice, expected while Docker isn't up
        // yet) are internal noise that clutters the setup progress.
        let mut log_col = column![].spacing(2).width(Length::Fill);
        let visible: Vec<&crate::logging::LogRecord> = self
            .log_records
            .iter()
            .filter(|r| level_rank(&r.level) >= level_rank("INFO"))
            .collect();
        let start = visible.len().saturating_sub(8);
        for rec in &visible[start..] {
            log_col = log_col.push(
                text(format!("{} {}", rec.level, rec.message))
                    .size(12)
                    .font(Font::MONOSPACE)
                    .color(level_color(&rec.level)),
            );
        }
        let log_panel = container(scrollable(log_col).height(Length::Fill))
            .padding(12)
            .width(Length::Fill)
            .max_width(PANEL_WIDTH)
            .height(Length::FillPortion(2))
            .style(card_style);

        let content = column![
            logo,
            title,
            subtitle,
            Space::with_height(10),
            cards_panel,
            Space::with_height(2),
            skip,
            busy_note,
            log_panel,
        ]
        .spacing(12)
        .padding(30)
        .align_x(Center)
        .height(Length::Fill);

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x(Length::Fill)
            .into()
    }

    /// Page 3: the main control panel with live container status.
    fn view_main(&self) -> Element<'_, Message> {
        // When the Settings dialog is open, render only the dialog. Building and
        // rasterizing the full main page (log/status/microservice tables) behind
        // it every frame under the software renderer makes the dialog slow to
        // open and laggy to type in. The dialog fills the screen with its own
        // dimmed backdrop, so nothing is lost.
        if self.settings_open {
            return self.view_settings_modal();
        }

        // Header: title on the left, a settings gear on the right. The gear opens
        // the Settings dialog (bridge pairing + cleanup).
        let gear = button(
            text(GEAR_GLYPH)
                .font(ICON_FONT)
                .size(22)
                .color(GEAR_COLOR),
        )
        .padding(6)
        .style(button::text)
        .on_press(Message::ShowSettings);
        let title = row![
            text("OpenC3 COSMOS").size(28),
            Space::with_width(Length::Fill),
            gear,
        ]
        .align_y(Center);

        // Hide the one-shot init container once it has completed successfully
        // (still show it while running or if it failed).
        let visible: Vec<&ContainerStatus> = self
            .statuses
            .iter()
            .filter(|c| {
                !(c.service == "openc3-cosmos-init"
                    && c.run_state() == monitor::RunState::ExitedSuccess)
            })
            .collect();

        let action = |label: &str, msg: Message| {
            let b = button(text(label.to_string())).padding(8);
            if self.busy {
                b
            } else {
                b.on_press(msg)
            }
        };

        let run_locally = self.settings.run_locally;
        let started = run_locally && self.statuses.iter().any(|c| c.is_running());

        // Prominent, full-width hero button. When running COSMOS locally it
        // transitions through the lifecycle (Start COSMOS → waiting → Open);
        // when using a remote COSMOS it's simply an always-enabled Open button.
        let hero_label = if !run_locally {
            "Open COSMOS in Browser"
        } else if !started {
            "Start COSMOS"
        } else if self.cosmos_ready {
            "Open COSMOS in Browser"
        } else {
            "Open COSMOS in Browser (waiting for COSMOS…)"
        };
        let hero_style = if !run_locally {
            button::success
        } else if !started {
            button::primary
        } else if self.cosmos_ready {
            button::success
        } else {
            button::secondary
        };
        let hero_msg = if !run_locally {
            Some(Message::OpenBrowser)
        } else if !started {
            (!self.busy).then_some(Message::Start)
        } else if self.cosmos_ready {
            Some(Message::OpenBrowser)
        } else {
            None
        };
        let open_button = button(
            text(hero_label)
                .size(18)
                .width(Length::Fill)
                .align_x(Center),
        )
        .width(Length::Fill)
        .padding(14)
        .style(hero_style)
        .on_press_maybe(hero_msg);

        // Secondary controls: Stop only appears while running locally and up.
        let buttons = if started {
            row![action("Shutdown COSMOS", Message::Stop)].spacing(10)
        } else {
            row![].spacing(10)
        };

        // Color-coded container status table
        // (Container | Tag | Status | CPU | Mem | Actions).
        let header_color = Color::from_rgb8(0x9E, 0x9E, 0x9E);
        let mut table = column![row![
            text("Container")
                .size(13)
                .font(Font::MONOSPACE)
                .width(260)
                .color(header_color),
            text("Tag")
                .size(13)
                .font(Font::MONOSPACE)
                .width(120)
                .color(header_color),
            text("Status")
                .size(13)
                .font(Font::MONOSPACE)
                .width(170)
                .color(header_color),
            text("CPU")
                .size(13)
                .font(Font::MONOSPACE)
                .width(70)
                .color(header_color),
            text("Mem")
                .size(13)
                .font(Font::MONOSPACE)
                .width(110)
                .color(header_color),
            text("Actions")
                .size(13)
                .font(Font::MONOSPACE)
                .width(60)
                .color(header_color),
        ]
        .spacing(10)]
        .spacing(6);
        table = table.push(horizontal_rule(1));
        if visible.is_empty() {
            table = table.push(text("No containers found.").size(14));
        } else {
            for c in visible.iter().copied() {
                let (indicator, color) = state_style(c);
                let logs_button = button(text("Logs").size(11))
                    .padding(4)
                    .on_press(Message::ViewLogs(c.service.clone()));
                let container_row = row![
                    text(c.service.clone())
                        .size(13)
                        .font(Font::MONOSPACE)
                        .width(260)
                        .wrapping(text::Wrapping::WordOrGlyph),
                    text(c.tag_display().to_string())
                        .size(13)
                        .font(Font::MONOSPACE)
                        .width(120)
                        .wrapping(text::Wrapping::WordOrGlyph),
                    text(format!("{indicator}{}", c.display_status()))
                        .size(13)
                        .font(Font::MONOSPACE)
                        .color(color)
                        .width(170),
                    text(c.cpu_display().to_string())
                        .size(13)
                        .font(Font::MONOSPACE)
                        .width(70),
                    text(c.mem_display().to_string())
                        .size(13)
                        .font(Font::MONOSPACE)
                        .width(110),
                    logs_button,
                ]
                .spacing(10)
                .align_y(Center);
                table = table.push(container_row);
            }
            // Totals footer: summed CPU% and memory across the visible rows.
            let (cpu_total, mem_total) = monitor::totals(visible.iter().copied());
            table = table.push(horizontal_rule(1));
            table = table.push(
                row![
                    text("Total")
                        .size(13)
                        .font(Font::MONOSPACE)
                        .width(260)
                        .color(header_color),
                    text("").size(13).font(Font::MONOSPACE).width(120),
                    text("").size(13).font(Font::MONOSPACE).width(170),
                    text(cpu_total).size(13).font(Font::MONOSPACE).width(70),
                    text(mem_total).size(13).font(Font::MONOSPACE).width(110),
                ]
                .spacing(10)
                .align_y(Center),
            );
        }

        let running = visible.iter().filter(|c| c.is_running()).count();
        let total = visible.len();
        let count_summary =
            text(format!("{running} of {total} containers running")).size(14);

        // Until the first snapshot arrives, show an animated loading indicator
        // instead of the (empty) table.
        let status_body: Element<'_, Message> = if self.status_loaded {
            column![
                scrollable(table).height(Length::FillPortion(2)),
                count_summary,
            ]
            .spacing(8)
            .into()
        } else {
            let frame = SPINNER[self.spinner % SPINNER.len()];
            container(
                row![
                    text(frame).size(20).font(Font::MONOSPACE),
                    text("Loading container status…").size(15),
                ]
                .spacing(10)
                .align_y(Center),
            )
            .height(Length::FillPortion(2))
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .into()
        };

        // Collapsible header: shows a summary while collapsed, toggles the full
        // table. Starts collapsed.
        let status_summary = if !self.status_loaded {
            "loading…".to_string()
        } else {
            format!("{running} of {total} running")
        };
        // Render the disclosure caret from our embedded icon font (the Unicode
        // triangles tofu'd on some Windows font fallbacks); the label stays in
        // the normal font.
        let caret = if self.status_collapsed {
            CARET_RIGHT_GLYPH
        } else {
            CARET_DOWN_GLYPH
        };
        let header_label = if self.status_collapsed {
            format!("Container Status  ({status_summary})")
        } else {
            "Container Status".to_string()
        };
        let status_header = button(
            row![
                text(caret).font(ICON_FONT).size(14).color(GEAR_COLOR),
                text(header_label).size(18),
            ]
            .spacing(8)
            .align_y(Center),
        )
        .on_press(Message::ToggleStatus)
        .style(button::text)
        .padding(0);
        // The local container table is only meaningful when running COSMOS
        // locally; hide it entirely for a remote COSMOS.
        let status_section: Element<'_, Message> = if !self.settings.run_locally {
            Space::with_height(0).into()
        } else if self.status_collapsed {
            column![status_header, horizontal_rule(2)].spacing(8).into()
        } else {
            column![status_header, horizontal_rule(2), status_body].spacing(8).into()
        };

        // Bridge microservices (host process supervisor) status table.
        let green = Color::from_rgb8(0x4C, 0xAF, 0x50);
        let red = Color::from_rgb8(0xF4, 0x43, 0x36);
        let mut ms_table = column![row![
            text("Microservice")
                .size(13)
                .font(Font::MONOSPACE)
                .width(300)
                .color(header_color),
            text("State")
                .size(13)
                .font(Font::MONOSPACE)
                .width(120)
                .color(header_color),
            text("PID")
                .size(13)
                .font(Font::MONOSPACE)
                .width(80)
                .color(header_color),
            text("Connection")
                .size(13)
                .font(Font::MONOSPACE)
                .width(140)
                .color(header_color),
            text("Rx")
                .size(13)
                .font(Font::MONOSPACE)
                .width(110)
                .color(header_color),
            text("Tx")
                .size(13)
                .font(Font::MONOSPACE)
                .width(Length::Fill)
                .color(header_color),
        ]
        .spacing(10)]
        .spacing(6);
        ms_table = ms_table.push(horizontal_rule(1));
        if self.microservices.is_empty() {
            ms_table = ms_table.push(text("No microservices running.").size(14));
        } else {
            for m in &self.microservices {
                let (glyph, color, label) = if m.running {
                    ("● ", green, "running")
                } else {
                    ("○ ", red, "stopped")
                };
                ms_table = ms_table.push(
                    row![
                        text(m.name.clone())
                            .size(13)
                            .font(Font::MONOSPACE)
                            .width(300)
                            .wrapping(text::Wrapping::WordOrGlyph),
                        text(format!("{glyph}{label}"))
                            .size(13)
                            .font(Font::MONOSPACE)
                            .color(color)
                            .width(120),
                        text(m.pid.map(|p| p.to_string()).unwrap_or_else(|| "-".to_string()))
                            .size(13)
                            .font(Font::MONOSPACE)
                            .width(80),
                        {
                            // Host interface connection state (for bridged interfaces).
                            let state = m
                                .interface_state
                                .clone()
                                .filter(|s| !s.is_empty())
                                .unwrap_or_else(|| "-".to_string());
                            let iface_color = match m.interface_state.as_deref() {
                                Some("CONNECTED") => green,
                                Some(s) if !s.is_empty() => {
                                    Color::from_rgb8(0xFF, 0xB3, 0x00) // amber: not connected
                                }
                                _ => header_color,
                            };
                            text(state)
                                .size(13)
                                .font(Font::MONOSPACE)
                                .width(140)
                                .color(iface_color)
                        },
                        text(
                            m.rxbytes
                                .map(crate::monitor::human_bytes)
                                .unwrap_or_else(|| "-".to_string())
                        )
                        .size(13)
                        .font(Font::MONOSPACE)
                        .width(110),
                        text(
                            m.txbytes
                                .map(crate::monitor::human_bytes)
                                .unwrap_or_else(|| "-".to_string())
                        )
                        .size(13)
                        .font(Font::MONOSPACE)
                        .width(Length::Fill),
                    ]
                    .spacing(10)
                    .align_y(Center),
                );
            }
        }
        // COSMOS connection indicator: paired (has keys + ticket) and connected
        // (last hub poll succeeded).
        let (cosmos_color, cosmos_glyph) = if self.bridge_status.connected {
            (green, "● ")
        } else if self.bridge_status.configured {
            (Color::from_rgb8(0xFF, 0xB3, 0x00), "● ") // amber: paired, connecting
        } else {
            (Color::from_rgb8(0x9E, 0x9E, 0x9E), "○ ") // grey: not paired
        };
        let cosmos_message = if self.bridge_status.message.is_empty() {
            "Not paired with COSMOS"
        } else {
            self.bridge_status.message.as_str()
        };
        let mut cosmos_row = row![
            text("COSMOS:").size(13).font(Font::MONOSPACE),
            // Fill + wrap so the (sometimes long) diagnostic reason stays fully
            // visible and never pushes the Retry button off the row.
            text(format!("{cosmos_glyph}{cosmos_message}"))
                .size(13)
                .font(Font::MONOSPACE)
                .color(cosmos_color)
                .width(Length::Fill)
                .wrapping(text::Wrapping::WordOrGlyph),
        ]
        .spacing(8)
        .align_y(Center);
        // Offer a manual retry whenever the bridge isn't connected (auto-enroll
        // gives up after a few tries per COSMOS up-session).
        if !self.bridge_status.connected {
            cosmos_row = cosmos_row.push(
                button(text("Retry").size(12))
                    .padding(4)
                    .on_press(Message::RetryBridge),
            );
        }

        let ms_section = column![
            text("Bridge Microservices").size(18),
            horizontal_rule(2),
            cosmos_row,
            scrollable(ms_table).height(Length::FillPortion(1)),
        ]
        .spacing(8);

        // While a task runs, show a spinner and the latest progress line (e.g.
        // the current `docker compose` pull status on first-run downloads) so the
        // app never looks hung. Full detail streams into the Log Messages table.
        let busy_note: Element<'_, Message> = if self.busy {
            let frame = SPINNER[self.spinner % SPINNER.len()];
            let status = self.activity.as_deref().unwrap_or("Working…");
            row![
                text(frame).size(18).font(Font::MONOSPACE).color(green),
                text(status.to_string())
                    .size(13)
                    .width(Length::Fill)
                    .wrapping(text::Wrapping::WordOrGlyph),
            ]
            .spacing(10)
            .align_y(Center)
            .into()
        } else {
            Space::with_height(0).into()
        };

        let content = column![
            title,
            Space::with_height(8),
            open_button,
            Space::with_height(4),
            buttons,
            busy_note,
            Space::with_height(8),
            status_section,
            Space::with_height(8),
            ms_section,
            Space::with_height(8),
            self.view_log_messages(),
        ]
        .spacing(6)
        .padding(20);

        // (The Settings dialog is handled by the early return at the top of this
        // method, so here we only render the main page.)
        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }

    /// Scrolling log messages table (replaces the old Activity panel). Shows
    /// everything openc3-app logs to stdout, newest first, filterable by level
    /// and search, with pause/clear. Modeled on COSMOS' LogMessages.vue.
    fn view_log_messages(&self) -> Element<'_, Message> {
        let header_color = Color::from_rgb8(0x9E, 0x9E, 0x9E);

        let pause_label = if self.log_paused { "Resume" } else { "Pause" };
        let controls = row![
            text("Log Messages").size(18),
            Space::with_width(Length::Fill),
            pick_list(
                LogLevelFilter::ALL,
                Some(self.log_level),
                Message::LogLevelChanged
            )
            .text_size(13),
            text_input("Search", &self.log_search)
                .on_input(Message::LogSearchChanged)
                .size(13)
                .width(200),
            button(text(pause_label).size(13)).padding(6).on_press(Message::ToggleLogPause),
            button(text("Clear").size(13)).padding(6).on_press(Message::ClearLog),
        ]
        .spacing(8)
        .align_y(Center);

        let col = |label, width| {
            text(label).size(12).font(Font::MONOSPACE).width(width).color(header_color)
        };
        let header = row![
            col("Time", Length::Fixed(100.0)),
            col("Level", Length::Fixed(70.0)),
            col("Source", Length::Fixed(200.0)),
            col("Message", Length::Fill),
        ]
        .spacing(10);

        // Filter to level >= the selected minimum and matching the search, then
        // show newest first (capped so a huge backlog doesn't stall rendering).
        let min_rank = self.log_level.rank();
        let needle = self.log_search.to_lowercase();
        let mut table = column![].spacing(2);
        let mut shown = 0usize;
        for rec in self.log_records.iter().rev() {
            if level_rank(&rec.level) < min_rank {
                continue;
            }
            if !needle.is_empty()
                && !rec.message.to_lowercase().contains(&needle)
                && !rec.source.to_lowercase().contains(&needle)
            {
                continue;
            }
            // "2026-07-19T20:37:33.129001Z" -> "20:37:33.129"
            let time = rec.timestamp.get(11..23).unwrap_or(rec.timestamp.as_str());
            table = table.push(
                row![
                    text(time.to_string()).size(12).font(Font::MONOSPACE).width(100),
                    text(rec.level.clone())
                        .size(12)
                        .font(Font::MONOSPACE)
                        .width(70)
                        .color(level_color(&rec.level)),
                    text(rec.source.clone())
                        .size(12)
                        .font(Font::MONOSPACE)
                        .width(200)
                        .wrapping(text::Wrapping::WordOrGlyph),
                    text(rec.message.clone())
                        .size(12)
                        .font(Font::MONOSPACE)
                        .width(Length::Fill)
                        .wrapping(text::Wrapping::WordOrGlyph),
                ]
                .spacing(10),
            );
            shown += 1;
            if shown >= 300 {
                break;
            }
        }
        if shown == 0 {
            table = table.push(text("No log messages.").size(13));
        }

        column![
            controls,
            horizontal_rule(2),
            header,
            horizontal_rule(1),
            scrollable(table).height(Length::FillPortion(2)),
        ]
        .spacing(6)
        .into()
    }

    /// Modal Settings dialog: bridge pairing and the destructive cleanup action.
    /// Rendered as a centered card over a dimmed backdrop; clicking the backdrop
    /// or the ✕ closes it.
    fn view_settings_modal(&self) -> Element<'_, Message> {
        let grey = Color::from_rgb8(0x9E, 0x9E, 0x9E);

        let header = row![
            text("Settings").size(24),
            Space::with_width(Length::Fill),
            button(
                text(CLOSE_GLYPH)
                    .font(ICON_FONT)
                    .size(16)
                    .color(GEAR_COLOR),
            )
            .padding(4)
            .style(button::text)
            .on_press(Message::CloseSettings),
        ]
        .align_y(Center);

        // COSMOS location: the URL the "Open COSMOS in Browser" button uses, and
        // whether this app manages a local COSMOS (Docker) or connects to a
        // remote one.
        let mut cosmos_section = column![
            text("COSMOS").size(16),
            row![
                text("Edition").size(13).width(70),
                pick_list(
                    crate::settings::Edition::ALL,
                    Some(self.settings.edition),
                    Message::EditionChanged,
                )
                .text_size(13),
            ]
            .spacing(8)
            .align_y(Center),
            text("Web address opened by \u{201C}Open COSMOS in Browser\u{201D}.")
                .size(13)
                .color(grey),
            text_input(crate::settings::DEFAULT_COSMOS_URL, &self.settings.cosmos_url)
                .on_input(Message::CosmosUrlChanged)
                .padding(8),
            checkbox("Run COSMOS locally", self.settings.run_locally)
                .on_toggle(Message::RunLocallyToggled),
            text(
                "When off, this app won't install or start/stop a local COSMOS — \
                 it just opens the URL above."
            )
            .size(12)
            .color(grey),
        ]
        .spacing(6);
        // Enterprise needs an access token for the private repos.openc3.com repo.
        if self.settings.edition.is_enterprise() {
            cosmos_section = cosmos_section.push(
                text_input("Enterprise access token", &self.settings.enterprise_token)
                    .on_input(Message::EnterpriseTokenChanged)
                    .secure(true)
                    .padding(8),
            );
            cosmos_section = cosmos_section.push(
                text("Access token for repos.openc3.com (COSMOS Enterprise).")
                    .size(12)
                    .color(grey),
            );
        }

        // Bridge pairing: redeem an enrollment token from a remote COSMOS's
        // Admin → Bridges page. Co-located COSMOS enrolls automatically.
        let pair_section = column![
            text("Bridge Pairing").size(16),
            text(
                "Paste an enrollment token from a remote COSMOS (Admin → Bridges) to \
                 pair with its bridge. A co-located COSMOS pairs automatically."
            )
            .size(13)
            .color(grey),
            // Multi-line editor so the long token wraps inside the box instead
            // of overflowing the dialog.
            text_editor(&self.bridge_token_content)
                .placeholder("Enrollment token")
                .on_action(Message::BridgeTokenAction)
                .font(Font::MONOSPACE)
                // The token is one long space-less string; break on glyphs so it
                // wraps inside the box instead of overflowing.
                .wrapping(text::Wrapping::WordOrGlyph)
                .height(90),
            row![
                Space::with_width(Length::Fill),
                {
                    let pairing = self.bridge_pairing.load(Ordering::Relaxed);
                    button(text(if pairing { "Pairing…" } else { "Pair" }))
                        .padding(8)
                        .on_press_maybe((!pairing).then_some(Message::SubmitBridgeToken))
                },
            ]
            .align_y(Center),
        ]
        .spacing(6);

        // Destructive cleanup: opens the typed-confirmation page.
        let cleanup_section = column![
            text("Cleanup").size(16),
            text(
                "Remove all COSMOS Docker volumes and data (targets, logs, databases). \
                 This cannot be undone."
            )
            .size(13)
            .color(grey),
            button(text("Cleanup..."))
                .padding(8)
                .style(button::danger)
                .on_press(Message::ShowCleanup),
        ]
        .spacing(6);

        // Development mode: forces the *_TAG env vars to "latest" and drives
        // COSMOS from a local source checkout's openc3.sh.
        let mut dev_section = column![
            text("Development").size(16),
            checkbox("Development Mode", self.settings.dev_mode)
                .on_toggle(Message::DevModeToggled),
            text(
                "Forces OPENC3_TAG and OPENC3_ENTERPRISE_TAG to \"latest\" (overriding the .env) \
                 and runs COSMOS from a local source checkout's openc3.sh."
            )
            .size(12)
            .color(grey),
        ]
        .spacing(6);
        if self.settings.dev_mode {
            dev_section = dev_section.push(
                row![
                    text_input(
                        "Development folder (contains openc3.sh)",
                        &self.settings.dev_folder
                    )
                    .on_input(Message::DevFolderChanged)
                    .padding(8)
                    .width(Length::Fill),
                    button(text("Browse…"))
                        .padding(8)
                        .on_press(Message::BrowseDevFolder),
                ]
                .spacing(8)
                .align_y(Center),
            );
        }

        let card = container(
            column![
                header,
                horizontal_rule(2),
                cosmos_section,
                dev_section,
                pair_section,
                cleanup_section,
            ]
            .spacing(18),
        )
        .width(540)
        .padding(24)
        .style(|theme: &Theme| {
            let palette = theme.extended_palette();
            container::Style {
                background: Some(palette.background.weak.color.into()),
                border: iced::border::rounded(8),
                ..container::Style::default()
            }
        });

        // Render as a full page (not an overlay): the card centered on the
        // normal background, scrollable if it's taller than the window. This
        // avoids compositing a full-window semi-transparent backdrop every frame
        // under the software renderer, which the modal did. The ✕ in the header
        // closes it.
        container(scrollable(
            container(card)
                .width(Length::Fill)
                .center_x(Length::Fill)
                .padding(20),
        ))
        .width(Length::Fill)
        .height(Length::Fill)
        .into()
    }

    /// The main page with a centered "Shutdown COSMOS?" confirmation modal
    /// layered over a dim scrim, so a shutdown is never a single misclick. The
    /// overlay is `opaque` so the dimmed main view behind it isn't interactive.
    fn view_shutdown_confirm(&self) -> Element<'_, Message> {
        fn scrim_style(_theme: &Theme) -> container::Style {
            container::Style {
                background: Some(Color::from_rgba8(0, 0, 0, 0.6).into()),
                ..container::Style::default()
            }
        }
        fn card_style(_theme: &Theme) -> container::Style {
            container::Style {
                background: Some(Color::from_rgb8(0x24, 0x24, 0x28).into()),
                border: iced::border::Border {
                    color: Color::from_rgb8(0x3A, 0x3A, 0x40),
                    width: 1.0,
                    radius: 10.0.into(),
                },
                ..container::Style::default()
            }
        }
        let card = container(
            column![
                text("Shutdown COSMOS?").size(22),
                text("This stops all COSMOS containers running locally. Are you sure?").size(15),
                Space::with_height(8),
                row![
                    button(text("Cancel"))
                        .padding(10)
                        .on_press(Message::CancelShutdown),
                    button(text("Shutdown COSMOS"))
                        .padding(10)
                        .style(button::danger)
                        .on_press(Message::ConfirmShutdown),
                ]
                .spacing(10),
            ]
            .spacing(12),
        )
        .padding(24)
        .style(card_style);
        let overlay = container(card)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .style(scrim_style);
        stack![self.view_main(), opaque(overlay)].into()
    }

    /// Destructive cleanup confirmation. Requires typing "cleanup" to enable
    /// the proceed button.
    fn view_cleanup_confirm(&self) -> Element<'_, Message> {
        let header = text("Cleanup — destroy all data").size(28);

        let warning = text(
            "This permanently removes ALL COSMOS Docker volumes and data:\n\
             • all targets, plugins, and stored configuration\n\
             • all command and telemetry logs\n\
             • the time-series database and Redis data\n\n\
             Running containers will be stopped and their volumes deleted. \
             This CANNOT be undone.",
        )
        .size(15);

        let prompt = text("Type \"cleanup\" to confirm:").size(15);
        let input = text_input("cleanup", &self.cleanup_input)
            .on_input(Message::CleanupInputChanged)
            .on_submit(Message::ConfirmCleanup)
            .padding(8)
            .width(320);

        let confirmed = self.cleanup_input.trim() == "cleanup";
        let proceed = button(text("Delete everything"))
            .padding(10)
            .on_press_maybe(confirmed.then_some(Message::ConfirmCleanup));
        let cancel = button(text("Cancel"))
            .padding(10)
            .on_press(Message::CancelCleanup);

        let content = column![
            header,
            warning,
            Space::with_height(8),
            prompt,
            input,
            Space::with_height(8),
            row![cancel, proceed].spacing(10),
        ]
        .spacing(12)
        .padding(30);

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .into()
    }

    /// Contents of the separate, draggable logs window.
    fn view_logs_window(&self) -> Element<'_, Message> {
        let service = self.viewing_logs.as_deref().unwrap_or("");
        let header = text(format!("Logs: {service}")).size(20).font(Font::MONOSPACE);

        let buttons = row![
            button(text("Refresh")).padding(8).on_press(Message::RefreshLogs),
            button(text("Close")).padding(8).on_press(Message::CloseLogs),
        ]
        .spacing(10);

        // text_editor renders the logs read-only but selectable (click-drag to
        // select, ⌘/Ctrl-C to copy); it scrolls internally.
        let logs = text_editor(&self.logs_content)
            .font(Font::MONOSPACE)
            .padding(10)
            .height(Length::Fill)
            .on_action(Message::LogsAction);

        let content = column![header, buttons, logs].spacing(12).padding(16);

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }

    fn subscription(&self) -> Subscription<Message> {
        // Tick quickly during the splash so we advance promptly at 3s; poll the
        // install page at a moderate rate; refresh container status every 2s.
        let interval = match self.page {
            Page::Splash => Duration::from_millis(200),
            // Tick fast while an install is running so the spinner animates;
            // otherwise poll the setup page at a moderate rate.
            Page::Install if self.busy => Duration::from_millis(120),
            Page::Install => Duration::from_millis(750),
            // Tick fast while the first status sample is still loading, or while
            // a task is running, so the spinner/progress animates; then settle to
            // a 2s status poll.
            Page::Main if self.busy || !self.status_loaded => Duration::from_millis(120),
            Page::Main => Duration::from_secs(2),
        };
        let mut subs = vec![
            iced::time::every(interval).map(|_| Message::Tick),
            window::close_requests().map(Message::CloseRequested),
            window::close_events().map(Message::WindowClosed),
        ];
        // Poll the tray for menu clicks (responsive even while the window is
        // hidden). Only when a real tray exists.
        if crate::tray::ENABLED {
            subs.push(iced::time::every(Duration::from_millis(200)).map(|_| Message::PollTray));
        }
        Subscription::batch(subs)
    }
}

/// Apply the development-mode process-environment overrides so child processes
/// (docker compose / openc3.sh) and host-microservice venvs pick them up:
///   * OPENC3_TAG / OPENC3_ENTERPRISE_TAG = "latest" (override the `.env`), and
///   * OPENC3_DEVEL = the local openc3 gem in the dev folder, so host venvs
///     install openc3 editable from the working-tree source (see
///     `operator::openc3_devel_source`) instead of the published package.
fn apply_dev_env(dev_mode: bool, dev_folder: Option<&std::path::Path>) {
    if dev_mode {
        std::env::set_var("OPENC3_TAG", "latest");
        std::env::set_var("OPENC3_ENTERPRISE_TAG", "latest");
        match dev_folder.and_then(openc3_gem_dir) {
            Some(gem) => std::env::set_var("OPENC3_DEVEL", gem),
            None => std::env::remove_var("OPENC3_DEVEL"),
        }
    } else {
        std::env::remove_var("OPENC3_TAG");
        std::env::remove_var("OPENC3_ENTERPRISE_TAG");
        std::env::remove_var("OPENC3_DEVEL");
    }
}

/// The local openc3 gem directory (containing a Python package) inside a dev
/// checkout, for OPENC3_DEVEL. Handles the monorepo layout (`<dev>/openc3/python`)
/// and the case where the dev folder itself is the openc3 gem (`<dev>/python`).
fn openc3_gem_dir(dev: &std::path::Path) -> Option<std::path::PathBuf> {
    let monorepo = dev.join("openc3");
    if monorepo.join("python").join("pyproject.toml").is_file() {
        return Some(monorepo);
    }
    if dev.join("python").join("pyproject.toml").is_file() {
        return Some(dev.to_path_buf());
    }
    None
}

/// The development source folder to drive COSMOS from, when dev mode is on and a
/// (non-empty) folder is configured.
fn dev_folder_from_settings(settings: &crate::settings::Settings) -> Option<std::path::PathBuf> {
    if settings.dev_mode && !settings.dev_folder.trim().is_empty() {
        Some(std::path::PathBuf::from(settings.dev_folder.trim()))
    } else {
        None
    }
}

/// Probe the COSMOS web UI: ready when `url` returns success and serves the
/// index HTML. Uses curl with a short timeout; returns false on any failure.
fn probe_cosmos(url: &str) -> bool {
    // Route through process::capture so it gets CREATE_NO_WINDOW on Windows —
    // this is polled continuously, and a bare Command would flash a curl console
    // window every time (the GUI has no console of its own).
    let mut cmd = std::process::Command::new("curl");
    cmd.args(["-fsSL", "--max-time", "3", url]);
    match crate::process::capture(&mut cmd) {
        Ok(o) if o.status.success() => {
            let body = String::from_utf8_lossy(&o.stdout).to_lowercase();
            body.contains("<html") || body.contains("<!doctype html")
        }
        _ => false,
    }
}

/// True when a running container has been up for less than a minute. Docker
/// reports sub-minute uptime in seconds (e.g. "Up 12 seconds", "Up Less than a
/// second"); once it crosses a minute the text switches to "minute(s)"/"hour"
/// etc. So a "second"-based status means freshly started.
fn started_recently(c: &ContainerStatus) -> bool {
    let s = c.status.to_lowercase();
    s.contains("up") && s.contains("second")
}

/// Map a container's lifecycle state to a status indicator glyph and color,
/// mirroring the OpenC3 launcher's table styling. Containers that have been up
/// for less than a minute show yellow (still starting up); running-but-unhealthy
/// containers show orange.
fn state_style(c: &ContainerStatus) -> (&'static str, Color) {
    let green = Color::from_rgb8(0x4C, 0xAF, 0x50);
    let red = Color::from_rgb8(0xF4, 0x43, 0x36);
    let orange = Color::from_rgb8(0xFF, 0x98, 0x00);
    let yellow = Color::from_rgb8(0xFF, 0xEB, 0x3B);
    let gray = Color::from_rgb8(0x9E, 0x9E, 0x9E);
    // Use only widely-supported glyphs (●, ○, ?); color carries the meaning.
    match c.run_state() {
        monitor::RunState::Running => {
            if started_recently(c) {
                ("● ", yellow)
            } else if c.health.eq_ignore_ascii_case("unhealthy")
                || c.health.eq_ignore_ascii_case("starting")
            {
                ("● ", orange)
            } else {
                ("● ", green)
            }
        }
        monitor::RunState::ExitedSuccess => ("○ ", green),
        monitor::RunState::ExitedFailure => ("○ ", red),
        monitor::RunState::Restarting => ("● ", orange),
        monitor::RunState::Paused => ("● ", gray),
        monitor::RunState::Unknown => ("? ", gray),
    }
}

/// Launch the GUI. Uses the multi-window `daemon` API so the logs can pop out
/// into their own draggable OS window. The main window is opened in the
/// initializer and the app exits when it is closed.
pub fn launch(root_override: Option<PathBuf>, enterprise: bool) -> anyhow::Result<()> {
    // Only one GUI instance may run — a second launch signals the first to show
    // its window (it may be hidden in the tray) and exits, rather than spawning a
    // duplicate (another tray icon / operator). Uses a per-user lock file (no
    // fixed port to collide with) that the OS releases on crash. See
    // `single_instance`. Resolve the root the same way Context will so the lock
    // lives in the app's data dir; fall back to the temp dir if that fails.
    let root = crate::context::Paths::resolve(root_override.clone())
        .map(|p| p.root)
        .unwrap_or_else(|_| std::env::temp_dir());
    let guard = match crate::single_instance::acquire(&root) {
        crate::single_instance::Acquire::Secondary => {
            crate::logging::info(
                "openc3-app",
                "OpenC3 COSMOS is already running; brought its window to the front.",
            );
            return Ok(());
        }
        crate::single_instance::Acquire::Primary(guard) => guard,
    };
    iced::daemon(State::title, State::update, State::view)
        .subscription(State::subscription)
        .theme(|_state, _window| Theme::Dark)
        .font(ICON_FONT_BYTES)
        .run_with(move || {
            let ctx = Context::new(root_override.clone(), enterprise)
                .expect("failed to build application context");
            // Create the tray icon here: the boot closure runs on the main
            // thread after the platform app/event loop is initialized.
            crate::tray::init();
            // Don't let Iced destroy the window on the close (X) button — we hide
            // it to the tray instead (see Message::CloseRequested).
            let settings = window::Settings {
                exit_on_close_request: false,
                ..window::Settings::default()
            };
            let (id, open) = window::open(settings);
            (State::new(ctx, id, guard), open.map(|_| Message::Ignore))
        })
        .map_err(|e| anyhow::anyhow!("GUI error: {e}"))
}
