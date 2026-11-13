#!/usr/bin/env bash
# Screenshot every slide of a standalone deck in light and dark themes.
# Usage: render.sh <deck-standalone.html> <out-dir>
# Writes slide-<n>-light.png and slide-<n>-dark.png. Set CHROME to override the browser.
set -euo pipefail

DECK="$(cd "$(dirname "${1:?standalone deck required}")" && pwd)/$(basename "$1")"
OUT="${2:?output directory required}"
WIDTH="${DECK_WIDTH:-1280}"
HEIGHT="${DECK_HEIGHT:-800}"
SCALE="${DECK_SCALE:-2}"

if [[ -z "${CHROME:-}" ]]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then CHROME="$candidate"; break; fi
  done
fi
[[ -n "${CHROME:-}" ]] || { echo "Chrome not found; set CHROME" >&2; exit 1; }

mkdir -p "$OUT"
COUNT=$(grep -c '<section class="slide' "$DECK")
for ((n = 1; n <= COUNT; n++)); do
  for theme in light dark; do
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
      --force-device-scale-factor="$SCALE" --window-size="$WIDTH,$HEIGHT" \
      --virtual-time-budget=6000 --screenshot="$OUT/slide-$n-$theme.png" \
      "file://$DECK?capture=1&theme=$theme#$n" >/dev/null 2>&1
  done
  echo "slide $n rendered"
done
