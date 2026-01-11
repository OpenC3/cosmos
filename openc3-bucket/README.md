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

Use the provided migration script for a safe, side-by-side migration. The script runs `mc` via Docker so no local installation is required.

```bash
# 1. Upgrade to COSMOS 7+ to get the migration scripts and openc3-bucket container
#    (MINIO keeps running until you stop/start)
./openc3.sh upgrade v7.0.0

# 2. Start temporary versitygw container for migration
./scripts/linux/openc3_migrate_s3.sh start

# 3. Migrate all data from MINIO to versitygw
./scripts/linux/openc3_migrate_s3.sh migrate

# 4. Stop all services
./openc3.sh stop

# 5. Start COSMOS with versitygw
./openc3.sh run

# 6. Verify everything works and old data is accessible

# 7. Cleanup migration container
./scripts/linux/openc3_migrate_s3.sh cleanup

# 8. Remove old minio volume
docker volume rm openc3-minio-v
```

The migration script:

- Runs versitygw on a temporary port (9002) alongside MINIO
- Creates the new volume (`openc3-bucket-v`) for versitygw
- Uses `mc mirror` to copy all buckets and objects via Docker
- Preserves object metadata and timestamps
- Fixes volume permissions to match your host user ID

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
./scripts/linux/openc3_migrate_s3.sh start
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
