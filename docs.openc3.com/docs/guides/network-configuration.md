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

COSMOS Enterprise needs the external URL users will browse to (the correct scheme, domain or IP address, and port) in several places. The examples below use `https://mydomain.com`.

1. In `.env.local`, set the COSMOS and Keycloak external URLs:

   ```sh
   OPENC3_EXTERNAL_URL=https://mydomain.com
   OPENC3_KEYCLOAK_EXTERNAL_URL=https://mydomain.com/auth
   ```

   Leave `OPENC3_KEYCLOAK_URL` set to the internal service URL `http://openc3-keycloak:8080/auth`. COSMOS containers use it to talk to Keycloak directly.

2. In `compose.override.yaml`, set the Keycloak hostname to the same URL as `OPENC3_KEYCLOAK_EXTERNAL_URL`:

   ```yaml
   services:
     openc3-keycloak:
       environment:
         KC_HOSTNAME: "https://mydomain.com/auth"
   ```

3. Edit `openc3-enterprise-grafana/cosmos.yaml` and change the `cosmosUrl` and `keycloakUrl` settings to the correct scheme, domain, and port. Keep `/auth` if present.

4. Edit `openc3-enterprise-grafana/grafana.ini` and change the `root_url`, `auth_url`, `token_url`, and `api_url` settings to the correct scheme, domain, and port. Leave any additional path information.

The Grafana files are tracked in the project, so check these edits again after upgrading COSMOS.

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
