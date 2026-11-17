# OpenC3 COSMOS Root Development Commands
# Run `just` or `just --list` to see all available commands
#
# Component commands live in per-component justfiles and are reached through
# their namespace, e.g. `just plugins::lint-all` or `just python::test`. Only
# repo-wide recipes belong here; RuboCop is one because its config, Gemfile
# and scan scope all span the whole repository.

# The root Gemfile reads its source from RUBYGEMS_URL (see .env)
rubygems_url := env("RUBYGEMS_URL", "https://rubygems.org")

# RuboCop config that inherits .rubocop.yml but excludes spec files
rubocop_src_config := ".rubocop-src.yml"

# Bundler version in the Docker images (openc3-ruby runs gem update --system
# 3.7.2). Lock with the same version so the images don't switch Bundler.
bundler_version := "2.7.2"

# Component command namespaces
mod playwright 'playwright/justfile'
mod plugins 'openc3-cosmos-init/plugins/justfile'
mod python 'openc3/python/justfile'
mod ruby 'openc3/justfile'

# Default recipe - show available commands
default:
    @just --list

# Run every linter/formatter check in the repo (no tests)
check:
    just lint-ruby
    just plugins::lint-check
    just python::lint-check
    just playwright::lint-check

# ---------------------------------------------------------------------------
# Lockfiles
# ---------------------------------------------------------------------------

# Regenerate every committed Ruby, uv and pnpm lockfile without upgrading
lock:
    just lock-ruby
    just lock-uv
    just lock-pnpm

# Regenerate the committed Gemfile.lock files with the image's Bundler version
lock-ruby:
    #!/usr/bin/env bash
    set -euo pipefail
    gem list -i bundler -v {{ bundler_version }} >/dev/null || gem install bundler -v {{ bundler_version }} --no-document
    # openc3 first: the API locks pick up its gemspec as a path gem
    for lock in openc3/Gemfile.lock $(git ls-files '*Gemfile.lock' | grep -v '^openc3/Gemfile.lock$'); do
      echo "--- ${lock}"
      (cd "$(dirname "${lock}")" && bundle _{{ bundler_version }}_ lock --add-platform x86_64-linux aarch64-linux)
    done

# Regenerate the committed uv.lock files and uv script locks
lock-uv:
    #!/usr/bin/env bash
    set -euo pipefail
    for lock in $(git ls-files '*uv.lock'); do
      echo "--- ${lock}"
      (cd "$(dirname "${lock}")" && uv lock)
    done
    for lock in $(git ls-files '*.py.lock'); do
      echo "--- ${lock}"
      uv lock --script "${lock%.lock}"
    done

# Regenerate the committed pnpm-lock.yaml files
lock-pnpm:
    #!/usr/bin/env bash
    set -euo pipefail
    for lock in $(git ls-files '*pnpm-lock.yaml'); do
      echo "--- ${lock}"
      (cd "$(dirname "${lock}")" && pnpm install --lockfile-only)
    done

# ---------------------------------------------------------------------------
# Linting
# ---------------------------------------------------------------------------

# Install the RuboCop gems declared in the root Gemfile
lint-ruby-install:
    RUBYGEMS_URL={{ rubygems_url }} bundle install

# Lint Ruby with RuboCop: just lint-ruby openc3/lib
lint-ruby *ARGS:
    RUBYGEMS_URL={{ rubygems_url }} bundle exec rubocop {{ ARGS }}

# Lint Ruby source only, skipping spec files: just lint-ruby-src openc3/lib
lint-ruby-src *ARGS:
    RUBYGEMS_URL={{ rubygems_url }} bundle exec rubocop -c {{ rubocop_src_config }} --force-exclusion {{ ARGS }}

# Never use -A/--autocorrect-all here: unsafe corrections can undo a SonarQube
# fix. The unsafe cops also have AutoCorrect: false set in .rubocop.yml.
# Auto-fix Ruby with RuboCop, safe corrections only
lint-ruby-fix *ARGS:
    RUBYGEMS_URL={{ rubygems_url }} bundle exec rubocop --autocorrect {{ ARGS }}

# Auto-fix Ruby source only, skipping spec files, safe corrections only
lint-ruby-src-fix *ARGS:
    RUBYGEMS_URL={{ rubygems_url }} bundle exec rubocop -c {{ rubocop_src_config }} --force-exclusion --autocorrect {{ ARGS }}

# Show RuboCop offense counts by cop
lint-ruby-stats:
    RUBYGEMS_URL={{ rubygems_url }} bundle exec rubocop --format offenses

# Show RuboCop offense counts by cop for source only, skipping spec files
lint-ruby-src-stats:
    RUBYGEMS_URL={{ rubygems_url }} bundle exec rubocop -c {{ rubocop_src_config }} --format offenses

# Write a RuboCop JSON report for SonarQube (sonar.ruby.rubocop.reportPaths)
lint-ruby-report:
    RUBYGEMS_URL={{ rubygems_url }} bundle exec rubocop --format json --out rubocop-report.json
