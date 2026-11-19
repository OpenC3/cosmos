#!/usr/bin/env bash
# Collect everything needed to summarize a PR into one directory.
# Usage: gather.sh <pr-number-or-url> <out-dir> [owner/repo]
set -euo pipefail

PR="${1:?pr number or url required}"
OUT="${2:?output directory required}"
REPO_ARGS=()
if [[ -n "${3:-}" ]]; then REPO_ARGS=(--repo "$3"); fi

mkdir -p "$OUT"

gh pr view "$PR" "${REPO_ARGS[@]}" \
  --json number,title,body,author,state,isDraft,baseRefName,headRefName,url,additions,deletions,changedFiles,labels,commits,files,reviewDecision,createdAt,updatedAt \
  > "$OUT/meta.json"

# Per-file size: additions, deletions, path
gh pr view "$PR" "${REPO_ARGS[@]}" --json files \
  --jq '.files[] | "\(.additions)\t\(.deletions)\t\(.changeType)\t\(.path)"' > "$OUT/files.tsv"

# Commit headlines and bodies, oldest first (the author's own narrative of the change)
gh pr view "$PR" "${REPO_ARGS[@]}" --json commits \
  --jq '.commits[] | "## \(.messageHeadline)\n\(.messageBody)\n"' > "$OUT/commits.md"

# Full diff, then split into source and test portions
gh pr diff "$PR" "${REPO_ARGS[@]}" > "$OUT/full.diff"
awk -v src="$OUT/src.diff" -v tst="$OUT/test.diff" '
  /^diff --git/ { is_test = ($0 ~ /(\/spec\/|\/test\/|_spec\.|test_|\.test\.|\.spec\.)/) }
  { if (is_test) print > tst; else print > src }
' "$OUT/full.diff"
touch "$OUT/src.diff" "$OUT/test.diff"

# CI status and review discussion (both optional; may be empty on new PRs)
gh pr checks "$PR" "${REPO_ARGS[@]}" > "$OUT/checks.txt" 2>/dev/null || true
gh pr view "$PR" "${REPO_ARGS[@]}" --json reviews,comments \
  --jq '(.reviews[] | "### review by \(.author.login) (\(.state))\n\(.body)\n"), (.comments[] | "### comment by \(.author.login)\n\(.body)\n")' \
  > "$OUT/discussion.md" 2>/dev/null || true

echo "Wrote $(ls "$OUT" | wc -l | tr -d ' ') files to $OUT"
wc -l "$OUT/src.diff" "$OUT/test.diff" | sed 's/^/  /'
