# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

OpenC3 COSMOS is an open-source command and control system for embedded systems. It provides a web-based UI for telemetry display, command sending, script execution, logging, and more.

- Docs: https://docs.openc3.com/docs (source in `docs.openc3.com/`, which has its own `CLAUDE.md`)
- Example user projects: [cosmos-project](https://github.com/OpenC3/cosmos-project) (Core), [cosmos-enterprise-project](https://github.com/OpenC3/cosmos-enterprise-project) (Enterprise)

## Architecture

### Microservices (Docker Containers)

- **openc3-cosmos-cmd-tlm-api** - Rails REST API for command/telemetry operations
- **openc3-cosmos-script-runner-api** - Rails API for script execution
- **openc3-operator** - Ruby operator managing interfaces and microservices
- **openc3-buckets** - S3-compatible object storage (Versitygw) for logs and configurations
- **openc3-redis** - Valkey data store and pub/sub messaging
- **openc3-traefik** - Reverse proxy (access at http://localhost:2900)

Services communicate via Valkey pub/sub and HTTP APIs. WebSockets go through AnyCable.

### Core Library

- **openc3/** - Ruby gem with C extensions for performance-critical operations
- **openc3/python/** - Python library (uv-managed) with equivalent functionality

### Frontend (pnpm Workspace)

Vue 3 + Vuetify 3, built with Vite. Located in `openc3-cosmos-init/plugins/packages/`:

- **openc3-tool-base** - Base Vue components for tools
- **openc3-vue-common** - Shared Vue components
- **openc3-js-common** - Shared JavaScript utilities
- **openc3-cosmos-tool-\*** - Individual tools (cmdsender, scriptrunner, tlmviewer, etc.)
- **openc3-cosmos-demo** - Demo plugin with test targets (INST, INST2, EXAMPLE, TEMPLATED)

### Enterprise vs Core

Set `ENTERPRISE=1` for Enterprise features. Enterprise uses Keycloak authentication; Core uses simple password authentication.

## Common Commands

### Docker

```bash
./openc3.sh build     # Build all containers from source
./openc3.sh start     # Build + run (first time setup)
./openc3.sh run       # Run containers (after build)
./openc3.sh stop      # Stop containers gracefully
./openc3.sh cleanup   # WARNING: Deletes all data and volumes
./openc3.sh test      # List containerized test suites (rspec, playwright, ...)
./openc3.sh cli help  # CLI: generate plugin/target, validate, load, etc.
```

### Ruby (openc3 gem)

```bash
cd openc3
bundle install
bundle exec rake build                       # Compile C extensions (required first time)
bundle exec rspec spec/path/to/spec.rb:42    # Run a file or a specific line
```

### Rails APIs

The Rails APIs depend on the local `openc3` gem, which must be built first. Set
`OPENC3_DEVEL` so Bundler resolves it from source instead of RubyGems.

```bash
export OPENC3_DEVEL=../openc3
cd openc3-cosmos-cmd-tlm-api && bundle install && bundle exec rspec
cd openc3-cosmos-script-runner-api && bundle install && bundle exec rspec
```

### Python

```bash
cd openc3/python
uv sync                                      # Create venv and install dependencies
uv run pytest test/path/to/test.py           # Run a test file
just verify-changed                          # Format, lint, and test changed files
just verify                                  # Format, lint, and test everything
```

Run `just` to list all recipes. Always invoke tools via `uv run` rather than activating the venv.

### Frontend

```bash
cd openc3-cosmos-init/plugins
pnpm install
pnpm build:common                            # Build shared packages first
cd packages/<package-name> && pnpm lint      # Lint one package (--fix to auto-fix)
```

### Playwright E2E

```bash
cd playwright
pnpm install
./playwright.sh install-playwright
./playwright.sh build-plugin                 # Required before running tests
pnpm test:parallel                           # *.p.spec.ts
pnpm test:serial                             # *.s.spec.ts
pnpm playwright test ./tests/command-sender.p.spec.ts --project=chromium
pnpm test:enterprise                         # Enterprise suite
PWDEBUG=1 pnpm test:parallel --headed        # Debug mode
```

## Code Style

- **Ruby**: RuboCop, configured in `.rubocop.yml`.
- **Python**: Ruff for lint and format, configured in `openc3/python/pyproject.toml`. Minimum supported Python is 3.11 (ruff `target-version = "py311"`), so don't use syntax newer than that. Commit `uv.lock` with any dependency change.
- **JavaScript/Vue**: ESLint 9 + Prettier, configured in `openc3-cosmos-init/plugins/eslint.config.mjs`. After editing Vue/JS files, always run `pnpm lint` in the package. CI runs `pnpm lint --max-warnings 0`, so any warning fails the build.

## Sharding

Sharding bugs are easy to miss because nothing fails locally: the default
`.env` and `compose.yaml` have one Redis, one ephemeral Redis, and one TSDB
(no `SHARDNUM` in the hostnames). The test mocks
(`mock_redis` in `spec_helper.rb`, `FakeValkey` in `test_helper.py`) also return
the same instance for every shard. So code that reads shard 0 instead of the
target's shard passes every test and only breaks in multi-shard Enterprise
deployments. Two separate concepts:

- **`db_shard`** - which Redis / ephemeral Redis / QuestDB instance holds a
  target's data. Set per target, interface, router, and microservice with
  `DB_SHARD`. Hostnames come from `OPENC3_REDIS_HOSTNAME`,
  `OPENC3_REDIS_EPHEMERAL_HOSTNAME`, and `OPENC3_TSDB_HOSTNAME` with `SHARDNUM`
  replaced by the shard number.
- **`shard`** - which operator runs a microservice (`SHARD` keyword,
  `OPENC3_SHARD` env var, filtered in `microservice_operator.rb`).

When touching code that reads or writes Redis, topics, or TSDB:

- **Target data lives on the target's db_shard; everything else is on db_shard 0.**
  Packet definitions (`openc3tlm`/`openc3cmd`), CVT, packet counts, and the
  `COMMAND`/`DECOMCMD`/`TELEMETRY`/`DECOM` topics are per target. Model configs
  like `TargetModel` itself are on 0. Look up the shard with
  `Store.db_shard_for_target` or `QuestDBClient.db_shard_for_target`, or use
  `TargetModel.store_for_target`.
- **Pass `db_shard:` explicitly.** `Topic`, `Store.instance`, `EphemeralStore.instance`,
  and `QuestDBClient` methods default to `db_shard: 0`, so a missing argument
  silently uses the wrong instance.
- **Reading many topics:** split them with `Topic.group_topics_by_db_shard` and
  read each group from its own instance. A single `read_topics` call can't
  span shards.
- **Listing or aggregating:** status and metric models (`InterfaceStatusModel`,
  `MicroserviceStatusModel`, `MetricModel`) include `DbShardedModel`, which
  iterates all active shards. New per-interface or per-microservice data should
  do the same, and queries that merge results across TSDB shards need care.
- **Per-shard state:** `StoreQueued` and `EphemeralStoreQueued` keep one instance
  per shard, and some are created lazily after startup. Settings like update
  interval, and shutdown or cleanup, must apply to every instance, including
  ones created later.
- **Ruby and Python must match.** Most of this logic exists in both
  `openc3/lib` and `openc3/python/openc3`; past bugs were fixed in one and not
  the other.
- **Tests:** a test that only uses db_shard 0 proves nothing about sharding.
  Because the mocks share one instance, assert that the call used the right
  `db_shard:` (e.g. `expect(Store).to receive(:instance).with(db_shard: 1)`)
  rather than only checking that the data came back.

## Cross-Repo Changes (Enterprise)

COSMOS Enterprise (`../cosmos-enterprise`, private) builds on this repo: its
images start from the core images and add the `openc3-enterprise` gem, and its
Python and frontend packages import core's. When changing core, check whether
enterprise depends on what you changed:

- **Optional enterprise hooks in core.** Core loads enterprise code with
  `begin; require 'openc3-enterprise/...'; rescue LoadError` (e.g. `RolesController`,
  `utilities/authorization.rb`, `api/api.rb`). Changing one of these files or its
  fallback means the enterprise version (`openc3-enterprise-gem/lib/openc3-enterprise/`)
  likely needs the same change. Find them with `grep -rn "openc3-enterprise" openc3/lib openc3-cosmos-*-api`.
- **Base classes and modules.** Enterprise subclasses `Model`, `Microservice`,
  `Operator`, `Migration`, `Bucket`, `Secrets`, `TargetFile`, and `ModelController`,
  and requires many `openc3/models`, `openc3/utilities`, and `openc3/topics` files.
  Renaming or changing the signature of anything public there can break enterprise.
- **Python.** `openc3enterprise` imports `openc3.utilities`, `models`, `topics`,
  `api`, `io`, and `environment`.
- **Frontend.** Enterprise tools import heavily from `@openc3/vue-common` and
  `@openc3/js-common`. Treat their exports as a public API.
- **Environment variables.** A new or renamed variable in `compose.yaml` usually
  also belongs in enterprise's `compose.yaml` and `openc3-helm/openc3/templates/_env-vars.tpl`.
- **Playwright.** Enterprise specs live in `cosmos-enterprise/playwright/enterprise`
  (the copy under `playwright/tests/enterprise` here is gitignored). UI changes in
  shared components can break them.

To check, grep `../cosmos-enterprise` for the changed class, method, export, or
variable name. If it isn't checked out, say so instead of assuming nothing breaks.
Report the enterprise changes needed; don't edit that repo unless asked.

## Ruby and Python Parity

Most of the core library exists in both languages, and users can write targets,
interfaces, and scripts in either. When changing one, search for the equivalent
in the other and change it too, including its tests:

| Ruby | Python |
| ---- | ------ |
| `openc3/lib/openc3/<dir>/<name>.rb` | `openc3/python/openc3/<dir>/<name>.py` |
| `openc3/spec/<dir>/<name>_spec.rb` | `openc3/python/test/<dir>/test_<name>.py` |

- Class and method names usually match (`CamelCase` classes, `snake_case`
  methods), so grep the other tree for the name. Ruby keyword arguments
  (`scope:`, `db_shard:`) are Python keyword arguments (`scope=`, `db_shard=`).
- Code under `openc3/ext/` is a Ruby C extension; its Python equivalent is plain
  Python (e.g. `ext/openc3/ext/structure` → `python/openc3/packets/structure.py`).
- Some Python modules have a `.pyi` stub next to them (`store_queued`,
  `store_implementation`, `logger`). Update the stub when the signature changes.
- Some Ruby areas have no Python equivalent (`operators/`, `migrations/`,
  `core_ext/`, `win32/`); a missing match there is expected. If you can't find
  an equivalent elsewhere, say so instead of skipping it silently.

## Scripting API

The scripting API is the public interface users call from scripts, tools, and
microservices. It is defined in:

- `openc3/lib/openc3/api/*_api.rb` (methods registered in `WHITELIST`) and
  `openc3/lib/openc3/script/*.rb`
- `openc3/python/openc3/api/` and `openc3/python/openc3/script/` (keep in sync
  per Ruby and Python Parity above)

When you add, remove, rename, or change the parameters, return value, or
behavior of one of these methods, update
`docs.openc3.com/docs/guides/scripting-api.md` in the same change. Each method
there has its own `###` heading with:

- a `Since X.Y.Z` badge. For a new method, write the version as the placeholder
  `_Coming Soon_`, never a version number:
  `<span class="badge badge--secondary since-heading">Since _Coming Soon_</span>`.
  `scripts/release/openc3_set_versions.rb` replaces it with the release version
  on a production release. (The same placeholder works for `since:` in the
  `openc3/data/config/*.yaml` files.)
- Python and Ruby syntax tabs, a parameter table, and Python and Ruby example tabs

Removed or deprecated methods go in the migration table near the top of the
file. See `docs.openc3.com/CLAUDE.md` for the docs build and
`check_doc_code_examples.py` for checking the examples.

## Commit Messages

[Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
`.claude/commands/commit-message.md` is the authority on format (Claude Code
users can run `/commit-message`); follow it rather than duplicating rules here.
