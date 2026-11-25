# Sweep brief

Fill the `{{…}}` placeholders and send the text below the line as the sub-agent prompt.

---

Read-only investigation in the OpenC3 COSMOS repo at {{repo root}}. Edit nothing.

Goal: find places where a Ruby method and its Python twin **behave** differently.
Users write scripts, targets and microservices in either language and expect the
same result. Your slice, as Ruby ↔ Python file pairs:

{{slice file pairs, one per line}}

A signature inventory has already been run. Its findings for your slice are in
{{inventory.md path}} (search for your files). Treat that as a starting point:
confirm or dismiss each item in your slice, then go further, because the
inventory sees signatures only, not bodies.

For each method pair, compare:

- **Arguments:**
  - which arguments are forwarded to the server or model, and which are dropped (`scope`, `type`, `timeout`, `cache_timeout`, `manual`);
  - defaults that differ;
  - positional vs keyword arguments.
- **Return value:**
  - its shape (list vs tuple, dict keys, `nil` vs `None` vs `[]`);
  - `bytes` vs `str`;
  - symbols vs strings;
  - time types;
  - sort order.
- **Errors:**
  - which exception is raised and when;
  - the message text users match on;
  - silent `None` where the twin raises.
- **Truthiness:**
  - `0`, `""` and `[]` are truthy in Ruby and falsy in Python;
  - a `requests.Response` is falsy for any 4xx or 5xx.
- **Edge inputs:** `LATEST`, an empty list, an unknown target/packet/item, a missing optional argument.
- **Docs:** for public methods, what `docs.openc3.com/docs/guides/scripting-api.md` says, and which side matches it.

Expected differences to skip:

- Ruby API methods take `manual:` and `token:` for JSON-RPC authorization, and Python's API runs in-process.
- Ruby `?` method names have Python aliases without the `?`.
- Ruby symbols arrive as strings over JSON.
- Python has `globals`/`locals` where Ruby has `binding`/`context`.

Already reported or fixed in open PRs, skip: {{exclusions}}.

Report back in at most 900 words: 5–8 findings ranked by user impact. For each finding give:

- the method name;
- Ruby file:line and Python file:line;
- the difference, with quoted lines from both sides;
- which side is right (it matches the docs, the other language's tests, or the server), or "unclear";
- a concrete script call that behaves differently;
- whether a test exists on either side that would catch it.

Then list smaller items in one line each. Read every line you cite.
