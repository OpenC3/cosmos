#!/usr/bin/env bash
# Assemble a deck from the template and a file of <section class="slide"> elements.
# Usage: build.sh <slides.html> <title> <out.html> [--standalone]
#   --standalone wraps the result in a full HTML document for opening directly in a
#   browser or uploading from CI. Without it the output is the fragment the Artifact
#   tool publishes (it adds its own document skeleton).
set -euo pipefail

SLIDES="${1:?slides file required}"
TITLE="${2:?title required}"
OUT="${3:?output file required}"
STANDALONE="${4:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 -I - "$DIR/template.html" "$SLIDES" "$TITLE" "$OUT" "$STANDALONE" <<'PY'
import html, sys
template_path, slides_path, title, out_path, standalone = sys.argv[1:6]
template = open(template_path, encoding="utf-8").read()
slides = open(slides_path, encoding="utf-8").read()
page = template.replace("{{TITLE}}", html.escape(title)).replace("<!-- SLIDES -->", slides.strip())
if standalone == "--standalone":
    page = (
        '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        "<style>body{margin:0}[hidden]{display:none!important}</style>\n"
        "</head>\n<body>\n" + page + "\n</body>\n</html>\n"
    )
open(out_path, "w", encoding="utf-8").write(page)
PY

python3 -I "$DIR/check_deck.py" "$OUT"
