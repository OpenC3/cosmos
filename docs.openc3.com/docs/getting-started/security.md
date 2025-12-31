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

The load balancer routes specific paths to MinIO or the COSMOS APIs, making them available to the outside network through the same hostname as the load balancer. In COSMOS Enterprise, Keycloak is also routed through the load balancer.

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

For production use, it is recommended to open COSMOS to the network and run clients from other machines. This removes browser load from the host computer and allows better securing of the host. See [SSL/TLS](../configuration/ssl-tls) for configuring HTTPS.

### Network Security

Between any external network and the private network containing the host computer should be a firewall that prevents unauthorized access.

Exposing COSMOS directly to the public internet is not recommended. While the system itself is secure, there is no built-in denial of service (DOS) protection, and an adversary could overwhelm the system with requests.

## Runtime Secrets in Docker

There are two ways to pass runtime secrets into containers: environment variables and mounted files.

Environment variables passed to containers can be sourced from host environment variables or from a `.env` file. Files mounted into containers must exist as local files accessible by the user starting COSMOS.

In both cases, secrets need to be available to the user account starting COSMOS. This account must have sufficient trust to control container lifecycles and all data within the containers.

Most standard containers for databases like MinIO are set up to receive secrets through environment variables. For a thorough discussion of secrets in Docker, see the [official thread](https://github.com/moby/moby/issues/13490).

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

### MinIO (S3 Storage) Credentials

MinIO provides S3-compatible object storage for logs, configurations, and other files.

| Variable                    | Default Value               | Description                             |
| --------------------------- | --------------------------- | --------------------------------------- |
| `OPENC3_BUCKET_USERNAME`    | `openc3minio`               | Root username for MinIO                 |
| `OPENC3_BUCKET_PASSWORD`    | `openc3miniopassword`       | Root password for MinIO                 |
| `OPENC3_SR_BUCKET_USERNAME` | `scriptrunnerminio`         | Username passed to spawned user scripts |
| `OPENC3_SR_BUCKET_PASSWORD` | `scriptrunnerminiopassword` | Password passed to spawned user scripts |

The `OPENC3_BUCKET_*` credentials are the MinIO root credentials used by COSMOS services to manage buckets and files.

The `OPENC3_SR_BUCKET_*` credentials create a separate MinIO user with limited permissions. Similar to the Redis credentials, these are passed to **spawned user scripts** rather than being used by the script-runner-api itself, following the principle of least privilege.

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

The `users.acl` file (located at `openc3-redis/users.acl`) configures Redis authentication and authorization. This file is **only for Redis** and has no relation to MinIO or other services.

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

**healthcheck**: Used during container startup to verify Redis is available. Has no password and can only run `cluster info` and `ping` commands.

### Relationship Between .env and users.acl

The passwords in `.env` must match the passwords in `users.acl`:

| .env Variable              | users.acl User | Must Match                                                      |
| -------------------------- | -------------- | --------------------------------------------------------------- |
| `OPENC3_REDIS_PASSWORD`    | `openc3`       | Yes - COSMOS services use these credentials to connect to Redis |
| `OPENC3_SR_REDIS_PASSWORD` | `scriptrunner` | Yes - Spawned user scripts use these credentials                |

The `admin` user in `users.acl` does not have a corresponding `.env` variable since it's only used for manual Redis administration.

The MinIO credentials (`OPENC3_BUCKET_*`, `OPENC3_SR_BUCKET_*`) and `OPENC3_SERVICE_PASSWORD` have no corresponding entries in `users.acl` since they are for different services.

## Securing Your Deployment

### Changing Redis Passwords

1. Generate a SHA-256 hash of your new password:

   ```bash
   ./openc3.sh util hash yournewpassword
   ```

2. Update `openc3-redis/users.acl` with the new hash:

   ```
   user openc3 on #newhashvalue allkeys allchannels ...
   ```

3. Update `.env` with the new cleartext password:

   ```
   OPENC3_REDIS_PASSWORD=yournewpassword
   ```

4. Repeat for the `scriptrunner` user if desired.

### Changing MinIO Passwords

Update the values in `.env`:

```
OPENC3_BUCKET_PASSWORD=yournewpassword
OPENC3_SR_BUCKET_PASSWORD=yournewsrpassword
```

### Changing the Service Password

Update the value in `.env`:

```
OPENC3_SERVICE_PASSWORD=yournewservicepassword
```

### Generating a New SECRET_KEY_BASE

```bash
openssl rand -hex 64
```

Then update `.env` with the new value.

### Removing Cleartext Passwords from .env

For enhanced security, you can remove passwords from the `.env` file entirely and pass them as environment variables at runtime:

```bash
OPENC3_REDIS_PASSWORD=mypassword OPENC3_BUCKET_PASSWORD=mypassword ./openc3.sh run
```

This prevents cleartext passwords from being stored on disk, though you must provide them each time you start COSMOS.

## Security Recommendations

For production deployments:

1. **Change all default passwords** before deploying COSMOS.

2. **Use hashed passwords** in `users.acl` to avoid storing cleartext passwords on disk.

3. **Restrict file permissions** on `.env` and `users.acl`:

   ```bash
   chmod 600 .env
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
