---
title: Podman
description: Installing and running COSMOS with Podman
sidebar_custom_props:
  myEmoji: 🫛
---

### OpenC3 COSMOS Using Rootless Podman and Docker-Compose

:::info[Optional Installation Option]
These directions are for installing and running COSMOS using Podman instead of Docker. If you have Docker available, that is a simpler method.
:::

Podman is an alternative container technology to Docker that is actively promoted by RedHat. The key benefit is that Podman can run without a root-level daemon service, making it significantly more secure by design, over standard Docker. However, it is a little more complicated to use. These directions will get you up and running with Podman. The following directions have been tested against RHEL 8 and RHEL 9, but should be similar on other operating systems.

:::warning[Rootless Podman Does Not Work (Directly) with NFS Home Directories]
NFS does not work for holding container storage due to issues with user ids and group ids. There are workarounds available but they all involve moving container storage to another location: either a different partition on the host local disk, or into a special mounted disk image. See: [https://www.redhat.com/sysadmin/rootless-podman-nfs](https://www.redhat.com/sysadmin/rootless-podman-nfs). Note that there is also a newish Podman setting that allows you to more easily change where the storage location is in /etc/containers/storage.conf called rootless_storage_path. See [https://www.redhat.com/sysadmin/nfs-rootless-podman](https://www.redhat.com/sysadmin/nfs-rootless-podman)
:::

## How COSMOS Detects Podman

`openc3.sh` detects your container runtime and whether it is running rootless, so there is nothing to edit in `compose.yaml`:

- It uses `docker` if present, otherwise `podman`.
- For the compose command it tries `<runtime> compose` first and falls back to the standalone `docker-compose`. `podman-compose` is **not** supported - install `docker-compose` (note that `podman compose` also delegates to `docker-compose` when it is installed).
- It runs `<runtime> info` and looks for `rootless`. When rootless Podman is detected it exports `OPENC3_USER_ID=0` and `OPENC3_GROUP_ID=0`, which is what the `user: "${OPENC3_USER_ID:-1001}:${OPENC3_GROUP_ID:-1001}"` lines in `compose.yaml` consume. Rootless Podman maps that container-side root back to your unprivileged host user, so the containers still run without privileges on the host.

:::warning[Do not edit compose.yaml]
Older versions of this guide told you to uncomment `user: 0:0` lines in `compose.yaml`, that has been removed. `openc3.sh` now handles the user ids automatically. Put any customization you need in `compose.override.yaml` (non-secret settings) or `.env.local` (passwords and keys) instead - see [Docker Compose](/docs/configuration/compose).
:::

# Redhat 8 and 9 Instructions

1. Install Prerequisite Packages

   Note: This downloads and installs the latest docker-compose release from Github. If your operating system has a docker-compose package, it will be easier to install using that instead. RHEL8 does not have a docker-compose package.

   ```bash
   sudo yum update
   sudo yum install git podman podman-docker netavark
   curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o docker-compose
   sudo mv docker-compose /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
   sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
   ```

1. Configure Host OS for Redis

   ```bash
   sudo su
   echo never > /sys/kernel/mm/transparent_hugepage/enabled
   echo never > /sys/kernel/mm/transparent_hugepage/defrag
   sysctl -w vm.max_map_count=262144
   exit
   ```

   Note that these are not persistent across reboots. To make `vm.max_map_count` permanent:

   ```bash
   sudo sh -c 'echo "vm.max_map_count=262144" > /etc/sysctl.d/99-openc3.conf'
   ```

1. Configure Podman to increase the PID limit

   ```bash
   sudo cp /usr/share/containers/containers.conf /etc/containers/.
   sudo vi /etc/containers/containers.conf
   ```

   Then edit the `pids_limit` value to -1 (unlimited)

1. Configure Podman to use Netavark for DNS

   ```bash
   sudo sh -c 'echo ip_tables > /etc/modules-load.d/ip_tables.conf'
   sudo vi /etc/containers/containers.conf
   ```

   Then edit the network_backend line to be "netavark" instead of "cni"

   Note that Podman 5 uses netavark by default, so on a current RHEL 9 install the `network_backend` line may already be correct or absent. Verify with `podman info --format '{{.Host.NetworkBackend}}'`.

:::warning[Netavark needs the ip_tables module]
The above "echo ip_tables" line is added because RHEL 9.x uses nftables by default. The legacy ip_tables kernel module is not guaranteed to be loaded at boot — particularly on cloud images such as AWS EC2. However, netavark still requires ip_tables to implement NAT and forwarding for rootless Podman containers. Rootless users cannot load kernel modules, so if ip_tables is missing, netavark networking fails silently. If using rootless Podman with netavark ensure the ip_tables kernel module is preload.
:::

## File Descriptor and Memory Limits

COSMOS runs many processes across the containers and rootless Podman cannot raise a limit above the hard limit of the user that started it. Check your limits:

```bash
ulimit -a
```

If `open files` (`ulimit -n`) is low, raise it - typically by adding a line to `/etc/security/limits.d/` (for example `* hard nofile 1048576`) and logging back in. See also the [Troubleshooting](/docs/guides/troubleshooting) page.

The `openc3-tsdb` service in `compose.yaml` requests `nofile` of 1048576 and unlimited `memlock`. If your host cannot grant those, the container fails to start with an error about setting rlimits. Lower them in `compose.override.yaml` to something your system allows:

```yaml
services:
  openc3-tsdb:
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
      memlock:
        soft: 65536
        hard: 65536
```

These values are system specific - use the largest values your host allows.

## Configure the Podman User

The following instructions must be performed for each user using COSMOS. Individual podman users store their own container image in their local home directory. This is especially important if you're in an airgapped environment as you will need to [load](/docs/getting-started/cli#load) the containers for each user.

1. Start rootless podman socket service

   ```bash
   systemctl enable --now --user podman.socket
   ```

1. Put the following into your .bashrc file (or .bash_profile or whatever)

   ```bash
   export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
   ```

1. Source the profile file for your current terminal

   ```bash
   source .bashrc
   ```

1. Get COSMOS - A release or the current main branch (main branch shown)

   ```bash
   git clone https://github.com/OpenC3/cosmos.git
   ```

1. Optional - Set Default Container Registry

   If you don't want podman to keep querying you for which registry to use, you can create a $HOME/.config/containers/registries.conf and modify to just have the main docker registry (or modify the /etc/containers/registries.conf file directly)

   ```bash
   mkdir -p $HOME/.config/containers
   cp /etc/containers/registries.conf $HOME/.config/containers/.
   vi $HOME/.config/containers/registries.conf
   ```

   Then edit the unqualified-search-registries = line to just have the registry you care about (probably docker.io)

1. Customize your deployment

   Do not edit `compose.yaml` or `.env` - `openc3.sh` merges `compose.override.yaml` on top of `compose.yaml` and loads `.env.local` after `.env`, so your changes survive a COSMOS upgrade. See [Docker Compose](/docs/configuration/compose) for the full details. Common Podman changes:

   - By default Traefik only listens on `127.0.0.1:2900` and `127.0.0.1:2943`. To allow access from other machines, republish the ports in `compose.override.yaml` without the `127.0.0.1` prefix. Rootless Podman cannot bind privileged ports, so choose a port above 1023 (or set `net.ipv4.ip_unprivileged_port_start`). Make sure your firewall allows the port you choose.
   - To allow HTTP (rather than HTTPS) connections, set `OPENC3_ALLOW_HTTP=1` under the `openc3-traefik` service's `environment:` in `compose.override.yaml`. For a real deployment use an SSL config instead - see [SSL-TLS](/docs/configuration/ssl-tls).
   - Set `OPENC3_EXTERNAL_URL` in `.env.local` to the URL users will browse to.

   ```yaml
   services:
     openc3-traefik:
       ports:
         - "2900:2900"
         - "2943:2943"
       environment:
         - OPENC3_ALLOW_HTTP=1
   ```

   :::warning[compose.override.yaml cannot be empty under Podman]
   COSMOS ships `compose.override.yaml` with everything commented out. Docker Compose accepts that, but a Podman build rejects a compose file with no content. If you hit an error parsing the override file, either delete it or give it a single valid key:

   ```yaml
   services: {}
   ```

   :::

1. Run COSMOS

   ```bash
   cd cosmos
   ./openc3.sh run
   ```

1. Wait until everything is built and running and then goto http://localhost:2900 in your browser

:::info[Podman on MacOS]
Podman can also be used on MacOS, though we still generally recommend Docker Desktop
:::

## MacOS Instructions

1. Install podman

   ```bash
   brew install podman
   ```

1. Start the podman virtual machine

   ```bash
   podman machine init
   podman machine start
   ```

   `podman machine start` prints the `DOCKER_HOST` value to use - the socket path depends on your username and the machine's VM provider. Copy it from that output, or derive it:

   ```bash
   export DOCKER_HOST=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' | sed 's|^|unix://|')
   ```

1. Install docker-compose (Optional if you already have Docker Desktop)

   ```bash
   brew install docker-compose
   ```

1. Run COSMOS

   ```bash
   cd cosmos
   ./openc3.sh run
   ```

   If a container fails to start because of an SELinux relabel error on a bind mount, remove the `:z` suffix from that mount by redeclaring it in `compose.override.yaml`. Compose merges volumes by their container-side path, so listing the same target without `:z` replaces the original:

   ```yaml
   services:
     openc3-traefik:
       volumes:
         - "./cacert.pem:/devel/cacert.pem"
         - "./openc3-traefik/traefik.yaml:/etc/traefik/traefik.yaml"
   ```
