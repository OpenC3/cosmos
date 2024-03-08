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

        http://localhost:2914/tools/scriptrunner/js/app.js

# Developing OpenC3 Base Application

1.  Run a development version of traefik

        openc3-cosmos-init> cd ../openc3-traefik
        traefik> docker ps
        # Look for the container with name including traefik
        traefik> docker stop cosmos-openc3-traefik-1
        traefik> docker build --build-arg TRAEFIK_CONFIG=traefik-dev-base.yaml -t openc3-traefik-dev-base .
        traefik> docker run --network=openc3-cosmos-network -p 2900:2900 -it --rm openc3-traefik-dev-base

1.  Serve a local base application (App, Auth, AppBar, AppFooter, etc)

        openc3-cosmos-init> cd plugins/openc3-tool-base
        openc3-tool-base> yarn serve

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
        > docker run --name cosmos-openc3-minio-1 --network=openc3-cosmos-network -v cosmos-openc3-minio-v:/data -p 9000:9000 -e "MINIO_ROOT_USER=openc3minio" -e "MINIO_ROOT_PASSWORD=openc3miniopassword" minio/minio:RELEASE.2024-01-05T22-17-24Z server --console-address ":9001" /data
