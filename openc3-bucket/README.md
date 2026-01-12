# OpenC3 S3 Gateway (versitygw)

This directory contains the Dockerfile and configuration for the versitygw S3 gateway, which replaces MINIO as the S3-compatible storage backend in COSMOS 7+.

## About versitygw

[Versity Gateway](https://github.com/versity/versitygw) is a high-performance S3 to file translation tool that bridges the gap between S3-reliant applications and POSIX storage systems.

## Building

The container downloads pre-built binaries from [versitygw GitHub releases](https://github.com/versity/versitygw/releases). The version is specified by `OPENC3_VERSITYGW_VERSION` in the Dockerfile.

## Configuration

### Environment Variables

| Variable          | Description                       | Default |
| ----------------- | --------------------------------- | ------- |
| `ROOT_ACCESS_KEY` | S3 access key for authentication  | -       |
| `ROOT_SECRET_KEY` | S3 secret key for authentication  | -       |
| `VGW_PORT`        | Port to listen on                 | `:9000` |
| `VGW_BACKEND`     | Storage backend type              | `posix` |
| `VGW_BACKEND_ARG` | Backend argument (path for posix) | `/data` |

For compatibility, the entrypoint also accepts MINIO-style credentials:

- `MINIO_ROOT_USER` (mapped to `ROOT_ACCESS_KEY`)
- `MINIO_ROOT_PASSWORD` (mapped to `ROOT_SECRET_KEY`)

## Migrating from MINIO

### Data Preservation

MINIO stores data in a specific internal format that is not directly compatible with versitygw's POSIX backend. To migrate existing data, you must use the MINIO client (`mc`) to transfer data via the S3 API.

### Automated Migration (Recommended)

Use the provided migration script for a safe, side-by-side migration. The script runs `mc` via Docker so no local installation is required. The script auto-detects your environment and handles all scenarios automatically.

**Option A: Pre-Migration (Recommended - Minimizes Downtime)**

Migrate your data while COSMOS 6 is still running, then upgrade:

```bash
# 1. While COSMOS 6 is running, pull the migration script from COSMOS 7
curl -O https://raw.githubusercontent.com/OpenC3/cosmos/main/scripts/linux/openc3_migrate_s3.sh
chmod +x openc3_migrate_s3.sh

# 2. Run the migration (COSMOS 6 MINIO -> temporary versitygw container)
./openc3_migrate_s3.sh migrate

# 3. Stop COSMOS 6
./openc3.sh stop

# 4. Upgrade to COSMOS 7+ and start
./openc3.sh upgrade v7.0.0
./openc3.sh run
```

**Option B: Post-Migration**

Stop COSMOS 6 first, then migrate after upgrading:

```bash
# 1. Stop COSMOS 6
./openc3.sh stop

# 2. Upgrade to COSMOS 7+ and start (versitygw will be running)
./openc3.sh upgrade v7.0.0
./openc3.sh run

# 3. Migrate all data from old MINIO volume to running versitygw
./scripts/linux/openc3_migrate_s3.sh migrate

# 4. Verify your data migrated correctly
./scripts/linux/openc3_migrate_s3.sh status
```

### Migration Script Features

The migration script:

- **Auto-detects environment**: Detects running MINIO (COSMOS 6) or versitygw (COSMOS 7) containers
- **Starts temporary containers as needed**: If source or destination isn't running, creates temporary containers
- **Idempotent operation**: Uses `mc mirror --preserve` so it only copies new or changed files (safe to run multiple times)
- **Handles volume prefixes**: Automatically detects Docker Compose project prefixes (e.g., `cosmos_openc3-bucket-v`)
- **Preserves metadata**: Maintains object metadata and timestamps during migration

### Configuration

The migration script uses **separate credentials** for the source (MINIO/COSMOS 6) and destination (versitygw/COSMOS 7) since these often differ between versions.

**Important:** If you customized your bucket credentials in your `.env` file, you'll need to provide the correct values:

```bash
# If you customized COSMOS 6 MINIO credentials (check your old .env file)
MINIO_ROOT_USER=your_old_minio_user MINIO_ROOT_PASSWORD=your_old_minio_pass ./openc3_migrate_s3.sh migrate

# If you customized COSMOS 7 versitygw credentials (check your current .env file)
OPENC3_BUCKET_USERNAME=your_bucket_user OPENC3_BUCKET_PASSWORD=your_bucket_pass ./openc3_migrate_s3.sh migrate

# Custom volume names (if using docker compose project prefix)
OLD_VOLUME=myproject_openc3-bucket-v NEW_VOLUME=myproject_openc3-block-v ./openc3_migrate_s3.sh migrate
```

| Variable                 | Description                              | Default               |
| ------------------------ | ---------------------------------------- | --------------------- |
| `OLD_VOLUME`             | Source MINIO volume name                 | `openc3-bucket-v`     |
| `NEW_VOLUME`             | Destination versitygw volume name        | `openc3-block-v`      |
| `MINIO_ROOT_USER`        | MINIO access key (COSMOS 6 source)       | `openc3minio`         |
| `MINIO_ROOT_PASSWORD`    | MINIO secret key (COSMOS 6 source)       | `openc3miniopassword` |
| `OPENC3_BUCKET_USERNAME` | versitygw access key (COSMOS 7 dest)     | `openc3bucket`        |
| `OPENC3_BUCKET_PASSWORD` | versitygw secret key (COSMOS 7 dest)     | `openc3bucketpassword`|

### Migration Performance

Benchmark results on Apple M3 Max (Docker Desktop, local volumes):

**50MB files (default log cycle size):**

| Data Size | Files | Duration    | Transfer Rate |
| --------- | ----- | ----------- | ------------- |
| 100 MB    | 2     | 1.8 sec     | 55 MB/s       |
| 1 GB      | 20    | 6.6 sec     | 151 MB/s      |
| 10 GB     | 200   | 31.6 sec    | 317 MB/s      |
| 50 GB     | 1000  | 2 min 2 sec | 410 MB/s      |

**Estimated migration times at 410 MB/s:**

| Data Size | Estimated Time |
| --------- | -------------- |
| 50 GB     | ~2 min         |
| 100 GB    | ~4 min         |
| 500 GB    | ~21 min        |
| 1 TB      | ~41 min        |

**10MB files (10 min of data running the COSMOS Demo):**

| Data Size | Files | Duration | Transfer Rate |
| --------- | ----- | -------- | ------------- |
| 1 GB      | 100   | 5.0 sec  | 199 MB/s      |

To run your own benchmarks:

```bash
./scripts/linux/benchmark_s3_migration.sh all
./scripts/linux/benchmark_s3_migration.sh --file-size 10 1gb
```

## Updating versitygw

To update to a newer version of versitygw:

1. Update the `OPENC3_VERSITYGW_VERSION` in the Dockerfile
2. Update the same in `scripts/linux/openc3_build_ubi.sh` and `scripts/release/build_multi_arch.sh`
3. Rebuild the container

## References

- [versitygw GitHub Repository](https://github.com/versity/versitygw)
- [versitygw Docker Documentation](https://github.com/versity/versitygw/wiki/Docker)
- [Versity Website](https://www.versity.com/products/versitygw/)
