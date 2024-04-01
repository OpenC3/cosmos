#!/bin/sh
# set -x

date
if [ -d "/gems/gems" ]; then
    # Run gem pristine on all gems
    # This ensures gems keep working on container upgrades
    # and if you change architectures
    previous=""
    for f in /gems/gems/* ; do
    x=${f%.gem}
    y=${x##*/}
    z=${y%-*}

    if [ "$previous" != "$z" ]
    then
        gem pristine $z
    fi
    previous=$z
    done;
fi
date

if [ -z "${OPENC3_BUCKET_URL}" ]; then
    OPENC3_BUCKET_URL='http://openc3-minio:9000'
fi

if [ ! -z "${OPENC3_ISTIO_ENABLED}" ]; then
    T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${T} OPENC3_ISTIO_ENABLED enabled."
    RC=1
    while [ $RC -gt 0 ]; do
        curl -fs http://localhost:15021/healthz/ready -o /dev/null
        RC=$?
        T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "${T} waiting for sidecar. RC: ${RC}"
        sleep 1
    done
    echo "Sidecar available. Running the command..."
fi

if [ "${OPENC3_CLOUD}" == "local" ]; then
    RC=1
    while [ $RC -gt 0 ]; do
        curl -fs ${OPENC3_BUCKET_URL}/minio/health/live -o /dev/null
        RC=$?
        T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "${T} waiting for Minio ${OPENC3_BUCKET_URL} RC: ${RC}";
        sleep 1
    done
fi

if [ -z "${OPENC3_REDIS_CLUSTER}" ]; then
    RC=1
    while [ $RC -gt 0 ]; do
        printf "AUTH healthcheck nopass\r\nPING\r\n" | nc -v -w 2 -i 1 ${OPENC3_REDIS_HOSTNAME} ${OPENC3_REDIS_PORT} 2>&1 | grep -q 'PONG'
        RC=$?
        T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "${T} waiting for Redis ${OPENC3_REDIS_HOSTNAME}:${OPENC3_REDIS_PORT}. RC: ${RC}";
        sleep 1
    done
    RC=1
    while [ $RC -gt 0 ]; do
        printf "AUTH healthcheck nopass\r\nPING\r\n" | nc -v -w 2 -i 1 ${OPENC3_REDIS_EPHEMERAL_HOSTNAME} ${OPENC3_REDIS_EPHEMERAL_PORT} 2>&1 | grep -q 'PONG'
        RC=$?
        T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "${T} waiting for Redis Ephemeral ${OPENC3_REDIS_EPHEMERAL_HOSTNAME}:${OPENC3_REDIS_EPHEMERAL_PORT}. RC: ${RC}";
        sleep 1
    done
else
    RC=1
    while [ $RC -gt 0 ]; do
        printf "AUTH healthcheck nopass\r\nCLUSTER INFO\r\n" | nc -v -w 2 -i 1 ${OPENC3_REDIS_HOSTNAME} ${OPENC3_REDIS_PORT} 2>&1 | grep -q 'cluster_state:ok'
        RC=$?
        T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "${T} waiting for Redis cluster ${OPENC3_REDIS_HOSTNAME}:${OPENC3_REDIS_PORT}. RC: ${RC}";
        sleep 1
    done
    RC=1
    while [ $RC -gt 0 ]; do
        printf "AUTH healthcheck nopass\r\nCLUSTER INFO\r\n" | nc -v -w 2 -i 1 ${OPENC3_REDIS_EPHEMERAL_HOSTNAME} ${OPENC3_REDIS_EPHEMERAL_PORT} 2>&1 | grep -q 'cluster_state:ok'
        RC=$?
        T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "${T} waiting for Redis Ephemeral cluster ${OPENC3_REDIS_EPHEMERAL_HOSTNAME} ${OPENC3_REDIS_EPHEMERAL_PORT}. RC: ${RC}";
        sleep 1
    done
fi

# Fail on errors
set -e

if [ -z "${OPENC3_NO_MIGRATE}" ]; then
    ruby /openc3/bin/openc3cli runmigrations || exit 1
fi

if [ "${OPENC3_CLOUD}" == "local" ]; then
    ruby /openc3/bin/openc3cli initbuckets || exit 1
    mc alias set openc3minio "${OPENC3_BUCKET_URL}" ${OPENC3_BUCKET_USERNAME} ${OPENC3_BUCKET_PASSWORD} || exit 1
    # Create new canned policy by name script using script-runner.json policy file.
    mc admin policy create openc3minio script /openc3/minio/script-runner.json || exit 1
    # Create a new user scriptrunner on MinIO use mc admin user.
    mc admin user add openc3minio ${OPENC3_SR_BUCKET_USERNAME} ${OPENC3_SR_BUCKET_PASSWORD} || exit 1
    # Once the user is successfully created you can now apply the getonly policy for this user.
    # "|| true" is required on subsequent startups due to the following error that is thrown:
    # mc: <ERROR> Unable to make user/group policy association. The specified policy change is already in effect. (Specified policy update has no net effect).
    mc admin policy attach openc3minio script --user=${OPENC3_SR_BUCKET_USERNAME} || true
fi

ruby /openc3/bin/openc3cli removeenterprise || exit 1
ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-tool-base-*.gem || exit 1
ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-iframe-*.gem || exit 1

if [ -z $OPENC3_NO_TOOLADMIN ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-admin-*.gem || exit 1
fi

if [ ! -z $OPENC3_LOCAL_MODE ]; then
    # Continue if local init fails - User will have to fix manually
    ruby /openc3/bin/openc3cli localinit || true
fi
if [ ! -z $OPENC3_DEMO ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-demo-*.gem || exit 1
fi
if [ -z $OPENC3_NO_CMDTLMSERVER ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-cmdtlmserver-*.gem || exit 1
fi
if [ -z $OPENC3_NO_LIMITSMONITOR ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-limitsmonitor-*.gem || exit 1
fi
if [ -z $OPENC3_NO_CMDSENDER ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-cmdsender-*.gem || exit 1
fi
if [ -z $OPENC3_NO_SCRIPTRUNNER ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-scriptrunner-*.gem || exit 1
fi
if [ -z $OPENC3_NO_PACKETVIEWER ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-packetviewer-*.gem || exit 1
fi
if [ -z $OPENC3_NO_TLMVIEWER ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-tlmviewer-*.gem || exit 1
fi
if [ -z $OPENC3_NO_TLMGRAPHER ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-tlmgrapher-*.gem || exit 1
fi
if [ -z $OPENC3_NO_DATAEXTRACTOR ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-dataextractor-*.gem || exit 1
fi
if [ -z $OPENC3_NO_DATAVIEWER ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-dataviewer-*.gem || exit 1
fi
if [ -z $OPENC3_NO_HANDBOOKS ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-handbooks-*.gem || exit 1
fi
if [ -z $OPENC3_NO_TABLEMANAGER ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-tablemanager-*.gem || exit 1
fi
if [ -z $OPENC3_NO_BUCKETEXPLORER ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-bucketexplorer-*.gem || exit 1
fi
if [ -z $OPENC3_NO_DOCS ]; then
    ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-docs-*.gem || exit 1
fi

# Need to allow errors during this wait
set +e

if [ ! -z "${OPENC3_ISTIO_ENABLED}" ]; then
    T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${T} OPENC3_ISTIO_ENABLED enabled. Calling quitquitquit..."
    RC=1
    while [ $RC -gt 0 ]; do
        curl -fs -X POST http://localhost:15020/quitquitquit -o /dev/null
        RC=$?
        T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "${T} waiting for sidecar quit. RC: ${RC}"
    done
fi

T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "${T} all done."
