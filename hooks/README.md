# Git Hooks

This directory contains git hooks that help maintain code quality and consistency across the COSMOS repository.

## Installation

After cloning the repository, install the hooks by running:

```bash
./hooks/install.sh
```

## Available Hooks

### pre-commit

Automatically updates copyright years in modified files during commits.

**What it does:**
- Scans all files staged for commit
- Updates `Copyright YYYY OpenC3, Inc.` to the current year
- Updates `All changes Copyright YYYY, OpenC3, Inc.` to the current year (for dual-copyright files)
- Does NOT modify Ball Aerospace copyright lines
- Automatically re-stages files with updated copyright headers

**Example:**
```ruby
# Before commit (in 2026):
# Copyright 2023 OpenC3, Inc.

# After commit:
# Copyright 2026 OpenC3, Inc.
```

The hook works with all comment styles (Ruby `#`, JavaScript `//`, C-style `/* */`).

## Manual Copyright Updates

If you need to update copyright headers without committing, you can manually edit the copyright line in each file, or use the hook by staging and committing files.

## Troubleshooting

If the hook doesn't run:
1. Verify it's installed: `ls -la .git/hooks/pre-commit`
2. Verify it's executable: `chmod +x .git/hooks/pre-commit`
3. Reinstall: `./hooks/install.sh`
