---
name: parity-review
description: Compare Ruby and Python twins of the COSMOS scripting API (api/ and script/) for signature and behavior drift, check open PRs for existing fixes, and publish a parity report.
argument-hint: "[api|script ...] [--prs 1234,5678]"
disable-model-invocation: true
---

# Parity review

Users write scripts, targets and microservices in Ruby or Python and expect the
same result from either language. This skill finds **drift**: places where a
Ruby method and its Python twin differ in signature, return value, errors, or
which arguments reach the server. Each finding names the side that is right.

The scripting API is the default scope because it is the surface users call
directly, `scripting-api.md` documents both languages, and the enterprise MCP
server builds tools from the Python signatures. For drift in the internals
(models, topics, microservices), run `/reuse-review python`, which checks
counterparts too.

## 1. Inventory

Run the signature inventory into the scratchpad (`$SCRATCH` is the session
scratchpad directory). With no area it covers both `api` and `script`:

```bash
python3 .claude/skills/parity-review/inventory.py . "$SCRATCH/parity" > "$SCRATCH/parity/inventory.md"
```

To restrict it, append `api` or `script` after `"$SCRATCH/parity"`.

It pairs Ruby and Python definitions by module and class, and lists:

- WHITELIST gaps;
- names that exist on only one side;
- per-method parameter differences: missing parameters, defaults, keyword vs positional.

It already ignores Ruby's `manual:`/`token:` JSON-RPC authorization
parameters.

When it pairs files wrongly (a Ruby module whose Python twin has a different
name), add the pair to `MODULE_ALIASES` or `CLASS_ALIASES` in `inventory.py`
and rerun.

Done when `inventory.md` exists and its counts line is in hand.

## 2. Exclusions

Fetch every open PR that changes a file in scope, by path rather than by title
search (a title search misses PRs like a limits feature that edits
`set_limits`). Run from the repo root:

```bash
python3 .claude/skills/reuse-review/open_prs.py fetch "$SCRATCH/parity/prs" \
  openc3/lib/openc3/api openc3/lib/openc3/script openc3/python/openc3/api openc3/python/openc3/script \
  openc3/lib/openc3/models/cvt_model.rb openc3/python/openc3/models/cvt_model.py
```

It saves `pr<N>.diff` and `pr<N>.md` for each. PRs given with `--prs` that
fall outside these paths: save them with `gh pr diff N`. The sweeps read the
saved files and skip anything they already fix.

## 3. Sweep

Split the Ruby ↔ Python file pairs into three slices of similar weight:

- `cmd`/`tlm`/`limits` + `api_shared` + `commands`/`telemetry`;
- the other `api/` modules + `web_socket_api` + `script.rb` ↔ `__init__.py`/`server_proxy.py`;
- the HTTP-backed `script/` modules + suites.

Spawn three `general-purpose` sub-agents in one message, each given
[BRIEF.md](BRIEF.md) with its placeholders filled. Wait for all three.

## 4. Verify

For every finding:

- Read both sides' cited lines. Keep the finding if the difference is real, and drop it if the code disagrees.
- Mark it **checked** if you read it yourself, or **sweep** if you did not.
- Confirm the PR check with `python3 .claude/skills/reuse-review/open_prs.py grep "$SCRATCH/parity/prs" "<method>"`, and read each matching hunk. Move the finding to **Fixed in open PRs** only when the PR's version of the code no longer has the difference: trace the finding's script call through it. A hunk that changes the cited lines but leaves the difference is not a fix. Otherwise keep the finding and note "conflicts with #N" so the fix lands after it.
- Settle "which side is right" from `docs.openc3.com/docs/guides/scripting-api.md` first, then the server code, then the tests. If none of them decides it, record "unclear".

Done when every finding is marked checked or sweep, and every finding has a side or "unclear".

## 5. Report

Write the report data as `$SCRATCH/parity/data.json`, following the schema in
the comment at the top of [template.html](template.html), then render it:

```bash
python3 .claude/skills/parity-review/render.py "$SCRATCH/parity/data.json" "$SCRATCH/parity/parity-review-<YYYYMMDD>.html"
```

Build `signatures` and `gaps` from `inventory.json` and `inventory.md` with a
short script. Give every row a status: a finding link, "expected", "dismissed:
<reason>", "fixed in #N", or "not reviewed". Code fields are plain text, so the
page escapes them. Prose fields may hold `<code>` and `<strong>`.

- **Findings:** behavior drift, ranked by user impact. Each finding shows the Ruby and Python lines side by side, the side that is right, and a script call that behaves differently.
- **Fixed in open PRs:** drift the sweeps found that an open PR already fixes, so reviewers can see the coverage.
- **Top recommendation:** group the fixes into PRs by module. Name the first PR and the docs changes it needs. AGENTS.md requires `scripting-api.md` updates for any signature or behavior change.

Publish as a new version of the standing report, so the link people already
have stays current and earlier runs stay in its version history:

1. Read it first: Artifact `action: "read"` on https://claude.ai/artifact/XYFqNkJkN4JyE8DtyBBsV9.
2. Publish the rendered file with that `url` and a `label` of `<YYYY-MM-DD> @ <short sha>`.
3. If the publish is refused because the user can't edit that artifact, publish a new one and tell them to ask its owner for edit access or to replace the URL above.

Give the user the link and ask which fixes to start.
