---
title: Blue/Green Upgrades
description: Upgrade COSMOS Enterprise on Kubernetes with a parallel release that follows live telemetry and a short planned cutover
sidebar_custom_props:
  myEmoji: 🔀
---

A blue/green upgrade runs the new COSMOS Enterprise release (green) beside the running release (blue). Green starts from a copy of blue's data and then receives the same live telemetry as blue, so you can test it for as long as you need before you switch. Only blue can command vehicles. At cutover, blue stops, green picks up the data it doesn't have yet, and green takes over the vehicle links. Blue's data is untouched, so rolling back means stopping green and starting blue again.

:::warning[Never point two releases at one database]
Green must not share blue's Redis, TSDB, or buckets. Green's init pod migrates the data it connects to, and the old release can't read migrated data. Two operators reading one Redis also start every interface twice, which opens two links to each vehicle and can send commands twice.
:::

:::info[Plan for a short outage]
The cutover takes a few minutes of downtime: vehicles have no uplink from when blue stops until green's interfaces connect. Preserving all data rules out a zero-downtime switch, because green has to read blue's final commands and state after blue stops writing them. Time the cutover in a rehearsal (see [Validate Green](#5-validate-green)) and schedule it for when that gap is acceptable.
:::

## Choose a Strategy

Both strategies use the same steps. They differ in how long green lives and in how much data you copy.

|                 | Temporary green                                                     | Standing pair                                                                                                        |
| --------------- | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Green exists    | From the start of the upgrade until blue is retired                 | Always. After each cutover, the old release becomes the standby for the next upgrade                                 |
| Full data copy  | Every upgrade                                                       | Once, when you create the standby                                                                                    |
| Kept current by | Live telemetry and a scheduled command copy during the upgrade      | Live telemetry and a scheduled command copy all the time, plus incremental bucket syncs                              |
| Storage         | Two copies of Redis, TSDB, and buckets while the upgrade is running | Two copies all the time                                                                                              |
| Also gives you  | Nothing beyond the upgrade                                          | A warm standby with the full telemetry history, for testing changes and for recovering when the active release fails |
| Choose it when  | Storage is limited, or upgrades are infrequent                      | The TSDB and logs bucket are too large to copy for each upgrade, or you want a standby anyway                        |

In a standing pair, "blue" and "green" are roles, not fixed releases. Name the namespaces by something that doesn't change when the roles swap and versions upgrade, such as `openc3-a` and `openc3-b`. For a temporary green deployment, a versioned name such as `openc3-{version}` avoids the same problem when green later becomes blue. The examples here use `openc3` for blue and `openc3-green` for green. Commands show db_shard 0. If you run more than one shard, repeat them for each (`openc3-redis-1`, `openc3-tsdb-1`, and so on).

## Overview

| Phase                                              | Blue                            | Green                                                                 | Vehicle impact          |
| -------------------------------------------------- | ------------------------------- | --------------------------------------------------------------------- | ----------------------- |
| [0. Prepare links](#0-prepare-the-links)           | Gains telemetry-only routers    | Doesn't exist                                                         | One reconnect per link  |
| [1. Install databases](#1-install-green-databases) | Running                         | Empty databases                                                       | None                    |
| [2. Seed data](#2-seed-greens-data)                | Running                         | Copy of blue's data                                                   | None                    |
| [3. Initialize](#3-initialize-green)               | Running                         | Migrated, standby mode                                                | None                    |
| [4. Follow blue](#4-follow-blue)                   | Running, commanding             | Receiving live telemetry and copies of blue's commands, can't command | None                    |
| [5. Validate](#5-validate-green)                   | Running, commanding             | Tested for as long as you need                                        | None                    |
| [6. Cut over](#6-cut-over)                         | Stopped                         | Takes the links                                                       | A few minutes of outage |
| [7. After cutover](#7-after-cutover)               | Removed, or becomes the standby | Active                                                                | None                    |

In a standing pair, steps 0 through 4 happen once. Each later upgrade starts by running `helm upgrade` on the standby with the new chart version, then continues from [step 5](#5-validate-green).

## How Green's Data Stays Complete

Blue keeps running normally through the whole upgrade: operators command, run scripts, and change configuration. This table shows how each kind of data reaches green.

| Data                                                                                     | Until cutover                                                                                                                           | At cutover                                                                    |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Telemetry                                                                                | Seeded from blue, then received live through blue's routers. Repair gaps (the seed-to-follow gap, a router outage) from blue's raw logs | Already on green                                                              |
| Commands                                                                                 | Only blue sends them, and routers don't forward commands. A scheduled job copies them from blue's TSDB into green's                     | Run the copy once more after blue stops                                       |
| Raw log files (logs bucket)                                                              | Seeded from blue. Green then writes its own telemetry logs                                                                              | Copy blue's command logs, so green's archive is complete                      |
| Configuration and user data in Redis (plugins, autonomic, Calendar, metadata, and so on) | Seeded from blue. Changes on blue after the seed don't reach green                                                                      | Copy blue's Redis again, or reconcile by hand (see [Sync State](#sync-state)) |
| Config and tools buckets (target files, saved scripts and screens)                       | Seeded from blue                                                                                                                        | Incremental sync                                                              |
| Keycloak users and roles                                                                 | Seeded from blue, or shared when you run your own Keycloak                                                                              | Copy again, unless shared                                                     |
| Current values (ephemeral Redis)                                                         | Not copied                                                                                                                              | Rebuilt from live telemetry                                                   |

Telemetry gap repair uses the TSDB tab of green's Admin Console: **Analyze Data Gap** finds missing time ranges in a table, and **Repair Gap** reingests them from the raw log files in the logs bucket. Reingest turns on `DEDUP` for the affected tables, so it overwrites rows green already has instead of duplicating them (see [Backfilling and Reingest](/docs/guides/packet-structure-changes#backfilling-and-reingest)). The routers use the `PREIDENTIFIED` protocol, which carries each packet's original received time, so green's live rows have the same timestamps as the reingested rows.

Commands reach green through the command copy, a Kubernetes CronJob in green's namespace that runs `openc3.utilities.tsdb_cmd_sync` (included in COSMOS v7.7.0 and later). For each db_shard and each command table (`<SCOPE>__CMD__<TARGET>__<PACKET>`), it reads the rows in blue's TSDB that are newer than the newest row in green's table and writes them to green unchanged, including the user and approver of each command. It doesn't touch telemetry tables. It skips tables and columns that green doesn't have, such as commands removed in green's version, and logs a warning for each.

The copy resumes from the newest row in each of green's command tables, so nothing else may write to those tables. Green can't command the vehicles, but a command sent on green to a simulator in a vehicle scope would make the copy skip blue's older commands. Test commanding in a separate scope (see [Validate Green](#5-validate-green)).

## Scaling the Data Copy

The TSDB and logs bucket grow for as long as the system runs, so copying them in full gets slower with every upgrade. You can reduce the copy in these ways, and combine them:

- **Copy once.** A [standing pair](#choose-a-strategy) copies history once. After that, live telemetry, the command copy, incremental bucket syncs, and gap repair keep it current.
- **Volume snapshots.** If your storage class supports [CSI volume snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/), snapshot blue's TSDB volume under a checkpoint and create green's volume from the snapshot. Most cloud block storage (EBS, Persistent Disk, Azure Disk) stores snapshots incrementally, and some storage systems clone volumes copy-on-write, so the cost no longer grows with the size of the database.
- **Incremental TSDB copy.** COSMOS partitions TSDB tables by day, and QuestDB doesn't rewrite a day's partition once the day is over. Use `rsync --delete` in [the TSDB seed](#tsdb) instead of clearing the volume and running `tar`, so that copying again copies only partitions that changed and still removes files green wrote itself. This works only before green starts ingesting, because restoring a checkpoint replaces green's whole database.
- **Less history in the TSDB.** Set [`TLM_DECOM_RETAIN_TIME`](/docs/configuration/plugins#tlm_decom_retain_time) and [`CMD_DECOM_RETAIN_TIME`](/docs/configuration/plugins#cmd_decom_retain_time), or [detach and archive old partitions](/docs/guides/backups#removing-and-restoring-partitions). Green copies only recent data, and you reattach archived partitions when someone needs them.
- **Bucket replication.** `aws s3 sync` and `gcloud storage rsync` only copy new or changed objects, but they still list every object. To skip the listing, use your provider's replication instead, such as S3 Replication or a scheduled Storage Transfer Service job on GCP. Set [`TLM_LOG_RETAIN_TIME`](/docs/configuration/plugins#tlm_log_retain_time) and [`CMD_LOG_RETAIN_TIME`](/docs/configuration/plugins#cmd_log_retain_time) to bound the logs bucket.

Whichever you choose, you still need storage for two copies while both releases exist.

## Prerequisites

- Read the [release notes](https://github.com/OpenC3/cosmos/releases) for every version between blue and green.
- Green runs COSMOS v7.7.0 or later, which includes the command copy.
- The cluster has room for a second full release, including storage for second copies of Redis, the TSDB, and PostgreSQL.
- The cluster's CNI enforces Kubernetes NetworkPolicy.
- You know how each vehicle link connects (COSMOS connects out, or the vehicle or ground station connects in) and how long each vehicle can go without uplink.
- Operations has agreed on a cutover window and a rollback window.

## 0. Prepare the Links

Green follows blue's telemetry through routers on blue. A router with [`MAP_TLM_TARGET`](/docs/configuration/plugins#map_tlm_target) sends the target's telemetry to its clients and drops any commands they send, because the target isn't mapped for commands. Green's interfaces also map telemetry only, so green has no path to command a vehicle while it is the standby.

Add a variable to each plugin that picks the link mode, and use it in `plugin.txt`:

```
VARIABLE link_mode vehicle
VARIABLE active_host none
VARIABLE veh01_router_port 7801

<% if link_mode == 'vehicle' %>
  INTERFACE VEH01_INT tcpip_client_interface.rb 10.20.0.11 5000 5000 10.0 nil LENGTH 0 16 0 1 BIG_ENDIAN 4
    MAP_TARGET VEH01

  # Telemetry-only router that the standby connects to
  ROUTER VEH01_TLM_ROUTER tcpip_server_interface.rb <%= veh01_router_port %> <%= veh01_router_port %> 10.0 nil PREIDENTIFIED 0xCAFEBABE
    MAP_TLM_TARGET VEH01
    PORT <%= veh01_router_port %>
<% else %>
  # Standby: the same interface name, fed from the active release's router
  INTERFACE VEH01_INT tcpip_client_interface.rb <%= active_host %> <%= veh01_router_port %> <%= veh01_router_port %> 10.0 nil PREIDENTIFIED 0xCAFEBABE
    MAP_TLM_TARGET VEH01
<% end %>
```

Keep the interface name the same in both modes, so its status, metrics, and packet counts carry over at cutover.

The router's [`PORT`](/docs/configuration/plugins#port) creates a Kubernetes Service named `<scope>-router-<router-name>-service`, with `_` and `__` replaced by `-` (for example `default-router-veh01-tlm-router-service`). On the standby, set `active_host` to that Service in the active release's namespace, such as `default-router-veh01-tlm-router-service.openc3.svc.cluster.local`. See [Exposing Microservices](/docs/guides/exposing-microservices) for how the name is formed with sharded operators.

Reinstall each plugin on blue with `link_mode` set to `vehicle`. Reinstalling restarts the plugin's interfaces, so each link reconnects once. Schedule it like any other plugin change.

Allow only the standby's namespace to reach the router ports:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tlm-routers-from-standby
  namespace: openc3
spec:
  podSelector:
    matchExpressions:
      - key: app
        operator: In
        values: [default-router-veh01-tlm-router] # One per router
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openc3-green
```

### Using a Front-End Processor Instead

If a front-end processor (FEP) or ground station already sits between COSMOS and the vehicles, it can split the links instead: it sends downlink to both releases and accepts uplink only from the active one. The standby's interfaces connect to the FEP with `MAP_TLM_TARGET`, and cutover includes switching the FEP's uplink to green. This removes the routers' load from blue, and the standby keeps receiving telemetry when blue is down.

## 1. Install Green Databases

Create the namespace and the same secrets as blue (re-run your edited `create_secrets.sh` in the new namespace). Then install `openc3-nfs` and `openc3-db` from the new chart version, as described in the [Helm README](https://repos.openc3.com/OpenC3/cosmos-enterprise/src/branch/main/openc3-helm/README.md):

```bash
kubectl create namespace openc3-green
kubectl config set-context --current --namespace=openc3-green
./openc3-helm/create_secrets.sh
helm install openc3-nfs openc3-helm/openc3-nfs --namespace=openc3-green --values green-nfs-values.yaml
helm install openc3-db openc3-helm/openc3-db --namespace=openc3-green --values green-db-values.yaml
```

Start green's values files from blue's. Green needs its own:

- Hostname: `cosmosDomain`, `cosmosExternalUrl`, `grafana.rootUrl`, `grafana.authUrl`, and `keycloak.externalUrl` (for example `cosmos-green.example.com`), plus a DNS record and certificate for it
- Bucket names: `logsBucket`, `toolsBucket`, and `configBucket`, when buckets are in cloud storage

Before green connects to anything, block its egress to the vehicle and ground station networks. Green keeps this policy until [cutover](#6-cut-over), so even a misconfigured interface can't reach a vehicle:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-vehicle-links
  namespace: openc3-green
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.20.0.0/16 # Replace with your vehicle and ground station networks
```

If vehicles or ground stations connect in to COSMOS, don't point them at green's interface ports until cutover.

## 2. Seed Green's Data

None of these copies stop blue. Seed the TSDB and buckets in the order shown, and go on to steps 3 and 4 promptly: telemetry that blue receives between the TSDB checkpoint and [step 4](#4-follow-blue) is a gap that you repair from blue's logs. Commands from that time need nothing extra: the command copy starts from the checkpoint.

### Redis

Copy only the persistent Redis. Ephemeral Redis holds current values, which rebuild from live telemetry.

Make green's Redis a replica of blue's, using the `admin` user from your `redis.conf`:

```bash
kubectl exec -it openc3-redis-0 -n openc3-green -- valkey-cli --user admin --pass $ADMIN_PASSWORD
```

```
CONFIG SET masteruser admin
CONFIG SET masterauth <ADMIN_PASSWORD>
REPLICAOF openc3-redis-0.openc3-redis.openc3.svc.cluster.local 6379
ROLE
```

Wait until `ROLE` shows `connected` as the replication state (the fourth line). The `admin` user can't run `INFO`, so use `ROLE` rather than `INFO replication`. Green now follows blue until you promote it in [step 3](#3-initialize-green).

### TSDB

Copy QuestDB under a checkpoint, as described in [Backups](/docs/guides/backups#questdb). See [Scaling the Data Copy](#scaling-the-data-copy) for faster alternatives to streaming the whole directory.

Every TSDB shard is a replica of the one `openc3-tsdb` StatefulSet, so scaling it down stops all shards at once. Copy every shard in the same scale-down window rather than repeating these steps per shard.

1. In blue's Admin Console, TSDB tab, run `CHECKPOINT CREATE` on each db_shard (choose the shard in the tab's shard selector).

2. Scale green's TSDB to zero, and start a temporary pod for each shard that mounts that shard's volume:

   ```bash
   SHARDS=1 # Your TSDB shard count
   kubectl scale statefulset openc3-tsdb --replicas=0 -n openc3-green
   for i in $(seq 0 $((SHARDS - 1))); do
   kubectl apply -n openc3-green -f - <<EOF
   apiVersion: v1
   kind: Pod
   metadata:
     name: tsdb-restore-$i
     labels:
       app: tsdb-restore
   spec:
     containers:
       - name: restore
         image: alpine
         command: ["sleep", "infinity"]
         volumeMounts:
           - name: data
             mountPath: /var/lib/questdb
     volumes:
       - name: data
         persistentVolumeClaim:
           claimName: openc3-tsdb-v-openc3-tsdb-$i
   EOF
   done
   kubectl wait --for=condition=Ready pod -l app=tsdb-restore -n openc3-green
   ```

3. For each shard, clear green's volume, stream blue's data directory into it, and mark it for restore. Green's QuestDB wrote its own files when it started in [step 1](#1-install-green-databases), and leftovers such as a newer table registry can hide blue's tables after the restore, so clear the volume first:

   ```bash
   for i in $(seq 0 $((SHARDS - 1))); do
     kubectl exec tsdb-restore-$i -n openc3-green -- sh -c 'rm -rf /var/lib/questdb/*'
     kubectl exec openc3-tsdb-$i -n openc3 -- tar -C /var/lib/questdb -cf - . \
       | kubectl exec -i tsdb-restore-$i -n openc3-green -- tar -C /var/lib/questdb -xpf -
     kubectl exec tsdb-restore-$i -n openc3-green -- touch /var/lib/questdb/_restore
   done
   ```

4. In blue's Admin Console, run `CHECKPOINT RELEASE` on each db_shard. Note the time: green's history ends here until [step 4](#4-follow-blue).

5. Delete the restore pods, then scale green's TSDB back up. QuestDB restores the checkpoint when it starts.

   ```bash
   kubectl delete pod -l app=tsdb-restore -n openc3-green
   kubectl scale statefulset openc3-tsdb --replicas=$SHARDS -n openc3-green
   ```

Blue's TSDB housekeeping is paused while the checkpoint is held, so release it as soon as the copy finishes.

### Buckets

Sync each of blue's buckets into green's. For example, on AWS:

```bash
aws s3 sync s3://$BLUE_LOGS_BUCKET s3://$GREEN_LOGS_BUCKET
aws s3 sync s3://$BLUE_CONFIG_BUCKET s3://$GREEN_CONFIG_BUCKET
aws s3 sync s3://$BLUE_TOOLS_BUCKET s3://$GREEN_TOOLS_BUCKET
```

On GCP, use `gcloud storage rsync -r`.

Don't sync the whole logs bucket again after this seed. Once green receives live telemetry in [step 4](#4-follow-blue), it writes its own telemetry logs, and copying blue's on top would duplicate them. Later syncs copy only the telemetry logs for specific gaps, and blue's command logs at cutover. The config and tools buckets are safe to sync in full at any time.

### Keycloak

If Keycloak runs in the release (`keycloak.enabled: true`), copy its database:

```bash
kubectl exec deploy/openc3-postgresql -n openc3 -- pg_dump -U keycloak -Fc keycloak > keycloak.dump
kubectl exec -i deploy/openc3-postgresql -n openc3-green -- pg_restore -U keycloak -d keycloak --clean --if-exists < keycloak.dump
```

If you use your own Keycloak, point green at it with `keycloak.url`. Both releases then share users and roles, and you don't copy them again at cutover.

In either case, add green's hostname to the COSMOS client's **Valid redirect URIs** and **Web origins** in Keycloak.

## 3. Initialize Green

1. Promote green's Redis. Blue keeps running normally. Changes on blue from now on reach green at [cutover](#sync-state).

   ```
   REPLICAOF NO ONE
   ```

2. Run the config and tools bucket syncs again to pick up recent changes.

3. Install the `openc3` chart. Its init pod runs migrations and plugin upgrades on green's data only.

   ```bash
   helm install openc3 openc3-helm/openc3 --namespace=openc3-green --values green-values.yaml --timeout 15m
   ```

   Green's interfaces start in `vehicle` mode, because that is what blue's Redis holds. The `block-vehicle-links` NetworkPolicy keeps them from reaching the vehicles.

4. On green, disable autonomic reactions and pause Calendar timelines. They stay off for as long as green is the standby.

## 4. Follow Blue

1. In green's Admin Console, edit each plugin: set `link_mode` to `standby` and `active_host` to the router's Service in blue's namespace. Green's interfaces restart and connect to blue's routers.
2. In green's CmdTlmServer, check that each interface is connected and its telemetry counts are increasing at the same rate as blue's.
3. Start the [command copy](#command-copy). Run it once by hand and check its log before relying on the schedule.
4. Repair the telemetry gap from the seed. Blue uploads a raw log file only when it closes it, after [`TLM_LOG_CYCLE_TIME`](/docs/configuration/plugins#tlm_log_cycle_time) (600 seconds by default) or [`TLM_LOG_CYCLE_SIZE`](/docs/configuration/plugins#tlm_log_cycle_size), so the end of the gap is still in blue's open files right after step 1. Wait at least one cycle time after green's interfaces connect, then sync blue's raw telemetry logs that cover the time from the TSDB checkpoint to green's connection into green's logs bucket, for example with `aws s3 sync` and `--exclude`/`--include` patterns on `<SCOPE>/raw_logs/tlm/`. Then, in green's Admin Console, TSDB tab, run **Analyze Data Gap** and **Repair Gap** for the affected tables.

From now until cutover, green has the same telemetry as blue, and its command tables are at most one schedule interval behind.

### Command Copy

Create the CronJob in green's namespace. It uses green's operator image, which has the script, and green's TSDB settings from the `env` ConfigMap and `openc3-tsdb` Secret. Find the image with:

```bash
kubectl get deployment,statefulset openc3-operator -n openc3-green \
  -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'
```

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: tsdb-cmd-sync
  namespace: openc3-green
spec:
  schedule: "0 * * * *" # Hourly. Any interval works, because each run copies only new rows
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        spec:
          restartPolicy: Never
          # imagePullSecrets: the same as green's other pods, if your registry needs them
          containers:
            - name: sync
              image: <green's operator image>
              command:
                - /openc3/python/.venv/bin/python
                - -m
                - openc3.utilities.tsdb_cmd_sync
                - --source-host=openc3-tsdb-SHARDNUM.openc3-tsdb.openc3.svc.cluster.local
                - --db-shards=1 # Your TSDB shard count
              envFrom:
                - configMapRef: { name: env } # Green's OPENC3_TSDB_* settings
              env:
                - name: OPENC3_TSDB_USERNAME
                  valueFrom:
                    secretKeyRef: { name: openc3-tsdb, key: username }
                - name: OPENC3_TSDB_PASSWORD
                  valueFrom:
                    secretKeyRef: { name: openc3-tsdb, key: password }
```

`--source-host` is blue's TSDB hostname, with `SHARDNUM` standing for the db_shard number. The script reads blue with green's TSDB credentials, which match when you created green's secrets with the same `create_secrets.sh`. If they differ, set `SOURCE_TSDB_USERNAME` and `SOURCE_TSDB_PASSWORD`. Green's pods must be able to reach port 8812 on blue's `app: openc3-tsdb` pods, so allow it if blue's namespace restricts ingress.

Run it by hand and read its log. `concurrencyPolicy: Forbid` only stops scheduled runs from overlapping, not a run you start by hand, and two runs at once copy the same rows twice. So suspend the CronJob and wait for any running job to finish first:

```bash
kubectl patch cronjob tsdb-cmd-sync -n openc3-green -p '{"spec":{"suspend":true}}'
kubectl get jobs -n openc3-green # Wait until no tsdb-cmd-sync job is still running
kubectl create job --from=cronjob/tsdb-cmd-sync tsdb-cmd-sync-manual -n openc3-green
kubectl logs -f job/tsdb-cmd-sync-manual -n openc3-green
kubectl patch cronjob tsdb-cmd-sync -n openc3-green -p '{"spec":{"suspend":false}}'
```

Each run logs the rows it copied per table and the tables or columns it skipped. A job fails if any table failed to copy, and the next run retries it. Add `--dry-run` to the command to count the rows without writing them.

## 5. Validate Green

1. Install all plugins. Check in green's Admin Console, Plugins tab, that every plugin from blue is installed and at the version you intend to run. Install new plugin versions now and repeat the checks below after any change.
2. Compare live telemetry: green's Telemetry Viewer and Limits Monitor should match blue's.
3. Check that Data Extractor and Telemetry Grapher return continuous history on green across the seed and the start of live telemetry, and that green's command history matches blue's up to the last command copy.
4. Test commanding against simulators or a telemetry replay, never live vehicles. Install them in a separate scope, so they don't change the vehicle plugins and their commands don't land in the tables the [command copy](#command-copy) fills.
5. Run your own procedures and the scripts for each vehicle class.
6. Load green with the full fleet's telemetry rate.
7. Rehearse the cutover against the simulators, and time it. That time is roughly the outage the vehicles will see.

You can keep green in this state for as long as you need. It keeps receiving telemetry the whole time.

## 6. Cut Over

All vehicles move together. The outage runs from step 1 to step 5 of **Switch**.

**Prepare (no outage):**

- Let any scripts commanding vehicles finish, or stop them.
- Approve or reject pending [critical commands](/docs/configuration/command#critical-commanding-enterprise).
- Release [command authority](/docs/configuration/command#command-authority-enterprise).
- On blue, note which autonomic reactions and Calendar timelines are active, then disable the reactions and pause the timelines.

### Stopping and Starting Microservices

Stop all of a release's microservices by stopping its operators. This doesn't change Redis, so the release starts again with the same configuration. With the default Kubernetes operator (`operator.shards: 0`), each microservice runs in its own Deployment and keeps running without the operator, so scale those down too:

```bash
# Kubernetes operator (operator.shards: 0)
kubectl scale deployment openc3-operator --replicas=0 -n openc3
kubectl scale deployment -l dynamic=true --replicas=0 -n openc3

# Sharded operators (operator.shards > 0)
kubectl scale statefulset openc3-operator --replicas=0 -n openc3
```

To start them again:

```bash
# Kubernetes operator (operator.shards: 0)
kubectl scale deployment openc3-operator --replicas=1 -n openc3
kubectl scale deployment -l dynamic=true --replicas=1 -n openc3

# Sharded operators (operator.shards > 0)
kubectl scale statefulset openc3-operator --replicas=<shards> -n openc3
```

The APIs and web tools keep running, so users can still log in and view history.

### Switch

1. Stop blue's microservices. Wait until all of blue's microservice pods have terminated, so the log microservices have written their last files to the bucket.
2. Confirm the links are free: the vehicles or ground stations show no connection to blue.
3. Stop green's microservices, then [sync state](#sync-state). Stopping them keeps green from writing to Redis while you replace or edit it. If green will serve your main hostname itself, set green's hostname values to it and run `helm upgrade` after the sync. Those values feed the environment ConfigMap, and the operator restarts every microservice when it changes, so green's microservices come back up. They can't reach the vehicles yet, because `block-vehicle-links` is still in place.
4. Delete green's `block-vehicle-links` NetworkPolicy. If vehicles or ground stations connect in, point them at green's interface ports. Any of green's interfaces that are already running connect on their next reconnect attempt.
5. Start green's microservices. If you ran `helm upgrade`, some or all of the microservices might have already started. Confirm each interface connects, then send a no-op command and check its response in telemetry.
6. Repair telemetry gaps: in green's Admin Console, TSDB tab, run **Analyze Data Gap** on the telemetry tables across the time since [step 2](#2-seed-greens-data) and **Repair Gap** for each gap. The command tables are already complete from the final command copy.
7. On green, re-enable the autonomic reactions and Calendar timelines that were active on blue, and take command authority where you use it.
8. Move users to green: repoint your main DNS name at green, unless you already moved the hostname in step 3.

Steps 6 to 8 happen after the vehicles have uplink again.

### Sync State

Run the command copy one last time, now that blue has stopped sending commands. Do this before green sends any command, because the copy resumes from the newest row in each of green's command tables.

Suspend the CronJob first and wait for any scheduled run to finish, so it can't overlap the final run and copy the same rows twice. Then run the final copy from the CronJob and remove it:

```bash
kubectl patch cronjob tsdb-cmd-sync -n openc3-green -p '{"spec":{"suspend":true}}'
kubectl get jobs -n openc3-green # Wait until no tsdb-cmd-sync job is still running
kubectl create job --from=cronjob/tsdb-cmd-sync tsdb-cmd-sync-final -n openc3-green
kubectl wait --for=condition=complete job/tsdb-cmd-sync-final -n openc3-green --timeout=30m
kubectl logs job/tsdb-cmd-sync-final -n openc3-green
kubectl delete cronjob tsdb-cmd-sync -n openc3-green
```

Sync the buckets. Green already has its own telemetry logs, so don't copy blue's. Copy blue's command logs for every scope, so green's logs bucket has the complete archive. The TSDB doesn't need them:

```bash
for SCOPE in DEFAULT; do # List every scope
  aws s3 sync s3://$BLUE_LOGS_BUCKET/$SCOPE/raw_logs/cmd/ s3://$GREEN_LOGS_BUCKET/$SCOPE/raw_logs/cmd/
done
aws s3 sync s3://$BLUE_CONFIG_BUCKET s3://$GREEN_CONFIG_BUCKET
aws s3 sync s3://$BLUE_TOOLS_BUCKET s3://$GREEN_TOOLS_BUCKET
```

If green's telemetry stopped for a while (for example, a router outage), also copy blue's `raw_logs/tlm/` files for that period, so **Repair Gap** can find them.

Then bring Redis and Keycloak up to date in one of two ways:

| Option                       | How                                                                                                                                                                                                                                                                                                                                                             | Outage                | Tradeoff                                                                                                                                                     |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Copy again** (recommended) | Make green's Redis a replica of blue's and promote it, as in [step 2](#redis) and [step 3](#3-initialize-green). Copy Keycloak again if it isn't shared. Run `helm upgrade` on green to re-run its init pod. This also starts green's operator, but `block-vehicle-links` still blocks the links. Green then has blue's exact configuration, in `vehicle` mode. | Includes green's init | Changes made on green during validation are replaced. Plugin versions you installed on green must be installed again before you start green's microservices. |
| **Reconcile**                | Keep green's Redis. Before cutover, make every configuration change on both releases: plugins, autonomic groups, Calendar, notes and metadata, and users (if Keycloak isn't shared). At cutover, compare the two releases' Admin Console tabs, then edit each plugin on green back to `link_mode` `vehicle`.                                                    | Shorter               | Anything not repeated on green is lost. Command history copies over through the command copy, but other changes made on blue after the seed don't.           |

## 7. After Cutover

### Temporary Green

Keep blue stopped, with its volumes, through the rollback window. Its microservices are already stopped, so save the replica counts of everything else (such as the Redis and TSDB shard counts), then scale it down:

```bash
kubectl get deployment,statefulset -n openc3 \
  -o jsonpath='{range .items[*]}{.kind}/{.metadata.name} {.spec.replicas}{"\n"}{end}' > blue-replicas.txt
kubectl scale deployment,statefulset --all --replicas=0 -n openc3
```

To bring blue back for a [rollback](#rollback), restore the saved counts. This brings back the databases, APIs, and web tools, but not the microservices, which were already stopped when you saved the counts:

```bash
while read -r name replicas; do
  kubectl scale "$name" --replicas="$replicas" -n openc3
done < blue-replicas.txt
```

At the end of the window, remove blue:

```bash
helm uninstall openc3 openc3-db openc3-nfs -n openc3
kubectl delete namespace openc3
```

### Standing Pair

Blue becomes the standby:

1. Apply the `block-vehicle-links` NetworkPolicy to blue's namespace, and add the `tlm-routers-from-standby` policy to green's namespace so blue can reach green's routers.
2. Start blue's microservices. Its interfaces start in `vehicle` mode, and the NetworkPolicy keeps them from reaching the vehicles.
3. On blue, disable autonomic reactions, pause Calendar timelines, and edit each plugin to `link_mode` `standby` with `active_host` set to green's router Services. Blue now follows green, as green followed blue in [step 4](#4-follow-blue).
4. Create the [command copy](#command-copy) CronJob in blue's namespace, with `--source-host` set to green's TSDB (`openc3-tsdb-SHARDNUM.openc3-tsdb.openc3-green.svc.cluster.local`). If blue's version doesn't include the script, use green's operator image. The script writes to blue's TSDB with that image's ingest protocol (`OPENC3_TSDB_INGEST_PROTOCOL`), so run it once by hand and check its log before relying on the schedule.

For the next upgrade, run `helm upgrade` on blue with the new chart version and continue from [step 5](#5-validate-green), with the roles swapped. Between upgrades, sync the config and tools buckets to the standby on a schedule (daily, for example), so that the work at the next cutover stays small. The command copy keeps the standby's command tables current.

## Rollback

| When                                      | Action                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Before cutover                            | Temporary green: delete the `openc3-green` namespace. Standing pair: nothing to do. Blue is unchanged either way.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| During the outage                         | Stop green's microservices, restore green's `block-vehicle-links` policy, and start blue's microservices. Blue's data is unchanged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| After cutover, within the rollback window | Run the cutover in reverse: stop green, run the [command copy](#command-copy) in blue's namespace with green as the source (as for a [standing pair](#standing-pair)), copy green's command logs (and telemetry logs if blue wasn't following) into blue's bucket, start blue, and repair the gaps in blue's telemetry tables. For a temporary green, first [restore blue's saved replica counts](#temporary-green) so its databases and APIs are running before you start its microservices. Configuration changes made on green after cutover are lost, because blue can't read green's migrated Redis. |
| After rollback window                    | No rollback. Fix forward on green.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |

Blue never runs green's migrations, so it is always safe to start blue again while it exists.

## Troubleshooting

See [Troubleshooting](/docs/guides/troubleshooting).
