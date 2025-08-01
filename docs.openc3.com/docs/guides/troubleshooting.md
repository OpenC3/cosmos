---
title: Troubleshooting
description: How to solve various issues we've encountered
sidebar_custom_props:
  myEmoji: 🤔
---

We've seen a number of issues deploying COSMOS via Docker in various types of installations from single server to the cloud. This page captures some of the subtle issues we've discovered and ways to solve the problem. NOTE: Don't forget to also search our [Github Issues](https://github.com/OpenC3/cosmos/issues) (hit '/' and start typing).

1. After dozens of installed targets and interfaces, the CmdTlmServer logs indicate "unable to create thread". Microservices are crashing or not starting.

   This is typically due to hard limits on processes or file handles imposed by Linux. If you're on Podman, ensure you've followed the directions from the [Podman](/docs/getting-started/podman) page and have increased the `pids_limit` in `/etc/containers/containers.conf`. Also check your `ulimit` variables by typing `ulimit -a` and increase your file descriptors (`ulimit -t 65536`).

1. COSMOS becomes slow or unresponsive especially as additional plugins are added

   You may be maxing out your system. If you're on Enterprise you can check the [System Health Tool](/docs/tools/systemhealth). Exec into the operator container (runs all the microservices) and see what the utilization is. NOTE: The container name may be different but you find it with `docker ps`.

   ```bash
   docker ps
   docker exec -it cosmos-openc3-operator-1 sh
   $ htop
   ```

   Check your memory utilization and CPU utilization. Is a single core pegged? You may need to distribute your workload better.

   If you're running Docker Desktop (Windows or Mac OS) you can update the Settings / Resources to add additional CPUs or Memory.

1. You're getting "too many files open" errors

   Check your `ulimit` variables by typing `ulimit -a` and increase your file descriptors `ulimit -t 65536`. Note that you may want to put this in your `.bashrc`, `.zshrc`, etc to make this permanent.

1. You get networking errors (without certificates)

   Make sure you're using `127.0.0.1` instead of `localhost`. Sometimes we've seen `localhost` get mapped to `::1` (IPV6) instead of `127.0.0.1` (IPV4) which typically breaks things.

   Check your `/etc/resolve.conf` and make sure you don't have any `search` entries. You should have simple `nameserver` entries.

   If you're on RHEL 9.x with rootless Podman make sure you've followed the directions from the [Podman](/docs/getting-started/podman) page and have configured Podman to use Netavark for DNS.

1. You've enabled certificates and you're getting networking errors

   Make sure you've read both the [SSL-TLS](/docs/configuration/ssl-tls) docs and the [COSMOS Enterprise Project](https://github.com/OpenC3/cosmos-enterprise-project?tab=readme-ov-file#opening-to-the-network) instructions.

1. You're getting 404 errors, missing icons, missing tools or functionality

   This is typically because the init container did not finish successfully. First examine the docker logs. NOTE: The container name maybe different but you find it with `docker ps -a`.

   ```bash
   docker ps -a
   docker logs cosmos-openc3-cosmos-init-1
   ```

   Next ensure the files are actually present by execing into the operator container and checking. NOTE: The container name may be different but you find it with `docker ps`.

   ```bash
   docker ps
   docker exec -it cosmos-openc3-operator-1 sh
   $ cd /gems/gems/
   $ ls
   $ cd openc3-tool-base-6.6.1.pre.beta0.20250718002117/tools/base
   $ ls
   ```

   In the above example we're making sure the tools/base files are there. You can `cd` into any of the tools and ensure the files are present.

1. On Windows, when using bind mounts in Docker compose, the system "locks up" and screens show "TooManyRequests" error

   We've seen this on old versions of Docker Desktop when using bind mounts instead of named volumes. Our docker compose files use named volumes by default so be careful with bind mounts. We also recommend upgrading Docker Desktop and WLS2 if possible as this maybe OBE in newer versions of Docker Desktop / WSL2.

1. When exposing COSMOS to the network through http, Chrome [DevTools](https://developer.chrome.com/docs/devtools/open) shows "Web crypto API is not avilable".

   Make sure to follow all the instructions in the [COSMOS Enterprise Project README](https://github.com/OpenC3/cosmos-enterprise-project/blob/main/README.md). In this case you need to do the following:

   - In Chrome go to: chrome://flags/#unsafely-treat-insecure-origin-as-secure
   - Add your http://&lt;Your IP Address&gt;:2900
   - Enable the Setting
   - Completely restart Chrome. On MacOS make sure the dot below the icon in chrome is gone by long pressing the icon and choosing Quit.

Encountering an issue not on this list? If you're a customer, please get in touch at [support@openc3.com](mailto:support@openc3.com).
