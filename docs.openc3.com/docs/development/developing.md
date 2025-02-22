---
title: Developing COSMOS
description: Building COSMOS and developing the frontend and backend
sidebar_custom_props:
  myEmoji: 💻
---

# Developing COSMOS

So you want to help develop COSMOS? All of our open source COSMOS code is on [Github](https://github.com/) so the first thing to do is get an [account](https://github.com/join). Next [clone](https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository) the [COSMOS](https://github.com/openc3/cosmos) repository. We accept contributions from others as [Pull Requests](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests).

## Development Tools

The core COSMOS team develops with the [Visual Studio Code](https://code.visualstudio.com/) editor and we highly recommend it. We also utilize a number of extensions including docker, kubernetes, gitlens, prettier, eslint, python, vetur, and ruby. We commit our `openc3.code-workspace` configuration for VSCode to help configure these plugins. You also need [Docker Desktop](https://www.docker.com/products/docker-desktop) which you should already have as it is a requirement to run COSMOS. You'll also need [NodeJS](https://nodejs.org/en/download/) and [yarn](https://yarnpkg.com/getting-started/install) installed.

# Building COSMOS

Note: We primarily develop COSMOS in MacOS so the commands here will reference bash scripts but the same files exist in Windows as batch scripts.

Build COSMOS using the `openc3.sh` script:

```bash
% ./openc3.sh build
```

This will pull all the COSMOS container dependencies and build our local containers. Note: This can take a long time especially for your first build!

Once the build completes you can see the built images with the following command:

```bash
% docker image ls | grep "openc3"
openc3inc/openc3-cosmos-init                latest   4cac7a3ea9d3   29 hours ago   446MB
openc3inc/openc3-cosmos-script-runner-api   latest   4aacbaf49f7a   29 hours ago   431MB
openc3inc/openc3-cosmos-cmd-tlm-api         latest   9a8806bd4be3   3 days ago     432MB
openc3inc/openc3-operator                   latest   223e98129fe9   3 days ago     405MB
openc3inc/openc3-base                       latest   98df5c0378c2   3 days ago     405MB
openc3inc/openc3-redis                      latest   5a3003a49199   8 days ago     111MB
openc3inc/openc3-traefik                    latest   ec13a8d16a2f   8 days ago     104MB
openc3inc/openc3-minio                      latest   787f6e3fc0be   8 days ago     238MB
openc3inc/openc3-node                       latest   b3ee86d3620a   8 days ago     372MB
openc3inc/openc3-ruby                       latest   aa158bbb9539   8 days ago     326MB
```

:::info Offline Building

If you're building in a offline environment or want to use a private Rubygems, NPM or APK server (e.g. Nexus), you can update the following environment variables: RUBYGEMS_URL, NPM_URL, APK_URL, and more in the [.env](https://github.com/openc3/cosmos/blob/main/.env) file. Example values:

    ALPINE_VERSION=3.19<br/>
    ALPINE_BUILD=7<br/>
    RUBYGEMS_URL=https://rubygems.org<br/>
    NPM_URL=https://registry.npmjs.org<br/>
    APK_URL=http://dl-cdn.alpinelinux.org<br/>

:::

# Running COSMOS

Running COSMOS in development mode enables localhost access to internal API ports as well as sets `RAILS_ENV=development` in the cmd-tlm-api and script-runner-api Rails servers. To run in development mode:

```bash
% ./openc3.sh dev
```

You can now see the running containers (I removed CONTAINER ID, CREATED and STATUS to save space):

```bash
% docker ps
IMAGE                                             COMMAND                  PORTS                      NAMES
openc3/openc3-cmd-tlm-api:latest         "/sbin/tini -- rails…"   127.0.0.1:2901->2901/tcp   cosmos-openc3-cmd-tlm-api-1
openc3/openc3-script-runner-api:latest   "/sbin/tini -- rails…"   127.0.0.1:2902->2902/tcp   cosmos-openc3-script-runner-api-1
openc3/openc3-traefik:latest             "/entrypoint.sh trae…"   0.0.0.0:2900->80/tcp       cosmos-openc3-traefik-1
openc3/openc3-operator:latest            "/sbin/tini -- ruby …"                              cosmos-openc3-operator-1
openc3/openc3-minio:latest               "/usr/bin/docker-ent…"   127.0.0.1:9000->9000/tcp   cosmos-openc3-minio-1
openc3/openc3-redis:latest               "docker-entrypoint.s…"   127.0.0.1:6379->6379/tcp   cosmos-openc3-redis-1
```

If you go to localhost:2900 you should see COSMOS up and running!

## Running a Frontend Application

So now that you have COSMOS up and running how do you develop an individual COSMOS application?

1.  Bootstrap the frontend with yarn

```bash
openc3-init % yarn
```

1.  Serve a local COSMOS application (CmdTlmServer, ScriptRunner, etc)

```bash
openc3-init % cd plugins/packages/openc3-tool-scriptrunner
openc3-tool-scriptrunner % yarn serve

DONE  Compiled successfully in 128722ms
App running at:
- Local:   http://localhost:2914/tools/scriptrunner/
- Network: http://localhost:2914/tools/scriptrunner/

Note that the development build is not optimized.
To create a production build, run npm run build.
```

1.  Set the [single SPA](https://single-spa.js.org/) override for the application

    Visit localhost:2900 and Right-click 'Inspect'<br/>
    In the console paste:

```javascript
localStorage.setItem("devtools", true);
```

    Refresh and you should see `{...}` in the bottom right<br/>
    Click the Default button next to the application (@openc3/tool-scriptrunner)<br/>
    Paste in the development path which is dependent on the port returned by the local yarn serve and the tool name (scriptrunner)

        http://localhost:2914/tools/scriptrunner/main.js

1.  Refresh the page and you should see your local copy of the application (Script Runner in this example). If you dynamically add code (like `console.log`) the yarn window should re-compile and the browser should refresh displaying your new code. It is highly recommended to get familiar with your browser's [development tools](https://developer.chrome.com/docs/devtools/overview/) if you plan to do frontend development.

## Running a Backend Server

If the code you want to develop is the cmd-tlm-api or script-runner-api backend servers there are several steps to enable access to a development copy.

1.  Run a development version of traefik. COSMOS uses traefik to direct API requests to the correct locations.

```bash
% cd openc3-traefik
openc3-traefik % docker ps
# Look for the container with name including traefik
openc3-traefik % docker stop cosmos-openc3-traefik-1
openc3-traefik % docker build --build-arg TRAEFIK_CONFIG=traefik-dev.yaml -t openc3-traefik-dev .
openc3-traefik % docker run --network=openc3-cosmos-network -p 2900:2900 -it --rm openc3-traefik-dev
```

1.  Run a local copy of the cmd-tlm-api or script-runner-api

```bash
% cd openc3-cosmos-cmd-tlm-api
openc3-cosmos-cmd-tlm-api % docker ps
# Look for the container with name including cmd-tlm-api
openc3-cosmos-cmd-tlm-api % docker stop cosmos-openc3-cosmos-cmd-tlm-api-1
# Run the following on Windows:
openc3-cosmos-cmd-tlm-api> dev_server.bat
# In Linux, set all the environment variables in the .env file, but override REDIS to be local
openc3-cosmos-cmd-tlm-api % set -a; source ../.env; set +a
openc3-cosmos-cmd-tlm-api % export OPENC3_REDIS_HOSTNAME=127.0.0.1
openc3-cosmos-cmd-tlm-api % export OPENC3_REDIS_EPHEMERAL_HOSTNAME=127.0.0.1
openc3-cosmos-cmd-tlm-api % bundle install
openc3-cosmos-cmd-tlm-api % bundle exec rails s
```

1.  Once the `bundle exec rails s` command returns you should see API requests coming from interactions in the frontend code. If you add code (like Ruby debugging statements) to the cmd-tlm-api code you need to stop the server (CTRL-C) and restart it to see the effect.
