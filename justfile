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
