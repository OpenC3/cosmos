---
sidebar_position: 2
title: Installation
description: Installing OpenC3 COSMOS
sidebar_custom_props:
  myEmoji: 💾
---

## Installing OpenC3 COSMOS

The following sections describe how to get OpenC3 COSMOS installed on various operating systems. This document should help you setup you host machine to allow you to have a running version of COSMOS in no time.

## Installing OpenC3 COSMOS on Host Machines

### Installation Videos

<div style={{display: 'flex', justifyContent: 'center', gap: '20px', flexWrap: 'wrap'}}>
  <div style={{textAlign: 'center', flex: '1 1 280px', minWidth: '280px', maxWidth: '400px'}}>
    <iframe style={{width: '100%', aspectRatio: '16/9'}} src="https://www.youtube.com/embed/Luiy30mUYHs" title="Getting Started with COSMOS on Windows 11" frameborder="0" allow="autoplay; encrypted-media; picture-in-picture; fullscreen"></iframe>
    <p><strong>Windows 11</strong></p>
  </div>
  <div style={{textAlign: 'center', flex: '1 1 280px', minWidth: '280px', maxWidth: '400px'}}>
    <iframe style={{width: '100%', aspectRatio: '16/9'}} src="https://www.youtube.com/embed/hmhOVIzg4-M" title="Getting Started with COSMOS on macOS" frameborder="0" allow="autoplay; encrypted-media; picture-in-picture; fullscreen"></iframe>
    <p><strong>macOS</strong></p>
  </div>
  <div style={{textAlign: 'center', flex: '1 1 280px', minWidth: '280px', maxWidth: '400px'}}>
    <iframe style={{width: '100%', aspectRatio: '16/9'}} src="https://www.youtube.com/embed/aLqAMvFjqY8" title="Getting Started with COSMOS on Linux Ubuntu" frameborder="0" allow="autoplay; encrypted-media; picture-in-picture; fullscreen"></iframe>
    <p><strong>Linux Ubuntu</strong></p>
  </div>
</div>

### Prerequisites

If you're on Linux (recommended for production), we recommend installing Docker using the [Install Docker Engine](https://docs.docker.com/engine/install/) instructions (do not use Docker Desktop on Linux). Note: Red Hat users should read the [Podman](podman) documentation. If you're on Windows or Mac, install [Docker Desktop](https://docs.docker.com/get-docker/). All platforms also need to install [Docker Compose](https://docs.docker.com/compose/install/).

- Minimum Resources allocated to Docker: 8GB RAM, 1 CPU, 80GB Disk
- Recommended Resources allocated to Docker: 16GB RAM, 2+ CPUs, 100GB Disk
- Docker on Windows with WSL2:
  - WSL2 consumes 50% of total memory on Windows or 8GB, whichever is less. However, on Windows builds before 20175 (use `winver` to check) it consumes 80% of your total memory. This can have a negative effect on Windows performance!
  - On Windows builds < 20175 or for more fine grained control, create C:\\Users\\\<username\>\\[.wslconfig](https://docs.microsoft.com/en-us/windows/wsl/wsl-config). Suggested contents on a 32GB machine (increase memory as needed):

    ```
    [wsl2]
    memory=16GB
    swap=0
    ```

:::warning Important: Modify Docker Connection Timeouts
Docker by default will break idle (no data) connections after a period of 5 minutes. This "feature" will eventually cause you problems if you don't adjust the Docker settings. This may manifest as idle connections dropping or simply failing to resume after data should have started flowing again. Find the file at C:\\Users\\username\\AppData\\Roaming\\Docker\\settings.json on Windows or ~/Library/Group Containers/group.com.docker/settings.json on MacOS. Modify the value `vpnKitMaxPortIdleTime` to change the timeout (recommend setting to 0). **Note:** 0 means no timeout (idle connections not dropped)
:::

**Note:** As of December 2021 the COSMOS Docker containers are based on the Alpine Docker image.

### Clone Project

We recommend using the COSMOS [project template](architecture#projects) to get started.

```bash
git clone https://github.com/OpenC3/cosmos-project.git
git clone https://github.com/OpenC3/cosmos-enterprise-project.git
```

Once the project is cloned you can checkout a specific COSMOS version by using the git tag (NOTE the 'v' prefix):

```bash
git checkout vX.Y.Z # <- change to the specific version you want
```

:::info Offline Installation

  <p style={{"margin-bottom": 20 + 'px'}}>If you need to install in an offline environment you should first see if you're able to directly use the COSMOS containers. If so you can first save the containers. First checkout the specific version of the `cosmos-project` or `cosmos-enterprise-project` you want to save as shown above.</p>

  <p style={{"margin-bottom": 20 + 'px'}}><code>./openc3.sh util save docker.io openc3inc X.Y.Z # &lt;- update to save a specific version</code></p>

  <p style={{"margin-bottom": 20 + 'px'}}>This will download the COSMOS containers from the docker.io repo using the openc3inc namespace and version 5.16.2. The repo, namespace and version are all configurable. Tar files are created in the 'tmp' directory which you can transfer to your offline environment. Transfer the tar files to your offline environment's project 'tmp' dir and  import them with:</p>

  <p style={{"margin-bottom": 20 + 'px'}}><code>./openc3.sh util load X.Y.Z # &lt;- update to match the save version</code></p>

  <p style={{"margin-bottom": 20 + 'px'}}>Note the version specified in save needs to match the version in load.</p>
:::

### Certificates

The COSMOS containers are designed to work and be built in the presence of an SSL Decryption device. To support this a cacert.pem file can be placed at the base of the COSMOS project that includes any certificates needed by your organization. **Note**: If you set the path to the ssl file in the `SSL_CERT_FILE` environment variables the openc3 setup script will copy it and place it for the docker container to load.

:::warning SSL Issues

Increasingly organizations are using some sort of SSL decryptor device which can cause curl and other command line tools like git to have SSL certificate problems. If installation fails with messages that involve "certificate", "SSL", "self-signed", or "secure" this is the problem. IT typically sets up browsers to work correctly but not command line applications. Note that the file extension might not be .pem, it could be .pem, crt, .ca-bundle, .cer, .p7b, .p7s, or potentially something else.

The workaround is to get a proper local certificate file from your IT department that can be used by tools like curl (for example C:\Shared\Ball.pem). Doesn't matter just somewhere with no spaces.

Then set the following environment variables to that path (ie. C:\Shared\Ball.pem)

SSL_CERT_FILE<br/>
CURL_CA_BUNDLE<br/>
REQUESTS_CA_BUNDLE<br/>

Here are some directions on environment variables in Windows: [Windows Environment Variables](https://www.computerhope.com/issues/ch000549.htm)

You will need to create new ones with the names above and set their value to the full path to the certificate file.
:::

### Run

Add the locally cloned project directory to your path so you can directly use the batch file or shell script. In Windows this would be adding "C:\cosmos-project" to the PATH. In Linux you would edit your shell's rc file and export the PATH. For example, on a Mac add the following to ~/.zshrc: `export PATH=~/cosmos-project:$PATH`.

Run `openc3.bat run` (Windows), or `./openc3.sh run` (linux/Mac).

Note, you can edit the .env file and change OPENC3_TAG to a specific release (e.g. 5.0.9) rather than 'latest'. For production deployments, you should also change the default passwords in the `.env` file. See [Security](security) for details.

If you see an error indicating docker daemon is not running ensure Docker and Docker compose is installed and running. If it errors please try to run `docker --version` or `docker-compose --version` and try to run the start command again. If the error continues please include the version in your issue if you choose to create one.

Running `docker ps` can help show the running containers.

`openc3.*` takes multiple arguments. Run with no arguments for help. An example run of openc3.sh with no arguments will show a usage guide.

```bash
./openc3.sh
Usage: ./openc3.sh [cli, cliroot, start, stop, cleanup, run, util]
*  cli: run a cli command as the default user ('cli help' for more info)
*  cliroot: run a cli command as the root user ('cli help' for more info)
*  start: start the docker-compose openc3
*  stop: stop the running dockers for openc3
*  cleanup: cleanup network and volumes for openc3
*  run: run the prebuilt containers for openc3
*  util: various helper commands
```

### Connect

Connect a web browser to http://localhost:2900. Set the password to whatever you want. This frontend password is separate from the backend service credentials in the `.env` file. See [Security](security) for details on how COSMOS credentials work.

### Next Steps

Continue to [Getting Started](gettingstarted).

---

### Stop COSMOS

The below command will stop all running COSMOS containers. This will _not_ remove Docker volumes and data, and will be preserved after stopping. If COSMOS is restarted using the `./openc3.sh run` command, the data will remain intact.

```bash
./openc3.sh stop
```

### Resume COSMOS

COSMOS can be started up again with the `run` command, with previously used data intact (if any). If there are previously used Docker volumes and data available, COSMOS will start up using that data. If COSMOS is used with [Local Mode](../guides/local-mode.md), the local configurations will be referenced and used. If this is a first time deploy, the `run` command will begin with a fresh installation.

```bash
./openc3.sh run
```

### Cleanup COSMOS

If you need to remove COSMOS from your system or reset your installation, follow these steps.

:::note Helpful guidance
The `--help` option on the `./openc3.sh` command will provide helpful guidance of the available options and further descriptions. Example below:

```
❯ ./openc3.sh cleanup --help
Usage: ./openc3.sh cleanup [local] [force]

Remove all COSMOS Core docker volumes and data.

WARNING: This is a destructive operation that removes ALL COSMOS Core data!

Arguments:
  local    Also remove local plugin files in plugins/DEFAULT/
  force    Skip confirmation prompt

Examples:
  ./openc3.sh cleanup              # Remove volumes (with confirmation)
  ./openc3.sh cleanup force        # Remove volumes (no confirmation)
  ./openc3.sh cleanup local        # Remove volumes and local plugins
  ./openc3.sh cleanup local force  # Remove volumes and local plugins (no confirmation)

Options:
  -h, --help    Show this help message
```

:::

#### To remove Docker networks, volumes, and data

To cleanup Docker volumes and data created by COSMOS:

```bash
./openc3.sh cleanup
```

:::warning Data Loss
The cleanup command will remove all Docker volumes, which means **all your COSMOS data will be permanently deleted**.
Make sure to backup any important data before running cleanup.
:::

#### To remove Docker networks, volumes, data, and Local Mode changes

If you're running COSMOS with [Local Mode](../guides/local-mode.md), you may notice that modified files and newly created files are added to your host machine, under the `plugins` directory in your repository. Files are synced between server and local file system, which eliminates the need for rebuilding & re-uploading a plugin for development. If you want these local changes to also be cleaned up, run the following:

```bash
./openc3.sh cleanup local
```

:::warning Data Loss
The cleanup command will remove all Docker volumes, which means **all your COSMOS data will be permanently deleted**, including **local mode changes added to your host machine**.
Make sure to backup any important data before running cleanup.
:::

#### To remove Docker networks, volumes, and data _without confirmation_

The `cleanup` options will prompt for a confirmation as they are going to delete your COSMOS installation. If you'd like to skip the confirmation, run the following:

```bash
./openc3.sh cleanup force
    or
./openc3.sh cleanup local force
```

The force option will remove containers, networks, volumes, and data without user confirmation.

#### Remove Docker Images (Optional)

If you want to free up disk space by removing the COSMOS Docker images:

```bash
docker images | grep openc3inc | awk '{print $3}' | xargs docker rmi
```

Or to remove all unused Docker images:

```bash
docker image prune -a
```

:::warning Docker image prune -a removes all unused images
With -a flag: The command docker image prune -a is more aggressive and removes all unused images, meaning any image that is not currently associated with a running or stopped container. Use this with caution, as it might remove base images you want to keep.
:::

---

### Feedback

:::note Find a problem in the documentation?

Please [create an issue](https://github.com/OpenC3/cosmos/issues/new/choose) on
GitHub describing what we can do to make it better.

:::
