---
sidebar_position: 1
title: Installation
---

## Installing OpenC3 COSMOS

The following sections describe how to get OpenC3 COSMOS installed on various operating systems. This document should help you setup you host machine to allow you to have a running version of COSMOS in no time.

## Installing OpenC3 COSMOS on Host Machines

### PREREQUISITES

Install [Docker](https://docs.docker.com/get-docker/) and install [Docker Compose](https://docs.docker.com/compose/install/).

- Minimum Resources allocated to Docker: 8GB RAM, 1 CPU, 80GB Disk
- Recommended Resources allocated to Docker: 16GB RAM, 2+ CPUs, 100GB Disk
- Docker on Windows with WSL2:

  - WSL2 consumes 50% of total memory on Windows or 8GB, whichever is less. However, on Windows builds before 20175 (use `winver` to check) it consumes 80% of your total memory. This can have a negative effect on Windows performance!
  - On Windows builds < 20175 or for more fine grained control, create C:\\Users\\\<username\>\\[.wslconfig](https://docs.microsoft.com/en-us/windows/wsl/wsl-config). Suggested contents on a 32GB machine:

        [wsl2]
        memory=16GB
        swap=0

:::warning Important: Modify Docker Connection Timeouts
Docker by default will break idle (no data) connections after a period of 5 minutes. This "feature" will eventually cause you problems if you don't adjust the Docker settings. This may manifest as idle connections dropping or simplying failing to resume after data should have started flowing again. Find the file at C:\\Users\\username\\AppData\\Roaming\\Docker\\settings.json on Windows or ~/Library/Group Containers/group.com.docker/settings.json on MacOS. Modify the value `vpnKitMaxPortIdleTime` to change the timeout (recommend setting to 0). **Note:** 0 means no timeout (idle connections not dropped)
:::

**Note:** As of December 2021 the COSMOS Docker containers are based on the Alpine Docker image.

### CLONE PROJECT

Since the COSMOS 5.0.9 release we recommend using the project template to get started.

        git clone https://github.com/OpenC3/cosmos-project.git tutorial

:::info Offline Installation

  <p style={{"margin-bottom": 20 + 'px'}}>If you need to install in an offline environment you should first see if you're able to directly use the COSMOS containers. If so you can first save the containers:</p>

  <p style={{"margin-bottom": 20 + 'px'}}><code>./openc3.sh util save</code></p>

  <p style={{"margin-bottom": 20 + 'px'}}>By default this will download the 'latest' images and create tar files in the 'tmp' directory which you can transfer to your offline environment. You can pass a release after 'save' to download a specific release (e.g. util save 5.0.9). Transfer the tar files to your offline environment's project 'tmp' dir and  import them with:</p>

  <p style={{"margin-bottom": 20 + 'px'}}><code>./openc3.sh util load</code></p>
:::

### CERTIFICATES

The COSMOS containers are designed to work and be built in the presence of an SSL Decryption device. To support this a cacert.pem file can be placed at the base of the COSMOS 5 project that includes any certificates needed by your organization. **Note**: If you set the path to the ssl file in the `SSL_CERT_FILE` environment variables the openc3 setup script will copy it and place it for the docker container to load.

:::warning SSL Issues

Increasingly organizations are using some sort of SSL decryptor device which can cause curl and other command line tools like git to have SSL certificate problems. If installation fails with messages that involve "certificate", "SSL", "self-signed", or "secure" this is the problem. IT typically sets up browsers to work correctly but not command line applications. Note that the file extension might not be .pem, it could be .pem, crt, .ca-bundle, .cer, .p7b, .p7s, or potentially something else.

The workaround is to get a proper local certificate file from your IT department that can be used by tools like curl (for example mine is at C:\Shared\Ball.pem). Doesn't matter just somewhere with no spaces.

Then set the following environment variables to that path (ie. C:\Shared\Ball.pem)

SSL_CERT_FILE<br/>
CURL_CA_BUNDLE<br/>
REQUESTS_CA_BUNDLE<br/>

Here are some directions on environment variables in Windows: [Windows Environment Variables](https://www.computerhope.com/issues/ch000549.htm)

You will need to create new ones with the names above and set their value to the full path to the certificate file.
:::

### RUN

Run `openc3.bat run` (Windows), or `./openc3.sh run` (linux/Mac).

Note, you can edit the .env file and change OPENC3_TAG to a specific release (e.g. 5.0.9) rather than 'latest'.

If you see an error indicating docker daemon is not running ensure Docker and Docker compose is installed and running. If it errors please try to run `docker --version` or `docker-compose --version` and try to run the start command again. If the error continues please include the version in your issue if you choose to create one.

Running `docker ps` can help show the running containers.

`openc3.*` takes multiple arguments. Run with no arguments for help. An example run of openc3.sh with no arguments will show a usage guide.

```
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

### CONNECT

Connect a web browser to http://localhost:2900. Set the password to whatever you want.

### NEXT STEPS

Continue to [Getting Started](gettingstarted.md).

---

### Feedback

:::note Find a problem in the documentation?

    Please [create an issue](https://github.com/OpenC3/cosmos/issues/new/choose">create an issue) on
    GitHub describing what we can do to make it better.

:::
