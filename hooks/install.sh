#!/bin/bash
# Install git hooks from the hooks directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_DIR="$(git rev-parse --git-dir)"

echo "Installing git hooks..."

# Install pre-commit hook
if [[ -f "$SCRIPT_DIR/pre-commit" ]]; then
  cp "$SCRIPT_DIR/pre-commit" "$GIT_DIR/hooks/pre-commit"
  chmod +x "$GIT_DIR/hooks/pre-commit"
  echo "✓ Installed pre-commit hook"
else
  echo "✗ pre-commit hook not found in $SCRIPT_DIR"
fi

echo "Done!"
