#!/usr/bin/env bash
# Publish a PR deck to the GitHub Pages deck repo and post its slides to the PR.
# Usage: post_slides.sh <pr> <deck-standalone.html> <png-dir> [--repo owner/repo] [--deck-repo owner/name] [--dry-run]
#
# The deck (as index.html) and slide images go in one commit to the deck repo
# ($PR_DECK_REPO, default OpenC3/pr-decks) under <owner>/<repo>/pr-<n>/<head-sha>/,
# which GitHub Pages serves. The PR gets one comment with each slide as a
# light/dark <picture> that links to the interactive deck at that slide. Images
# are linked by commit SHA so old comments keep theirs. The comment starts with
# a marker, so a later run updates it instead of adding another.
#
# Set PR_DECK_TOKEN when the default gh token can't push to the deck repo (CI).
# --dry-run prints the comment body and pushes nothing.
set -euo pipefail

PR="${1:?pr number required}"
DECK="${2:?standalone deck required}"
PNG="${3:?png directory required}"
shift 3
REPO=""
DECK_REPO="${PR_DECK_REPO:-OpenC3/pr-decks}"
DRY_RUN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --deck-repo) DECK_REPO="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" ]] || REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
MARKER="<!-- pr-deck -->"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Calls to the deck repo use PR_DECK_TOKEN when set
deck_api() {
  if [[ -n "${PR_DECK_TOKEN:-}" ]]; then GH_TOKEN="$PR_DECK_TOKEN" gh api "$@"; else gh api "$@"; fi
}

HEAD_SHA="$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid)"
DIR="$REPO/pr-$PR/${HEAD_SHA:0:12}"
OWNER="${DECK_REPO%%/*}"
PAGES_URL="https://$(tr '[:upper:]' '[:lower:]' <<< "$OWNER").github.io/${DECK_REPO#*/}/$DIR/"

if [[ -n "$DRY_RUN" ]]; then
  ASSET_SHA="DRY_RUN_SHA"
else
  # Upload every file as a blob once, then commit; retry the commit if another
  # run moved main in the meantime
  : > "$WORK/entries"
  for file in "$DECK" "$PNG"/*.png; do
    name="$(basename "$file")"
    [[ "$file" == "$DECK" ]] && name="index.html"
    python3 -I -c 'import base64,json,sys; json.dump({"content": base64.b64encode(open(sys.argv[1],"rb").read()).decode(), "encoding": "base64"}, sys.stdout)' "$file" > "$WORK/blob.json"
    sha="$(deck_api "repos/$DECK_REPO/git/blobs" --input "$WORK/blob.json" --jq .sha)"
    printf '%s/%s\t%s\n' "$DIR" "$name" "$sha" >> "$WORK/entries"
  done
  for attempt in 1 2 3; do
    PARENT="$(deck_api "repos/$DECK_REPO/git/ref/heads/main" --jq .object.sha)"
    BASE_TREE="$(deck_api "repos/$DECK_REPO/git/commits/$PARENT" --jq .tree.sha)"
    python3 -I - "$WORK/entries" "$BASE_TREE" > "$WORK/tree.json" <<'PY'
import json, sys
entries, base_tree = sys.argv[1:3]
tree = [{"path": p, "mode": "100644", "type": "blob", "sha": s} for p, s in (line.rstrip("\n").split("\t") for line in open(entries))]
json.dump({"base_tree": base_tree, "tree": tree}, sys.stdout)
PY
    TREE="$(deck_api "repos/$DECK_REPO/git/trees" --input "$WORK/tree.json" --jq .sha)"
    python3 -I -c 'import json,sys; tree,parent,msg=sys.argv[1:4]; json.dump({"message": msg, "tree": tree, "parents": [parent]}, sys.stdout)' \
      "$TREE" "$PARENT" "Deck for $REPO#$PR at ${HEAD_SHA:0:7}" > "$WORK/commit.json"
    ASSET_SHA="$(deck_api "repos/$DECK_REPO/git/commits" --input "$WORK/commit.json" --jq .sha)"
    if deck_api -X PATCH "repos/$DECK_REPO/git/refs/heads/main" -f sha="$ASSET_SHA" >/dev/null 2>&1; then break; fi
    [[ $attempt -lt 3 ]] || { echo "could not update $DECK_REPO main" >&2; exit 1; }
    sleep $((attempt * 2))
  done
fi

# One linked <picture> per slide, with alt text from each slide's data-title
python3 -I - "$DECK" "$PNG" "$DECK_REPO" "$ASSET_SHA" "$DIR" "$HEAD_SHA" "$MARKER" "$PAGES_URL" > "$WORK/body.md" <<'PY'
import html, os, re, sys
deck, png_dir, deck_repo, asset_sha, prefix, head_sha, marker, pages_url = sys.argv[1:9]
titles = re.findall(r'<section class="slide[^"]*"[^>]*data-title="([^"]*)"', open(deck, encoding="utf-8").read())
count = len([n for n in os.listdir(png_dir) if re.fullmatch(r"slide-\d+-light\.png", n)])
base = f"https://raw.githubusercontent.com/{deck_repo}/{asset_sha}/{prefix}"
lines = [
    marker,
    f"### PR deck · {count} slides",
    f"<sub>AI-generated from {head_sha[:7]} with the pr-deck skill. "
    f"Click a slide, or <a href=\"{pages_url}\">open the deck</a>, to present it full screen.</sub>",
    "",
]
for n in range(1, count + 1):
    title = html.unescape(titles[n - 1]) if n - 1 < len(titles) else f"Slide {n}"
    alt = html.escape(f"Slide {n} of {count}: {title}", quote=True)
    # The <picture> must be its own unindented HTML block (blank line before, one
    # line) or GitHub's Markdown parser splits it and drops the dark <source>
    lines += [
        f"**{n}. {html.escape(title)}**",
        "",
        f'<a href="{pages_url}#{n}"><picture>'
        f'<source media="(prefers-color-scheme: dark)" srcset="{base}/slide-{n}-dark.png">'
        f'<img alt="{alt}" src="{base}/slide-{n}-light.png"></picture></a>',
        "",
    ]
print("\n".join(lines))
PY

if [[ -n "$DRY_RUN" ]]; then
  cat "$WORK/body.md"
  exit 0
fi

EXISTING="$(gh api "repos/$REPO/issues/$PR/comments" --paginate \
  --jq ".[] | select(.body | startswith(\"$MARKER\")) | .id" | tail -1)"
if [[ -n "$EXISTING" ]]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$EXISTING" -F body=@"$WORK/body.md" --jq .html_url
else
  gh api "repos/$REPO/issues/$PR/comments" -F body=@"$WORK/body.md" --jq .html_url
fi
echo "Deck: $PAGES_URL"
