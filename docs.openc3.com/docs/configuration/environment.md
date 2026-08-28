---
sidebar_position: 16
title: Environment Variables
description: Configuring COSMOS with .env and .env.local
sidebar_custom_props:
  myEmoji: ⚙️
---

COSMOS reads its configuration from environment variables. Two files in your COSMOS project supply them, and [Docker Compose](compose.md) decides which variables reach which container.

| File | Tracked by git | Purpose |
| --- | --- | --- |
| `.env` | Yes | The upstream COSMOS defaults. Treat as read only. |
| `.env.local` | No (gitignored) | Your secrets and any value you want to keep out of git. |

## .env

`.env` ships the defaults: which image tag to deploy, the registries to pull from, bucket and volume names, Redis and database hostnames, and the development passwords.

Editing it works, but it conflicts on every COSMOS upgrade. Where your change belongs instead:

| What you are changing | Where it goes |
| --- | --- |
| A non-secret value, an install flag, an extra service, port or volume | `compose.override.yaml` |
| A password, key or token | `.env.local` |
| A COSMOS Admin Console setting | `OPENC3_SETTING_<NAME>` in `compose.override.yaml` |

## .env.local

`.env.local` sits next to `.env`, is gitignored, and is loaded after `.env`, so any value it sets overrides the matching default. It is where secrets belong - passwords, keys and tokens - because neither `.env` nor `compose.override.yaml` can hold them safely, both being tracked by git.

[Security](../getting-started/security.md#overriding-secrets-with-envlocal) covers this in full: which credentials COSMOS ships, which of them you must change, the `users.acl` files a Redis password change has to stay in sync with, and how to inject a secret at run time instead of writing it to disk.

`.env.local` is not only for secrets. Any value you want to keep out of git, or want to differ from `.env` without editing a tracked file, can go there.

## Precedence

The same variable can be set in several places at once. Which one wins depends on *what the value is being used for*, because Compose does two separate things with environment variables and they have different rules.

### 1. Filling in `${VAR}` in the compose files (interpolation)

Before Compose does anything else, it substitutes every `${VAR}` in `compose.yaml` and `compose.override.yaml`. This is where `.env` and `.env.local` are read, and only here. Highest wins:

```text
shell environment  >  .env.local  >  .env
```

`openc3.sh` produces that order by passing the files in sequence, and Compose gives a later `--env-file` precedence over an earlier one:

```bash
docker compose --env-file .env --env-file .env.local -f compose.yaml -f compose.override.yaml ...
```

So `OPENC3_REDIS_PASSWORD=mypassword` in `.env.local` beats the default in `.env`, and `export OPENC3_REDIS_PASSWORD=other` in your shell beats both for that one command. See [Security](../getting-started/security.md#overriding-secrets-with-envlocal) for the secret handling that relies on this.

### 2. Setting the variables inside the container

What a container actually receives comes from that service's `environment:` key, after the two compose files are merged. Highest wins:

```text
compose.override.yaml environment:  >  compose.yaml environment:  >  env_file:
```

A literal value here is not an "environment variable" that `.env` can influence at all - it is written into the merged compose file:

```yaml
services:
  openc3-cosmos-cmd-tlm-api:
    environment:
      # Fixed. Nothing in .env or your shell changes this.
      - WEB_CONCURRENCY=16
      # Interpolated. Comes from .env / .env.local / your shell, per section 1.
      - OPENC3_REDIS_HOSTNAME=${OPENC3_REDIS_HOSTNAME}
```

### Putting the two together

`OPENC3_REDIS_PASSWORD` is a good example of the full chain. `compose.yaml` passes it to the services that need it as `${OPENC3_REDIS_PASSWORD}`, `.env` supplies the development default, and `.env.local` supplies your real one:

1. Compose resolves `${OPENC3_REDIS_PASSWORD}` - your shell first, then `.env.local`, then `.env`
2. The resolved value is written into the container's environment by the `environment:` entry that referenced it
3. The container reads it at startup

Two consequences fall out of this:

- **Setting a variable in `.env` or `.env.local` does nothing on its own.** It only has an effect if some service's `environment:` references it, either as `${VAR}` or as a bare `- VAR` pass-through. To get a brand new variable into a container, add it in `compose.override.yaml` - see [How a variable reaches a container](#how-a-variable-reaches-a-container).
- **A hardcoded value in `compose.override.yaml` cannot be overridden from `.env.local` or your shell.** If you want a value to stay configurable, write it as `${VAR}` in the override and set `VAR` in an env file.

### Other things worth knowing

- Once `openc3.sh` passes `--env-file` explicitly - which it always does - Compose stops auto-loading `.env` from the current directory. Only the files `openc3.sh` names are read, which is why `.env` is listed explicitly rather than being picked up implicitly.
- Exporting a variable in your shell is the way to inject a secret at run time from a vault or a CI secret store without writing it to disk. It applies only to the `openc3.sh` command you run it with, so `export` it in the same shell (or prefix the command) if you need it to persist across `openc3.sh stop` and `openc3.sh run`.
- Set `ENV_FILE` to use a different base file in place of `.env`, for example a per-environment file checked out alongside it. `.env.local` is still loaded on top when it exists.
- A `${VAR}` in a compose file that no env file and no shell variable supplies resolves to an empty string, and Compose warns about it. This is why `.env` defines a few variables as blank on purpose, such as `OPENC3_IMAGE_SUFFIX`.

## How a variable reaches a container

`compose.yaml` lists, under each service's `environment:` key, the variables that service reads. A variable not listed for a service does not reach it, even when it is set in `.env`. Two forms appear:

```yaml
    environment:
      # Interpolated: the value comes from .env / .env.local, and compose
      # warns when it is unset
      - OPENC3_REDIS_HOSTNAME=${OPENC3_REDIS_HOSTNAME}
      # Bare pass-through: forwarded only if set in the shell or an env file,
      # and omitted entirely otherwise
      - OPENC3_DEMO
```

To pass a variable that `compose.yaml` does not list, add it under `environment:` for that service in `compose.override.yaml`. See [Adding a variable compose.yaml does not list](compose.md#adding-a-variable-composeyaml-does-not-list).

## Common variables

Set in `.env`, or overridden per service in `compose.override.yaml`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENC3_TAG` | `latest` | Image tag to deploy, e.g. `7.3.0` |
| `OPENC3_EXTERNAL_URL` | `http://localhost:2900` | External domain name and port used to reach COSMOS |
| `OPENC3_LOCAL_MODE` | `1` | Sync plugin and configuration changes to the `plugins` directory on the host. See [Local Mode](../guides/local-mode.md) |
| `OPENC3_DEMO` | `true` | Install the Demo plugin. Accepts `false` and `0` to disable |
| `OPENC3_REGISTRY`, `OPENC3_NAMESPACE` | `docker.io`, `openc3inc` | Where to pull COSMOS images from |
| `OPENC3_LOGS_BUCKET`, `OPENC3_TOOLS_BUCKET`, `OPENC3_CONFIG_BUCKET` | `logs`, `tools`, `config` | Bucket names |
| `OPENC3_REDIS_HOSTNAME`, `OPENC3_REDIS_PORT` | `openc3-redis`, `6379` | Redis / Valkey connection |
| `OPENC3_CLOUD` | `local` | Cloud provider, for bucket and secret handling |
| `RUBYGEMS_URL`, `PYPI_URL`, `NPM_URL`, `MAVEN_URL` | public mirrors | Package sources used at *build* time. To change the URLs COSMOS uses at *run* time, set the `rubygems_url` / `pypi_url` Admin settings |

Per-service runtime flags - `OPENC3_NO_*`, `OPENC3_FORCE_INSTALL`, `OPENC3_ALLOW_HTTP`, `OPENC3_DEFAULT_QUEUE`, `OPENC3_AUTH_RATE_LIMIT_*`, `OPENC3_LANGUAGE`, `OPENC3_LOG_STDERR` - are documented in `compose.override.yaml` under the service each one applies to, because a flag only takes effect on the container that reads it. See [Install and runtime flags](compose.md#install-and-runtime-flags) for how their values are interpreted.

## Admin Console settings

`OPENC3_SETTING_<NAME>` variables on the init container seed the [Admin Settings tab](../tools/admin.md#settings) at deploy time, so a fresh install comes up with your time zone, time format, theme and package URLs already set. They are not listed in `compose.yaml`; add them to `compose.override.yaml`. See [cli initsettings](../getting-started/cli.md#initsettings).
