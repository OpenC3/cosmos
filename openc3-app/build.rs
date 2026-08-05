// Build script: embed the OpenC3 COSMOS icon into the Windows executable.
//
// A bare `cargo build` produces a Windows .exe with NO icon resource, so
// Explorer, the taskbar, and any shortcut that points at the exe fall back to a
// generic icon — the app's desktop shortcut then "isn't the COSMOS logo".
// Embedding assets/icons/icon.ico as the exe's icon resource fixes all of those.
//
// The `#[cfg(windows)]` gate matches the host-scoped `winresource` build
// dependency in Cargo.toml: the crate is only present (and this only runs) when
// building on a Windows host, which is how the release workflow builds the
// Windows target. No-op on macOS/Linux.
fn main() {
    #[cfg(windows)]
    {
        let mut res = winresource::WindowsResource::new();
        res.set_icon("assets/icons/icon.ico");
        if let Err(e) = res.compile() {
            // Don't fail the build over the icon; just surface it.
            println!("cargo:warning=failed to embed Windows app icon: {e}");
        }
    }
}
