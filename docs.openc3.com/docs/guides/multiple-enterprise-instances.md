---
title: Multiple Enterprise Instances
description: Run several COSMOS Enterprise installations, or use scopes instead, and share a single Keycloak for single sign-on
sidebar_custom_props:
  myEmoji: 🏢
---

Many organizations run more than one COSMOS Enterprise installation, for example separate development, test, and operations systems, or one system per mission or ground station. This guide covers how to decide whether you need separate installations and how to set them up so they work well together. Start with [Consider Scopes First](#consider-scopes-first). If you do need separate installations, read [Planning Separate Installations](#planning-separate-installations) and then set up a [Shared Keycloak](#shared-keycloak-for-single-sign-on) so users have one account across all of them.

## Consider Scopes First

Before you deploy a second installation, check whether [scopes](/docs/tools/admin#scopes-enterprise) meet your needs. A scope is a data boundary inside a single COSMOS Enterprise installation. Each scope has its own plugins, targets, scripts, telemetry, logs, and [secrets](/docs/guides/secrets), and users switch between their scopes from the scope dropdown in the top right corner of the COSMOS window. [Command Authority](/docs/configuration/command#command-authority-enterprise) and [Critical Commanding](/docs/configuration/command#critical-commanding-enterprise) are configured per scope, and roles are assigned per scope (for example `OPS__operator` and `TEST__viewer`), as described in [Roles and Permissions](/docs/guides/roles-permissions).

Scopes are often simpler than separate installations:

- You deploy, upgrade, back up, and monitor one system.
- Users log in once and see every scope their roles allow. There's only one Keycloak, so no extra setup is needed for single sign-on.
- Hardware is shared. Large deployments can spread the load with [operator and database sharding](/docs/getting-started/architecture#cosmos-enterprise-architecture).

Use separate installations when the systems must be independent of each other:

- **Different COSMOS versions.** All scopes run the same COSMOS version, so testing an upgrade needs its own installation.
- **Network isolation.** Systems on separate networks, such as a classified network and an unclassified one, or an air-gapped network, can't share a deployment.
- **Independent availability.** Restarting, upgrading, or losing one installation doesn't affect another. Scopes all go down together.
- **Resource isolation.** A heavy load in one scope competes for the same CPU, memory, and databases as the other scopes.
- **Data isolation.** Scopes are permission boundaries but admins typically have cross-scope data accessibility.

## Planning Separate Installations

### Hardware

Every installation runs its own full set of infrastructure: Traefik, both Rails APIs, the operator, both Valkey instances, QuestDB, bucket storage, Grafana, and the metrics service. That base load is paid once per installation, before any targets are added. [Hardware Requirements](/docs/guides/performance) can help you estimate Enterprise resource requirements.

Size each installation separately for its own targets and data rates. Disk is usually the resource that grows fastest, because each installation keeps its own logs in bucket storage and its own telemetry in QuestDB.

For production, put each installation on its own host or virtual machine so that a hardware failure, a full disk, or a heavy load only affects one installation. If you run several installations on one host, for example for development:

- Put each installation in its own project directory. Docker Compose names the containers and volumes after the directory, which keeps them separate.
- Give each installation its own host ports. Two installations can't both publish the same port, so change the host side of the Traefik ports (`2900` and `2943`) and any interface or router ports you've opened. The operator also publishes a fixed UDP port range for [bridges](/docs/guides/bridges). Docker Compose adds the ports in `compose.override.yaml` to the ones in `compose.yaml` instead of replacing them, so use `!override` to replace the list:

  ```yaml
  services:
    openc3-traefik:
      ports: !override
        - "127.0.0.1:3900:2900"
        - "127.0.0.1:3943:2943"
  ```

  Then update `OPENC3_EXTERNAL_URL` and `OPENC3_KEYCLOAK_EXTERNAL_URL` in `.env.local` to match the new port.

- QuestDB is the heaviest user of disk I/O and memory, so several QuestDB instances on one host can slow each other down.

In Kubernetes, give each installation its own namespace and Helm release. Set resource requests and limits so one installation can't starve the others on shared nodes.

### Upgrades and Downtime

[Upgrading](/docs/getting-started/upgrading) COSMOS restarts all of an installation's containers, so the installation is unavailable while the upgrade runs, and interfaces disconnect from their targets until it comes back up. With scopes, every scope is down at the same time. With separate installations, you can:

- Upgrade a test installation first and check your plugins, scripts, and screens against the new version before upgrading operations.
- Schedule each installation's upgrade around its own operations, for example between passes or outside a test campaign.
- Keep an installation on an older version until its users are ready to move.

Every installation must be upgraded on its own. Check the release notes for each upgrade, since migrations and changes to `compose.yaml` or `.env` apply to every installation you upgrade. Keep each installation's `compose.override.yaml` in version control so the upgrades are repeatable, and keep a secure backup of its `.env.local`, which holds its secrets and isn't checked in.

A [shared Keycloak](#shared-keycloak-for-single-sign-on) is the exception: it stays up while an installation upgrades, but upgrading or restarting Keycloak affects logins on every installation at once. Schedule Keycloak maintenance when all installations can tolerate it, and keep it at a Keycloak version that every COSMOS version you run supports.

### Targets and Interfaces

Decide which installation owns each target. Many targets accept only one connection, and two installations commanding the same hardware can conflict with each other. If a second installation needs the same telemetry, connect it through the owning installation, for example with a [router](/docs/configuration/plugins#router), rather than connecting both installations to the target.

### Plugins and Configuration

Each installation has its own plugins, so installing or upgrading a plugin on one installation doesn't change the others. Keep plugin source in version control and install the same built `.gem` on each installation, using plugin variables for the settings that differ, such as hostnames and ports. This makes it possible to test a plugin on one installation and then promote the same file to the next.

### Data

Installations don't share data. Telemetry history, command history, logs, scripts, screens, and tool configurations all live in the installation that created them, and a script or tool in one installation can't query another installation's data. If you later need data in another installation, for example to analyze test data alongside operations data, plan how to copy it across.

### Backups and Monitoring

[Back up](/docs/guides/backups) and [monitor](/docs/guides/monitoring) each installation separately. A shared Keycloak's PostgreSQL database needs its own backup, since it holds every user and role for all installations.

## Shared Keycloak for Single Sign-On

By default, every COSMOS Enterprise installation deploys its own Keycloak, backed by its own PostgreSQL database. With several installations, that means several separate user lists. Each user needs an account in every installation, password changes don't carry over, and moving users between installations requires [migrating them](/docs/guides/keycloak-user-migration).

Instead, you can run one standalone Keycloak and point every COSMOS Enterprise installation at it:

- Users and roles live in one place, and every installation sees the same accounts.
- Users who log in to one installation are already logged in to the others in the same browser.
- Password policies, multi-factor authentication, and identity provider or LDAP federation are configured once.
- You never need to migrate users when you add or rebuild an installation.

### Set Up the Standalone Keycloak

Deploy Keycloak, with its own PostgreSQL database, somewhere that both your users' browsers and every COSMOS installation can reach. Serve it over HTTPS with a stable hostname, for example `https://sso.example.com`.

You can use the `openc3-enterprise-keycloak` image that COSMOS Enterprise already ships. It serves Keycloak under `/auth` and imports the `openc3` realm from its built-in `realm.json` the first time it starts. Set these environment variables on it:

- `KC_HOSTNAME`: the public URL, for example `https://sso.example.com/auth`.
- `KC_DB_URL`, `KC_DB_USERNAME`, and `KC_DB_PASSWORD`: your PostgreSQL database.
- `KC_BOOTSTRAP_ADMIN_USERNAME` and `KC_BOOTSTRAP_ADMIN_PASSWORD`: the Keycloak admin account, created on the first start.
- `OPENC3_GRAFANA_CLIENT_SECRET`: a new secret for the `grafana` client. Keycloak only uses it when it first imports the realm, so set it before the first start. Otherwise the realm gets the default secret, which is the same in every COSMOS Enterprise installation.

You can also use a stock Keycloak and import the realm through **Create realm** in the Keycloak Admin Console, using the `realm.json` from the `openc3-enterprise-keycloak` directory of your COSMOS Enterprise project. A stock Keycloak serves from `/` instead of `/auth` unless you set `KC_HTTP_RELATIVE_PATH=/auth`, so leave `/auth` out of the URLs below if you don't set it.

The imported realm is meant for a single local installation, so update it before you put users on it:

- **Remove or change the demo users.** The realm comes with example users such as `admin`, `operator`, and `viewer` that have well-known passwords.
- **Add each installation to the `api` client.** Open **Clients** > **api** and add every installation's URL to **Valid redirect URIs** (for example `https://cosmos-ops.example.com/*` and `https://cosmos-test.example.com/*`). Also add each URL to **Web origins**, or leave it set to `*`. To give each installation its own client instead, create a public client per installation with the same settings as `api` and set that installation's client ID as described below.
- **Add each installation to the `grafana` client.** Add every installation's `/grafana/login/generic_oauth` URL to **Valid redirect URIs**. If you didn't set `OPENC3_GRAFANA_CLIENT_SECRET` before the first start, or you imported the realm into a stock Keycloak, regenerate the secret on the client's **Credentials** tab. Every installation uses this one secret.

Keycloak is now shared by every installation, so plan for it to be highly available. If it's down, no one can log in to any installation, and logged-in users are logged out when their access token expires (5 minutes by default). Run more than one Keycloak node if you can, and back up its PostgreSQL database.

### Point Each COSMOS Installation at the Shared Keycloak

:::note
These steps are for COSMOS Enterprise _Coming Soon_ and later, where Grafana reads its Keycloak settings from the same environment variables as the rest of COSMOS. In earlier versions, also change the Keycloak URLs and `client_secret` in `openc3-enterprise-grafana/grafana.ini`.
:::

Each installation needs to know the Keycloak URL that browsers use, the Keycloak URL that the COSMOS containers and Grafana use, the realm, the client ID, and the `grafana` client secret. Usually both URLs are the shared Keycloak's public URL. They differ only if the containers have to reach Keycloak through a different address than browsers do.

If Keycloak's certificate is signed by a private certificate authority, add that certificate authority to the `cacert.pem` file in your COSMOS Enterprise project (or the `openc3-cacert` secret in Kubernetes) so the COSMOS containers trust it.

#### Docker Compose

Don't edit `compose.yaml`. COSMOS upgrades replace it. Make all the changes in `.env.local` and `compose.override.yaml`, which upgrades never touch.

Set the Keycloak settings in `.env.local`:

```bash
OPENC3_KEYCLOAK_EXTERNAL_URL=https://sso.example.com/auth
OPENC3_KEYCLOAK_URL=https://sso.example.com/auth
OPENC3_KEYCLOAK_REALM=openc3
OPENC3_API_CLIENT=api
OPENC3_GRAFANA_CLIENT_SECRET=<the grafana client secret>
```

`compose.yaml` passes these to every COSMOS container and to Grafana, so no other changes are needed for COSMOS or Grafana to use the shared Keycloak.

Next, turn off the bundled Keycloak and PostgreSQL in `compose.override.yaml`. If you don't have one yet, copy `compose.override.example.yaml` to `compose.override.yaml` to start. Docker Compose only starts a service with `profiles` when that profile is turned on, and `openc3.sh` never turns this one on, so the two services and their volumes are left out:

```yaml
services:
  openc3-keycloak:
    profiles: ["bundled-keycloak"]
  openc3-postgresql:
    profiles: ["bundled-keycloak"]
```

Browsers now go straight to the shared Keycloak, so the `/auth` route in COSMOS's Traefik configuration isn't used. It's safe to leave, but requests to `/auth` on the COSMOS host return an error. To remove it, copy the Traefik file your installation uses (`openc3-enterprise-traefik/traefik.yaml` by default) to a new file, delete `keycloak-router` and `service-keycloak` from the copy, and mount the copy in `compose.override.yaml`. Docker Compose replaces the default file because both mounts use the same path in the container:

```yaml
services:
  openc3-traefik:
    volumes:
      - "./openc3-enterprise-traefik/traefik-shared-sso.yaml:/etc/traefik/traefik.yaml:z"
```

The copy doesn't get updates to the default Traefik file, so compare the two after each upgrade.

#### Kubernetes

In the values for the `openc3` chart, turn off the bundled Keycloak and point COSMOS at the shared one. Grafana uses the same settings:

```yaml
keycloak:
  enabled: false
  url: https://sso.example.com/auth
  externalUrl: https://sso.example.com/auth
  clientId: api
  realm: openc3
```

Grafana reads the `grafana` client secret from the `client-secret` key of a secret named `openc3-grafana`. Create it in each installation's namespace:

```bash
kubectl create secret generic openc3-grafana --from-literal=client-secret='<the grafana client secret>'
```

PostgreSQL is only used by Keycloak, so also turn it off in the values for the `openc3-db` chart:

```yaml
postgresql:
  enabled: false
```

### Roles Across Installations

COSMOS reads a user's roles from the Keycloak realm roles in their token, named `{SCOPE}__{ROLE_NAME}` (see [Roles and Permissions](/docs/guides/roles-permissions)). Every installation that uses the same realm sees the same roles, so a role means the same thing everywhere:

- `DEFAULT__operator` makes the user an operator in the `DEFAULT` scope of **every** installation.
- `ALLSCOPES__admin` makes the user a superadmin on **every** installation.

If users should have different permissions on different installations, give each installation its own scope names. For example, create an `OPS` scope on the operations installation and a `TEST` scope on the test installation, and assign roles like `OPS__operator` and `TEST__admin`. A role for a scope that doesn't exist on an installation has no effect there. Use `ALLSCOPES` roles only for users who should have that role on every installation.

Custom roles are defined in each COSMOS installation, so create the custom role's definition on every installation where it's used. The matching Keycloak realm role only needs to be created once.

Tokens are signed by the realm, and every installation accepts any valid token from it. An access token or [offline access token](/docs/getting-started/architecture#offline-access-token) a user got from one installation also works for API calls to the others, with the same roles.

:::note[Separate realms are not single sign-on]
You can also give each installation its own realm on the shared Keycloak by setting a different realm name. That keeps roles fully separate and you only run one Keycloak, but each realm has its own users and passwords, so users still need an account in every realm.
:::

### Moving Existing Installations to a Shared Keycloak

If your installations already have their own Keycloak, [migrate their users](/docs/guides/keycloak-user-migration) into the shared Keycloak once, then point each installation at it as described above. If the same username exists in more than one source Keycloak, the partial import's **Skip** option keeps the first one imported, so check those users' roles afterward.
