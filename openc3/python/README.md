## Python support for OpenC3 COSMOS

---

This project allows accessing the COSMOS API from the python programming language.
Additional functionality and support will be added over time.

---

## Installation

### For Users

```bash
pip install openc3
```

### For Development

See [README-DEV.md](README-DEV.md) for complete development setup.

#### Install Development Tools

Install UV, Ruff, and Just using pipx (recommended for isolated environments):

```bash
# Install pipx if not already installed
pip install --user pipx
pipx ensurepath

# Install development tools
pipx install uv
pipx install ruff
pipx install just
```

Or using your system package manager:

- **macOS**: `brew install uv ruff just`
- **Linux**: See [UV docs](https://docs.astral.sh/uv/getting-started/installation/), [Ruff docs](https://docs.astral.sh/ruff/installation/), [Just docs](https://github.com/casey/just#installation)
- **Windows**: See tool documentation links above

#### Quick Start

```bash
# Create virtual environment and install dependencies
cosmos/openc3/python % uv venv
cosmos/openc3/python % uv sync

# Run tests
cosmos/openc3/python % uv run pytest

# Run tests with coverage
cosmos/openc3/python % uv run coverage run -m pytest
cosmos/openc3/python % uv run coverage html
```
