---
sidebar_position: 4
title: Security
description: Security considerations and credential management for COSMOS deployments
sidebar_custom_props:
  myEmoji: "\U0001F512"
---

This document covers security considerations for COSMOS deployments, including credential management, security boundaries, and recommendations for production environments.

## Overview

COSMOS uses several backend service credentials that are separate from the frontend user account you create when first accessing the web interface. The backend passwords authenticate communication between COSMOS microservices, while the frontend password is for human users accessing COSMOS through a web browser. In COSMOS Enterprise, the frontend user accounts are managed by Keycloak.

When you first navigate to COSMOS Core and are prompted to create a password, you are creating a **frontend user password** that is separate from all the backend service passwords discussed below.

## Security Boundaries

Proper security is always a matter of trade-offs and layers. This section discusses the different security boundaries relevant to COSMOS.

### Docker Network

All COSMOS containers run in a Docker network called `openc3-cosmos-network`. Only the Traefik load balancer is exposed directly to any outside network, with ports for HTTP and HTTPS traffic. If HTTPS is enabled, all HTTP traffic is redirected to HTTPS.

The load balancer routes specific paths to VersityGW or the COSMOS APIs, making them available to the outside network through the same hostname as the load balancer. In COSMOS Enterprise, Keycloak is also routed through the load balancer.

Other COSMOS services such as Redis and all worker microservices have no direct exposure outside of the Docker network.

### Host Computer

The host computer is the most critical layer to protect because it has control of the Docker infrastructure. A user with Docker access on the host computer can:

1. Kill all containers
2. Access any container with root permission and view all files and data
3. See the environment variables for any process
4. Read all of the COSMOS configuration files

The host computer should ideally be dedicated to running COSMOS and have limited access by only trusted users.

### Local vs Network Configuration

By default, COSMOS only listens on localhost (127.0.0.1). This configuration keeps COSMOS completely off the network and is only vulnerable to local users of the host computer.

For production use, it is recommended to configure COSMOS to listen on a network interface (not just localhost) so that users can access the web interface from their own workstations rather than directly on the host computer. This means users connect via their web browsers over the local network instead of needing access to the host machine itself, which reduces exposure of the host and allows it to be more tightly secured. See [Network Configuration](../guides/network-configuration) for opening COSMOS to the network and [SSL/TLS](../configuration/ssl-tls) for configuring HTTPS.

### Content Security Policy

COSMOS sets a [Content Security Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) (CSP) header via Traefik to mitigate cross-site scripting (XSS) and other code-injection attacks. The default policy forbids inline scripts but allows `eval()` for third-party plugin compatibility. Scripts may only be loaded from the same origin and trusted sources.

The following environment variables control the CSP:

| Variable | Default | Description |
| --- | --- | --- |
| `OPENC3_ALLOW_HTTP` | _(unset)_ | When set (e.g. `1`), broadens the CSP to allow resources over plain HTTP in addition to HTTPS. Useful for development or air-gapped networks without TLS. |
| `OPENC3_NO_EVAL` | _(unset)_ | When set (e.g. `1`), removes `'unsafe-eval'` from the CSP `script-src` directive, blocking `eval()`, `new Function()`, and similar dynamic code execution. Only set this if no installed plugins require runtime code evaluation (e.g. Open MCT and other tools that bundle Vue's runtime template compiler will break). |

By default `'unsafe-eval'` is **allowed** for third-party plugin compatibility. WebAssembly (`'wasm-unsafe-eval'`) is always allowed regardless of these flags.

To harden the CSP on a deployment that does not use plugins requiring eval, add `OPENC3_NO_EVAL` to `.env.local` (recommended) or `compose.override.yaml` under the `openc3-traefik` service, then recreate the Traefik container:

```bash
# .env.local
OPENC3_NO_EVAL=1
```

```bash
./openc3.sh stop
./openc3.sh run
```

These are runtime settings evaluated by Traefik at container startup -- no image rebuild is needed.

### Network Security

Between any external network and the private network containing the host computer should be a firewall that prevents unauthorized access.

Exposing COSMOS directly to the public internet is not recommended. While the system itself is secure, there is no built-in denial of service (DOS) protection, and an adversary could overwhelm the system with requests.

## Runtime Secrets in Docker

There are two ways to pass runtime secrets into containers: environment variables and mounted files.

Environment variables passed to containers can be sourced from host environment variables or from a `.env` file. Files mounted into containers must exist as local files accessible by the user starting COSMOS.

The `.env` file ships the upstream COSMOS defaults and is tracked by git, so editing it directly causes merge conflicts when you pull future COSMOS updates and risks committing secrets. Instead, put secret overrides in a `.env.local` file next to `.env` (see [Overriding Secrets with .env.local](#overriding-secrets-with-envlocal) below).

In both cases, secrets need to be available to the user account starting COSMOS. This account must have sufficient trust to control container lifecycles and all data within the containers.

Most standard containers for databases like VersityGW are set up to receive secrets through environment variables. For a thorough discussion of secrets in Docker, see the [official thread](https://github.com/moby/moby/issues/13490).

### Infrastructure Secrets vs. Plugin Secrets

The variables documented on this page are COSMOS's own infrastructure credentials: Redis/Valkey passwords, bucket keys, and `SECRET_KEY_BASE`. They are configured through the environment because the services need them before COSMOS is running.

Credentials that your **plugins** need — a device password, an API token, a client certificate — should not be put in `.env.local` or `compose.override.yaml`. Use the COSMOS Secrets system instead: store the value once (Admin tool, API, or a Kubernetes Secret) and reference it by name with the `SECRET` keyword in `plugin.txt`. COSMOS then injects it into just the interface or microservice that declared it, rather than into every container. See the [Secrets guide](../guides/secrets.md), which also covers Kubernetes and integrating HashiCorp Vault or AWS Secrets Manager.

## Credentials

The `.env` file contains environment variables that configure COSMOS. The password-related variables fall into several categories.

### Redis Credentials

Redis is the primary data store and pub/sub messaging system for COSMOS.

| Variable                   | Default Value          | Description                                   |
| -------------------------- | ---------------------- | --------------------------------------------- |
| `OPENC3_REDIS_USERNAME`    | `openc3`               | Username for the main COSMOS Redis connection |
| `OPENC3_REDIS_PASSWORD`    | `openc3password`       | Password for the main COSMOS Redis connection |
| `OPENC3_SR_REDIS_USERNAME` | `scriptrunner`         | Username passed to spawned user scripts       |
| `OPENC3_SR_REDIS_PASSWORD` | `scriptrunnerpassword` | Password passed to spawned user scripts       |

The `OPENC3_REDIS_*` credentials are used by COSMOS services (cmd-tlm-api, script-runner-api, operator, and init containers) to connect to Redis with full access to the COSMOS keyspace.

The `OPENC3_SR_REDIS_*` credentials are passed to **spawned user scripts** when Script Runner executes them. The script-runner-api itself uses the main `OPENC3_REDIS_*` credentials, but when it spawns a user script process, it substitutes the limited `SR` credentials. This prevents user scripts from accessing or modifying data they shouldn't have access to.

### VersityGW (S3 Storage) Credentials

VersityGW provides S3-compatible object storage for logs, configurations, and other files.

| Variable                    | Default Value                | Description                             |
| --------------------------- | ---------------------------- | --------------------------------------- |
| `OPENC3_BUCKET_USERNAME`    | `openc3bucket`               | Root username for VersityGW             |
| `OPENC3_BUCKET_PASSWORD`    | `openc3bucketpassword`       | Root password for VersityGW             |
| `OPENC3_SR_BUCKET_USERNAME` | `scriptrunnerbucket`         | Username passed to spawned user scripts |
| `OPENC3_SR_BUCKET_PASSWORD` | `scriptrunnerbucketpassword` | Password passed to spawned user scripts |

The `OPENC3_BUCKET_*` credentials are the VersityGW root credentials used by COSMOS services to manage buckets and files.

The `OPENC3_SR_BUCKET_*` credentials create a separate VersityGW user with limited permissions. Similar to the Redis credentials, these are passed to **spawned user scripts** rather than being used by the script-runner-api itself, following the principle of least privilege.

### Service Authentication

| Variable                  | Default Value   | Description                                              |
| ------------------------- | --------------- | -------------------------------------------------------- |
| `OPENC3_SERVICE_PASSWORD` | `openc3service` | Service account password for internal API authentication |

The `OPENC3_SERVICE_PASSWORD` is a backend service account password that allows internal COSMOS services to authenticate with the APIs without requiring a frontend user's credentials. It is used in the following contexts:

**COSMOS Core:**

- **Script Runner**: When spawning user scripts, the script process uses this password to authenticate with the COSMOS APIs (cmd-tlm-api) to send commands, retrieve telemetry, etc.
- **Command Queues**: When executing queued commands, the queues controller uses this password for API authentication.

**COSMOS Enterprise (additional uses):**

- **Calendar (Timeline Microservice)**: When executing scheduled commands or scripts, uses this password for authentication.
- **Autonomic (Reaction Microservice)**: When executing reaction commands or scripts in response to triggers, uses this password for authentication.

Note: In COSMOS Enterprise with Keycloak, user offline access tokens can be used instead when available, but the service password serves as a fallback for automated operations.

### Rails Application Secret

| Variable          | Description                                                     |
| ----------------- | --------------------------------------------------------------- |
| `SECRET_KEY_BASE` | A 128-character hexadecimal string used by Rails for encryption |

The `SECRET_KEY_BASE` is used by the Rails applications (cmd-tlm-api and script-runner-api) for encrypting session data and other security-sensitive operations. This should be a unique, randomly-generated value for each COSMOS installation. The default value in the `.env` file should be changed for production deployments.

You can generate a new secret key with:

```bash
openssl rand -hex 64
```

### COSMOS Enterprise Credentials

COSMOS Enterprise has additional credentials for Keycloak and PostgreSQL. See the `DockerComposeSecurity.md` file in your project directory for Enterprise-specific credential documentation.

## The users.acl File

The `users.acl` file (located at `openc3-redis/users.acl`) configures Redis authentication and authorization. This file is **only for Redis** and has no relation to VersityGW or other services.

### ACL File Format

Each line defines a user with the syntax:

```
user <username> [on/off] <password> [keyspace] [commands]
```

Passwords can be specified as:

- SHA-256 hash: prefix with `#` (e.g., `#022bd57...`)
- Plaintext: prefix with `>` (e.g., `>openc3password`)

Using hashed passwords is recommended for production to avoid storing cleartext passwords on disk.

### Default Users

| User           | Default Password       | Purpose                                               |
| -------------- | ---------------------- | ----------------------------------------------------- |
| `openc3`       | `openc3password`       | Main COSMOS service account with full keyspace access |
| `scriptrunner` | `scriptrunnerpassword` | Limited access for Script Runner                      |
| `admin`        | `admin`                | Optional admin account for Redis management           |
| `healthcheck`  | (no password)          | Health check user with minimal permissions            |
| `default`      | (disabled)             | Default Redis user, disabled for security             |

### User Permissions

**openc3**: Has access to the entire COSMOS keyspace but cannot reconfigure Redis itself. This is the main service account used by COSMOS.

**scriptrunner**: Has restricted access to only:

- Keys matching `running-script*`, `*script-locks`, `*script-breakpoints`, `*openc3_log_messages`
- Channels for `_action_cable_internal`, `script-api:*`

This prevents user scripts from accessing or destroying other COSMOS data.

**admin**: Has `@admin` permissions which includes the `ACL` command. This user is optional and can be disabled by changing `on` to `off` or removing the line entirely.

**healthcheck**: Used during container startup to verify Redis is available. Has no password and can only run the `ping` command (Enterprise also allows `info`).

### Relationship Between .env and users.acl

The effective Redis passwords (the `.env` defaults as overridden by `.env.local`) must match the passwords in `users.acl`:

| .env Variable              | users.acl User | Must Match                                                      |
| -------------------------- | -------------- | --------------------------------------------------------------- |
| `OPENC3_REDIS_PASSWORD`    | `openc3`       | Yes - COSMOS services use these credentials to connect to Redis |
| `OPENC3_SR_REDIS_PASSWORD` | `scriptrunner` | Yes - Spawned user scripts use these credentials                |

The `admin` user in `users.acl` does not have a corresponding `.env` variable since it's only used for manual Redis administration.

The VersityGW credentials (`OPENC3_BUCKET_*`, `OPENC3_SR_BUCKET_*`) and `OPENC3_SERVICE_PASSWORD` have no corresponding entries in `users.acl` since they are for different services.

## Securing Your Deployment

### Overriding Secrets with .env.local

Do not edit `.env` to change passwords. It is tracked by git, so edits cause merge conflicts on upgrade and can leak secrets into your repository. `compose.override.yaml` is also tracked and must not hold secrets either.

Instead, create a `.env.local` file next to `.env`. It is gitignored, and `openc3.sh` loads it after `.env`, so any value you set there overrides the matching default in `.env`. `compose.yaml` already reads every secret via `${VAR}` interpolation, so setting the value in `.env.local` is all that is needed — no `compose.override.yaml` entry is required.

Example `.env.local`:

```
OPENC3_REDIS_PASSWORD=my-real-redis-password
OPENC3_SR_REDIS_PASSWORD=my-real-scriptrunner-redis-password
OPENC3_BUCKET_PASSWORD=my-real-bucket-password
OPENC3_SR_BUCKET_PASSWORD=my-real-scriptrunner-bucket-password
OPENC3_SERVICE_PASSWORD=my-real-service-password
SECRET_KEY_BASE=<output of openssl rand -hex 64>
```

The precedence order is:

```
shell environment  >  .env.local  >  .env
```

So a shell environment variable still wins over `.env.local`, letting you inject secrets from a vault at run time if you prefer (see [Injecting Secrets at Runtime](#injecting-secrets-at-runtime)).

The sections below tell you to set each secret in `.env.local`. When you change a Redis password you must also update the corresponding hash in `users.acl`, since those are two separate files that must stay in sync.

### Changing Redis Passwords

1. Generate a SHA-256 hash of your new password:

   ```bash
   ./openc3.sh util hash yournewpassword
   ```

2. Update `openc3-redis/users.acl` with the new hash:

   ```
   user openc3 on #newhashvalue allkeys allchannels ...
   ```

3. Add the new cleartext password to `.env.local`:

   ```
   OPENC3_REDIS_PASSWORD=yournewpassword
   ```

4. Repeat for the `scriptrunner` user if desired.

### Changing VersityGW Passwords

Add the values to `.env.local`:

```
OPENC3_BUCKET_PASSWORD=yournewpassword
OPENC3_SR_BUCKET_PASSWORD=yournewsrpassword
```

### Changing the Service Password

Add the value to `.env.local`:

```
OPENC3_SERVICE_PASSWORD=yournewservicepassword
```

### Generating a New SECRET_KEY_BASE

```bash
openssl rand -hex 64
```

Then add the new value to `.env.local`:

```
SECRET_KEY_BASE=yournewsecretkeybase
```

### Injecting Secrets at Runtime

For enhanced security, you can keep secrets out of any on-disk file entirely and pass them as shell environment variables at runtime. Shell environment variables override both `.env.local` and `.env`:

```bash
OPENC3_REDIS_PASSWORD=mypassword OPENC3_BUCKET_PASSWORD=mypassword ./openc3.sh run
```

This prevents cleartext passwords from being stored on disk, though you must provide them each time you start COSMOS. This pairs well with a secrets vault that exports the values into the environment before launch.

## Security Recommendations

For production deployments:

1. **Change all default passwords** before deploying COSMOS. Put the overrides in `.env.local`, not `.env`.

2. **Use hashed passwords** in `users.acl` to avoid storing cleartext passwords on disk.

3. **Restrict file permissions** on `.env.local` and `users.acl`:

   ```bash
   chmod 600 .env.local
   chmod 600 openc3-redis/users.acl
   ```

4. **Configure SSL/TLS** before exposing COSMOS to any network. See [SSL/TLS Configuration](../configuration/ssl-tls).

5. **Disable or secure the Redis admin user** if not needed:

   ```
   user admin off #hashvalue +@admin
   ```

6. **Generate a unique SECRET_KEY_BASE** for each installation.

7. **Limit host computer access** to only trusted administrators.

8. **Use a firewall** to restrict network access to COSMOS.

## Frontend vs Backend Authentication

It's important to understand the distinction:

- **Backend credentials** (this document): Service-to-service authentication between COSMOS containers. Users never enter these passwords directly.

- **Frontend credentials**: User accounts for accessing COSMOS through a web browser.
  - **COSMOS Core**: Uses password-based authentication. The first user who connects sets the password that all users share.
  - **COSMOS Enterprise**: Uses Keycloak for authentication with individual user accounts, roles, and permissions.

The frontend password you set when first accessing COSMOS at `http://localhost:2900` is stored in Redis and is completely separate from the backend service credentials documented here.

## Session Length and Automatic Logout

### COSMOS Core

COSMOS Core sessions do not expire, so there is no automatic logout to disable or extend. When you log in, COSMOS issues a session token that is stored in Redis with no expiration and saved in the browser's local storage, so it also survives closing the browser. There is no idle timeout and no setting to add one.

A Core session only ends when:

- The user clicks **Logout**, which ends the session for that browser only.
- The password is changed, which ends every session in every browser and also clears the session tokens used by running scripts and other API clients. The browser that changed the password is given a new session automatically.

If you need sessions that expire after a period of inactivity, use COSMOS Enterprise, where session length is controlled by Keycloak.

### COSMOS Enterprise

In COSMOS Enterprise, session length is controlled entirely by the `openc3` realm in Keycloak. COSMOS has no session timeout setting or environment variable of its own. The defaults are:

| Keycloak Setting      | Default    | Effect                                                                                                                 |
| --------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------- |
| SSO Session Idle      | 30 minutes | The user must log in again if no COSMOS tab refreshes its token for this long, e.g. the browser was closed.            |
| SSO Session Max       | 10 hours   | The user must log in again this long after logging in, even if they were active the whole time.                        |
| Access Token Lifespan | 5 minutes  | How long each access token is valid. COSMOS refreshes it automatically, so users don't notice this.                    |

SSO Session Idle and SSO Session Max are on the **Realm settings** > **Sessions** tab of the Keycloak Admin Console, and Access Token Lifespan is on the **Realm settings** > **Tokens** tab.

While a COSMOS tab is open, the browser refreshes the access token every few minutes (see [Automatic Token Refresh](/docs/getting-started/architecture#automatic-token-refresh)), which keeps resetting the idle timeout. Leaving a tab open therefore does not log the user out after 30 minutes, but they are still logged out when SSO Session Max is reached. When a refresh fails because the session has ended, COSMOS redirects to the Keycloak login page.

#### Changing the Session Length

Change the session settings in the Keycloak Admin Console:

1. Browse to `http://localhost:2900/auth/` (or your `OPENC3_KEYCLOAK_EXTERNAL_URL`) and log in with the Keycloak admin account. Its initial username and password are `KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD` from `.env` (or `.env.local` if you [override them there](#overriding-secrets-with-envlocal)). These are only applied the first time Keycloak initializes its database, so if the admin password was changed later in Keycloak, use the current one.
2. Select the **openc3** realm from the realm dropdown. Don't change the `master` realm, which only holds the Keycloak admin account.
3. Go to **Realm settings** > **Sessions** and change **SSO Session Idle** and **SSO Session Max**. For example, set SSO Session Idle to 8 hours and SSO Session Max to 24 hours so operators aren't logged out during a shift.
4. Click **Save**.
5. Log out of COSMOS and log back in to start a session with the new settings.

You can also script the change with `kcadm.sh` inside the Keycloak container. Open a shell in the container, replacing `cosmos-enterprise-openc3-keycloak-1` with the name of your Keycloak container (see `docker ps`):

```bash
docker exec -it cosmos-enterprise-openc3-keycloak-1 sh
```

Then log in and update the realm. The values are in seconds:

```bash
K=/opt/keycloak/bin/kcadm.sh
C="--config /tmp/kcadm.config"
$K config credentials $C --server http://localhost:8080/auth --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD"
$K update realms/openc3 $C -s ssoSessionIdleTimeout=28800 -s ssoSessionMaxLifespan=86400
rm /tmp/kcadm.config
```

The `--config` file is written to `/tmp` because the container's filesystem is read only. It holds admin tokens and `/tmp` is a persistent volume, so the last command deletes it. `KC_BOOTSTRAP_ADMIN_USERNAME` and `KC_BOOTSTRAP_ADMIN_PASSWORD` are set from `KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD` in `.env` (or `.env.local`). If the admin username or password has since been changed in Keycloak, use the current values instead.

COSMOS imports its default realm only the first time Keycloak starts and does not overwrite an existing realm, so settings you change in Keycloak persist across COSMOS upgrades. For the same reason, editing a realm export file does not change a realm that already exists.

:::note[Session expiry cannot be fully disabled]
Keycloak always enforces session expiry and has no "never expire" option, so to keep users logged in for a long time, set a long duration. Choose values that fit your operations; longer sessions also give a stolen or unattended session more time to be misused. To let individual users opt into longer sessions instead, enable **Remember me** under **Realm settings** > **Login** and set **SSO Session Idle Remember Me** and **SSO Session Max Remember Me** under **Sessions**.
:::

#### Scripts and Background Tasks

Session length does not affect scripts or other automation:

- Scripts, the CLI, and external programs using `OPENC3_API_USER` / `OPENC3_API_PASSWORD` refresh their token automatically and log in again when the refresh token expires.
- Work that continues after the browser is closed, such as a running Script Runner script, uses an [offline access token](/docs/getting-started/architecture#offline-access-token). It is controlled by the separate **Offline Session Idle** setting (default 30 days) on the same Sessions page. COSMOS refreshes stored offline tokens once a day, so with the defaults they only expire if COSMOS is stopped for longer than Offline Session Idle.
