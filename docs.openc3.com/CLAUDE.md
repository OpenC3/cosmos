# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Docusaurus

We use the `docusaurus` project to build and generate the docs. There are modifications to the docusaurus project in the `plugins` and `src` directories.

## Generated Docs

`build.sh` at the repo root is the entry point. It calls `scripts/generate_docs_from_yaml.rb`, which reads YAML files from `../../openc3/data/config/` (repo-root `openc3/data/config/`, not under `docs.openc3.com/`) and merges them into the source markdown under `docs/`. When checking for documentation updates, check the YAML files as well as the `docs` markdown.

Some of the docs files start with an underscore. They are source files which are combined with generated documentation from the YAML files to produce the non-underscore file. For example, `_command.md` generates `command.md`. Users should only edit the underscore file, not the generated file.

The YAML → markdown mappings (from `scripts/generate_docs_from_yaml.rb`):

| YAML source (in `openc3/data/config/`) | Output markdown (in `docs/configuration/`) |
| -------------------------------------- | ------------------------------------------ |
| `target_config.yaml`                   | `target.md`                                |
| `table_manager.yaml`                   | `table.md`                                 |
| `screen.yaml`                          | `telemetry-screens.md`                     |
| `command.yaml`                         | `command.md`                               |
| `plugins.yaml`                         | `plugins.md`                               |
| `telemetry.yaml`                       | `telemetry.md`                             |
| `conversions.yaml`                     | `conversions.md`                           |
| `processors.yaml`                      | `processors.md`                            |

Static image files live in the `static` directory and are referenced in the docs.

### Build Process

- Local iteration with hot reload: `pnpm start` (Docusaurus dev server). Note: Search does not work in this mode.
- Full build + static preview: `./build.sh` then `pnpm serve`.
- `pnpm build` writes the static site to `../docs` (sibling of `docs.openc3.com/`, not the source `docs/` directory inside it).

### Helper Scripts

- `check_doc_code_examples.py` — parses fenced code blocks in `.md` files and runs language-appropriate syntax checks (Python, Ruby, Bash, JS, JSON). Supports `--check-urls` for broken-link detection.
- `process_ruby_blocks.py` — rewrites `Ruby Example:` / `Python Example:` fenced blocks in markdown.
- `Rakefile` — builds the docs plugin gem (`rake build VERSION=X.X.X`), not the doc site itself.
