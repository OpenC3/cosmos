# OpenC3 Python Library - Development Guide

This directory contains the Python implementation of the OpenC3 COSMOS library.

## Development Tools

This project uses modern Python tooling:

- **[UV](https://github.com/astral-sh/uv)** - Fast Python package manager (10-100x faster than pip)
- **[Ruff](https://github.com/astral-sh/ruff)** - Fast Python linter and formatter
- **[Just](https://github.com/casey/just)** - Command runner (like Make but better)

### Installing Tools

**macOS:**
```bash
brew install uv ruff just
```

**Linux/WSL:**
```bash
# Install UV
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Ruff and Just (via cargo or package manager)
cargo install ruff just
# Or on Debian/Ubuntu: apt-get install ruff just (if available in repos)
```

## Quick Start

### First Time Setup (New Developers)

If you're cloning the repository for the first time:

```bash
# Install Python (reads .python-version, installs if needed)
uv python install

# Install dependencies (automatically creates venv if needed)
uv sync

# View all commands
just

# Run tests
just test

# Verify code before committing
just verify
```

**Note:** UV will automatically:
- Install Python 3.12 (specified in `.python-version`) if not already installed
- Create a `.venv` virtual environment if it doesn't exist
- Install all project dependencies and the openc3 package

### Migration from Poetry

If you were previously using Poetry, follow these steps to switch to uv:

```bash
# 1. Remove Poetry virtual environment
rm -rf .venv
poetry env remove --all  # If you have Poetry installed

# 2. Remove Poetry cache (optional but recommended)
rm -rf ~/.cache/pypoetry

# 3. Install uv and dependencies
uv python install
uv sync

# 4. Verify everything works
just test
```

**What's different:**
- `poetry.lock` is replaced by `uv.lock`
- `poetry install` → `uv sync`
- `poetry add` → `just add` or `uv add`
- `poetry run` → `uv run`
- `poetry shell` → `source .venv/bin/activate` (or just use `uv run`)

You can now uninstall Poetry if you no longer need it: `brew uninstall poetry` or `pip uninstall poetry`

## Available Commands

Run `just` to see all available commands. Here are the most common:

### Code Quality
```bash
just format              # Format all code with Ruff
just format-changed      # Format only changed files (fast!)
just lint                # Check code quality (shows issues, doesn't fail)
just lint-changed        # Lint only changed files (fast!)
just lint-fix            # Auto-fix linting issues (fixes what it can)
just lint-strict         # Strict lint check (fails on any issues - for CI)
just lint-stats          # Show linting statistics
```

### Testing
```bash
just test                # Run all tests
just test-cov            # Run with coverage report
just test-cov-html       # Generate HTML coverage report
just test-fast           # Skip slow tests
just test-file FILE      # Run specific test file
```

### Pre-commit
```bash
just verify              # Format, lint, and test everything
just verify-changed      # Format and lint only changed files (fast!)
just check               # CI-friendly check (no modifications)
```

### Dependencies
```bash
just add PACKAGE         # Add new dependency
just add-dev PACKAGE     # Add dev dependency
just update              # Update all dependencies
just deps                # Show dependency tree
```

### Building
```bash
just build               # Build wheel and source distribution
just build-wheel         # Build wheel only
just build-sdist         # Build source distribution only
just build-info          # Build and show package info
just install-editable    # Install package in editable mode
```

### Cleanup
```bash
just clean               # Remove build artifacts
```

## Project Structure

```
openc3/python/
├── openc3/              # Main package source
├── test/                # Test files
├── pyproject.toml       # Project configuration
├── uv.lock              # Locked dependencies
├── justfile             # Development commands
└── README-DEV.md        # This file
```

## Python Version Support

This library supports Python 3.10 through 3.14. The library uses environment markers to install version-specific dependencies (e.g., different numpy versions for different Python versions).

## Code Style

- **Line length**: 120 characters
- **Quote style**: Double quotes
- **Import sorting**: Automatic via Ruff (isort rules)
- **Formatting**: Ruff format (Black-compatible)
- **Linting**: Multiple rule sets enabled (E, F, I, N, UP, B, W, C4, SIM)

## Running Tests

```bash
# All tests
just test

# With coverage
just test-cov

# Fast tests only (exclude slow tests)
just test-fast

# Specific test file
just test-file test/packets/test_packet.py

# Tests matching pattern
just test-pattern "test_limits"
```

## Before Committing

### Quick Check (Recommended - Fast!)

For a quick pre-commit check of only your changes:

```bash
just verify-changed
```

This will:
1. Format only changed Python files
2. Auto-fix linting issues in changed files
3. Show any remaining issues

### Full Verification

For a complete verification (slower but thorough):

```bash
just verify
```

This will:
1. Format all code
2. Auto-fix all linting issues
3. Run all tests

If all checks pass, you're ready to commit!

## CI/CD

For continuous integration, use the `check` command which doesn't modify files:

```bash
just check
```

## Manual Commands (without Just)

If you prefer not to use Just:

```bash
# Setup
uv python install        # Install Python from .python-version
uv sync                  # Create venv and install dependencies

# Test
uv run pytest

# Lint
uv run ruff check openc3
uv run ruff check openc3 --fix

# Format
uv run ruff format openc3

# Coverage
uv run coverage run -m pytest
uv run coverage report
uv run coverage html
```

## Documentation

See the [COSMOS Development Guide](https://docs.openc3.com/docs/development/developing) for more information.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `just verify` to ensure code quality
5. Commit and push
6. Create a Pull Request

## License

AGPLv3 - See [LICENSE.txt](LICENSE.txt) for details.
