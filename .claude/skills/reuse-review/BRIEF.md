# Sweep brief

Fill the `{{…}}` placeholders and send the text below the line as the sub-agent prompt.

---

Read-only investigation in the OpenC3 COSMOS repo at {{repo root}}. Edit nothing.

Goal: find logic written two or more times in this slice, where one shared helper
module would replace the copies:

{{slice directories, one per line}}

Look for: copy-pasted blocks; near-identical functions or classes that differ by
one parameter, key prefix or label; families of methods that could funnel through
one private helper; repeated request/response, encode/decode, validation, lookup,
retry or thread-loop scaffolding; and pass-through modules that add nothing.

Hunt hardest for **drift**: small differences between copies, where one copy got
a fix the others lack. Quote the differing lines. Common COSMOS drift:

- Truthiness: `0` is truthy in Ruby and falsy in Python. `requests.Response` is falsy for any 4xx or 5xx.
- `bytes` from Redis in Python where Ruby has `String`; ids or keys left undecoded.
- `json.dumps` without `cls=JsonEncoder` next to copies that use it.
- `"true"` vs `"True"`; `== 0` vs `!= 0`.
- A method reference compared instead of called (`q.qsize != 0`).
- A missing `return`.
- A lock taken without `with`/`finally` where Ruby uses `synchronize`.
- A parse or lookup outside the `try` that its twin has inside.
- A scope, db_shard or other keyword argument dropped, so the default applies.
- A singleton created without re-checking under its lock.

Counterpart: {{counterpart root, or "none"}}. For every finding, open the
counterpart and classify it:

- (a) the counterpart already shares this logic in one place, so this side diverged;
- (b) the counterpart duplicates it the same way, so fix both;
- (c) there is no counterpart.

Cite the counterpart's file:line.

Keep the names and signatures of these public surfaces: the scripting API,
base classes users subclass (`Interface`, `Protocol`, `Conversion`, `Processor`,
`Accessor`, `Stream`), classes COSMOS Enterprise subclasses or imports (see
AGENTS.md "Cross-Repo Changes"), and `@openc3/vue-common` / `@openc3/js-common`
exports. A helper sits behind them.

Already reported, skip: {{exclusions, or "none"}}.

Report back in at most 900 words: 4–7 findings ranked by value. For each finding give:

- the title;
- every copy as an exact file:line;
- what is duplicated, in 1–3 sentences;
- the drift, with quoted lines;
- the parity class with the counterpart's file:line;
- the proposed helper name and rough signature;
- the estimated lines removed per side;
- the risk.

Then list smaller items in one line each. Read every line you cite. Every finding
needs file:line for all its copies and its parity class.
