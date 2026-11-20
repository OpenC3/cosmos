#!/usr/bin/env python3
"""Render a parity report: inject data.json into template.html.

Usage: python3 render.py <data.json> <out.html>

The JSON schema is documented at the top of template.html. Prose fields may
contain inline HTML (<code>, <strong>); code fields are plain text and are
escaped by the page.
"""

import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
template = (Path(__file__).parent / "template.html").read_text()
payload = json.dumps(data, indent=1).replace("</", "<\\/")
html = template.replace("{{DATA}}", payload).replace("{{TITLE}}", data["meta"].get("title", "COSMOS Parity Review"))
Path(sys.argv[2]).write_text(html)
print(f"wrote {sys.argv[2]}")
