# Code Heritage Measurement

`code_heritage.py` answers a question that gets asked often and answered badly:

> How much of the current OpenC3 COSMOS code base is still the original
> Ball Aerospace COSMOS 5.0.5 release?

There is no single objectively correct number, because "still the original
code" is a judgement call, not a measurement. So the tool does not produce one
number. It produces a **range bounded by two independent methods**, each of
which is reproducible from the git history alone, and it shows its work.

Run it:

```bash
scripts/heritage/code_heritage.py --content-similarity
```

## Why v5.0.5 is the right baseline

`v5.0.5` (commit `cad3a5ea`, 2022-06-25) is the last release cut under Ball
Aerospace before the OpenC3 fork. It is a **direct ancestor of `main`** — this
repository is a continuation of the Ball Aerospace history, not a re-import —
so every line in the tree today has an unbroken, verifiable chain of custody
back through it. The tool refuses to run if the baseline is not an ancestor of
the ref being measured, because line provenance would then be meaningless.

## Method 1 — line provenance via `git blame` (primary)

Every line of every in-scope file at `HEAD` is attributed by `git blame` to the
commit that last modified it. A line counts as **5.0.5 heritage** if and only
if that commit is an ancestor of (or is) the baseline tag.

Ancestry is resolved against the full set of commits reachable from `v5.0.5`
(`git rev-list v5.0.5`, 4,364 commits), so the classification is exact set
membership in the commit graph — not a similarity score, not an estimate.

Two metrics fall out of it:

| Metric | Definition | Answers |
|---|---|---|
| **Retention** | heritage lines ÷ current lines | "How much of what we ship today is 5.0.5 code?" |
| **Survival** | heritage lines ÷ 5.0.5 lines | "How much of 5.0.5 is still standing?" |

Blame options, and why:

- **`-w`** — ignore whitespace-only changes. Reindenting a file, or reflowing it
  through a formatter, does not make the logic new. Disable with
  `--no-ignore-whitespace`.
- **`-M -C`** — follow lines moved within a file and copied from files touched by
  the same commit. The fork restructured the tree heavily (`cosmos/` → `openc3/`,
  `cosmos-init/` → `openc3-cosmos-init/`); without move detection that
  restructuring would masquerade as new code. Tunable with `--copy-detection`
  (`none` / `moves` / `commit` / `deep`).

**This is a lower bound.** Blame credits the commit that last *touched* a line.
The fork mechanically rewrote the `Cosmos`/`COSMOS` identifiers to
`OpenC3`/`OPENC3` across the tree; every line carrying such an identifier is
genuinely different text today and is correctly, if unsatisfyingly, counted as
post-5.0.5. Method 2 exists to put a ceiling on how much that costs.

## Method 2 — normalized content similarity (`--content-similarity`)

Each in-scope file at `HEAD` is mapped back to its 5.0.5 counterpart using
git's rename/copy detection (`--find-renames=30%`, tunable). Both versions are
then **normalized**:

- whitespace runs collapsed (matching Method 1's `-w`);
- the Cosmos → OpenC3 rebranding undone, case-preserving
  (`COSMOS`→`OPENC3`, `Cosmos`→`OpenC3`, `cosmos`→`openc3`, `cosmosc2`→`openc3`);
- license/copyright header lines collapsed to a single `<<LICENSE>>` token,
  since the fork replaced those headers wholesale.

The two normalized line lists are diffed for longest common subsequences, and
the matching lines are counted.

**This is an upper bound**, for two reasons: it credits any line that is
unchanged apart from rebranding, and a line-level LCS cannot distinguish real
inheritance from coincidental matches (`end`, `}`, blank lines).

### The paired-subset trap

Method 2 can only speak about files it could map back to a baseline file. Code
that was *extracted* out of a 5.0.5 file into a new one is invisible to
file-level rename detection but is followed correctly by blame's `-C`. On this
repository that is not a rounding error: ~20,000 heritage lines live in files
with no 5.0.5 counterpart.

So Method 2's percentages are reported **against the paired subset**, never
against the whole tree, and the full-scope ceiling uses one uniform rule:

```
ceiling = Σ over files of max(blame_heritage_lines, normalized_match_lines)
```

For unpaired files Method 2 contributes 0 and the rule reduces to Method 1.
The report prints a WARNING if Method 2 ever falls *below* Method 1 on the
paired subset, which would indicate the normalization or rename threshold needs
review.

## What is counted

The credibility of the result depends entirely on scope, so scope is explicit
and symmetric — the same rules are applied to both trees.

**Excluded** as not human-authored source (the report prints the tally):

| Reason | What |
|---|---|
| `generated-docs-site` | `docs/` — the committed output of `docusaurus build --out-dir=../docs`; the authored source is `docs.openc3.com/` |
| `generated-lockfile` | `pnpm-lock.yaml`, `uv.lock`, `Gemfile.lock`, … |
| `minified-or-sourcemap` | `*.min.js`, `*.min.css`, `*.map` |
| `vendored` | `node_modules/`, `vendor/`, `third_party/` |
| `build-output` | `dist/`, `staticdocs/`, `coverage/` |
| `vendored-web-asset` | versioned third-party libraries in `*-tool-base/public/{js,css}/` (`vue-2.6.14.min.js`, `astro-web-components-7.24.0.css`), plus the Google Fonts `roboto.css` |
| `binary` | any blob containing NUL in its first 8 KiB |

Note the vendored-web-asset rule keys on the *version number* in the filename.
OpenC3's own hand-written files in those same directories — `auth.js`,
`bootstrap.js`, `browsercheck.js` — carry no version and are counted. A blanket
directory exclusion there would silently understate heritage.

**Categories.** Every counted file is classified as `source`, `test`, `config`,
`docs`, `data`, or `other`. The headline scope is `--scope code`
(`source` + `test`); `--scope source` drops tests, `--scope all` counts every
text file. All categories are reported in the breakdown regardless, so the
reader can see what the headline omits.

COSMOS `.txt` target definitions (`cmd.txt`, `tlm.txt`, screens, `plugin.txt`)
are classified `config`, not `source`: they are a real COSMOS configuration DSL
but not program source, and lumping them in either direction without saying so
would be misleading.

## Known limitations

- Blame attributes a line to the last commit that touched it, so a one-character
  fix to a 2014 line reassigns the whole line to the fix. This is the standard
  and intended behaviour of code-survival analysis, but it means Method 1
  systematically *under*-credits long-lived code.
- Method 2's rebranding normalization is deliberately aggressive: `COSMOS` is
  still a live product name in OpenC3 COSMOS, so some matches it creates are not
  really rebranding artifacts. That is why it is used only as a ceiling.
- Line counts are not a proxy for value or effort. A retained 5,000-line
  telemetry parser and 5,000 lines of retained boilerplate count the same.
- Results shift as history is rewritten. Numbers should be quoted with the
  `HEAD` sha the report prints.

## Reproducing and diffing over time

```bash
# headline numbers only (fast, ~35s on this repo)
scripts/heritage/code_heritage.py

# both methods, with machine-readable output for tracking over time
scripts/heritage/code_heritage.py --content-similarity \
    --json heritage.json --csv heritage-per-file.csv

# every text file, not just code
scripts/heritage/code_heritage.py --scope all

# a different baseline
scripts/heritage/code_heritage.py --baseline v5.0.0
```

`--json` captures every aggregate; `--csv` emits one row per file with its
line count, heritage lines, retention percentage, and the baseline path it was
mapped to. Both are stable enough to commit and diff release over release.
