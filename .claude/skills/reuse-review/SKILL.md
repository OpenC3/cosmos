---
name: reuse-review
description: Find duplicated logic in one COSMOS language tree (python, ruby or vue), check each copy against its counterpart for drift, and publish a ranked reuse report with the bugs the drift caused.
argument-hint: "<python|ruby|vue|path> [--exclude \"item; item\"]"
disable-model-invocation: true
---

# Reuse review

Find logic written more than once, propose one shared helper module per cluster,
and keep the Ruby/Python counterpart in step. The prize is **drift**: copies of
the same logic that have quietly diverged, so one copy has a fix or a bug the
others lack. Drift is both the best evidence that a helper is needed and a list
of bugs to fix today.

Use the codebase-design vocabulary (module, interface, seam, leverage,
locality) in the report.

## 1. Scope

Parse `$ARGUMENTS`. A language maps to roots and a counterpart:

| Arg | Roots | Counterpart |
| --- | --- | --- |
| `python` | `openc3/python/openc3` | `openc3/lib/openc3` (C extensions in `openc3/ext`) |
| `ruby` | `openc3/lib/openc3`, `openc3-cosmos-cmd-tlm-api/app`, `openc3-cosmos-script-runner-api/app` | `openc3/python/openc3` for `lib`; the Rails apps have none |
| `vue` | `openc3-cosmos-init/plugins/packages` | none across languages; check against what `openc3-vue-common` and `openc3-js-common` already export |

A path argument: use it as the root and find its counterpart with the AGENTS.md
parity table.

Then:

- Rank hot spots: `git log --since="6 months ago" --name-only --pretty=format: -- <roots> | sort | uniq -c | sort -rn | head -30`.
- Size the tree: `find <roots> -name '*.<ext>' | xargs wc -l | sort -n | tail -25`.
- Split the roots into **three slices** of similar weight, grouping directories that call each other (api + script; models + topics + utilities + logs; interfaces + microservices + packets + accessors for python).
- Collect **exclusions**: `--exclude` items, plus candidates from earlier reviews the user names. Sweeps skip them.

Done when you have three slices, each a list of directories, and an exclusion list (possibly empty).

## 2. Sweep

Spawn three `general-purpose` sub-agents in one message, one per slice, each
given [BRIEF.md](BRIEF.md) with its placeholders filled. They run in the
background; wait for all three hand-backs.

## 3. Verify

Sweep output is a lead, not a fact. For every bug claimed in a hand-back:

- Read the cited lines yourself. Keep it as **checked** if the code shows the bug, **sweep** if you did not get to it, and drop it if the code disagrees.
- Check any claim of the form "X raises" or "branch is unreachable" against the actual control flow and library behaviour.

Then check the downstream users of what the candidates touch:

- `../cosmos-enterprise`: grep its Python, Ruby and frontend sources (skip `.venv`, `node_modules`) for every module, class and export a candidate would change. If it is not checked out, say so in the report.
- Public surfaces that keep their names and signatures: the scripting API (`openc3.script` signatures feed the enterprise MCP server), user-subclassed base classes (`Interface`, `Protocol`, `Conversion`, `Processor`, `Accessor`, `Stream`), the enterprise-subclassed classes listed in AGENTS.md, and `@openc3/vue-common` / `@openc3/js-common` exports.

Then check open PRs against every bug and candidate. Fetch the PRs that touch
the roots and their counterpart into the scratchpad (from the repo root):

```bash
python3 .claude/skills/reuse-review/open_prs.py fetch "$SCRATCH/prs" <roots> <counterpart roots>
python3 .claude/skills/reuse-review/open_prs.py grep "$SCRATCH/prs" "<method or function>" ...
```

Grep for each bug's method and each candidate's functions, then read every
matching hunk and sort it:

- **Fixed:** the code after the PR no longer has the bug. Replay the bug's failing case against the PR's version of the lines; a hunk that only changes them is not enough. Set the bug row's `pr` field to `#N` and say so in its card.
- **Overlap:** the PR edits the same functions, or changes the cited lines, without fixing the finding. Name it in the card ("land after #N"), because the refactor will conflict with it. A PR that adds another copy of the duplicated code strengthens the card; say that too.

Done when every bug row is marked checked or sweep, has a PR status, and every candidate states which enterprise imports and open PRs it touches.

## 4. Report

Copy [template.html](template.html) to the scratchpad as
`reuse-review-<lang>-<YYYYMMDD>.html`. Fill the `{{…}}` placeholders and replace
the example entries in `CARDS`, `SMALL` and `BUGS`. The page renders the cards,
diagrams and tables from those arrays, so edit data, not markup.

- **Cards:** 6–10 candidates, merged across slices, ranked by value. Value = lines removed × bugs prevented, weighted toward hot spots.
- **Strength:** `Strong`, `Worth exploring` or `Speculative`.
- **Parity:**
  - (a) the counterpart already shares this logic, so copy its shape;
  - (b) both sides duplicate it, so refactor both in one PR;
  - (c) there is no counterpart.
- **Smaller items** go in the `SMALL` table rather than getting cards.
- **Top recommendation:** Step 0 is a bug-fix PR for the one-line fixes in `BUGS`, each with a regression test, landed before any refactor. Then name the first candidate. Prefer parity class (a), because the shape is already decided there.

The diagrams are HTML boxes, not Mermaid. The artifact viewer renders Mermaid nodes dark and drops `<br/>`, so the template's boxes stay readable.

Publish as a new version of the standing report for that language. Each
language has its own artifact, so the link people already have stays current
and earlier runs stay in its version history:

| Language | Report |
| --- | --- |
| `python` | https://claude.ai/artifact/244jzhZQMRcxt8N8nsmUKy |
| `ruby` | https://claude.ai/artifact/5zaDNnceVPSeEJN8XKmeX5 |
| `vue` | https://claude.ai/artifact/25a7uee5CcysJTgBPbqJk6 |

1. Take the URL from the row for the language in `$ARGUMENTS`, and only that row: a ruby run never publishes to the python or vue report.
2. Artifact `action: "read"` on it, then publish the rendered file with that `url` and a `label` of `<YYYY-MM-DD> @ <short sha>`.
3. A path argument has no row: publish a new artifact.
4. If the publish is refused because the user can't edit that artifact, publish a new one and tell them to ask its owner for edit access or to replace the URL above.

Give the user the link and ask which candidate to take on. A chosen candidate continues with the grilling skill, as in
improve-codebase-architecture.
