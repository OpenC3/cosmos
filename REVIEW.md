# Review instructions

COSMOS commands and monitors real hardware. A packet defined wrong or a command
validated wrong doesn't produce a stack trace — it produces a bad write to a
spacecraft. Weight findings accordingly.

## What Important means here

Reserve 🔴 Important for findings that would corrupt data, damage hardware, or
break deployed plugins:

- Packet or item definitions with wrong bit offset, bit size, endianness, or
  data type, and accessor/conversion logic that reads or writes them wrongly
- Command validation bypassed, hazardous commands not requiring confirmation,
  or range/state checks dropped
- Behavioral divergence between the Ruby and Python implementations of the same
  API — an operator scripting in Python must get the same result as in Ruby
- Interface or protocol changes that drop, duplicate, reorder, or truncate data
- Backward-incompatible changes to plugin config format (`plugin.txt`,
  `cmd.txt`, `tlm.txt`, screen definitions) — these break plugins already
  installed in the field
- Thread-safety errors in `interfaces/`, `microservices/`, and `operators/`
- Migrations under `openc3/lib/openc3/migrations/` that aren't backward
  compatible

Style, naming, structure, and refactoring suggestions are 🟡 Nit at most.

## Cap the nits

Report at most five Nits per review. If you found more, say "plus N similar
items" in the summary rather than posting them inline. If everything you found
is a Nit, lead the summary with "No blocking issues."

## Do not report

CI already enforces these — flagging them is pure noise:

- Python style and lint (`ruff check openc3`, python_lint.yml)
- JS/Vue style and formatting (ESLint + Prettier, eslint.yml, `--max-warnings 0`)
- Spelling (codespell, spelling.yml)
- Shell script issues at warning severity (shellcheck, shell_lint.yml)
- Static security analysis (CodeQL) and container CVEs (Trivy, ClamAV)
- Dependency vulnerabilities (dependency-review.yml)

Also skip:

- Lockfiles: `uv.lock`, `pnpm-lock.yaml`
- Generated and machine-authored content: docs builds (commits titled
  "Automated Doc Build Change"), `coverage/`, `plugins/DEFAULT/`,
  `openc3/openc3/`, `playwright/openc3-cosmos-pw-test/`, and build artifacts
  (`*.gem`, `*.so`, `*.bundle`)
- Test fixtures and demo targets (`openc3-cosmos-demo`) that intentionally
  violate production rules

## Always check

- **Ruby/Python parity.** These subsystems are mirrored between
  `openc3/lib/openc3/` and `openc3/python/openc3/`: `accessors`, `api`,
  `bridge`, `config`, `conversions`, `interfaces`, `io`, `logs`,
  `microservices`, `models`, `packets`, `processors`, `script`,
  `script_engines`, `streams`, `subpacketizers`, `system`, `tools`, `topics`,
  `utilities`. A behavioral change in one without the other is a finding.
  Ruby-only (`ccsds`, `core_ext`, `ext`, `migrations`, `operators`, `win32`) is
  expected and not a finding.
- **Public API parity specifically.** A change to `openc3/lib/openc3/api/*_api.rb`
  needs the matching `openc3/python/openc3/api/*_api.py`. Both exist for
  `cmd`, `tlm`, `limits`, `target`, `interface`, `router`, `config`, `settings`,
  `stash`, `calendar`, and `offline_access`.
- New or changed config keywords are documented under `docs.openc3.com/`
- New interfaces, protocols, accessors, and conversions have specs in
  `openc3/spec/` and tests in `openc3/python/test/`
- Enterprise-only code paths are guarded and degrade cleanly in Core

## Verification bar

Behavior claims need a `file:line` citation in the source, not an inference from
naming. For a parity finding, confirm the counterpart file actually lacks the
change before reporting it — read the file, don't infer from the diff alone.

## Re-review convergence

After the first review of a PR, suppress new Nits and report Important findings
only. A one-line fix should not reach round seven on style.

## Summary shape

Open the review body with a one-line tally, such as `2 important, 4 nits`. When
there are no correctness issues, lead with "No factual issues" before the
details.
