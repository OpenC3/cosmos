#!/usr/bin/env python3
"""Lint a generated PR deck: every content slide needs a visual, and prose stays short.

Usage: python3 -I check_deck.py deck.html
Exits 1 and lists problems when a rule is broken.
"""

import re
import sys
from html.parser import HTMLParser

# Class names (from template.html) that count as a diagram or visual
VISUAL_CLASSES = {
    "flow", "fan", "compare", "phases", "lanes", "matrix", "diagram", "sizebar", "stats", "checks", "snippet",
}
# Elements whose text counts as prose (diagram labels and code don't)
PROSE_TAGS = {"p", "li"}
MAX_PROSE_WORDS = 110  # per slide, across all <p> and <li>
MAX_PARAGRAPH_WORDS = 45  # any single <p> or <li>
MAX_SLIDES = 12


class DeckParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.slides = []
        self.depth = 0
        self.slide_depth = None
        self.prose_depth = None
        self.prose_buf = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = set((attrs.get("class") or "").split())
        if tag in {"br", "img", "meta", "link", "input", "hr", "path", "line", "circle", "rect", "polyline", "use"}:
            # Void (or usually self-closed) elements don't change depth
            if self.slide_depth is not None and classes & VISUAL_CLASSES:
                self.slides[-1]["visual"] = True
            return
        self.depth += 1
        if tag == "section" and "slide" in classes:
            self.slide_depth = self.depth
            self.slides.append(
                {"title": "", "visual": False, "prose": [], "kind": "title" if "title" in classes else ""}
            )
        elif self.slide_depth is not None:
            if classes & VISUAL_CLASSES or tag == "svg":
                self.slides[-1]["visual"] = True
            if tag in PROSE_TAGS and self.prose_depth is None:
                self.prose_depth = self.depth
                self.prose_buf = []
            if tag in {"h1", "h2"}:
                self.slides[-1]["_in_title"] = True

    def handle_endtag(self, tag):
        if tag in {"br", "img", "meta", "link", "input", "hr", "path", "line", "circle", "rect", "polyline", "use"}:
            return
        if self.prose_depth == self.depth:
            self.slides[-1]["prose"].append(" ".join(self.prose_buf))
            self.prose_depth = None
        if self.slide_depth == self.depth:
            self.slide_depth = None
        if self.slide_depth is not None and tag in {"h1", "h2"}:
            self.slides[-1]["_in_title"] = False
        self.depth -= 1

    def handle_data(self, data):
        if self.slide_depth is None:
            return
        if self.slides[-1].get("_in_title") and not self.slides[-1]["title"]:
            self.slides[-1]["title"] = data.strip()
        if self.prose_depth is not None:
            self.prose_buf.append(data)


def words(text):
    return len(re.findall(r"\S+", text))


def main(path):
    parser = DeckParser()
    with open(path, encoding="utf-8") as f:
        html = f.read()
    parser.feed(html)
    problems = []
    if "<!-- SLIDES -->" in html or "{{TITLE}}" in html:
        problems.append("template placeholders were not replaced")
    if not parser.slides:
        problems.append("no <section class=\"slide\"> elements found")
    if len(parser.slides) > MAX_SLIDES:
        problems.append(f"{len(parser.slides)} slides; the limit is {MAX_SLIDES}")
    for number, slide in enumerate(parser.slides, 1):
        label = f"slide {number} ({slide['title'][:50] or 'untitled'})"
        if number > 1 and not slide["visual"]:
            problems.append(f"{label}: no diagram or visual component")
        total = sum(words(p) for p in slide["prose"])
        if total > MAX_PROSE_WORDS:
            problems.append(f"{label}: {total} words of prose (max {MAX_PROSE_WORDS})")
        for p in slide["prose"]:
            if words(p) > MAX_PARAGRAPH_WORDS:
                problems.append(f"{label}: a paragraph/bullet has {words(p)} words (max {MAX_PARAGRAPH_WORDS})")
    for problem in problems:
        print(f"FAIL {problem}")
    print(f"{len(parser.slides)} slides checked, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
