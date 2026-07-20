#!/usr/bin/env python3
"""Generate the app-tile icon and the per-platform installer icon set.

Composites the raw OpenC3 mark (assets/logo.png) onto a brand-colored rounded
"app tile" -> assets/icon.png (the 1024x1024 master), then derives the PNG sizes
+ a multi-resolution Windows .ico with Pillow and a macOS .icns via `iconutil`
(macOS only). Results live in assets/icons/ and are referenced by
`[package.metadata.packager].icons` in Cargo.toml.

Run from the openc3-app directory:

    uv run --with pillow python tools/gen_app_icons.py

Commit the regenerated assets/icon.png and assets/icons/*.
"""

import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

LOGO = "assets/logo.png"  # raw mark on transparent background
MASTER = "assets/icon.png"  # composed app tile (1024x1024)
OUT = "assets/icons"
SIZE = 1024
MARGIN = round(SIZE * 0.06)  # transparent margin around the tile
RADIUS = round(SIZE * 0.20)  # corner radius (~squircle)
MARK_FRACTION = 0.74  # mark size relative to the tile's inner area


def brand_color(logo):
    """Average color of the mark's opaque pixels (the OpenC3 blue)."""
    r = g = b = n = 0
    for pr, pg, pb, pa in logo.getdata():
        if pa > 200:
            r += pr
            g += pg
            b += pb
            n += 1
    n = max(n, 1)
    return (r // n, g // n, b // n)


def build_tile(logo):
    color = brand_color(logo)
    print(f"Tile color: #{color[0]:02x}{color[1]:02x}{color[2]:02x}")

    # Rounded-rectangle tile filled with the brand color.
    tile = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (MARGIN, MARGIN, SIZE - MARGIN, SIZE - MARGIN), radius=RADIUS, fill=255
    )
    solid = Image.new("RGBA", (SIZE, SIZE), color + (255,))
    tile = Image.composite(solid, tile, mask)

    # Recolor the (cropped) mark white, using its alpha as the shape.
    mark = logo.crop(logo.getbbox())
    white = Image.new("RGBA", mark.size, (255, 255, 255, 255))
    transparent = Image.new("RGBA", mark.size, (255, 255, 255, 0))
    white_mark = Image.composite(white, transparent, mark.split()[3])

    # Scale the mark to fit the tile's inner area and center it.
    inner = SIZE - 2 * MARGIN
    target = round(inner * MARK_FRACTION)
    w, h = white_mark.size
    scale = target / max(w, h)
    nw, nh = round(w * scale), round(h * scale)
    white_mark = white_mark.resize((nw, nh), Image.LANCZOS)
    tile.alpha_composite(white_mark, ((SIZE - nw) // 2, (SIZE - nh) // 2))
    return tile


def main():
    logo = Image.open(LOGO).convert("RGBA")
    if logo.size[0] != logo.size[1]:
        sys.exit(f"{LOGO} must be square, got {logo.size}")
    logo = logo.resize((SIZE, SIZE), Image.LANCZOS) if logo.size != (SIZE, SIZE) else logo

    master = build_tile(logo)
    master.save(MASTER)
    print(f"Wrote {MASTER} (app tile)")

    os.makedirs(OUT, exist_ok=True)

    def resized(px):
        return master.resize((px, px), Image.LANCZOS)

    resized(32).save(f"{OUT}/32x32.png")
    resized(128).save(f"{OUT}/128x128.png")
    resized(256).save(f"{OUT}/128x128@2x.png")
    resized(256).save(f"{OUT}/256x256.png")
    resized(512).save(f"{OUT}/512x512.png")
    master.save(
        f"{OUT}/icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("Wrote PNG sizes and icon.ico")

    if sys.platform == "darwin":
        with tempfile.TemporaryDirectory(suffix=".iconset") as iconset:
            for base in (16, 32, 128, 256, 512):
                resized(base).save(f"{iconset}/icon_{base}x{base}.png")
                resized(base * 2).save(f"{iconset}/icon_{base}x{base}@2x.png")
            subprocess.run(
                ["iconutil", "-c", "icns", iconset, "-o", f"{OUT}/icon.icns"], check=True
            )
        print("Wrote icon.icns")
    else:
        print("Skipping icon.icns (requires macOS `iconutil`); build it on a Mac.")


if __name__ == "__main__":
    main()
