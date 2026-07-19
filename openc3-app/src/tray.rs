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
            crate::logging::warn("tray", "failed to build tray menu");
            return;
        }
        match TrayIconBuilder::new()
            .with_menu(Box::new(menu))
            .with_tooltip("OpenC3 COSMOS")
            .with_icon(icon())
            // On macOS the icon is a black+alpha template so the OS tints it to
            // match the menu bar (light/dark). Other platforms use it as-is.
            .with_icon_as_template(cfg!(target_os = "macos"))
            .build()
        {
            // Keep the icon (and its menu/items) alive for the process lifetime.
            Ok(tray) => std::mem::forget(tray),
            Err(e) => crate::logging::warn("tray", &format!("failed to create tray icon: {e}")),
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

    /// "COS" over "MOS" on a transparent background, rendered from a tiny
    /// built-in 5x7 bitmap font (no asset file / font crate needed). On macOS
    /// the letters are black so the template icon tints correctly for the menu
    /// bar; elsewhere they're white (visible on the typically-dark tray).
    fn icon() -> Icon {
        const W: usize = 64;
        const H: usize = 64;
        const SCALE: usize = 3; // pixels per font cell
        const CELL_W: usize = 5;
        const CELL_H: usize = 7;
        const CHAR_W: usize = CELL_W * SCALE; // 15
        const CHAR_H: usize = CELL_H * SCALE; // 21
        const CHAR_SP: usize = 3; // gap between characters
        const LINE_GAP: usize = 6; // gap between the two lines

        // Transparent background (all-zero RGBA); opaque letters.
        let fg: [u8; 4] = if cfg!(target_os = "macos") {
            [0x00, 0x00, 0x00, 0xFF] // black: macOS template tints it per menu bar
        } else {
            [0xFF, 0xFF, 0xFF, 0xFF] // white: visible on Windows' dark tray
        };

        let mut rgba = vec![0u8; W * H * 4]; // zeroed = fully transparent

        let line_w = 3 * CHAR_W + 2 * CHAR_SP;
        let x0 = (W - line_w) / 2;
        let y0 = (H - (2 * CHAR_H + LINE_GAP)) / 2;

        let mut draw = |text: &str, oy: usize| {
            for (i, ch) in text.chars().enumerate() {
                let ox = x0 + i * (CHAR_W + CHAR_SP);
                for (ry, row) in glyph(ch).iter().enumerate() {
                    for (cx, cell) in row.bytes().enumerate() {
                        if cell != b'#' {
                            continue;
                        }
                        for dy in 0..SCALE {
                            for dx in 0..SCALE {
                                let x = ox + cx * SCALE + dx;
                                let y = oy + ry * SCALE + dy;
                                if x < W && y < H {
                                    let idx = (y * W + x) * 4;
                                    rgba[idx..idx + 4].copy_from_slice(&fg);
                                }
                            }
                        }
                    }
                }
            }
        };
        draw("COS", y0);
        draw("MOS", y0 + CHAR_H + LINE_GAP);

        Icon::from_rgba(rgba, W as u32, H as u32).expect("valid tray icon")
    }

    /// 5x7 bitmap glyphs for the letters used in "COS" / "MOS".
    fn glyph(c: char) -> [&'static str; 7] {
        match c {
            'C' => [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
            'O' => [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
            'S' => [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
            'M' => ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
            _ => ["", "", "", "", "", "", ""],
        }
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
