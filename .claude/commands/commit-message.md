Generate a commit message in Conventional Commits format for the staged changes.

Spec: https://www.conventionalcommits.org/en/v1.0.0/

## Scope: staged changes only

The message describes `git diff --cached` and nothing else.

```bash
git diff --cached          # the changes to describe — the ONLY source of content
git diff --cached --stat   # which files are affected
git log --oneline -15      # STYLE REFERENCE ONLY — type/scope conventions, not content
git branch --show-current  # may carry an issue number worth referencing
```

`git log` is for inferring this repo's conventions: which types and scopes it
uses, how descriptions are phrased, whether it references issues. Do not
describe anything it shows. Work already committed but not yet pushed has its
own commit message — repeating it makes this commit claim changes it does not
contain.

Unstaged and untracked changes are equally out of scope. If a bullet you are
about to write has no corresponding `+`/`-` line in `git diff --cached`, drop it.

If `git diff --cached` is empty, say nothing is staged rather than generating a
message from the working tree or from recent commits.

## Structure

```
<type>[(<scope>)][!]: <description>

[body]

[footer(s)]
```

### Required by the spec

- A **type**, a noun, followed by the optional scope, optional `!`, then a
  colon and a space (rule 1). `feat` for a new feature (2), `fix` for a bug
  fix (3); other types are allowed (14).
- A **scope**, if present, is a noun in parentheses describing a section of the
  codebase: `fix(parser):` (4).
- A **description** immediately after the colon and space (5).
- A **body**, if present, starts one blank line after the description (6) and
  is free-form, any number of newline-separated paragraphs (7).
- **Footers**, if present, start one blank line after the body (8). Each is
  `token: value` or `token #value`, and the token uses `-` in place of spaces —
  `Reviewed-by`, `Refs` — the sole exception being `BREAKING CHANGE` (9). A
  footer value may span lines until the next token (10).
- Type, scope and description are case-insensitive; only `BREAKING CHANGE` must
  be uppercase (15). `BREAKING-CHANGE` is a synonym for it (16).

### Convention, not spec — follow unless the repo differs

- Types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `style`, `build`,
  `ci`, `chore`, `revert`
- Scope in kebab-case: `data-extractor`, `cmd-sender`, `settings`. Omit it
  rather than inventing a vague one; match the scopes already in `git log`.
- Description in imperative mood ("add" not "added"), lowercase, no trailing
  period, whole first line under 72 characters.

## Choosing the type

Pick by what the change *does*, not which files it touches. Tests added
alongside a bug fix are part of the `fix`; a commit that only adds or repairs
tests is `test`. Making something work that never worked is `feat`, not `fix`.

## Description

State what changed, not that something changed: "fix off-by-one in log
rotation", not "fix bug".

## Body

Include one when there is more than one logical change:

- One bullet per logical change, most important first
- Explain **what** and **why**; the diff already shows how
- Name the concrete symbol, file, or flag so the bullet is checkable
- Note a non-obvious consequence a reviewer would otherwise miss
- Omit the body entirely for a single-purpose change — a good description is enough

If the staged changes are several unrelated things, say so and suggest which
files to split out rather than writing one message that papers over it.

## Breaking changes

Indicate one in the type/scope prefix, in a footer, or both (rule 11).

`!` immediately before the colon is enough on its own — the footer MAY then be
omitted and the description carries the breaking change (rule 13):

```
feat(api)!: require v2 telemetry endpoint, /api/tlm/v1 removed
```

Add a `BREAKING CHANGE:` footer when the migration needs more room than the
description allows (rule 12):

```
feat(api)!: remove deprecated telemetry endpoint

BREAKING CHANGE: /api/tlm/v1 callers must move to /api/tlm/v2. Response
envelopes lose the top-level `status` key; check the HTTP status instead.
```

## Footers

Reference an issue only when the repo's history shows that convention or the
branch name carries a number — `Closes #3471`, `Refs #3471`. Do not invent
references.

End with the attribution:

```
Co-Authored-By: Claude <noreply@anthropic.com>
```

## Repo conventions win

If the repo's CLAUDE.md, CONTRIBUTING file, or commit history specifies
something different — a required scope, a body length limit, a different
attribution footer, a changelog trailer — follow that over the guidance above.

## Output

Print only the commit message text. No markdown fences, no preamble, no
explanation — the user copies it directly.
