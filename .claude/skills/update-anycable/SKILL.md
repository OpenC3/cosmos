---
name: update-anycable
description: Rebuild the bundled anycable-go binaries (openc3-anycable/anycable-go-linux-amd64 and -arm64). Syncs a local anycable checkout with upstream, bumps the Go toolchain and module dependencies when a newer Go patch release is out, builds with openc3-anycable/build-anycable.sh, and opens a COSMOS PR with the new binaries. Optionally opens a dependency-bump PR against anycable/anycable from the user's fork. Use when asked to update or rebuild anycable or to pick up Go security releases.
argument-hint: "[go-minor, e.g. 1.26] [--force-build]"
---

# Update the anycable-go binaries

COSMOS ships prebuilt `anycable-go` binaries in `openc3-anycable/` (copied into
the API images by their Dockerfiles). We build them ourselves
so they pick up Go security releases faster than upstream anycable does.

## Inputs

`$ARGUMENTS` can include:
- A Go minor line such as `1.26`. If it's missing, read the `toolchain` line in
  the anycable `go.mod` and use its major.minor.
- `--force-build` rebuilds and opens the COSMOS PR even when the toolchain is
  already current (for example, after upstream released a new anycable version).

## Requirements

- `go` (any recent version; Go downloads the toolchain go.mod asks for)
- `gh`, authenticated (`gh auth status`)
- An anycable checkout at `$ANYCABLE_DIR`, defaulting to `../anycable` relative
  to the cosmos repo root

The shell's cwd resets to the cosmos repo between commands, so use
`git -C "$ANYCABLE_DIR"` or absolute paths.

## Steps

### 1. Ask about the upstream PR

Ask the user (AskUserQuestion) whether to also open a dependency-bump PR against
`anycable/anycable`. Opening it needs a GitHub fork of anycable under their
account. Recommend "yes" only if nobody else on the team usually does it, so
upstream doesn't get duplicate Go-bump PRs. Remember the answer as `UPSTREAM_PR`.

### 2. Find or create the anycable checkout

```bash
ANYCABLE_DIR="${ANYCABLE_DIR:-$(cd .. && pwd)/anycable}"
GH_USER=$(gh api user -q .login)
```

If `$ANYCABLE_DIR` doesn't exist:
- `UPSTREAM_PR` = yes: `cd "$(dirname "$ANYCABLE_DIR")" && gh repo fork anycable/anycable --clone`.
  This forks under `$GH_USER` (or reuses an existing fork), clones it into
  `./anycable`, and sets `origin` = fork and `upstream` = anycable/anycable. If
  `$ANYCABLE_DIR`'s basename isn't `anycable`, rename the clone to match.
- `UPSTREAM_PR` = no: `git clone https://github.com/anycable/anycable.git "$ANYCABLE_DIR"`.

Then work out the remote names by URL rather than assuming them:

```bash
git -C "$ANYCABLE_DIR" remote -v
```

- `UPSTREAM` = the remote whose URL is `github.com/anycable/anycable` (or `.git`)
- `FORK` = the remote whose URL is `github.com/$GH_USER/anycable`, if any

If there's no `UPSTREAM` remote (for example, a clone of the fork alone), add
one with `git -C "$ANYCABLE_DIR" remote add upstream https://github.com/anycable/anycable.git`
and use `UPSTREAM=upstream`.

If `UPSTREAM_PR` = yes but there's no `FORK` remote, run
`gh repo fork anycable/anycable --remote --remote-name fork` from inside the
checkout and use `FORK=fork`. If the checkout has local commits or a dirty tree
(`git status --short`), stop and ask the user before continuing. Untracked
`dist/` or build scripts are fine to ignore.

### 3. Sync with upstream

```bash
git -C "$ANYCABLE_DIR" fetch "$UPSTREAM" --tags
git -C "$ANYCABLE_DIR" switch main
git -C "$ANYCABLE_DIR" merge --ff-only "$UPSTREAM/main"
```

If the fast-forward fails, local `main` has diverged from upstream. Stop and
ask the user. Don't rebase, reset, or force-push. Don't push `main` to the
fork. Only the `go/$NEW` branch in step 9 goes there.

### 4. Check whether Go is out of date

Find the newest patch release in the minor line, using the release page as the
source of truth:

```bash
curl -s https://go.dev/doc/devel/release | grep -oE 'go1\.26\.[0-9]+' | sort -uV | tail -1
grep '^toolchain' "$ANYCABLE_DIR/go.mod"
```

(Replace `1\.26` with the requested minor line.) `https://go.dev/dl/?mode=json`
makes a good cross-check. If a newer minor line exists (for example `go1.27.x`),
mention it to the user, but stay on the current line unless they ask to move.

If the toolchain is already current and `--force-build` wasn't given, report
that and stop.

### 5. Bump the toolchain and dependencies on a branch

Name the branch `go/<version>`. Update **both** modules, the root module and
`etc/benchi`:

```bash
NEW=1.26.9   # newest patch from step 4
cd "$ANYCABLE_DIR"
git switch -c go/$NEW
go mod edit -toolchain=go$NEW && go get -u ./... && go mod tidy
(cd etc/benchi && go mod edit -toolchain=go$NEW && go get -u ./... && go mod tidy)
git diff --stat              # expect only go.mod/go.sum in both modules
```

Leave the `go 1.26.0` directive alone. Only `toolchain` changes.

### 6. Verify

```bash
go version                   # must report the new toolchain
go test ./...                # must pass
(cd etc/benchi && go build ./...)
go vet ./...
```

`go vet` already reports three `copies lock value` warnings on upstream main
(`redis/config_test.go`, `config/config.go`), and they're expected. Flag any
**new** vet output to the user. If tests fail, stop and report the output
instead of building.

### 7. Commit in anycable

Commit **before** building so the SHA stamped into the binaries is the
dependency-bump commit:

```bash
git -C "$ANYCABLE_DIR" add go.mod go.sum etc/benchi/go.mod etc/benchi/go.sum
git -C "$ANYCABLE_DIR" commit -m "Bump dependencies including toolchain go$NEW"   # plus attribution footer
```

### 8. Build the binaries into COSMOS

From the cosmos repo root:

```bash
openc3-anycable/build-anycable.sh "$ANYCABLE_DIR"
```

This builds linux/amd64 and linux/arm64 straight into `openc3-anycable/` and prints
`go version` for both, which must show `go$NEW`. Report the new sizes.

### 9. Open the upstream PR (only if `UPSTREAM_PR` = yes)

Before creating the PR, run `gh pr list -R anycable/anycable --author "$GH_USER" --state open`
to look for a dependency PR that's still open. If one exists, ask the user
whether to update it or open a new one. Follow the format of earlier merged
PRs (#334, #339):

```bash
git -C "$ANYCABLE_DIR" push -u "$FORK" go/$NEW
gh pr create -R anycable/anycable --base main --head "$GH_USER:go/$NEW" \
  --title "Bump dependencies including toolchain go$NEW" \
  --body "### What is the purpose of this pull request?

Bump dependencies to close Go CVEs: https://go.dev/doc/devel/release#go1.26.minor

### What changes did you make? (overview)

Just dependency updates"   # plus attribution footer
```

Afterwards, switch the checkout back to `main` (`git -C "$ANYCABLE_DIR" switch main`).
If `UPSTREAM_PR` = no, leave the `go/$NEW` branch local and switch back to `main`.

### 10. Open the COSMOS PR

Work in the cosmos repo root:

```bash
git status --short           # note any unrelated changes; commit only the two binaries
git fetch origin
git switch -c anycable-go$NEW origin/main
git add openc3-anycable/anycable-go-linux-amd64 openc3-anycable/anycable-go-linux-arm64
git commit -m "build(openc3-anycable): update anycable-go binaries to go$NEW"   # plus attribution footer
git push -u origin anycable-go$NEW
gh pr create --base main --head anycable-go$NEW \
  --title "build(openc3-anycable): update anycable-go binaries to go$NEW" \
  --body "Rebuilds the anycable-go linux/amd64 and linux/arm64 binaries with toolchain go$NEW and bumped Go dependencies, picking up the security fixes in https://go.dev/doc/devel/release#go1.26.minor.

Upstream dependency PR: <URL from step 9, or 'none'>"   # plus attribution footer
```

`git switch -c ... origin/main` carries over uncommitted working-tree changes
(the new binaries included). If the switch fails because of conflicting local
changes, stop and ask the user. Don't stash or discard their work.

If the pre-commit hook fails with `invalid byte sequence in UTF-8`, the
installed `.git/hooks/pre-commit` is an old copy that tries to read the
binaries as text. Run `hooks/install.sh` to install the current hook, which
skips files without a supported extension, then commit again. Don't use `--no-verify`.

Afterwards, switch back to the branch the user started on.

## Report

Tell the user:
- Which anycable checkout was used, and whether it was cloned, forked, or fast-forwarded
- The old and new toolchain versions, plus notable dependency bumps
- Test and vet results
- The new binary sizes
- The upstream anycable PR URL (or that it was skipped) and the COSMOS PR URL
