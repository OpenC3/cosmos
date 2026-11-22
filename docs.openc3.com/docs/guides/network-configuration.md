---
title: Network Configuration
description: Opening COSMOS to the network with HTTPS or HTTP
sidebar_custom_props:
  myEmoji: 🌐
---

By default COSMOS only listens on localhost (127.0.0.1), so it can only be reached from a browser on the host computer. This guide describes how to open COSMOS to the network so users can connect from their own workstations.

:::warning[Change all default credentials first]
Before exposing COSMOS to any network, even a local network, change all default credentials and secrets. See [Securing Your Deployment](/docs/getting-started/security#securing-your-deployment).
:::

COSMOS supports four network configurations:

1. **Only accessible from localhost** - the default. Great for single terminal access and development.
2. **Open to the network using HTTPS with your own certificates** - **recommended for production**.
3. **Open to the network using HTTPS with Let's Encrypt certificates** - requires the server to be reachable from the public internet, which is generally not recommended.
4. **Open to the network using HTTP** - supported, but passwords and data are sent unencrypted. Use HTTPS whenever you can.

## Where to Make Changes

Don't edit `.env` or `compose.yaml`. They ship the upstream defaults, and editing them causes conflicts every time you upgrade COSMOS. Instead:

- Put environment variable values in `.env.local`, next to `.env`. It is gitignored and loaded after `.env`, so its values win. See [Environment Variables](/docs/configuration/environment).
- Put service changes (ports, volumes, per-service variables) in `compose.override.yaml`, which `openc3.sh` merges on top of `compose.yaml` automatically. See [Docker Compose](/docs/configuration/compose).

Each service can only appear once in `compose.override.yaml`. If this guide and another guide both add entries for the same service (such as `openc3-traefik`), combine them into a single block for that service. YAML keeps only the last of two identical keys, so a repeated service name silently discards the first block.

## Changes Required for All Network Configurations

COSMOS Core needs no changes in this step. Skip to [Choose a Configuration](#choose-a-configuration).

COSMOS Enterprise needs the external URL users will browse to: the correct scheme, domain or IP address, and port. The example below uses `https://mydomain.com`.

In `.env.local`, set the COSMOS and Keycloak external URLs:

```sh
OPENC3_EXTERNAL_URL=https://mydomain.com
OPENC3_KEYCLOAK_EXTERNAL_URL=https://mydomain.com/auth
```

A variable exported in your shell overrides `.env.local`, so if either one is exported, unset it or change it before starting COSMOS.

That is the only file change needed. `compose.yaml` passes these values to Keycloak (its `KC_HOSTNAME`) and to Grafana, whose `grafana.ini` and COSMOS data source are built into its image and read them from the environment, so you don't edit any Keycloak or Grafana files. Keycloak itself must also accept the new URL: add it to the valid redirect URIs of the `api` and `grafana` clients as described in [Keycloak Configuration](https://repos.openc3.com/OpenC3/cosmos-enterprise-project/src/branch/main/KeycloakConfiguration.md#updating-the-redirect-url).

Leave `OPENC3_KEYCLOAK_URL` set to the internal service URL `http://openc3-keycloak:8080/auth`. COSMOS containers, including Grafana, use it to talk to Keycloak directly.

To change any other Grafana setting, add a `GF_<SECTION>_<KEY>` variable to the `openc3-grafana` service in `compose.override.yaml`, e.g. `GF_LOG_LEVEL=debug` for `level` under `[log]`. If you regenerate the secret of the Keycloak `grafana` client, set `OPENC3_GRAFANA_CLIENT_SECRET` in `.env.local`.

:::note[Upgrading from 7.5.1 or earlier]
Earlier releases had you set `KC_HOSTNAME` in `compose.override.yaml` and edit `openc3-enterprise-grafana/cosmos.yaml` and `grafana.ini` directly. Those files are no longer used. The upgrade (or the first `openc3.sh run` afterwards, if an older upgrade script did the upgrade) migrates them for you: it moves a changed client secret into `.env.local`, prints any other changed setting as the `GF_` line to add to `compose.override.yaml`, and saves copies as `.bak` files. Once the two URLs are in `.env.local`, you can remove the `KC_HOSTNAME` entry from your `compose.override.yaml`.
:::

## Choose a Configuration

### HTTPS with Your Own Certificates

This is the recommended production configuration. In general you should ask your IT department for a domain name and associated certificates. Follow [Using TLS and your own certificates](/docs/configuration/ssl-tls#using-tls-and-your-own-certificates) in the SSL-TLS guide, which also explains how to make test certificates with mkcert and add a private certificate authority to `cacert.pem`.

### HTTPS with Let's Encrypt

Only use this when COSMOS is exposed to the public internet. Make sure you understand the risks and have properly configured your server settings and firewall. Follow [Using a global certificate from Let's Encrypt](/docs/configuration/ssl-tls#using-a-global-certificate-from-lets-encrypt) in the SSL-TLS guide.

### HTTP

:::warning[HTTP sends passwords in plain text]
Only use HTTP on a network you trust, such as for temporary testing on a local network or over an encrypted VPN like Tailscale. We recommend HTTPS for everything else. The COSMOS Enterprise [MCP Server](/docs/guides/mcp-server) requires HTTPS.
:::

1. For COSMOS Enterprise, use `http://` and your IP address or domain and port in the [changes required for all network configurations](#changes-required-for-all-network-configurations), for example `http://192.168.1.10:2900` and `http://192.168.1.10:2900/auth`.

2. In `compose.override.yaml`, allow HTTP in the Traefik Content Security Policy and listen on all interfaces instead of only localhost. `!override` replaces the `ports` list from `compose.yaml` rather than adding to it. Change the first port number if desired, but leave the second `2900`:

   ```yaml
   services:
     openc3-traefik:
       environment:
         - OPENC3_ALLOW_HTTP=1
       ports: !override
         - "2900:2900"
   ```

   You can set `OPENC3_ALLOW_HTTP=1` in `.env.local` instead of the `environment:` entry.

3. Browsers restrict some features on insecure origins. In Chrome go to `chrome://flags/#unsafely-treat-insecure-origin-as-secure`, or in Edge go to `edge://flags/#unsafely-treat-insecure-origin-as-secure`:
   1. Add `http://<Your IP Address>:<Port>`, using the published port from the previous step (for example `http://192.168.1.10:2900`)
   2. Enable the setting
   3. Completely restart the browser. On macOS make sure the dot below the Chrome icon is gone by long-pressing the icon and choosing Quit.

## Start COSMOS

1. Start COSMOS with `./openc3.sh run` (Linux/Mac) or `openc3.bat run` (Windows).
2. After approximately 2 minutes, open a web browser to your COSMOS URL. If you run `docker ps`, you can watch until the init container completes, at which point the system is fully configured and ready to use.
3. COSMOS Enterprise: **IMPORTANT** - you must configure Keycloak before the main COSMOS app and Grafana will work (you'll just see a solid color page until you do). Open your Keycloak URL (for example `https://mydomain.com/auth/`) and follow the [Keycloak Configuration](https://repos.openc3.com/OpenC3/cosmos-enterprise-project/src/branch/main/KeycloakConfiguration.md) documentation.
