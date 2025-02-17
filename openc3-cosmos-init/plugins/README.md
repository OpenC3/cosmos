# Developing OpenC3 Frontend Applications

NOTE: All commands are assumed to be executed from this (openc3-cosmos-init) directory

1.  Bootstrap the frontend with yarn

        openc3-cosmos-init> yarn

1.  Start openc3

        openc3-cosmos-init> cd ..
        openc3> openc3.bat dev

1.  Serve a local OpenC3 COSMOS application (CmdTlmServer, ScriptRunner, etc)

        openc3-cosmos-init> cd plugins/packages/openc3-cosmos-tool-scriptrunner
        openc3-cosmos-tool-scriptrunner> yarn
        ...
        openc3-cosmos-tool-scriptrunner> yarn serve

1.  Set the single SPA override for the application

    Visit localhost:2900 and Right-click 'Inspect'<br>
    In the console paste:

        localStorage.setItem('devtools', true)

    Refresh and you should see {...} in the bottom right<br>
    Click the Default button next to the application (@openc3/tool-scriptrunner)<br>
    Paste in the development path which is dependent on the port returned by the local yarn serve and the tool name (scriptrunner)

        http://localhost:2914/tools/scriptrunner/main.js

## Developing OpenC3 Base Application

As of COSMOS 6, developing the base application (openc3-tool-base) is the same as developing other frontend
applications, described in the steps above.

## Developing OpenC3 Common Packages

There are two packages that contain shared code between OpenC3 frontend applications: openc3-js-common and
openc3-vue-common. openc3-js-common contains framework-agnostic JavaScript code such as the API and Action Cable
adapters, and openc3-vue-common contains Vue components, plugins, and mixins.

In previous versions of COSMOS, this code was in a package called openc3-tool-common, and you would
test changes by serving a tool such as CmdTlmServer. As of COSMOS 6, you must also serve the common packages as you
would any other frontend application, alongside the tool.

To see changes while developing one of these common packages, you must serve it alongside a tool that consumes the changes:

1. Start serving the tool, as described in the steps above

1. Open a second terminal and repeat that process for openc3-js-common or openc3-vue-common

   a. You may omit the final single SPA override step, as it will have no affect for the common package

1. If you are making style/layout changes, you must also open a third terminal and repeat the process for openc3-tool-base

   a. **Do** complete the single SPA override step for openc3-tool-base

We are currently working on externalizing the common packages, which will greatly simplify this process (you'd only
need to serve and override openc3-js-common or openc3-vue-common). This ability will come in a later release of COSMOS.

# API development

1.  Run a development version of traefik

        openc3-cosmos-init> cd ../openc3-traefik
        traefik> docker ps
        # Look for the container with name including traefik
        traefik> docker stop cosmos-openc3-traefik-1
        traefik> docker build --build-arg TRAEFIK_CONFIG=traefik-dev.yaml -t openc3-traefik-dev .
        traefik> docker run --network=openc3-cosmos-network -p 2900:2900 -it --rm openc3-traefik-dev

1.  Run a local copy of the CmdTlm API or Script API

        openc3-cosmos-init> cd ../openc3-cosmos-cmd-tlm-api
        openc3-cosmos-cmd-tlm-api> docker ps
        # Look for the container with name including cmd-tlm-api
        openc3-cosmos-cmd-tlm-api> docker stop cosmos-openc3-cosmos-cmd-tlm-api-1
        # Run the following on Windows:
        openc3-cosmos-cmd-tlm-api> dev_server.bat
        # On Linux execute the equivalent commands:
        openc3-cosmos-cmd-tlm-api> set -a; source ../.env; set +a
        openc3-cosmos-cmd-tlm-api> export OPENC3_REDIS_HOSTNAME=127.0.0.1
        openc3-cosmos-cmd-tlm-api> export OPENC3_REDIS_EPHEMERAL_HOSTNAME=127.0.0.1
        openc3-cosmos-cmd-tlm-api> bundle install
        openc3-cosmos-cmd-tlm-api> bundle exec rails s

# MINIO development

Note running OpenC3 COSMOS in development mode (openc3.bat dev) already does this step. This is only necessary to debug a minio container running in production mode.

1.  Run a development version of minio

        > docker ps
        # Look for the container with name including minio
        > docker stop cosmos-openc3-minio-1
        > docker run --name cosmos-openc3-minio-1 --network=openc3-cosmos-network -v cosmos-openc3-minio-v:/data -p 9000:9000 -e "MINIO_ROOT_USER=openc3minio" -e "MINIO_ROOT_PASSWORD=openc3miniopassword" minio/minio:RELEASE.2024-05-01T01-11-10Z server --console-address ":9001" /data
