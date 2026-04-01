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
  -v /mnt/backup:/backup \
  alpine rsync -a /data/ /backup/buckets/
```

Replace `/mnt/backup` with your shared network drive or backup destination. This mounts the `openc3-object-v` volume as read-only and copies its contents to the backup location. This command is safe to run on a schedule for incremental backups since `rsync` only copies changed files.

### QuestDB

QuestDB requires a checkpoint-based backup procedure. See the [QuestDB backup documentation](https://questdb.com/docs/operations/backup/#questdb-oss-manual-backups-with-checkpoints) for full details.

The QuestDB data is stored in the `openc3-tsdb-v` Docker volume mounted at `/var/lib/questdb` inside the `openc3-tsdb` container.

#### Backup Procedure

1. **Create a checkpoint** to pause housekeeping while keeping the database available for reads and writes. Open the Admin Console and the TSDB tab. Run the following:

   ```sql
   CHECKPOINT CREATE
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

   ```sql
   CHECKPOINT RELEASE
   SELECT * FROM checkpoint_status()
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

:::info Version Compatibility
QuestDB backups are compatible across patch versions within the same major version (e.g., 9.0.0 and 9.1.0 are compatible).
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
