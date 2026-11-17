---
title: Blue/Green Upgrades
description: Upgrade COSMOS Enterprise on Kubernetes with a parallel release and a staged cutover
sidebar_custom_props:
  myEmoji: 🔀
---

A blue/green upgrade installs the new COSMOS Enterprise release (green) beside the running release (blue), copies blue's data into it, and moves vehicles to green in waves. Blue keeps running until every vehicle has moved, so rolling back is a link swap rather than a database restore. Use this guide when your fleet can't take the outage of an in-place [upgrade](/docs/getting-started/upgrading).

:::warning[Never point two releases at one database]
Green must not share blue's Redis, TSDB, or buckets. Green's init pod migrates the data it connects to, and the old release can't read migrated data. Two operators reading one Redis also start every interface twice, which opens two links to each vehicle and can send commands twice.
:::

## Overview

| Phase                                              | Blue                         | Green                        | Vehicle impact            |
| -------------------------------------------------- | ---------------------------- | ---------------------------- | ------------------------- |
| [1. Install databases](#1-install-green-databases) | Running                      | Empty databases              | None                      |
| [2. Copy data](#2-copy-blues-data)                 | Running                      | Copy of blue's data          | None                      |
| [3. Initialize](#3-initialize-green)               | Running, frozen              | Migrated, interfaces stopped | None                      |
| [4. Validate](#4-validate-green)                   | Running, frozen              | Tested against simulators    | None                      |
| [5. Cut over](#5-cut-over-a-wave)                  | Wave's interfaces stopped    | Wave's interfaces started    | One short gap per vehicle |
| [6. Retire blue](#6-retire-blue)                   | Scaled to zero, then removed | Runs every vehicle           | None                      |

The examples use `openc3` for blue's namespace and `openc3-green` for green's. In a real implementation, using `openc3-{version}` would prevent future namespace renaming when `openc3-green` eventually becomes the blue deployment.  Commands show db_shard 0. If you run more than one shard, repeat them for each (`openc3-redis-1`, `openc3-tsdb-1`, and so on).

## Prerequisites

- Read the [release notes](https://github.com/OpenC3/cosmos/releases) for every version between blue and green.
- The cluster has room for a second full release, including storage for second copies of Redis, the TSDB, and PostgreSQL.
- The cluster's CNI enforces Kubernetes NetworkPolicy.
- Vehicles are grouped into waves: a canary of a few vehicles, then progressively larger waves.
- Operations has agreed to a configuration freeze from [step 3](#3-initialize-green) until the last wave. During the freeze, do not install plugins, change targets, change Keycloak users, or add autonomic rules on blue. Green never receives changes made on blue after the copy.
- You know how each vehicle link connects (COSMOS connects out, or the vehicle or ground station connects in) and how long each vehicle can go without uplink.

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

Before green connects to anything, block its egress to the vehicle and ground station networks:

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

If vehicles or ground stations connect in to COSMOS, don't point them at green's interface ports until their wave.

## 2. Copy Blue's Data

None of these copies stop blue.

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
INFO replication
```

Wait until `INFO replication` shows `master_link_status:up`. Green now follows blue until you promote it in [step 3](#3-initialize-green).

### TSDB

Copy QuestDB under a checkpoint, as described in [Backups](/docs/guides/backups#questdb):

1. In blue's Admin Console, TSDB tab, run `CHECKPOINT CREATE`.

2. Scale green's TSDB to zero, and start a temporary pod that mounts green's TSDB volume:

   ```bash
   kubectl scale statefulset openc3-tsdb --replicas=0 -n openc3-green
   kubectl apply -n openc3-green -f - <<EOF
   apiVersion: v1
   kind: Pod
   metadata:
     name: tsdb-restore
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
           claimName: openc3-tsdb-v-openc3-tsdb-0
   EOF
   ```

3. Stream blue's data directory into green's volume, then mark it for restore:

   ```bash
   kubectl exec openc3-tsdb-0 -n openc3 -- tar -C /var/lib/questdb -cf - . \
     | kubectl exec -i tsdb-restore -n openc3-green -- tar -C /var/lib/questdb -xpf -
   kubectl exec tsdb-restore -n openc3-green -- touch /var/lib/questdb/_restore
   ```

4. In blue's Admin Console, run `CHECKPOINT RELEASE`.

5. Delete `tsdb-restore`, then scale green's TSDB back up. QuestDB restores the checkpoint when it starts.

   ```bash
   kubectl delete pod tsdb-restore -n openc3-green
   kubectl scale statefulset openc3-tsdb --replicas=1 -n openc3-green # Your shard count
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

### Keycloak

If Keycloak runs in the release (`keycloak.enabled: true`), copy its database:

```bash
kubectl exec deploy/openc3-postgresql -n openc3 -- pg_dump -U keycloak -Fc keycloak > keycloak.dump
kubectl exec -i deploy/openc3-postgresql -n openc3-green -- pg_restore -U keycloak -d keycloak --clean --if-exists < keycloak.dump
```

If you use your own Keycloak, point green at it with `keycloak.url`.

In either case, add green's hostname to the COSMOS client's **Valid redirect URIs** and **Web origins** in Keycloak.

## 3. Initialize Green

1. Promote green's Redis. **The freeze starts now.**

   ```
   REPLICAOF NO ONE
   ```

2. Run the bucket sync again to pick up recent changes.

3. Install the `openc3` chart. Its init pod runs migrations and plugin upgrades on green's data only.

   ```bash
   helm install openc3 openc3-helm/openc3 --namespace=openc3-green --values green-values.yaml --timeout 15m
   ```

4. Open green's Admin Console. On the Microservices tab, stop every `<SCOPE>__INTERFACE__*` and `<SCOPE>__ROUTER__*` microservice. Stopping one saves it as disabled, so it stays stopped through restarts.

5. On green, disable autonomic reactions and pause Calendar timelines.

Keep the `block-vehicle-links` NetworkPolicy until green's interfaces are stopped and you have checked that they stay stopped.

## 4. Validate Green

- Connect green to simulators or a telemetry replay, never to live vehicles.
- Run your own procedures and the scripts for each vehicle class.
- Check that Data Extractor and Data Viewer return blue's history.
- Load green with the full fleet's telemetry rate before the first wave.

## 5. Cut Over a Wave

Cut over the canary first. Let each wave run on green for an agreed soak period before you start the next one. The wave's vehicles have no uplink between steps 1 and 3 of the swap. Time this gap during validation, and schedule each wave when that gap is acceptable.

**Prepare blue (for the wave's targets):**

- Let any scripts commanding these vehicles finish, or stop them.
- Approve or reject pending [critical commands](/docs/configuration/command#critical-commanding-enterprise).
- Disable autonomic reactions.
- Release [command authority](/docs/configuration/command#command-authority-enterprise).

**Swap:**

1. On blue, go to Admin Console, Microservices, and stop the wave's interface microservices.
2. Confirm the links are free: CmdTlmServer on blue shows each interface disconnected, and the vehicle or ground station shows no connection.
3. On green, go to Admin Console, Microservices, and start the same microservices.
4. Confirm each interface connects, then send a no-op command and check its response in telemetry.
5. On green, re-enable autonomic reactions, Calendar timelines, and command authority for these targets.

To script the swap, call the same endpoints the Admin Console uses. This requires the admin role. See [Curl](/docs/guides/curl) for getting a token.

```bash
curl -X POST -H "Authorization: $BLUE_TOKEN" \
  "https://<blue-domain>/openc3-api/microservices/DEFAULT__INTERFACE__VEH01_INT/stop?scope=DEFAULT"
curl -X POST -H "Authorization: $GREEN_TOKEN" \
  "https://<green-domain>/openc3-api/microservices/DEFAULT__INTERFACE__VEH01_INT/start?scope=DEFAULT"
```

## 6. Retire Blue

After the last wave's soak period:

1. Point your main hostname at green. Set green's values to the main hostname and run `helm upgrade`. Green's init runs again, but it skips plugins that are already installed at the same version.
2. Scale blue to zero but keep its volumes, so you can still roll back during an agreed window:

   ```bash
   kubectl scale deployment,statefulset --all --replicas=0 -n openc3
   ```

3. At the end of the window, archive blue's history if you need it (see [Telemetry History](#telemetry-history)), then remove blue:

   ```bash
   helm uninstall openc3 openc3-db openc3-nfs -n openc3
   kubectl delete namespace openc3
   ```

## Rollback

| When                   | Action                                                                                                                   |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Before the first wave  | Delete the `openc3-green` namespace. Blue is unchanged.                                                                  |
| During/after a wave or in the rollback window | Stop the wave's interfaces on green and start them on blue. Restore autonomic, timelines, and command authority on blue. |
| After blue is removed  | No rollback. Fix forward on green.                                                                                       |

Blue never runs green's migrations, so it is always safe to move vehicles back to blue while blue still exists.

## Telemetry History

Green has blue's history up to the TSDB copy in [step 2](#tsdb). For each vehicle, the telemetry from that copy until its wave exists only in blue's TSDB and logs bucket. Query blue for that period while it is kept. To keep that history after blue is removed, archive blue's TSDB and logs bucket as described in [Backups](/docs/guides/backups).

## Troubleshooting

See [Troubleshooting](/docs/guides/troubleshooting).
