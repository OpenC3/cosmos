#!/usr/bin/env python3
"""Generate the system-tray / menu-bar icon: a "COS" / "MOS" two-line badge.

The full app icon (assets/icon.png) is a detailed mark that turns to mush when
the OS shrinks it to ~16-22px in the tray. This renders a purpose-built badge
instead — bold white "COS" over "MOS" on the brand-blue rounded square — which
stays legible and high-contrast at tray size on any taskbar theme. Output ->
assets/tray.png, loaded by src/tray.rs.

Run from the openc3-app directory:

    uv run --with pillow python tools/gen_tray_icon.py

Commit the regenerated assets/tray.png.
"""

from PIL import Image, ImageDraw, ImageFont

S = 256  # master size; the OS downscales this to the tray size
# Heaviest common system font so the letters read when shrunk.
FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"


def main():
    # Match the app icon's brand blue by sampling it (center-top is solid blue).
    brand = (0, 50, 159, 255)
    try:
        ic = Image.open("assets/icon.png").convert("RGBA")
        px = ic.getpixel((ic.width // 2, int(ic.height * 0.16)))
        if px[3] > 200:
            brand = (px[0], px[1], px[2], 255)
    except Exception as e:  # noqa: BLE001 - best effort; fall back to the constant
        print("brand sample failed, using default:", e)

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = 6
    d.rounded_rectangle([pad, pad, S - 1 - pad, S - 1 - pad], radius=46, fill=brand)

    target_w = S - 2 * pad - 26  # a little side margin

    def width_of(text, font):
        box = d.textbbox((0, 0), text, font=font)
        return box[2] - box[0]

    # Grow the font until the wider line fills the target width.
    size = 10
    while size < 400:
        f = ImageFont.truetype(FONT, size + 4)
        if max(width_of("COS", f), width_of("MOS", f)) > target_w:
            break
        size += 4
    font = ImageFont.truetype(FONT, size)

    def height_of(text):
        box = d.textbbox((0, 0), text, font=font)
        return box[3] - box[1]

    line_h = max(height_of("COS"), height_of("MOS"))
    # ~1px of visible separation once the OS shrinks this 256px master down to
    # the ~16-22px tray size (256 / ~22 ≈ 12); otherwise the lines merge.
    gap = 12
    top = (S - (2 * line_h + gap)) / 2

    def draw_centered(text, center_y):
        box = d.textbbox((0, 0), text, font=font)
        x = (S - (box[2] - box[0])) / 2 - box[0]
        y = center_y - (box[3] - box[1]) / 2 - box[1]
        d.text((x, y), text, font=font, fill=(255, 255, 255, 255))

    draw_centered("COS", top + line_h / 2)
    draw_centered("MOS", top + line_h + gap + line_h / 2)

    img.save("assets/tray.png")
    print(f"wrote assets/tray.png  brand={brand}  font_size={size}")


if __name__ == "__main__":
    main()
