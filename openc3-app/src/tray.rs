//! System tray / menu-bar integration for "minimize (hide) to tray".
//!
//! Iced has no built-in tray support, so on Windows and macOS we add a
//! `tray-icon` icon with a Show/Quit menu. Closing the window hides it (Iced
//! `Mode::Hidden`) instead of quitting; the tray restores or quits it. On other
//! platforms (Linux) there is no tray — the window minimizes instead, and these
//! functions are no-ops.
//!
//! The tray icon must be created on the main/event-loop thread after the app is
//! initialized (macOS requires an initialized `NSApplication`); [`init`] is
//! therefore called from Iced's boot closure. Menu clicks are delivered on that
//! thread's run loop into a global channel that [`poll`] drains.

/// Whether a real tray is available on this platform (drives close = hide vs
/// minimize).
pub const ENABLED: bool = cfg!(any(target_os = "windows", target_os = "macos"));

/// A tray menu action selected by the user. Only constructed on platforms with
/// a real tray (Windows/macOS); on others `poll` is a no-op, so the variants
/// would otherwise look dead there.
#[allow(dead_code)]
#[derive(Debug, Clone, Copy)]
pub enum TrayAction {
    /// Restore/focus the main window.
    Show,
    /// Quit the application.
    Quit,
}

#[cfg(any(target_os = "windows", target_os = "macos"))]
mod imp {
    use super::TrayAction;
    use tray_icon::menu::{Menu, MenuEvent, MenuItem};
    use tray_icon::{Icon, TrayIconBuilder};

    const SHOW_ID: &str = "openc3-show";
    const QUIT_ID: &str = "openc3-quit";

    /// Create the tray icon and leak it so it lives for the whole process
    /// (menu events are read via the global receiver in [`poll`]). Best effort:
    /// logs and continues if the platform rejects it.
    pub fn init() {
        let menu = Menu::new();
        let show = MenuItem::with_id(SHOW_ID, "Show OpenC3 COSMOS", true, None);
        let quit = MenuItem::with_id(QUIT_ID, "Quit", true, None);
        if menu.append(&show).is_err() || menu.append(&quit).is_err() {
            eprintln!("WARN  [tray] failed to build tray menu");
            return;
        }
        match TrayIconBuilder::new()
            .with_menu(Box::new(menu))
            .with_tooltip("OpenC3 COSMOS")
            .with_icon(icon())
            .build()
        {
            // Keep the icon (and its menu/items) alive for the process lifetime.
            Ok(tray) => std::mem::forget(tray),
            Err(e) => eprintln!("WARN  [tray] failed to create tray icon: {e}"),
        }
        std::mem::forget(show);
        std::mem::forget(quit);
    }

    /// Drain pending tray menu clicks, returning the most recent action.
    pub fn poll() -> Option<TrayAction> {
        let mut action = None;
        while let Ok(event) = MenuEvent::receiver().try_recv() {
            match event.id.0.as_str() {
                SHOW_ID => action = Some(TrayAction::Show),
                QUIT_ID => action = Some(TrayAction::Quit),
                _ => {}
            }
        }
        action
    }

    /// A small solid OpenC3-blue 32x32 icon (no asset file needed).
    fn icon() -> Icon {
        let (w, h) = (32u32, 32u32);
        let mut rgba = Vec::with_capacity((w * h * 4) as usize);
        for _ in 0..(w * h) {
            rgba.extend_from_slice(&[0x1E, 0x88, 0xE5, 0xFF]);
        }
        Icon::from_rgba(rgba, w, h).expect("valid tray icon")
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
mod imp {
    use super::TrayAction;
    pub fn init() {}
    pub fn poll() -> Option<TrayAction> {
        None
    }
}

pub use imp::{init, poll};
