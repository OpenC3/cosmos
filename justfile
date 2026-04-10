# OpenC3 COSMOS Root Development Commands
# Run `just` or `just --list` to see all available commands

plugins_dir := "openc3-cosmos-init/plugins/packages"

# Default recipe - show available commands
default:
    @just --list

# ---------------------------------------------------------------------------
# Shared dependency builds
# ---------------------------------------------------------------------------

# Build all shared frontend dependencies (js-common, vue-common, tool-base)
# Skips packages whose src/ hasn't changed since the last build
build-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    build_if_stale() {
        local name="$1" src="$2" out="$3"
        local dir="{{ plugins_dir }}/$name"
        if [[ ! -d "$dir/$out" ]] || [[ -n "$(find "$dir/$src" -newer "$dir/$out" -type f 2>/dev/null | head -1)" ]]; then
            echo "Building $name ..."
            (cd "$dir" && pnpm install && pnpm build)
        else
            echo "Skipping $name (up to date)"
        fi
    }
    build_if_stale openc3-js-common  src dist
    build_if_stale openc3-vue-common src dist
    build_if_stale openc3-tool-base  src tools/base

# Force-build all shared frontend dependencies (ignore cache)
build-deps-force:
    cd {{ plugins_dir }}/openc3-js-common && pnpm install && pnpm build
    cd {{ plugins_dir }}/openc3-vue-common && pnpm install && pnpm build
    cd {{ plugins_dir }}/openc3-tool-base && pnpm install && pnpm build

# ---------------------------------------------------------------------------
# Generic dev server
# ---------------------------------------------------------------------------

# Run any plugin dev server: just dev openc3-cosmos-tool-admin
dev plugin *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    plugin="{{ plugin }}"
    skip_deps=false
    for flag in {{ FLAGS }}; do
        if [[ "$flag" == "--skip-deps" ]]; then
            skip_deps=true
        fi
    done
    dir="{{ plugins_dir }}/$plugin"
    if [[ ! -d "$dir" ]]; then
        echo "Error: plugin '$plugin' not found in {{ plugins_dir }}"
        echo ""
        echo "Available plugins:"
        ls {{ plugins_dir }} | grep openc3-cosmos-tool-
        exit 1
    fi
    if [[ "$skip_deps" == false ]]; then
        just build-deps
    fi
    cd "$dir"
    pnpm install
    port=$(grep -o 'port: [0-9]*' vite.config.js 2>/dev/null | grep -o '[0-9]*' | head -1)
    port="${port:-2900}"
    echo ""
    echo "Starting $plugin on http://localhost:$port"
    echo ""
    pnpm serve

# ---------------------------------------------------------------------------
# Individual tool dev servers (alphabetical)
# ---------------------------------------------------------------------------

# Dev server for Admin (port 2930)
dev-admin *FLAGS:
    just dev openc3-cosmos-tool-admin {{ FLAGS }}

# Dev server for Bucket Explorer (port 2921)
dev-bucket-explorer *FLAGS:
    just dev openc3-cosmos-tool-bucketexplorer {{ FLAGS }}

# Dev server for Command Sender (port 2913)
dev-cmd-sender *FLAGS:
    just dev openc3-cosmos-tool-cmdsender {{ FLAGS }}

# Dev server for CmdTlm Server (port 2911)
dev-cmd-tlm-server *FLAGS:
    just dev openc3-cosmos-tool-cmdtlmserver {{ FLAGS }}

# Dev server for Data Extractor (port 2918)
dev-data-extractor *FLAGS:
    just dev openc3-cosmos-tool-dataextractor {{ FLAGS }}

# Dev server for Data Viewer (port 2919)
dev-data-viewer *FLAGS:
    just dev openc3-cosmos-tool-dataviewer {{ FLAGS }}

# Dev server for Handbooks (port 2922)
dev-handbooks *FLAGS:
    just dev openc3-cosmos-tool-handbooks {{ FLAGS }}

# Dev server for iFrame (port 2915)
dev-iframe *FLAGS:
    just dev openc3-cosmos-tool-iframe {{ FLAGS }}

# Dev server for Limits Monitor (port 2912)
dev-limits-monitor *FLAGS:
    just dev openc3-cosmos-tool-limitsmonitor {{ FLAGS }}

# Dev server for Packet Viewer (port 2915)
dev-packet-viewer *FLAGS:
    just dev openc3-cosmos-tool-packetviewer {{ FLAGS }}

# Dev server for Script Runner (port 2914)
dev-script-runner *FLAGS:
    just dev openc3-cosmos-tool-scriptrunner {{ FLAGS }}

# Dev server for Table Manager (port 2916)
dev-table-manager *FLAGS:
    just dev openc3-cosmos-tool-tablemanager {{ FLAGS }}

# Dev server for Telemetry Grapher (port 2917)
dev-tlm-grapher *FLAGS:
    just dev openc3-cosmos-tool-tlmgrapher {{ FLAGS }}

# Dev server for Telemetry Viewer (port 2920)
dev-tlm-viewer *FLAGS:
    just dev openc3-cosmos-tool-tlmviewer {{ FLAGS }}

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

# List all available frontend plugins
list-plugins:
    @ls {{ plugins_dir }} | grep openc3-cosmos-tool-
