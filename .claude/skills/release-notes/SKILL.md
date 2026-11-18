---
name: release-notes
description: Use when writing or updating GitHub release notes for a COSMOS Core (OpenC3/cosmos) or COSMOS Enterprise (OpenC3/cosmos-enterprise) release, or when asked to replace the "Generate release notes" button output with curated notes.
argument-hint: "<version, e.g. 7.6.0> [previous version] [core|enterprise]"
---

# COSMOS release notes

Core and Enterprise are released separately, and Enterprise builds on Core. Write
the Core notes first, and get them approved. Write the Enterprise notes in a
separate step, starting from the approved Core notes.

The output is a markdown file for each release. Publishing it is a separate step
that needs the user's go-ahead.

## Inputs

From `$ARGUMENTS` or the user:

- **Version**: e.g. `7.6.0`. The tag is `v7.6.0`.
- **Previous version**: if not given, use the newest published release in
  `gh release list -R OpenC3/cosmos` that is older than the requested version
  (when updating the notes for an existing v7.6.0, that is the release before
  v7.6.0, not v7.6.0 itself). If that release's body starts with
  `# Incomplete Release`, use the release before it (7.5.1 was compared against
  7.4.1, not 7.5.0). State which previous version you used.
- **Target**: check each repo separately before collecting from it. If the new
  tag doesn't exist in that repo yet (`gh api repos/OpenC3/<repo>/git/ref/tags/v7.6.0`
  404s), pass `--target main` to the script for that repo. Core may be tagged
  while Enterprise is not.

Work in a scratch directory (`$OUT` below), not in the repo.

## Step 1: Core notes

### Collect

```bash
python3 .claude/skills/release-notes/scripts/collect_prs.py \
  --repo OpenC3/cosmos --tag v7.6.0 --previous v7.5.1 --out "$OUT" [--target main]
```

This writes:

- `$OUT/cosmos-generated.md`: exactly what the GitHub "Generate release notes"
  button produces (What's Changed, New Contributors, Full Changelog).
- `$OUT/cosmos-prs.md`: every PR with its title, author, and its `RELEASE NOTES:`
  section from the PR template. Older PRs have no such section, so the start of
  the body is included instead. When a body ends in `...` and the PR might be
  breaking or a headline, read all of it: `gh pr view N -R OpenC3/cosmos --json body --jq .body`.

Also read the last published Core release
(`gh release view v7.5.1 -R OpenC3/cosmos --json body --jq .body`) for the
standing Migration Notes text and the tone of the intro.

### Sort every PR

Go through `cosmos-prs.md` and put each PR into exactly one bucket:

| Bucket | What goes there |
| ------ | --------------- |
| Breaking | Users must act on upgrade: a removed or renamed API or setting, a new minimum version, a file users keep a copy of (`compose.yaml`, `.env`, `openc3-redis/users.acl`) that changed in a way they must merge. A `RELEASE NOTES:` section that tells users to do something always lands here. A feature that changes a default goes in its own section (often Performance), and also gets a short Breaking bullet saying how to get the old behavior. |
| 🚀 Performance and scalability | Throughput, memory, latency, large-target scaling |
| 🛠 Enhancements | New features and user-visible improvements |
| 🔒 Security | Security fixes, CVE fixes, and dependency or base-image bumps. Group the version bumps into one line with versions. |
| 📚 Documentation | New or substantially changed docs |
| 🪲 Bug Fixes | User-visible fixes |
| Omit | CI, tests, refactors, release tooling, lint rules, license text changes, and "AI review fixes for #N" PRs. They still appear in What's Changed. |

`RELEASE NOTES: None` means omit. When a PR has a written `RELEASE NOTES:`
section, base the bullet on it. Otherwise write the bullet from the title and
body. Only state facts that the PR says. Don't invent numbers or results.

Several PRs that fix the same thing become one bullet with all their numbers:
`(#4106, #4109, #4166)`. A human follow-up PR to another PR in the release
("review follow-ups", "fix X again") adds its number to that PR's bullet. A
dependency bumped more than once gets one entry with the final version and all
the PR numbers: `Traefik 3.7.15 (#4058, #4093)`.

### Write the Core notes

Save to `$OUT/core-v7.6.0.md`. This is the document, top to bottom. Sections
other than the title, intro, Migration Notes, and What's Changed are left out
when empty.

```markdown
# OpenC3 COSMOS Core 7.6.0 - <3-8 word theme of the release>

<1-3 short paragraphs on the headline changes, in plain language, citing their
PR numbers inline: "New data flow metrics (#3903) track throughput...">

## Migration Notes
<The standing compose.override.yaml / .env.local paragraph copied from the previous
release, with BOTH cosmos-project links changed to the new tag:
https://github.com/OpenC3/cosmos-project/blob/v7.6.0/compose.yaml and .../v7.6.0/.env>

### 🛑 Breaking Changes from 6.x
<Copied unchanged from the previous release>

### 🛑 Breaking Changes from 7.5.1
- <Area>: <what changed and exactly what the user must do> (#N)

See the [COSMOS 7.0.0](https://github.com/OpenC3/cosmos/releases/tag/v7.0.0) release notes for all the amazing new features in COSMOS 7!

## 🚀 Performance and scalability
- <Area>: <user-visible effect> (#N)

## 🛠 Enhancements
- <Area>: <user-visible effect> (#N)

## 🔒 Security
- <fix> (#N)
- Traefik 3.7.16 (#N), Versitygw 1.9.1 (#N), ... plus general dependency updates (#N, #N)

## 📚 Documentation
- <what was documented> (#N)

## 🪲 Bug Fixes
### Tools
- <Tool name>: <what now works> (#N)

### <Other group, e.g. Interfaces and microservices / Plugins, config and build / Streaming, topics and logging / Scripting and API>
- <what now works> (#N)

<The contents of cosmos-generated.md, unchanged: ## What's Changed, ## New Contributors (if present), **Full Changelog**>
```

Bullet rules:

- Each bullet is one line of roughly 8 to 25 words. Breaking bullets can run to
  two sentences, because they must say what to do. Details stay in the PR,
  which the number links to. Match these published bullets:
  - `- Faster limits group enable/disable (#4112): a 70k-item group now takes about 1.5s instead of about 45s`
  - `- Queued Redis writes by default: interfaces now batch Redis writes every 0.1s, which greatly reduces Redis load at high packet rates (#4015)`
  - `- Table Manager: edits are kept when using Save As (#3960)`
- Every bullet in the curated sections and every headline in the intro ends with
  its Core PR number(s). The Enterprise step depends on this.
- Bullets start with `- `, then the area (tool, API, subsystem) and a colon when
  that helps: `- Packet Viewer: fuzzy search that tolerates typos (#3941)`.
- Describe the effect a user sees, not the implementation.
- Use `### ` sub-groups under Bug Fixes when there are more than about 8 fixes.
  Otherwise use a flat list.
- Core notes contain only Core PRs. Enterprise-only changes go in the
  Enterprise notes, never as `[Enterprise]` items in Core.
- Breaking bullets go under "Breaking Changes from <previous>" and nowhere
  else, with no other heading names. The same PR can also have a feature bullet
  in another section, as described for changed defaults.

Show the user the file path and a summary: the theme, the breaking changes, and
which PRs you omitted that might matter. Wait for their edits or approval.

## Step 2: Enterprise notes

Start this step only after the Core notes are approved (or published). If the Core
release is published, use its body as the source. It may have hand edits that
your local file doesn't.

### Build the base from Core

```bash
gh release view v7.6.0 -R OpenC3/cosmos --json body --jq .body > "$OUT/core-final.md"   # or use the approved local file
python3 .claude/skills/release-notes/scripts/enterprise_base.py "$OUT/core-final.md" > "$OUT/ent-base.md"
```

The script removes every Core PR number such as `(#4015)` from the curated
sections, because those numbers would link to the wrong PRs in the Enterprise
repo. It also changes the title to "OpenC3 COSMOS Enterprise", and renames the
headings to "What's Changed in Core", "New Core Contributors", and "Full Core
Changelog". If it prints a warning about leftover refs, fix them by hand.

### Collect Enterprise PRs

Check whether the tag exists in `OpenC3/cosmos-enterprise` first (see **Target**
above). Don't reuse the Core answer.

```bash
python3 .claude/skills/release-notes/scripts/collect_prs.py \
  --repo OpenC3/cosmos-enterprise --tag v7.6.0 --previous v7.5.1 --out "$OUT" [--target main]
```

Sort these PRs into buckets the same way as Core. Watch for Enterprise-only
breaking changes, such as a new minimum Python version or Helm value renames.

### Write the Enterprise notes

Save to `$OUT/ent-v7.6.0.md`, starting from `ent-base.md`:

- **Intro**: keep the Core paragraphs. Add a paragraph for Enterprise headlines,
  with Enterprise PR numbers.
- **Breaking Changes from 7.5.1**: Enterprise items first, then the Core items.
  Add the heading if Core had none.
- **Each curated section**: Enterprise bullets first, with Enterprise PR numbers
  `(#820)`. Then the Core bullets from the base, without numbers. Under Bug Fixes,
  put each Enterprise fix in the matching `###` group, or in a new group if none fits.
- **Never put a number on a Core bullet**, and never drop the number from an
  Enterprise bullet.
- **Bottom**, in this order:
  1. `## What's Changed in Core`: from the base, unchanged.
  2. `## What's Changed in Enterprise`: the What's Changed list from
     `cosmos-enterprise-generated.md`.
  3. `## New Core Contributors` and `## New Enterprise Contributors`: only if
     either has entries.
  4. The two changelog lines:

```markdown
**Full Core Changelog**: https://github.com/OpenC3/cosmos/compare/v7.5.1...v7.6.0
**Full Enterprise Changelog**: https://github.com/OpenC3/cosmos-enterprise/compare/v7.5.1...v7.6.0
```

Show the user the path and a summary, and wait for approval.

## Publishing

Only publish after the user says to, and confirm which repo. For each repo:

```bash
gh release view v7.6.0 -R OpenC3/<repo> >/dev/null 2>&1 \
  && gh release edit v7.6.0 -R OpenC3/<repo> --notes-file <file> \
  || gh release create v7.6.0 -R OpenC3/<repo> --draft --verify-tag --title "v7.6.0" --notes-file <file>
```

Create a new release as a draft, so the user publishes it.

## Common mistakes

| Mistake | Fix |
| ------- | --- |
| Copying the section layout of an older release | Use the template above. It matches the 7.5.1 notes. |
| Bullets without PR numbers in Core | Every Core curated bullet ends with `(#N)`. |
| Core PR numbers left in Enterprise | Run `enterprise_base.py`. Never hand-copy Core bullets. |
| Rewriting the Core content for Enterprise | Keep the Core text. Only add Enterprise items. |
| A breaking change listed as an enhancement (a new minimum Python, a changed default) | Put it under Breaking Changes from the previous version. |
| Migration links still pointing at the previous tag | Change both cosmos-project links to the new tag. |
| Numbers or results not in any PR | Leave them out. |
| Bullets that explain every option, env var, and default | One line. The PR has the details. |
| A changed default only under Breaking | Feature bullet in its section, plus a short opt-out bullet under Breaking. |
