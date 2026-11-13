---
name: pr-deck
description: Summarize a GitHub pull request as a diagram-first slide deck (a single self-contained HTML page). Use when asked to present, explain, walk through, or summarize a PR as slides or a presentation. Works locally (publishes as an Artifact) and headless in CI (writes an HTML file for a GitHub Action to upload).
argument-hint: "<pr-number-or-url> [--repo owner/repo] [--out path/to/deck.html] [--post]"
---

# PR deck

Turn a pull request into a short slide deck a reviewer can click through in a few
minutes. Every slide explains the change with a diagram. Text labels the diagram;
it never replaces it.

## Inputs

`$ARGUMENTS`:
- A PR number or URL (required).
- `--repo owner/repo` when the PR isn't in the current repo.
- `--out path` writes the finished standalone HTML there. This is CI mode: never
  ask questions, never use the Artifact tool, and finish by printing the path.

## 1. Gather

Use the scratchpad directory (or `$RUNNER_TEMP` in CI) as `$WORK`:

```bash
.claude/skills/pr-deck/gather.sh <pr> "$WORK" [owner/repo]
```

This writes `meta.json`, `files.tsv`, `commits.md`, `src.diff`, `test.diff`,
`full.diff`, `checks.txt` and `discussion.md`.

## 2. Understand the change

- Read **all** of `src.diff`. When a change mirrors across languages (COSMOS keeps
  Ruby in `openc3/lib` and Python in `openc3/python` in parity), read one side in
  full and skim the other for differences. Any difference is worth a slide.
- Read `commits.md`: commit bodies are often the clearest statement of intent.
- Skim `test.diff` to learn what's verified, not to summarize the tests.
- For each failing check in `checks.txt`, find the reason (`gh run view <id>
  --log-failed`, or check-run annotations via `gh api`). Say whether it's caused by
  this PR. When you don't know, say "not inspected"; don't guess.
- Open surrounding source in the repo whenever the diff alone doesn't explain the
  old behavior. You need to know what happened *before* to draw before/after.

Every claim in the deck must trace to the diff, the commits, or the CI output.
Use real identifiers (method names, keys, error messages). When a diagram needs
example data the PR doesn't provide, add the `illustrative` class to its caption.

## 3. Plan the story

**Exactly 6 slides or fewer** (`check_deck.py` enforces it). Small PRs may need 3.
Group related changes onto one slide rather than dropping them. Use this arc:

1. **Overview**: one-line thesis as the `h1`, a 1–2 sentence `lede` saying what
   changed and why, PR number, author, branches, a `stats` row (+/−, files,
   commits) and a `sizebar` splitting lines by area (source vs. tests, per
   language or service).
2. **Before**: a `flow` of the existing mechanism the PR touches, plus a `matrix`
   of area → before → after with one row per theme.
3. **The model**: the rule the change follows (e.g. "reads resolve one, writes fan
   out") as `lanes`, each with a small SVG glyph, a sentence, and the affected APIs.
   If there's no unifying rule, use this slide for the largest theme instead.
4. **Theme slides (4–5)**: the most important mechanisms, two per slide in `.cols`
   if needed. Pick the shape that matches the mechanism:
   - identity or key changes → `compare` with the actual keys in `.node.code`
   - one input becoming many → `fan`
   - ordering, validation, or a protocol → `phases` or a vertical `flow`
   - anything about time → an SVG timeline
   - refactors → a call graph (`flow`/`fan` of old and new helpers)
5. **Verify and review (last)**: tests added, what's unchecked, each failing CI
   check with its cause, then `checks` cards for behavior changes, risks,
   performance, and anything that must be fixed before merge. Reviewers need this
   slide most.

## 4. Writing rules

- Headline (`h2`) is an assertion of 10 words or fewer: "Writes now reach every
  packet", not "Writes".
- Every slide carries at least one diagram; text explains it, never replaces it.
- A slide may have a `p.lede` of 1–2 sentences, short `p.note` captions under
  diagrams, and a `ul.bullets` list of up to 5 items of 15 words or fewer.
  Keep any single paragraph or bullet under 45 words and the slide under 110 words
  of prose. Use the text for *why* and consequences; let the diagram show *what*.
- When you want a long list, you probably want a `matrix`, `checks`, or `chips`.
- Code goes in `.snippet` only when the exact line *is* the change, 6 lines max.
  Mark lines with `<span class="a">` (added), `<span class="d">` (removed).
- Don't narrate the PR description back. Show the mechanism.

## 5. Build

Write only the `<section class="slide">` elements to `$WORK/slides.html`, then:

```bash
.claude/skills/pr-deck/build.sh "$WORK/slides.html" "PR #<n> <short name>" "$WORK/deck.html"            # Artifact fragment
.claude/skills/pr-deck/build.sh "$WORK/slides.html" "PR #<n> <short name>" "<out>.html" --standalone     # CI / browser
```

`build.sh` runs `check_deck.py`, which fails when a content slide has no visual
or prose runs long. Fix every failure and rebuild.

The title is a name like `PR #4052 LATEST Handling`; no explanation after a colon.

### Components (all styled in `template.html`)

```html
<section class="slide" data-title="Nav bar title (optional)">
  <div class="frame">
    <div class="head">
      <div class="eyebrow">Streaming</div>
      <h2>Assertion headline</h2>
      <p class="lede">One sentence.</p>
    </div>
    <!-- one or two visuals -->
  </div>
</section>
```

| Component | Markup |
|---|---|
| Node | `<div class="node [code|accent|latest|ok|bad|ghost|strike]">Label<small>sub</small></div>` |
| Flow | `<div class="flow [vertical|keep]">node <span class="arrow [accent|bad]" data-label="opt"></span> node …</div>` (stacks vertically on phones unless `keep`) |
| Fan-out | `<div class="fan [accent]"><div class="node">src</div><div class="fan-out">node node node</div></div>` |
| Before/after | `<div class="compare"><div class="side before"><div class="side-label">Before</div>…</div><div class="side after"><div class="side-label">After</div>…</div></div>` |
| Phases | `<div class="phases"><div class="phase [ok|bad]"><h3>Step</h3><span class="note">…</span></div>…</div>` (numbered; real sequences only) |
| Lanes | `<div class="lanes"><div class="lane"><svg …></svg><h3>Rule</h3><div class="chips">…</div></div>…</div>` |
| Matrix | `<div class="table-wrap"><table class="matrix">` with `<td class="was">` / `<td class="now">` |
| Stats | `<div class="stats"><div class="stat"><b class="add">+1,929</b><span>lines added</span></div>…</div>` |
| Size bar | `<div class="sizebar"><div class="track"><div class="seg c1" style="flex:599"></div>…</div><div class="legend"><span><i class="c1"></i>Ruby src 599</span>…</div></div>` |
| Chips | `<div class="chips"><span class="chip [accent|add|del|warn|latest|rb|py]">text</span></div>` |
| Review cards | `<div class="checks"><div class="check"><span class="chip warn tag">Risk</span><h3>…</h3><span class="note">…</span></div></div>` |
| Snippet | `<pre class="snippet"><span class="d">- old</span>\n<span class="a">+ new</span></pre>` |
| Callout | `<div class="callout [bad|ok]">…</div>` |
| Bullets | `<ul class="bullets"><li>…</li></ul>` (5 items max) |
| Layout | `.cols` (2 columns, stacks on phones), `.row`, `.stack` |

**Inline SVG** for timelines and custom shapes: wrap in `<div class="diagram">`,
give it a `viewBox` with room for outer labels, and color only with the `sv-*`
classes (`sv-line`, `sv-accent`, `sv-amber`, `sv-bad`, `sv-ok`, `sv-dash`,
`sv-fill-*`, `sv-text`, `sv-label`, `sv-text-accent|amber|bad`) so it follows the
light and dark themes. Never hard-code colors.

## 6. Render slide images

```bash
.claude/skills/pr-deck/render.sh "$WORK/deck-standalone.html" "$WORK/png"
```

Headless Chrome writes `slide-<n>-light.png` and `slide-<n>-dark.png` at
1280×800 @2x. Capture mode hides the nav bar and shrinks any slide taller than
the window so nothing is cut off. Look at each image once and fix overlaps
(SVG labels crossing lines, orphaned cards) before delivering.

## 7. Deliver

- **Interactive session**: publish `$WORK/deck.html` with the Artifact tool
  (icon `slides`, a one-sentence description), then reply with the link and 2 to 3
  lines on what the deck covers and anything that must be fixed before merge.
- **PR comment** (when asked, or `--post` in CI): render the images (step 6), then

  ```bash
  .claude/skills/pr-deck/post_slides.sh <pr> "$WORK/deck-standalone.html" "$WORK/png" [--repo owner/repo] [--deck-repo owner/name] [--dry-run]
  ```

  It commits the deck (as `index.html`) and the PNGs to the GitHub Pages deck repo
  (`$PR_DECK_REPO`, default `OpenC3/pr-decks`) under
  `<owner>/<repo>/pr-<n>/<head-sha>/`, so one site serves decks for every source
  repo. Then it posts a single PR comment showing each slide as a light/dark
  `<picture>` that links to the interactive deck at that slide; later runs update
  that comment. Create the deck repo once with `create_deck_repo.sh`. This writes
  to GitHub, so confirm with the user first in an interactive session. Use
  `--dry-run` to preview the comment body.
- **CI (`--out`)**: write the standalone build to the `--out` path and print it.
  With `--post`, also render and post the images as above
  (see `github-action.example.yml`).
