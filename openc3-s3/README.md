# OpenC3 S3 Gateway (versitygw)

This directory contains the Dockerfile and configuration for the versitygw S3 gateway, which replaces MINIO as the S3-compatible storage backend.

## About versitygw

[Versity Gateway](https://github.com/versity/versitygw) is a high-performance S3 to file translation tool that bridges the gap between S3-reliant applications and POSIX storage systems.

## Building

The container is built from source using the version specified in the Dockerfile (`OPENC3_VERSITYGW_VERSION`).

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ROOT_ACCESS_KEY` | S3 access key for authentication | - |
| `ROOT_SECRET_KEY` | S3 secret key for authentication | - |
| `VGW_PORT` | Port to listen on | `:9000` |
| `VGW_BACKEND` | Storage backend type | `posix` |
| `VGW_BACKEND_ARG` | Backend argument (path for posix) | `/data` |

For compatibility, the entrypoint also accepts MINIO-style credentials:
- `MINIO_ROOT_USER` (mapped to `ROOT_ACCESS_KEY`)
- `MINIO_ROOT_PASSWORD` (mapped to `ROOT_SECRET_KEY`)

## Migrating from MINIO

### Data Preservation

MINIO stores data in a specific internal format that is not directly compatible with versitygw's POSIX backend. To migrate existing data, you must use the MINIO client (`mc`) to transfer data via the S3 API.

### Automated Migration (Recommended)

Use the provided migration script for a safe, side-by-side migration:

```bash
# 1. Install mc (MINIO client) if not already installed
# macOS
brew install minio/stable/mc
# Linux
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && sudo mv mc /usr/local/bin/

# 2. Ensure MINIO is running
./openc3.sh run

# 3. Start temporary versitygw container for migration
./scripts/linux/openc3_migrate_s3.sh start

# 4. Migrate all data from MINIO to versitygw
./scripts/linux/openc3_migrate_s3.sh migrate

# 5. Verify the migration
./scripts/linux/openc3_migrate_s3.sh status

# 6. Stop all services
./openc3.sh stop

# 7. Cleanup migration container
./scripts/linux/openc3_migrate_s3.sh cleanup

# 8. compose.yaml already uses openc3-s3-v, so just start COSMOS

# 9. Start with versitygw
./openc3.sh run
```

The migration script:
- Runs versitygw on a temporary port (9002) alongside MINIO
- Creates the new volume (`openc3-s3-v`) for versitygw
- Uses `mc mirror` to copy all buckets and objects
- Preserves object metadata and timestamps

### Manual Migration Steps

If you prefer to migrate manually:

1. **Ensure MINIO is running** and accessible

2. **Install mc (MINIO client)**:
   ```bash
   # macOS
   brew install minio/stable/mc

   # Linux
   wget https://dl.min.io/client/mc/release/linux-amd64/mc
   chmod +x mc
   sudo mv mc /usr/local/bin/
   ```

3. **Configure mc to connect to your MINIO instance**:
   ```bash
   mc alias set openc3minio http://localhost:9000 openc3minio openc3miniopassword
   ```

4. **Export data from MINIO** to a local directory:
   ```bash
   # List all buckets
   mc ls openc3minio

   # Mirror all buckets to a local backup directory
   mc mirror --preserve openc3minio /path/to/backup
   ```

5. **Stop MINIO and switch to versitygw** by updating compose.yaml

6. **Start versitygw** and verify it's running:
   ```bash
   docker compose up -d openc3-s3
   ```

7. **Import data into versitygw**:
   ```bash
   mc alias set openc3s3 http://localhost:9000 openc3minio openc3miniopassword

   # Create buckets
   mc mb openc3s3/config
   mc mb openc3s3/logs
   mc mb openc3s3/tools

   # Copy data back
   mc mirror --preserve /path/to/backup openc3s3
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
