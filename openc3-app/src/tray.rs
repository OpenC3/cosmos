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
            // Show the branded logo as-is on every platform (not tinted as a
            // macOS template), so the colored icon appears in the menu bar/tray.
            .with_icon_as_template(false)
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

    /// The tray/menu-bar icon: a purpose-built "COS"/"MOS" badge (bold white on
    /// the brand-blue rounded square) on every platform. The full app logo turned
    /// to mush when the OS shrank it to tray size, and a plain monochrome template
    /// is invisible on a light Windows 11 taskbar; this badge stays legible and
    /// high-contrast at ~16-22px. Regenerate with tools/gen_tray_icon.py.
    fn icon() -> Icon {
        icon_badge()
    }

    /// The COS/MOS badge PNG decoded to RGBA for the tray. Falls back to the drawn
    /// template if decoding ever fails, so the tray always gets an icon.
    fn icon_badge() -> Icon {
        const BADGE_PNG: &[u8] = include_bytes!("../assets/tray.png");
        match image::load_from_memory(BADGE_PNG) {
            Ok(img) => {
                let rgba = img.into_rgba8();
                let (w, h) = rgba.dimensions();
                Icon::from_rgba(rgba.into_raw(), w, h).expect("valid tray icon")
            }
            Err(e) => {
                crate::logging::warn("tray", &format!("failed to decode tray badge: {e}; using fallback"));
                icon_template()
            }
        }
    }

    /// "COS" over "MOS" on a transparent background, rendered from a tiny
    /// built-in 5x7 bitmap font (no asset file / font crate needed). Fallback
    /// only — used if the branded logo ever fails to decode — so the tray still
    /// gets an icon. Letters are black on macOS, white elsewhere.
    fn icon_template() -> Icon {
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

/// Show or hide the macOS Dock icon. When the app is hidden to the tray we switch
/// to the "accessory" activation policy so it drops out of the Dock (menu-bar-app
/// style); showing it again restores the "regular" policy and the Dock icon. This
/// is what stops a tray-hidden app from lingering in the Dock. No-op off macOS —
/// only macOS has this Dock / activation-policy concept.
#[cfg_attr(not(target_os = "macos"), allow(unused_variables))]
pub fn set_dock_visible(visible: bool) {
    #[cfg(target_os = "macos")]
    {
        use objc2::runtime::AnyObject;
        use objc2::{class, msg_send};
        // NSApplicationActivationPolicy: Regular = 0 (Dock icon shown),
        // Accessory = 1 (no Dock icon). Must be called on the main thread — the
        // iced update loop, our only caller, runs there.
        let policy: isize = if visible { 0 } else { 1 };
        unsafe {
            let app: *mut AnyObject = msg_send![class!(NSApplication), sharedApplication];
            if !app.is_null() {
                // -[NSApplication setActivationPolicy:] returns BOOL, so the
                // declared return type must be `bool` — objc2 verifies the
                // Objective-C type encoding at runtime and aborts on a mismatch
                // (declaring `()` panicked with "expected 'B', found 'v'").
                let _changed: bool = msg_send![app, setActivationPolicy: policy];
            }
        }
    }
}
