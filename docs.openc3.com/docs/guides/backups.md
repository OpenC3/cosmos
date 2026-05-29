---
title: Backups
description: How to backup and restore COSMOS
sidebar_custom_props:
  myEmoji: 🛟
---

## COSMOS 7

COSMOS 7 stores data in two places: the S3-compatible bucket storage (versitygw) and the Time Series Database (QuestDB). Both must be backed up for a complete recovery.

### Bucket Storage (S3)

#### Kubernetes / AWS with S3

If you are running COSMOS in Kubernetes or on an AWS EC2 with S3 as your bucket backend, S3 already handles durability and redundancy. No additional backup steps are required for bucket data.

#### Standalone Server

On a standalone server, versitygw uses a standard POSIX filesystem backend. The data is stored in the `openc3-object-v` Docker volume mounted at `/data` inside the `openc3-buckets` container. Since it's a regular filesystem, you can copy the files directly without needing the MinIO Client.

To back up, use a temporary Docker container to mount both the COSMOS volume and your backup destination:

```bash
# Back up bucket data to a shared network drive or external path
docker run --rm \
  -v openc3-object-v:/data:ro \
  -v /mnt/backup:/backup eeacms/rsync \
  rsync -a /data/ /backup/buckets/
```

Replace `/mnt/backup` with your shared network drive or backup destination. This mounts the `openc3-object-v` volume as read-only and copies its contents to the backup location. This command is safe to run on a schedule for incremental backups since `rsync` only copies changed files.

### QuestDB

QuestDB requires a checkpoint-based backup procedure. See the [QuestDB backup documentation](https://questdb.com/docs/operations/backup/#questdb-oss-manual-backups-with-checkpoints) for full details.

The QuestDB data is stored in the `openc3-tsdb-v` Docker volume mounted at `/var/lib/questdb` inside the `openc3-tsdb` container.

#### Backup Procedure

1. **Create a checkpoint** to pause housekeeping while keeping the database available for reads and writes.

   **From the COSMOS Admin Console:** Open the Admin Console and the TSDB tab. Run the following:

   ```sql
   CHECKPOINT CREATE
   ```

   **From the command line:** Execute the SQL directly against the QuestDB container's HTTP API:

   ```bash
   docker exec openc3-tsdb-1 \
     curl -sS -u "$OPENC3_TSDB_USERNAME:$OPENC3_TSDB_PASSWORD" \
     'http://localhost:9000/exec?query=CHECKPOINT+CREATE'
   ```

2. **Copy the QuestDB data directory.** While the checkpoint is active, copy the entire volume contents (including `db`, `snapshot`, and all subdirectories) to your backup destination.

   **Kubernetes / AWS:** Copy to an S3 bucket. Replace openc3-tsdb-1 with the real container name. Replace XXXXX and YYYYY with actual keys:

   ```bash
   # Example using a temporary pod or container with aws cli
   docker run --rm --volumes-from openc3-tsdb-1 \
     -e AWS_ACCESS_KEY_ID=XXXXX -e AWS_SECRET_ACCESS_KEY=YYYYY \
     amazon/aws-cli s3 sync /var/lib/questdb/ s3://your-backup-bucket/questdb/
   ```

   **Standalone server:** Copy to a local directory. Replace openc3-tsdb-1 with the real container name. Using rsync allows for incremental backups:

   ```bash
   # Example using eeacms/rsync container
   docker run --rm --volumes-from openc3-tsdb-1 \
     -v $(pwd):/backup eeacms/rsync \
     rsync -a /var/lib/questdb/ /backup/questdb/
   ```

3. **Release the checkpoint** to resume normal operations:

   **From the COSMOS Admin Console:**

   ```sql
   CHECKPOINT RELEASE
   SELECT * FROM checkpoint_status()
   ```

   **From the command line:**

   ```bash
   docker exec openc3-tsdb-1 \
     curl -sS -u "$OPENC3_TSDB_USERNAME:$OPENC3_TSDB_PASSWORD" \
     'http://localhost:9000/exec?query=CHECKPOINT+RELEASE'
   ```

#### Restore Procedure

1. **Stop COSMOS**

   ```bash
   openc3.sh stop
   ```

2. **Restore the QuestDB volume contents from your backup.** Replace openc3-tsdb-v with the real volume name:

   ```bash
   docker run --rm -v openc3-tsdb-v:/var/lib/questdb \
     -v $(pwd):/backup alpine \
     sh -c "rm -rf /var/lib/questdb/* && cp -a /backup/questdb/. /var/lib/questdb/"
   ```

3. **Create a trigger file to initiate the restore:**

   ```bash
   docker run --rm \
     -v openc3-tsdb-v:/var/lib/questdb alpine \
     touch /var/lib/questdb/_restore
   ```

4. **Run COSMOS** -- QuestDB will automatically perform the restore procedure and remove the `_restore` file on success

   ```bash
   openc3.sh run
   # Monitor the TSDB docker logs to watch progress
   docker logs -f openc3-tsdb-1
   ```

:::info[Version Compatibility]
QuestDB backups are compatible across patch versions within the same major version (e.g., 9.0.0 and 9.1.0 are compatible).
:::

#### Removing and Restoring Partitions

COSMOS creates QuestDB tables partitioned by day (`PARTITION BY DAY`). Each day of telemetry/command data for a given packet lives in its own partition directory under `/var/lib/questdb/db/<table_name>/`. This allows individual partitions to be detached from the live database for long-term archival, then reattached when the historical data is needed again. See the [QuestDB DETACH PARTITION](https://questdb.com/docs/reference/sql/alter-table-detach-partition/) and [ATTACH PARTITION](https://questdb.com/docs/reference/sql/alter-table-attach-partition/) reference for the underlying SQL semantics.

:::warning
Detaching a partition removes it from query results until it is reattached. Verify that downstream consumers (Data Extractor, Tlm Grapher, scripts) do not need the partition before detaching it. Always copy the detached partition directory to long-term storage before deleting it.
:::

##### Identifying Partitions

List the partitions for a table to find the boundaries and disk size. Run the query from the **TSDB tab of the Admin Console** or via the HTTP API:

```sql
SELECT name, minTimestamp, maxTimestamp, diskSize FROM table_partitions('DEFAULT__TLM__INST__HEALTH_STATUS');
```

Partition names use the format `YYYY-MM-DD` for daily partitions (e.g., `2026-04-15`). COSMOS uses the table naming convention `<SCOPE>__TLM__<TARGET>__<PACKET>` for telemetry and `<SCOPE>__CMD__<TARGET>__<PACKET>` for commands (e.g., `DEFAULT__TLM__INST__HEALTH_STATUS`).

##### Detach Procedure

1. **Detach the partition(s).** This atomically renames the partition directory from `2026-04-15.<n>` to `2026-04-15.detached` and removes it from the active table. The data remains on disk inside the QuestDB volume.

   ```sql
   ALTER TABLE 'DEFAULT__TLM__INST__HEALTH_STATUS' DETACH PARTITION LIST '2026-04-15';
   ```

   Multiple partitions or a range can be detached in one statement:

   ```sql
   ALTER TABLE 'DEFAULT__TLM__INST__HEALTH_STATUS' DETACH PARTITION LIST '2026-04-15', '2026-04-16', '2026-04-17';
   ALTER TABLE 'DEFAULT__TLM__INST__HEALTH_STATUS' DETACH PARTITION WHERE timestamp < dateadd('d', -90, now());
   ```

2. **Archive the detached partition** to your long-term storage. The detached partition is now named `<date>.detached` inside the table directory. Copy it out using a temporary container:

   ```bash
   docker run --rm --volumes-from openc3-tsdb-1 \
     -v $(pwd):/backup eeacms/rsync \
     rsync -a /var/lib/questdb/db/DEFAULT__TLM__INST__HEALTH_STATUS/2026-04-15.detached \
     /backup/archive/DEFAULT__TLM__INST__HEALTH_STATUS/
   ```

3. **(Optional) Delete the detached partition from the live volume** once archival is verified. Removing the `.detached` directory frees the disk space:

   ```bash
   docker run --rm --volumes-from openc3-tsdb-1 alpine \
     rm -rf /var/lib/questdb/db/DEFAULT__TLM__INST__HEALTH_STATUS/2026-04-15.detached
   ```

##### Restore Procedure

1. **Stage the archived partition** back into the table directory with the `.attachable` suffix. QuestDB only attaches partition directories that end in `.attachable`.

   ```bash
   docker run --rm --volumes-from openc3-tsdb-1 \
     -v $(pwd):/backup eeacms/rsync \
     rsync -a /backup/archive/DEFAULT__TLM__INST__HEALTH_STATUS/2026-04-15.detached/ \
     /var/lib/questdb/db/DEFAULT__TLM__INST__HEALTH_STATUS/2026-04-15.attachable/
   ```

   Ensure the directory is owned by the QuestDB process user inside the container (`questdb:questdb`, typically uid `10001`):

   ```bash
   docker exec openc3-tsdb-1 chown -R 10001:10001 \
     /var/lib/questdb/db/DEFAULT__TLM__INST__HEALTH_STATUS/2026-04-15.attachable
   ```

2. **Attach the partition** back into the active table:

   ```sql
   ALTER TABLE 'DEFAULT__TLM__INST__HEALTH_STATUS' ATTACH PARTITION LIST '2026-04-15';
   ```

3. **Verify** the partition is queryable:

   ```sql
   SELECT count() FROM 'DEFAULT__TLM__INST__HEALTH_STATUS' WHERE PACKET_TIMESECONDS IN '2026-04-15';
   ```

:::info[Schema Compatibility]
A detached partition must be reattached to a table whose schema is compatible with the partition's schema at detach time. If columns were added, removed, or had their type changed via [ALTER TYPE](https://questdb.com/docs/reference/sql/alter-table-alter-column-type/) since detachment, the attach may fail or only attach a subset of columns. Detach and reattach against the same major QuestDB version where possible.
:::

## COSMOS 6

The primary data to backup in COSMOS 6 is the bucket storage in MINIO.

### Kubernetes / AWS with S3

If you are running COSMOS in Kubernetes or on AWS with S3 as your bucket backend, S3 already handles durability and redundancy. No additional backup steps are required.

### Standalone Server

On a standalone server, MINIO uses an internal object format that requires the [MinIO Client (`mc`)](https://min.io/docs/minio/linux/reference/minio-mc.html) to access. Use `mc` to copy files to a backup location such as a shared network drive.

#### Backup Procedure

1. **Copy the MINIO /data directory.** Replace openc3-minio-1 with the actual container name:

```bash
docker run --rm --volumes-from openc3-minio-1 \
  -v $(pwd):/backup openc3inc/openc3-init \
  mc mirror --preserve /data /backup/minio
```

The `mc mirror --preserve` command is idempotent and only copies new or changed files, making it safe to run on a schedule for incremental backups.

#### Restore Procedure

1. **Stop COSMOS**

   ```bash
   openc3.sh stop
   ```

2. **Restore the MINIO backup.** Replace openc3-bucket-v with the actual container name:

```bash
docker run --rm --user root -v openc3-bucket-v:/data \
  -v $(pwd):/backup openc3inc/openc3-init \
  sh -c "rm -rf /data/* && mc mirror --preserve /backup/minio /data && chown -R 501:501 /data && chmod -R 777 /data"
```

3. **Restart COSMOS**

   ```bash
   openc3.sh start
   ```
