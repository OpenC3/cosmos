---
sidebar_position: 15
title: Docker Compose
description: Customizing your deployment with compose.yaml and compose.override.yaml
sidebar_custom_props:
  myEmoji: 🐳
---

COSMOS runs as a set of containers described by two Docker Compose files in your COSMOS project:

| File | Owner | Purpose |
| --- | --- | --- |
| `compose.yaml` | COSMOS | The upstream service definitions. Treat as read only. |
| `compose.override.yaml` | You | Your customizations, merged on top of `compose.yaml`. |

Environment variable *values* live in `.env` and `.env.local` - see [Environment Variables](environment.md).

## compose.yaml

`compose.yaml` defines every COSMOS service (`openc3-cosmos-cmd-tlm-api`, `openc3-operator`, `openc3-redis`, `openc3-traefik`, ...), the volumes they mount and, under each service's `environment:` key, the variables that service reads.

Editing it works, but it conflicts on every COSMOS upgrade, because upgrading a COSMOS project means pulling in a new `compose.yaml`. Put your changes in `compose.override.yaml` instead and `compose.yaml` stays pristine.

## compose.override.yaml

`openc3.sh` merges this file automatically whenever it exists:

```bash
docker compose --env-file .env -f compose.yaml -f compose.override.yaml ...
```

No other change is needed - creating the file is enough. Compose merges the two per the [multiple compose files](https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/) rules: only the keys you specify change, and everything else is inherited.

The file that ships with a COSMOS project is entirely comments, with a worked example for every service. Uncomment what you need.

### Uncomment `services:` too

Every service block nests under the top level `services:` key, so uncomment that line as well as the block you want. Compose only allows `services`, `networks`, `volumes`, `configs` and `secrets` at the top level, so a service key left at column 0 fails with:

```text
additional properties 'openc3-cosmos-init' not allowed
```

Keep the indentation as shipped: service at 2 spaces, its keys at 4, list items at 6.

### Overriding a value

Redeclare the variable under `environment:` for the same service. A value set in an override's `environment:` block wins over the value in `compose.yaml` (and over any `env_file:`):

```yaml
services:
  openc3-cosmos-cmd-tlm-api:
    environment:
      # Number of Puma workers - roughly the number of CPU cores you want the API to use
      - WEB_CONCURRENCY=16
```

### Adding a variable compose.yaml does not list

An override's `environment:` block also *adds* variables. This matters because `compose.yaml` only passes through the variables each container reads today, so anything new - a variable your custom target or interface reads, or an `OPENC3_SETTING_*` variable - has to be added here:

```yaml
services:
  openc3-operator:
    environment:
      - MY_CUSTOM_SETTING=value
```

`env_file:` also adds variables, but it cannot *override* one that `compose.yaml` already lists.

### Adding ports, volumes and services

An override is a full compose file, so it can also expose a port, bind mount a host directory, or add a service of your own:

```yaml
services:
  openc3-operator:
    ports:
      # Expose an interface port to the host, bound to localhost only
      - "127.0.0.1:7779:7779"
    volumes:
      # Mount a host directory for a FileInterface dropbox
      - "/path/on/host/dropbox:/dropbox"
```

## Install and runtime flags

Several variables are flags rather than values. Most are enabled *by presence*: an empty value (`VAR=`) turns the flag off and any non-empty value turns it on.

```yaml
services:
  openc3-cosmos-init:
    environment:
      # Don't install the Table Manager tool
      - OPENC3_NO_TABLEMANAGER=1
      # Reinstall all plugins even if the same version exists
      - OPENC3_FORCE_INSTALL=1
```

:::warning[Do not use 0 to disable a presence flag]
`VAR=0` is a non-empty value, so it counts as ON. `OPENC3_NO_DOCS=0` disables the docs tool rather than enabling it. Use `VAR=` to turn a presence flag off.

The exceptions, which read their value instead: `OPENC3_DEMO`, and the `OPENC3_SETTINGS_OVERWRITE` / `OPENC3_SETTINGS_ALLOW_UNKNOWN` / `OPENC3_SETTINGS_STRICT` variables described in [Controlling how the settings are applied](../getting-started/cli.md#controlling-how-the-settings-are-applied). Those accept `true`/`false` (and `1`/`0`), so `OPENC3_DEMO=false` does not install the Demo.
:::

Each flag is documented in `compose.override.yaml` under the service it applies to, since a flag only takes effect on the container that reads it - `OPENC3_NO_*` tool flags and `OPENC3_FORCE_INSTALL` on `openc3-cosmos-init`, `OPENC3_ALLOW_HTTP` on `openc3-traefik`, and so on.

## Configuring Admin settings at deploy time

Every setting on the [Admin Settings tab](../tools/admin.md#settings) can be seeded from an `OPENC3_SETTING_<NAME>` variable on the init container, so a fresh install comes up already configured:

```yaml
services:
  openc3-cosmos-init:
    environment:
      - OPENC3_SETTING_TIME_ZONE=UTC
      - OPENC3_SETTING_TIME_FORMAT=24hr
      - OPENC3_SETTING_THEME=cosmosDarkSlate
      - OPENC3_SETTING_PYPI_URL=https://pypi.org
```

These variables are deliberately absent from `compose.yaml`; adding them here is what makes them reach the container, so a setting added by a later COSMOS release needs no `compose.yaml` edit. A setting is written on first init and then left alone so Admin Console edits survive a restart. See [cli initsettings](../getting-started/cli.md#initsettings) for the full list, the JSON settings, `--dry-run` and `--export`.

## Do not put secrets in this file

`compose.override.yaml` is tracked by git. Never hardcode a password or key (`OPENC3_*_PASSWORD`, `SECRET_KEY_BASE`) here. `compose.yaml` already reads those through `${VAR}` interpolation, so setting the value in a gitignored `.env.local` is all that is needed - see [Environment Variables](environment.md#envlocal) and [Security](../getting-started/security.md#overriding-secrets-with-envlocal).
