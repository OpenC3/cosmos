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
    OPENC3_BUCKET_URL='http://openc3-buckets:9000'
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

# Maximum seconds to wait for a dependency before exiting non-zero so the init
# hook pod restarts (restartPolicy OnFailure) and retries on a fresh network
# path, rather than hanging forever and stalling the deploy.
OPENC3_INIT_WAIT_TIMEOUT=${OPENC3_INIT_WAIT_TIMEOUT:-300}

# Diagnostic: when a dependency wait stalls, a curl/nc timeout doesn't tell us
# whether name resolution or the TCP connection is the problem. This resolves
# the host, then connects to the resolved IP separately, so the logs show which
# layer is failing (DNS vs the kube-proxy ClusterIP path). Uses ruby (always
# present in this image) so it works regardless of busybox nc/nslookup flags.
# Args: host port
probe_conn() {
    ruby -rresolv -rsocket -e '
host, port = ARGV[0], ARGV[1].to_i
begin
  ips = Resolv.getaddresses(host)
  if ips.empty?
    puts "  PROBE DNS: no addresses resolved for #{host}"
  else
    puts "  PROBE DNS: #{host} -> #{ips.join(",")}"
    begin
      Socket.tcp(ips.first, port, connect_timeout: 5) {}
      puts "  PROBE TCP: #{ips.first}:#{port} connect OK"
    rescue => e
      puts "  PROBE TCP: #{ips.first}:#{port} FAIL #{e.class}: #{e.message}"
    end
  end
rescue => e
  puts "  PROBE DNS: resolve error #{e.class}: #{e.message}"
end' "$1" "$2" 2>&1
}

if [ "${OPENC3_CLOUD}" = "local" ]; then
    # Parse host/port out of the bucket URL for the DNS/TCP probe
    bhp=${OPENC3_BUCKET_URL#*://}; bhp=${bhp%%/*}
    bhost=${bhp%%:*}; bport=${bhp##*:}; [ "$bport" = "$bhp" ] && bport=80
    deadline=$(( $(date +%s) + OPENC3_INIT_WAIT_TIMEOUT ))
    attempt=0
    RC=1
    while [ $RC -gt 0 ]; do
        # Check if buckets endpoint is responding (accept any HTTP response, even 403)
        # Remove -f flag so curl only fails on connection errors, not HTTP errors
        # --connect-timeout/--max-time keep each probe short so the loop retries
        # quickly instead of blocking ~2 min on an unanswered TCP connect (which
        # also masks the moment the endpoint becomes reachable)
        curl -s --connect-timeout 5 --max-time 10 ${OPENC3_BUCKET_URL}/ -o /dev/null
        RC=$?
        T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "${T} waiting for buckets ${OPENC3_BUCKET_URL} RC: ${RC}";
        # On the 1st and every 5th failure, log whether DNS or TCP is the problem
        if [ $RC -gt 0 ]; then
            attempt=$(( attempt + 1 ))
            if [ $(( attempt % 5 )) -eq 1 ]; then
                probe_conn "${bhost}" "${bport}"
            fi
        fi
        if [ $(date +%s) -ge $deadline ]; then
            echo "${T} ERROR: timed out after ${OPENC3_INIT_WAIT_TIMEOUT}s waiting for buckets ${OPENC3_BUCKET_URL}; exiting to restart init"
            exit 1
        fi
        sleep 1
    done
fi

deadline=$(( $(date +%s) + OPENC3_INIT_WAIT_TIMEOUT ))
attempt=0
RC=1
while [ $RC -gt 0 ]; do
    hostname=$(echo "${OPENC3_REDIS_HOSTNAME}" | sed "s/SHARDNUM/0/")
    printf "AUTH healthcheck nopass\r\nPING\r\n" | nc -v -w 2 -i 1 ${hostname} ${OPENC3_REDIS_PORT} 2>&1 | grep -q 'PONG'
    RC=$?
    T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${T} waiting for Redis ${hostname}:${OPENC3_REDIS_PORT}. RC: ${RC}";
    # On the 1st and every 5th failure, log whether DNS or TCP is the problem
    if [ $RC -gt 0 ]; then
        attempt=$(( attempt + 1 ))
        if [ $(( attempt % 5 )) -eq 1 ]; then
            probe_conn "${hostname}" "${OPENC3_REDIS_PORT}"
        fi
    fi
    if [ $(date +%s) -ge $deadline ]; then
        echo "${T} ERROR: timed out after ${OPENC3_INIT_WAIT_TIMEOUT}s waiting for Redis ${hostname}:${OPENC3_REDIS_PORT}; exiting to restart init"
        exit 1
    fi
    sleep 1
done
deadline=$(( $(date +%s) + OPENC3_INIT_WAIT_TIMEOUT ))
attempt=0
RC=1
while [ $RC -gt 0 ]; do
    hostname=$(echo "${OPENC3_REDIS_EPHEMERAL_HOSTNAME}" | sed "s/SHARDNUM/0/")
    printf "AUTH healthcheck nopass\r\nPING\r\n" | nc -v -w 2 -i 1 ${hostname} ${OPENC3_REDIS_EPHEMERAL_PORT} 2>&1 | grep -q 'PONG'
    RC=$?
    T=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${T} waiting for Redis Ephemeral ${hostname}:${OPENC3_REDIS_EPHEMERAL_PORT}. RC: ${RC}";
    # On the 1st and every 5th failure, log whether DNS or TCP is the problem
    if [ $RC -gt 0 ]; then
        attempt=$(( attempt + 1 ))
        if [ $(( attempt % 5 )) -eq 1 ]; then
            probe_conn "${hostname}" "${OPENC3_REDIS_EPHEMERAL_PORT}"
        fi
    fi
    if [ $(date +%s) -ge $deadline ]; then
        echo "${T} ERROR: timed out after ${OPENC3_INIT_WAIT_TIMEOUT}s waiting for Redis Ephemeral ${hostname}:${OPENC3_REDIS_EPHEMERAL_PORT}; exiting to restart init"
        exit 1
    fi
    sleep 1
done

# Fail on errors
set -e

# Trace every command (to stderr, captured by `kubectl logs`) with a UTC
# timestamp so a silent hang during a plugin load is visible: the last traced
# line shows exactly which `openc3cli load` was running when it stalled.
export PS4='+ [$(date -u +%H:%M:%SZ)] '
set -x

if [ -z "${OPENC3_NO_MIGRATE}" ]; then
    ruby /openc3/bin/openc3cli runmigrations || exit 1
fi

ruby /openc3/bin/openc3cli initbuckets || exit 1
ruby /openc3/bin/openc3cli removeenterprise || exit 1
ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-tool-base-*.gem || exit 1
ruby /openc3/bin/openc3cli load /openc3/plugins/gems/openc3-cosmos-tool-iframe-*.gem || exit 1

if [ ! -z $OPENC3_DEFAULT_QUEUE ]; then
    ruby /openc3/bin/openc3cli createqueue $OPENC3_DEFAULT_QUEUE DEFAULT || exit 1
fi
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

# Stop command tracing now that all plugin loads are done
set +x

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
