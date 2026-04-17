Generate an Angular-style commit message for the currently staged changes.

Follow these steps:

1. Run `git diff --cached` to see all staged changes
2. Run `git diff --cached --stat` to see which files are affected
3. Run `git log --oneline -10` to see recent commit style for reference

Analyze the staged changes and generate a commit message following the Angular commit convention:

## Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

## Rules

### Subject line
- Use imperative mood ("add" not "added", "fix" not "fixed")
- Lowercase first letter, no period at the end
- Max 72 characters
- Must accurately reflect the change (e.g., "add" = new feature, "fix" = bug fix, "update" = enhancement)

### Type (required) — one of:
- `feat` — a new feature
- `fix` — a bug fix
- `docs` — documentation only
- `style` — formatting, missing semicolons, etc. (no code change)
- `refactor` — code change that neither fixes a bug nor adds a feature
- `perf` — performance improvement
- `test` — adding or updating tests
- `build` — build system or external dependencies
- `ci` — CI configuration
- `chore` — maintenance tasks, tooling, etc.
- `revert` — reverts a previous commit

### Scope (required)
- The component, module, or area affected (e.g., `data-extractor`, `streaming-api`, `cmd-sender`)
- Use kebab-case
- Keep it concise

### Body (optional but encouraged)
- Explain **what** and **why**, not how
- Keep concise: 2-4 lines max
- Wrap at 72 characters
- Separate from subject with a blank line

### Footer (required)
- Always include the Claude Code attribution:
```
Co-Authored-By: Claude <noreply@anthropic.com>
```

### Breaking changes
- If the commit introduces a breaking change, add `BREAKING CHANGE:` in the footer before the attribution
- Optionally append `!` after the type/scope: `feat(api)!: remove deprecated endpoint`

## Output

Print ONLY the commit message text — no markdown fences, no explanation. The user will copy it directly.
