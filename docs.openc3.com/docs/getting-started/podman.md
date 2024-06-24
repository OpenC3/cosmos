---
sidebar_position: 7
title: Podman
---

### OpenC3 COSMOS Using Rootless Podman and Docker-Compose

:::info Optional Installation Option
These directions are for installing and running COSMOS using Podman instead of Docker. If you have Docker available, that is a simpler method.
:::

Podman is an alternative container technology to Docker that is actively promoted by RedHat. The key benefit is that Podman can run without a root-level daemon service, making it significantly more secure by design, over standard Docker. However, it is a little more complicated to use. These directions will get you up and running with Podman. The following directions have been tested against RHEL 8.8, and RHEL 9.2, but should be similar on other operating systems.

:::warning Rootless Podman Does Not Work (Directly) with NFS Home Directories
NFS does not work for holding container storage due to issues with user ids and group ids. There are workarounds available but they all involve moving container storage to another location: either a different partition on the host local disk, or into a special mounted disk image. See: [https://www.redhat.com/sysadmin/rootless-podman-nfs]https://www.redhat.com/sysadmin/rootless-podman-nfs). Note that there is also a newish Podman setting that allows you to more easily change where the storage location is in /etc/containers/storage.conf called rootless_storage_path. See [https://www.redhat.com/sysadmin/nfs-rootless-podman](https://www.redhat.com/sysadmin/nfs-rootless-podman)
:::

# Redhat 8.8 and 9.2 Instructions

1. Install Prerequisite Packages

   Note: This downloads and installs docker-compose from the latest 2.x release on Github. If your operating system has a docker-compose package, it will be easier to install using that instead. RHEL8 does not have a docker-compose package.

   ```bash
   sudo yum update
   sudo yum install git podman-docker netavark
   curl -SL https://github.com/docker/compose/releases/download/v2.16.0/docker-compose-linux-x86_64 -o docker-compose
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

1. Configure Podman to use Netavark for DNS

   ```bash
   sudo cp /usr/share/containers/containers.conf /etc/containers/.
   sudo vi /etc/containers/containers.conf
   ```

   Then edit the network_backend line to be "netavark" instead of "cni"

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

1. Edit cosmos/compose.yaml

   ```bash
   cd cosmos
   vi compose.yaml
   ```

   Edit compose.yaml and uncomment the user: 0:0 lines and comment the user: `"${OPENC3_USER_ID}:${OPENC3_GROUP_ID}"` lines.
   You may also want to update the traefik configuration to allow access from the internet by removing 127.0.0.1 and probably switching to either an SSL config file, or the allow http one. Also make sure your firewall allows
   whatever port you choose to use in. Rootless podman will need to use a higher numbered port (not 1-1023).

1. Run COSMOS

   ```bash
   ./openc3.sh run
   ```

1. Wait until everything is built and running and then goto http://localhost:2900 in your browser

:::info Podman on MacOS
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
   # Note: update to your username in the next line or copy paste from what 'podman machine start' says
   export DOCKER_HOST='unix:///Users/ryanmelt/.local/share/containers/podman/machine/qemu/podman.sock'
   ```

1. Install docker-compose

   ```bash
   brew install docker-compose # Optional if you already have Docker Desktop
   ```

1. Edit cosmos/compose.yaml

   Edit compose.yaml and uncomment the user: 0:0 lines and comment the user: `"${OPENC3_USER_ID}:${OPENC3_GROUP_ID}"` lines.

   Important: on MacOS you must also remove all :z from the volume mount lines

   You may also want to update the traefik configuration to allow access from the internet.

1. Run COSMOS

   ```bash
   cd cosmos
   ./openc3.sh run
   ```
