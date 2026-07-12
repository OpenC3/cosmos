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

use iced::widget::{
    button, column, container, horizontal_rule, progress_bar, row, scrollable, text, text_editor,
    text_input, Space,
};
use iced::{window, Center, Color, Element, Font, Length, Size, Subscription, Task, Theme};

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

/// Result of the startup environment check.
#[derive(Debug, Clone, Copy)]
struct EnvCheck {
    /// A docker or podman binary is available.
    container_ok: bool,
    /// The isolated Python runtime is installed.
    python_ok: bool,
    /// The COSMOS environment (cosmos-project folder) is installed.
    cosmos_ok: bool,
}

impl EnvCheck {
    /// True when nothing needs installing (the install page can be skipped).
    fn all_present(&self) -> bool {
        self.container_ok && self.python_ok && self.cosmos_ok
    }
}

/// Data produced by background worker threads, polled by the UI on each tick.
#[derive(Default)]
struct Shared {
    log: Vec<String>,
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
    log: Vec<String>,
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
    bridge_token_input: String,
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

fn start_operator(ctx: &Context) -> OperatorHandles {
    let mut operator =
        MicroserviceOperator::new(ctx.paths.python.clone(), ctx.paths.microservices.clone());
    // Auto-enroll runs in the operator loop once COSMOS has been up a while
    // (retried, bounded, re-armed on restart). Give it a connector + a cheap
    // COSMOS-up check, both capturing the context.
    let connect_ctx = ctx.clone();
    let ready_ctx = ctx.clone();
    operator.set_bridge_connector(
        Box::new(move || crate::enroll::connect_bridge(&connect_ctx)),
        // COSMOS "uptime" = how long the whole stack has been up = the uptime of
        // its most-recently-started running container.
        Box::new(move || {
            crate::monitor::snapshot(&ready_ctx)
                .ok()
                .and_then(|s| s.iter().filter_map(|c| c.uptime()).min())
        }),
    );
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
    InstallDockerMac(install::MacEngine),
    InstallDockerWin(install::WinEngine),
    InstallPython,
    InstallCosmos,
    Skip,
    Start,
    Stop,
    OpenBrowser,
    ShowCleanup,
    CleanupInputChanged(String),
    ConfirmCleanup,
    CancelCleanup,
    BridgeTokenChanged(String),
    SubmitBridgeToken,
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
    fn new(ctx: Context, main_window: window::Id) -> Self {
        let env = EnvCheck {
            container_ok: ctx.runtime.is_some(),
            python_ok: ctx.paths.python_installed(),
            cosmos_ok: ctx.paths.cosmos_installed(),
        };

        // Start the host microservice operator (process spawner/monitor) on a
        // background thread and keep a handle to its published status.
        let (operator_status, bridge_status_handle, operator_shutdown, operator_thread) =
            start_operator(&ctx);

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
            log: vec!["OpenC3 COSMOS control panel ready.".to_string()],
            busy: false,
            viewing_logs: None,
            logs_content: text_editor::Content::new(),
            cleanup_confirm: false,
            cleanup_input: String::new(),
            bridge_token_input: String::new(),
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
                python_ok: paths.python_installed(),
                cosmos_ok: paths.cosmos_installed(),
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
        let url = cosmos_url(&self.ctx);
        std::thread::spawn(move || {
            let result = monitor::snapshot(&ctx);
            // Probe the web UI so the Open button only enables once it serves
            // index.html.
            let ready = probe_cosmos(&url);
            if let Ok(mut s) = shared.lock() {
                match result {
                    Ok(statuses) => {
                        s.statuses = Some(statuses);
                    }
                    Err(_e) => {
                        s.statuses = Some(Vec::new());
                    }
                }
                s.cosmos_ready = Some(ready);
                s.refreshing = false;
            }
        });
    }

    fn drain_shared(&mut self) {
        if let Ok(mut s) = self.shared.lock() {
            self.busy = s.busy;
            if !s.log.is_empty() {
                self.log.append(&mut s.log);
                // Keep the log from growing without bound.
                let len = self.log.len();
                if len > 200 {
                    self.log.drain(0..len - 200);
                }
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
                            if self.env.all_present() {
                                self.go_main();
                            } else {
                                self.page = Page::Install;
                            }
                        }
                    }
                    Page::Install => {
                        // Keep the install page in sync as components are added,
                        // and once everything is present, advance automatically.
                        if !self.busy {
                            self.maybe_refresh_env();
                            if self.env.all_present() {
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
                Task::none()
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
            Message::InstallDockerMac(engine) => {
                let label = match engine {
                    install::MacEngine::Colima => "Installing Docker (colima)",
                    install::MacEngine::DockerDesktop => "Installing Docker Desktop",
                };
                self.spawn(label, move || install::install_docker_macos(engine));
                Task::none()
            }
            Message::InstallDockerWin(engine) => {
                let label = match engine {
                    install::WinEngine::DockerDesktop => "Installing Docker Desktop",
                    install::WinEngine::Podman => "Installing Podman",
                    install::WinEngine::RancherDesktop => "Installing Rancher Desktop",
                };
                self.spawn(label, move || install::install_docker_windows(engine));
                Task::none()
            }
            Message::InstallPython => {
                let ctx = self.ctx.clone();
                self.spawn("Installing Python", move || install::python(&ctx));
                Task::none()
            }
            Message::InstallCosmos => {
                let ctx = self.ctx.clone();
                self.spawn("Installing COSMOS", move || install::cosmos(&ctx, "latest"));
                Task::none()
            }
            Message::Start => {
                let ctx = self.ctx.clone();
                self.spawn("Starting COSMOS", move || commands::run(&ctx));
                Task::none()
            }
            Message::Stop => {
                let ctx = self.ctx.clone();
                self.spawn("Stopping COSMOS", move || commands::stop(&ctx));
                Task::none()
            }
            Message::OpenBrowser => {
                let url = cosmos_url(&self.ctx);
                if let Err(e) = commands::open_browser(&url) {
                    if let Ok(mut s) = self.shared.lock() {
                        s.log.push(format!("Failed to open browser: {e}"));
                    }
                }
                Task::none()
            }
            Message::ShowCleanup => {
                self.cleanup_input.clear();
                self.cleanup_confirm = true;
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
                Task::none()
            }
            Message::BridgeTokenChanged(value) => {
                self.bridge_token_input = value;
                Task::none()
            }
            Message::SubmitBridgeToken => {
                let token = self.bridge_token_input.trim().to_string();
                if token.is_empty() {
                    return Task::none();
                }
                match crate::enroll::enroll_with_token(&self.ctx, &token) {
                    Ok(bridge) => {
                        self.bridge_token_input.clear();
                        self.log.push(format!("Paired with bridge '{bridge}'. Reconnecting..."));
                        // Restart the operator so it picks up the new pairing.
                        self.operator_shutdown.store(true, Ordering::Relaxed);
                        if let Some(handle) = self.operator_thread.take() {
                            let _ = handle.join();
                        }
                        let (status, bridge_status, shutdown, thread) = start_operator(&self.ctx);
                        self.operator_status = status;
                        self.bridge_status_handle = bridge_status;
                        self.operator_shutdown = shutdown;
                        self.operator_thread = thread;
                    }
                    Err(e) => {
                        self.log.push(format!("Enrollment failed: {e:#}"));
                    }
                }
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
                    // Closing the main window doesn't quit: hide it to the tray
                    // (or just minimize where there's no tray). The tray's Quit
                    // (or a real close) exits.
                    if crate::tray::ENABLED {
                        window::change_mode(id, window::Mode::Hidden)
                    } else {
                        window::minimize(id, true)
                    }
                } else {
                    // Other windows (e.g. logs) close normally.
                    window::close(id)
                }
            }
            Message::PollTray => match crate::tray::poll() {
                Some(crate::tray::TrayAction::Show) => {
                    window::change_mode(self.main_window, window::Mode::Windowed)
                        .chain(window::gain_focus(self.main_window))
                }
                Some(crate::tray::TrayAction::Quit) => self.quit(),
                None => Task::none(),
            },
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
                s.log.push("A task is already running; please wait.".to_string());
                return;
            }
            s.busy = true;
            s.log.push(format!("{label}..."));
        }
        let shared = self.shared.clone();
        std::thread::spawn(move || {
            // Mirror install progress / NEXT STEPS messages into the activity log
            // so GUI users see them (not just the terminal).
            let sink = shared.clone();
            install::set_notifier(Box::new(move |m| {
                if let Ok(mut s) = sink.lock() {
                    s.log.push(m);
                }
            }));
            let result = f();
            install::clear_notifier();
            let mut s = shared.lock().unwrap();
            match result {
                Ok(()) => s.log.push(format!("{label}: done.")),
                Err(e) => s.log.push(format!("{label}: ERROR: {e}")),
            }
            s.busy = false;
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
        match self.page {
            Page::Splash => self.view_splash(),
            Page::Install => self.view_install(),
            Page::Main => {
                if self.cleanup_confirm {
                    self.view_cleanup_confirm()
                } else {
                    self.view_main()
                }
            }
        }
    }

    /// Page 1: branded splash shown for [`SPLASH_DURATION`] while the
    /// environment is checked.
    fn view_splash(&self) -> Element<'_, Message> {
        // Fill the bar quickly (well before the splash ends), then hold full.
        const BAR_FILL_SECS: f32 = 1.0;
        let fraction = (self.splash_start.elapsed().as_secs_f32() / BAR_FILL_SECS).clamp(0.0, 1.0);
        let content = column![
            text("OpenC3 COSMOS").size(48).font(Font::MONOSPACE),
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
        let title = text("Setup").size(32);
        let subtitle =
            text("Some components are missing. Install them now, or skip.").size(16);

        let action = |label: &str, msg: Message| {
            let b = button(text(label.to_string())).padding(10);
            if self.busy {
                b
            } else {
                b.on_press(msg)
            }
        };

        let mut items = column![].spacing(12);
        if !self.env.container_ok {
            // Offer a choice of engine on macOS and Windows; a single installer
            // elsewhere.
            let docker_row = if cfg!(target_os = "macos") {
                row![
                    text("Docker").size(16).width(220),
                    action("Colima", Message::InstallDockerMac(install::MacEngine::Colima)),
                    action(
                        "Docker Desktop",
                        Message::InstallDockerMac(install::MacEngine::DockerDesktop)
                    ),
                ]
            } else if cfg!(target_os = "windows") {
                row![
                    text("Docker").size(16).width(220),
                    action(
                        "Docker Desktop",
                        Message::InstallDockerWin(install::WinEngine::DockerDesktop)
                    ),
                    action("Podman", Message::InstallDockerWin(install::WinEngine::Podman)),
                    action(
                        "Rancher Desktop",
                        Message::InstallDockerWin(install::WinEngine::RancherDesktop)
                    ),
                ]
            } else {
                row![
                    text("Docker / Podman").size(16).width(220),
                    action("Install Docker", Message::InstallDocker),
                ]
            }
            .spacing(12)
            .align_y(Center);
            items = items.push(docker_row);
            // Docker Desktop licensing caveat (it's an option on macOS and Windows).
            if cfg!(any(target_os = "macos", target_os = "windows")) {
                items = items.push(
                    text(install::DOCKER_DESKTOP_LICENSE)
                        .size(11)
                        .color(Color::from_rgb8(0x9E, 0x9E, 0x9E)),
                );
            }
        }
        if !self.env.python_ok {
            items = items.push(
                row![
                    text("Python runtime").size(16).width(220),
                    action("Install Python", Message::InstallPython),
                ]
                .spacing(12)
                .align_y(Center),
            );
        }
        if !self.env.cosmos_ok {
            items = items.push(
                row![
                    text("COSMOS environment").size(16).width(220),
                    action("Install COSMOS", Message::InstallCosmos),
                ]
                .spacing(12)
                .align_y(Center),
            );
        }

        let skip = button(text("Skip").size(16)).padding(10).on_press(Message::Skip);

        let busy_note = if self.busy {
            text("Working… (detailed output in the terminal)").size(13)
        } else {
            text(" ").size(13)
        };

        let mut log_col = column![].spacing(2);
        for line in self.log.iter().rev().take(8).rev() {
            log_col = log_col.push(text(line).size(12).font(Font::MONOSPACE));
        }

        let content = column![
            title,
            subtitle,
            Space::with_height(16),
            items,
            Space::with_height(16),
            skip,
            busy_note,
            scrollable(log_col).height(Length::FillPortion(1)),
        ]
        .spacing(10)
        .padding(30)
        .align_x(Center);

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x(Length::Fill)
            .into()
    }

    /// Page 3: the main control panel with live container status.
    fn view_main(&self) -> Element<'_, Message> {
        let title = text("OpenC3 COSMOS").size(28);

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

        // Show Start when nothing is running, Stop once any container is up.
        let started = self.statuses.iter().any(|c| c.is_running());
        let primary = if started {
            action("Stop", Message::Stop)
        } else {
            action("Start", Message::Start)
        };
        let buttons = row![primary, action("Cleanup", Message::ShowCleanup)].spacing(10);

        // Prominent, full-width button to open the COSMOS web UI; enabled only
        // once COSMOS is up and serving index.html.
        let open_label = if self.cosmos_ready {
            "Open COSMOS in Browser"
        } else {
            "Open COSMOS in Browser (waiting for COSMOS…)"
        };
        let open_button = button(
            text(open_label)
                .size(18)
                .width(Length::Fill)
                .align_x(Center),
        )
        .width(Length::Fill)
        .padding(14)
        .style(if self.cosmos_ready {
            button::success
        } else {
            button::secondary
        })
        .on_press_maybe(self.cosmos_ready.then_some(Message::OpenBrowser));

        // Color-coded container status table (Container | Status | Ports).
        let header_color = Color::from_rgb8(0x9E, 0x9E, 0x9E);
        let mut table = column![row![
            text("Container")
                .size(13)
                .font(Font::MONOSPACE)
                .width(260)
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
            text("Ports")
                .size(13)
                .font(Font::MONOSPACE)
                .width(80)
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
                    text(c.ports_summary())
                        .size(13)
                        .font(Font::MONOSPACE)
                        .width(80),
                    logs_button,
                ]
                .spacing(10)
                .align_y(Center);
                table = table.push(container_row);
            }
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
        let arrow = if self.status_collapsed {
            "\u{25B6}" // ▶
        } else {
            "\u{25BC}" // ▼
        };
        let header_label = if self.status_collapsed {
            format!("{arrow}  Container Status  ({status_summary})")
        } else {
            format!("{arrow}  Container Status")
        };
        let status_header = button(text(header_label).size(18))
            .on_press(Message::ToggleStatus)
            .style(button::text)
            .padding(0);
        let status_section = if self.status_collapsed {
            column![status_header, horizontal_rule(2)].spacing(8)
        } else {
            column![status_header, horizontal_rule(2), status_body].spacing(8)
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
                    ]
                    .spacing(10)
                    .align_y(Center),
                );
            }
        }
        // Manual pairing: redeem an enrollment token from a remote COSMOS's
        // Admin → Bridges page. Co-located COSMOS enrolls automatically.
        let pair_row = row![
            text_input(
                "Enrollment token (to pair with a remote COSMOS bridge)",
                &self.bridge_token_input,
            )
            .on_input(Message::BridgeTokenChanged)
            .on_submit(Message::SubmitBridgeToken)
            .width(Length::Fill),
            button(text("Pair")).on_press(Message::SubmitBridgeToken),
        ]
        .spacing(8)
        .align_y(Center);

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
        let cosmos_row = row![
            text("COSMOS:").size(13).font(Font::MONOSPACE),
            text(format!("{cosmos_glyph}{cosmos_message}"))
                .size(13)
                .font(Font::MONOSPACE)
                .color(cosmos_color),
        ]
        .spacing(8)
        .align_y(Center);

        let ms_section = column![
            text("Bridge Microservices").size(18),
            horizontal_rule(2),
            cosmos_row,
            scrollable(ms_table).height(Length::FillPortion(1)),
            pair_row,
        ]
        .spacing(8);

        let mut log_col = column![text("Activity").size(18)].spacing(2);
        for line in self.log.iter().rev().take(12).rev() {
            log_col = log_col.push(text(line).size(13));
        }

        let busy_note = if self.busy {
            text("Working… (detailed output in the terminal)").size(13)
        } else {
            text("Idle").size(13)
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
            scrollable(log_col).height(Length::FillPortion(1)),
        ]
        .spacing(6)
        .padding(20);

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
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
            Page::Install => Duration::from_millis(750),
            // Tick fast while the first status sample is still loading so the
            // spinner animates, then settle to a 2s status poll.
            Page::Main if !self.status_loaded => Duration::from_millis(120),
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

/// The COSMOS web UI URL, taken from the install's `.env`
/// (`OPENC3_EXTERNAL_URL`) when available, else the default.
fn cosmos_url(ctx: &Context) -> String {
    let env = ctx.paths.env_file();
    if env.exists() {
        if let Ok(map) = crate::env_file::parse(&env) {
            if let Some(u) = map.get("OPENC3_EXTERNAL_URL") {
                if !u.is_empty() {
                    return u.clone();
                }
            }
        }
    }
    "http://localhost:2900".to_string()
}

/// Probe the COSMOS web UI: ready when `url` returns success and serves the
/// index HTML. Uses curl with a short timeout; returns false on any failure.
fn probe_cosmos(url: &str) -> bool {
    let out = std::process::Command::new("curl")
        .args(["-fsSL", "--max-time", "3", url])
        .output();
    match out {
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
    iced::daemon(State::title, State::update, State::view)
        .subscription(State::subscription)
        .theme(|_state, _window| Theme::Dark)
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
            (State::new(ctx, id), open.map(|_| Message::Ignore))
        })
        .map_err(|e| anyhow::anyhow!("GUI error: {e}"))
}
