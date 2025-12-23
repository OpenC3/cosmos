# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenC3 COSMOS is an open-source command and control system for embedded systems. It provides a web-based UI for telemetry display, command sending, script execution, logging, and more. The system is designed for testing, operating, and monitoring embedded systems that communicate via TCP/IP, UDP, Serial, etc.

## Documentation

The COSMOS documentation can be found at https://docs.openc3.com/docs. To get started with COSMOS Core reference https://github.com/OpenC3/cosmos-project and to get started with COSMOS Enterprise reference https://github.com/OpenC3/cosmos-enterprise-project.

## Architecture

### Microservices (Docker Containers)
- **openc3-cosmos-cmd-tlm-api** - Rails 7.2 REST API for command/telemetry operations
- **openc3-cosmos-script-runner-api** - Rails 7.2 API for script execution
- **openc3-operator** - Ruby operator managing interfaces and microservices
- **openc3-minio** - S3-compatible object storage for logs and configurations
- **openc3-redis** - Data store and pub/sub messaging
- **openc3-traefik** - Reverse proxy (access at http://localhost:2900)

### Core Library
- **openc3/** - Ruby gem with ~40 C extensions for performance-critical operations
- **openc3/python/** - Python library (Poetry-managed) with equivalent functionality

### Frontend (pnpm Workspace)
Located in `openc3-cosmos-init/plugins/packages/`:
- **openc3-tool-base** - Base Vue 3 components for tools
- **openc3-vue-common** - Shared Vue 3 components (Vuetify 3)
- **openc3-js-common** - Shared JavaScript utilities
- **openc3-cosmos-tool-*** - Individual tool packages (cmdsender, scriptrunner, tlmviewer, etc.)
- **openc3-cosmos-demo** - Demo plugin with test targets (INST, INST2, EXAMPLE, TEMPLATED)

### Communication Flow
Services communicate via Redis pub/sub and HTTP APIs. WebSocket support via AnyCable.

## Common Commands

### Docker Management (Primary Development Method)
```bash
./openc3.sh build     # Build all containers from source
./openc3.sh start     # Build + run (first time setup)
./openc3.sh run       # Run containers (after build)
./openc3.sh stop      # Stop containers gracefully
./openc3.sh cleanup   # WARNING: Deletes all data and volumes
```

### CLI Commands
```bash
./openc3.sh cli help                          # Show CLI help
./openc3.sh cli generate plugin MyPlugin      # Generate new plugin
./openc3.sh cli generate target MY_TARGET     # Generate new target
./openc3.sh cli validate myplugin.gem         # Validate plugin
./openc3.sh cli load myplugin.gem             # Load plugin
```

### Ruby Tests
```bash
cd openc3
bundle install
bundle exec rake build        # Compile C extensions (required first time)
bundle exec rspec             # Run all tests
bundle exec rspec spec/path/to/spec.rb           # Run single test file
bundle exec rspec spec/path/to/spec.rb:42        # Run specific line
```

### Python Tests
```bash
cd openc3/python
poetry install
poetry run ruff check openc3                     # Lint
poetry run pytest                                # Run all tests
poetry run pytest test/path/to/test.py           # Run single test file
poetry run coverage run -m pytest && poetry run coverage report
```

### Frontend (Vue.js/Vuetify)
```bash
cd openc3-cosmos-init/plugins
pnpm install
pnpm build:common             # Build shared packages first
pnpm lint                     # ESLint, run from the openc3-cosmos-init/plugins/packages/*tool*/ directory
```

### API Tests (Rails)
```bash
cd openc3-cosmos-cmd-tlm-api && bundle exec rspec
cd openc3-cosmos-script-runner-api && bundle exec rspec
```

### Playwright E2E Tests
```bash
cd playwright
pnpm install
./playwright.sh install-playwright
./playwright.sh build-plugin              # Required before running tests
pnpm test                                 # Run all tests
pnpm test:parallel                        # Run parallel tests (*.p.spec.ts)
pnpm test:serial --workers=1              # Run serial tests (*.s.spec.ts)
pnpm playwright test ./tests/command-sender.p.spec.ts --project=chromium  # Single file
ENTERPRISE=1 pnpm test:parallel           # Enterprise edition tests
pnpm test:parallel --headed               # Visible browser
PWDEBUG=1 pnpm test:parallel --headed     # Debug mode
```

### Test Commands via Docker
```bash
./openc3.sh test rspec        # Run Ruby tests in container
./openc3.sh test playwright   # Run Playwright tests
```

## Technology Stack

- **Ruby 3.4** - Backend APIs and core library
- **Rails 7.2** - REST APIs with AnyCable for WebSockets
- **Python 3.10-3.12** - Alternative scripting language
- **Vue.js 3 + Vuetify 3** - Frontend UI framework
- **Vite** - Frontend build tool
- **pnpm 10** - Frontend package management (monorepo workspace)
- **Node.js 24** - JavaScript runtime
- **Docker Compose** - Container orchestration
- **Redis** - Caching, pub/sub, ephemeral state
- **MinIO** - S3-compatible object storage
- **Playwright** - E2E testing

## Code Style

### File Headers
- When modifying any file, update the "Copyright YYYY OpenC3, Inc." line in the file header to the current year (2025). Do NOT modify the Ball Aerospace copyright line.

### Ruby
- RuboCop configured in `.rubocop.yml` (many rules disabled)
- Target Ruby version: 3.4

### Python
- Ruff for linting (pycodestyle E + Pyflakes F rules)
- Line length: 120
- Target Python: 3.12
- Config in `openc3/python/pyproject.toml`

### JavaScript/TypeScript
- ESLint 9 with Vue parser
- Prettier for formatting
- Config in `openc3-cosmos-init/plugins/eslint.config.mjs`

## Plugin Development

Plugins extend COSMOS with new targets, tools, and interfaces. Located in `openc3-cosmos-init/plugins/packages/`.

Each plugin is a Ruby gem containing:
- Target definitions (commands, telemetry, screens)
- Optional Vue.js tools
- Interface implementations

Generate new plugins: `./openc3.sh cli generate plugin MyPlugin`

## Enterprise vs Core

Set `ENTERPRISE=1` environment variable for Enterprise features. Enterprise uses Keycloak authentication. Core uses simple password authentication.
