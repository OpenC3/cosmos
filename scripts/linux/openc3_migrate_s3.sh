#!/bin/bash
#
# Migration script to transfer data from MINIO (COSMOS 6) to versitygw (COSMOS 7)
#
# This script supports multiple migration scenarios:
# 1. Pre-migration while COSMOS 6 is running (uses live MINIO, starts temp versitygw)
# 2. Post-migration after COSMOS 6 stopped (starts temp MINIO, starts temp versitygw)
# 3. Migration with COSMOS 7 running (starts temp MINIO, uses live versitygw)
#
# The script is idempotent - mc mirror only copies new/changed files, so it's safe
# to run multiple times. This allows users to pre-migrate data while COSMOS 6 is
# running, then do a final sync after shutdown to minimize downtime.
#
# Prerequisites:
# - Docker must be running
# - The old MINIO volume (OLD_VOLUME) must exist
# - For pre-migration: openc3-buckets image must be available (pulled or built)
#
# Migration workflow for upgrading from COSMOS 6 to COSMOS 7:
# 1. (Optional) While COSMOS 6 is running, run: ./openc3_migrate_s3.sh start && ./openc3_migrate_s3.sh migrate
# 2. Stop COSMOS 6: ./openc3.sh stop
# 3. Upgrade to COSMOS 7
# 4. Run final migration: ./openc3_migrate_s3.sh migrate
# 5. Cleanup: ./openc3_migrate_s3.sh cleanup
# 6. Start COSMOS 7: ./openc3.sh run

set -e

# Configuration - these can be overridden by environment variables
# MINIO credentials (source - COSMOS 6 defaults)
MINIO_USER="${MINIO_ROOT_USER:-openc3minio}"
MINIO_PASS="${MINIO_ROOT_PASSWORD:-openc3miniopassword}"
# Versitygw credentials (destination - uses COSMOS 7 bucket credentials)
VERSITY_USER="${OPENC3_BUCKET_USERNAME:-openc3bucket}"
VERSITY_PASS="${OPENC3_BUCKET_PASSWORD:-openc3bucketpassword}"
OLD_VOLUME="${OLD_VOLUME:-openc3-bucket-v}"
NEW_VOLUME="${NEW_VOLUME:-openc3-object-v}"
# User IDs - must match openc3.sh behavior
# openc3.sh sets these to current user (id -u/id -g) for non-rootless Docker
if [[ -z "$OPENC3_USER_ID" ]]; then
    if docker info 2>/dev/null | grep -qE "rootless$|rootless: true"; then
        # Rootless - use 0
        OPENC3_USER_ID=0
        OPENC3_GROUP_ID=0
    else
        # Not rootless - use current user (matches openc3.sh)
        OPENC3_USER_ID=$(id -u)
        OPENC3_GROUP_ID=$(id -g)
    fi
fi
OPENC3_GROUP_ID="${OPENC3_GROUP_ID:-1001}"

# Container/image names
MINIO_MIGRATION_CONTAINER="openc3-minio-migration"
VERSITY_MIGRATION_CONTAINER="openc3-versity-migration"
MINIO_IMAGE="ghcr.io/openc3/openc3-minio:latest"
VERSITY_IMAGE="${OPENC3_REGISTRY:-docker.io}/${OPENC3_NAMESPACE:-openc3inc}/openc3-buckets:${OPENC3_TAG:-latest}"
MC_IMAGE="ghcr.io/openc3/openc3-cosmos-init:6.10.4"  # Contains patched mc client

# Network - will be auto-detected or created
MIGRATION_NETWORK="openc3-migration-net"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# State variables
MINIO_SOURCE=""        # Where to read MINIO data from (live or temp container)
VERSITY_DEST=""        # Where to write versitygw data to (live or temp container)
USING_TEMP_MINIO=false
USING_TEMP_VERSITY=false
DOCKER_NETWORK=""

usage() {
    cat << EOF
Usage: $0 [start|migrate|status|cleanup|help]

Migrate data from MINIO (COSMOS 6) to versitygw (COSMOS 7).

This script is idempotent and can be run multiple times safely. It supports:
- Pre-migration while COSMOS 6 is running (to minimize downtime)
- Post-migration after COSMOS 6 is stopped
- Incremental sync (only copies new/changed files)

Commands:
  start     Start temporary containers needed for migration
  migrate   Mirror data from MINIO to versitygw (idempotent)
  status    Check migration status and compare bucket contents
  cleanup   Remove temporary migration containers
  help      Show this help message

Migration workflow:
  1. (Optional) Pre-migrate while COSMOS 6 is running:
     $0 start
     $0 migrate
     (repeat migrate as needed to sync new data)

  2. Stop COSMOS 6 and upgrade to COSMOS 7

  3. Final migration:
     $0 migrate

  4. Cleanup and start COSMOS 7:
     $0 cleanup
     ./openc3.sh run

Configuration (via environment variables):
  OLD_VOLUME    Old MINIO volume name (default: openc3-bucket-v)
  NEW_VOLUME    New versitygw volume name (default: openc3-object-v)
  OPENC3_BUCKET_USERNAME  S3 credentials (default: openc3minio)
  OPENC3_BUCKET_PASSWORD  S3 credentials (default: openc3miniopassword)

EOF
    exit 0
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Check if a Docker container is running
container_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^$1$"
}

# Check if a Docker container exists (running or stopped)
container_exists() {
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^$1$"
}

# Check if a Docker volume exists
volume_exists() {
    docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^$1$"
}

# Check if a Docker network exists
network_exists() {
    docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^$1$"
}

# Find a running container by partial name match
find_container() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -E "$1" | grep -v migration | head -1
}

# Get the network a container is connected to
get_container_network() {
    docker inspect --format '{{range $net, $config := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' "$1" 2>/dev/null | grep -v '^$' | head -1
}

# Ensure migration network exists
ensure_network() {
    if [[ -n "$DOCKER_NETWORK" ]]; then
        return 0
    fi

    # Try to find an existing COSMOS network
    local cosmos_container
    cosmos_container=$(find_container "openc3-buckets|openc3-minio")
    if [[ -n "$cosmos_container" ]]; then
        DOCKER_NETWORK=$(get_container_network "$cosmos_container")
        if [[ -n "$DOCKER_NETWORK" ]]; then
            log_info "Using existing Docker network: $DOCKER_NETWORK"
            return 0
        fi
    fi

    # Create migration network if needed
    if ! network_exists "$MIGRATION_NETWORK"; then
        log_info "Creating migration network: $MIGRATION_NETWORK"
        docker network create "$MIGRATION_NETWORK" >/dev/null
    fi
    DOCKER_NETWORK="$MIGRATION_NETWORK"
    log_info "Using migration network: $DOCKER_NETWORK"
}

# Detect the current environment and set up source/destination
detect_environment() {
    log_step "Detecting environment..."

    # Check for old volume
    local volume_prefix=""
    if ! volume_exists "$OLD_VOLUME"; then
        # Check with common prefixes (docker compose adds project name)
        local prefixed_old
        prefixed_old=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "^.+_${OLD_VOLUME}$" | head -1)
        if [[ -n "$prefixed_old" ]]; then
            volume_prefix="${prefixed_old%"${OLD_VOLUME}"}"
            OLD_VOLUME="$prefixed_old"
            log_info "Found old volume with prefix: $OLD_VOLUME"
        else
            log_error "Old MINIO volume '$OLD_VOLUME' not found"
            echo "This volume should exist from your COSMOS 6 installation."
            echo "If you haven't run COSMOS 6 before, there's nothing to migrate."
            exit 1
        fi
    else
        log_info "Found old MINIO volume: $OLD_VOLUME"
    fi

    # Apply the same prefix to new volume if one was detected
    if [[ -n "$volume_prefix" ]]; then
        NEW_VOLUME="${volume_prefix}${NEW_VOLUME}"
        log_info "Using matching prefix for new volume: $NEW_VOLUME"
    fi

    # Check for new volume (may not exist yet)
    if ! volume_exists "$NEW_VOLUME"; then
        log_info "New volume '$NEW_VOLUME' will be created"
    else
        log_info "Found new versitygw volume: $NEW_VOLUME"
    fi

    # Detect MINIO source (COSMOS 6 running or temp container)
    local live_minio
    live_minio=$(find_container "openc3-minio")
    if [[ -n "$live_minio" ]] && [[ "$live_minio" != "$MINIO_MIGRATION_CONTAINER" ]]; then
        MINIO_SOURCE="$live_minio"
        USING_TEMP_MINIO=false
        log_info "Found live MINIO (COSMOS 6): $MINIO_SOURCE"
        DOCKER_NETWORK=$(get_container_network "$MINIO_SOURCE")
    elif container_running "$MINIO_MIGRATION_CONTAINER"; then
        MINIO_SOURCE="$MINIO_MIGRATION_CONTAINER"
        USING_TEMP_MINIO=true
        log_info "Using temp MINIO container: $MINIO_SOURCE"
    else
        MINIO_SOURCE=""
        USING_TEMP_MINIO=true
        log_info "No MINIO running - will start temp container"
    fi

    # Detect versitygw destination (COSMOS 7 running or temp container)
    local live_versity
    live_versity=$(find_container "openc3-buckets")
    if [[ -n "$live_versity" ]] && [[ "$live_versity" != "$VERSITY_MIGRATION_CONTAINER" ]]; then
        VERSITY_DEST="$live_versity"
        USING_TEMP_VERSITY=false
        log_info "Found live versitygw (COSMOS 7): $VERSITY_DEST"
        if [[ -z "$DOCKER_NETWORK" ]]; then
            DOCKER_NETWORK=$(get_container_network "$VERSITY_DEST")
        fi
    elif container_running "$VERSITY_MIGRATION_CONTAINER"; then
        VERSITY_DEST="$VERSITY_MIGRATION_CONTAINER"
        USING_TEMP_VERSITY=true
        log_info "Using temp versitygw container: $VERSITY_DEST"
    else
        VERSITY_DEST=""
        USING_TEMP_VERSITY=true
        log_info "No versitygw running - will start temp container"
    fi

    ensure_network
}

# Start temporary MINIO container
start_temp_minio() {
    if container_running "$MINIO_MIGRATION_CONTAINER"; then
        log_info "Temp MINIO already running"
        MINIO_SOURCE="$MINIO_MIGRATION_CONTAINER"
        return 0
    fi

    if container_exists "$MINIO_MIGRATION_CONTAINER"; then
        log_info "Starting existing temp MINIO container..."
        docker start "$MINIO_MIGRATION_CONTAINER" >/dev/null
        sleep 2
        MINIO_SOURCE="$MINIO_MIGRATION_CONTAINER"
        return 0
    fi

    log_step "Starting temporary MINIO container..."
    # Note: We run as root because the original MINIO volume may have been created
    # by a container running as a different user. MINIO needs write access to
    # .minio.sys for internal metadata even when we're only reading data.
    docker run -d \
        --name "$MINIO_MIGRATION_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --user root \
        -v "${OLD_VOLUME}:/data" \
        -e "MINIO_ROOT_USER=${MINIO_USER}" \
        -e "MINIO_ROOT_PASSWORD=${MINIO_PASS}" \
        "$MINIO_IMAGE" \
        server --address ":9000" --console-address ":9001" /data >/dev/null

    # Wait for MINIO to be ready
    log_info "Waiting for MINIO to be ready..."
    local retries=0
    while [ $retries -lt 30 ]; do
        # Check if container is running and MINIO is responding
        # Use mc admin info which works reliably across MINIO versions
        if docker run --rm --network "$DOCKER_NETWORK" --entrypoint "" \
            -e "MC_HOST_minio=http://${MINIO_USER}:${MINIO_PASS}@${MINIO_MIGRATION_CONTAINER}:9000" \
            "$MC_IMAGE" mc admin info minio >/dev/null 2>&1; then
            log_info "MINIO is ready"
            MINIO_SOURCE="$MINIO_MIGRATION_CONTAINER"
            return 0
        fi
        sleep 1
        retries=$((retries + 1))
    done

    # Check if container is at least running
    if container_running "$MINIO_MIGRATION_CONTAINER"; then
        log_warn "MINIO health check timed out, but container is running. Proceeding anyway."
        MINIO_SOURCE="$MINIO_MIGRATION_CONTAINER"
        return 0
    fi

    log_error "MINIO failed to start"
    docker logs "$MINIO_MIGRATION_CONTAINER"
    exit 1
}

# Start temporary versitygw container
start_temp_versity() {
    if container_running "$VERSITY_MIGRATION_CONTAINER"; then
        log_info "Temp versitygw already running"
        VERSITY_DEST="$VERSITY_MIGRATION_CONTAINER"
        return 0
    fi

    if container_exists "$VERSITY_MIGRATION_CONTAINER"; then
        log_info "Starting existing temp versitygw container..."
        docker start "$VERSITY_MIGRATION_CONTAINER" >/dev/null
        sleep 2
        VERSITY_DEST="$VERSITY_MIGRATION_CONTAINER"
        return 0
    fi

    # Pull image if needed
    if ! docker image inspect "$VERSITY_IMAGE" >/dev/null 2>&1; then
        log_info "Pulling versitygw image: $VERSITY_IMAGE"
        docker pull "$VERSITY_IMAGE"
    fi

    log_step "Starting temporary versitygw container..."
    # Run as same user as production (matches compose.yaml)
    docker run -d \
        --name "$VERSITY_MIGRATION_CONTAINER" \
        --network "$DOCKER_NETWORK" \
        --user "${OPENC3_USER_ID:-1001}:${OPENC3_GROUP_ID:-1001}" \
        -v "${NEW_VOLUME}:/data" \
        -e "ROOT_ACCESS_KEY=${VERSITY_USER}" \
        -e "ROOT_SECRET_KEY=${VERSITY_PASS}" \
        "$VERSITY_IMAGE" >/dev/null

    # Wait for container to be running
    log_info "Waiting for versitygw to start..."
    sleep 2
    if container_running "$VERSITY_MIGRATION_CONTAINER"; then
        log_info "versitygw is ready"
        VERSITY_DEST="$VERSITY_MIGRATION_CONTAINER"
        return 0
    fi

    log_error "versitygw failed to start"
    docker logs "$VERSITY_MIGRATION_CONTAINER"
    exit 1
}

# Run mc command via docker using old init container with patched mc
run_mc() {
    docker run --rm \
        --network "$DOCKER_NETWORK" \
        --entrypoint "" \
        -e "MC_HOST_minio=http://${MINIO_USER}:${MINIO_PASS}@${MINIO_SOURCE}:9000" \
        -e "MC_HOST_versity=http://${VERSITY_USER}:${VERSITY_PASS}@${VERSITY_DEST}:9000" \
        "$MC_IMAGE" \
        mc "$@"
}

# Start command - ensure containers are running
cmd_start() {
    detect_environment

    # Start temp MINIO if no live MINIO
    if [[ -z "$MINIO_SOURCE" ]]; then
        start_temp_minio
    fi

    # Start temp versitygw if no live versitygw
    if [[ -z "$VERSITY_DEST" ]]; then
        start_temp_versity
    fi

    echo ""
    log_info "Migration containers ready"
    echo "  MINIO source: $MINIO_SOURCE"
    echo "  versitygw destination: $VERSITY_DEST"
    echo ""
    echo "Run '$0 migrate' to start migration"
}

# Migrate command - sync data from MINIO to versitygw
cmd_migrate() {
    detect_environment

    # Ensure source is available
    if [[ -z "$MINIO_SOURCE" ]]; then
        start_temp_minio
    fi

    # Ensure destination is available
    if [[ -z "$VERSITY_DEST" ]]; then
        start_temp_versity
    fi

    echo ""
    log_step "Starting data migration from MINIO to versitygw"
    echo "  Source: $MINIO_SOURCE (volume: $OLD_VOLUME)"
    echo "  Destination: $VERSITY_DEST (volume: $NEW_VOLUME)"
    echo ""

    # List buckets in MINIO
    log_info "Buckets in MINIO (source):"
    run_mc ls minio/ 2>/dev/null || true
    echo ""

    # Get list of buckets
    local buckets
    buckets=$(run_mc ls minio/ 2>/dev/null | awk '{print $NF}' | tr -d '/' | grep -v '^$' || true)

    if [[ -z "$buckets" ]]; then
        log_warn "No buckets found in MINIO - nothing to migrate"
        return 0
    fi

    # Migrate each bucket
    local bucket
    for bucket in $buckets; do
        echo ""
        log_step "Processing bucket: $bucket"

        # Create bucket in versitygw if it doesn't exist
        if ! run_mc ls "versity/${bucket}" >/dev/null 2>&1; then
            log_info "Creating bucket: $bucket"
            run_mc mb "versity/${bucket}" 2>/dev/null || true
        fi

        # Mirror data (idempotent - only copies new/changed files)
        log_info "Mirroring data..."
        if run_mc mirror --preserve "minio/${bucket}" "versity/${bucket}" 2>&1; then
            log_info "Bucket $bucket migrated successfully"
        else
            log_warn "Some files may have failed - check output above"
        fi
    done

    echo ""
    log_info "Migration complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify data: $0 status"
    echo "  2. If COSMOS 6 is still running, you can run '$0 migrate' again to sync new data"
    echo "  3. When ready, stop COSMOS 6, run final '$0 migrate', then '$0 cleanup'"
    echo "  4. Start COSMOS 7: ./openc3.sh run"
    echo ""
}

# Status command - show migration status
cmd_status() {
    detect_environment

    echo ""
    log_step "Migration Status"
    echo ""

    echo "Volumes:"
    echo "  Old (MINIO): $OLD_VOLUME"
    if volume_exists "$OLD_VOLUME"; then
        echo -e "    ${GREEN}exists${NC}"
    else
        echo -e "    ${YELLOW}not found${NC}"
    fi
    echo "  New (versitygw): $NEW_VOLUME"
    if volume_exists "$NEW_VOLUME"; then
        echo -e "    ${GREEN}exists${NC}"
    else
        echo -e "    ${YELLOW}not found${NC}"
    fi

    echo ""
    echo "Containers:"
    echo "  MINIO source: ${MINIO_SOURCE:-none}"
    if [[ -n "$MINIO_SOURCE" ]]; then
        echo -e "    ${GREEN}running${NC}"
    fi
    echo "  versitygw destination: ${VERSITY_DEST:-none}"
    if [[ -n "$VERSITY_DEST" ]]; then
        echo -e "    ${GREEN}running${NC}"
    fi

    # If both are running, compare bucket sizes
    if [[ -n "$MINIO_SOURCE" ]] && [[ -n "$VERSITY_DEST" ]]; then
        echo ""
        echo "Bucket sizes (source -> destination):"
        echo ""
        echo "  MINIO (source):"
        run_mc du minio/config 2>/dev/null | sed 's/^/    /' || echo "    config: (unable to get size)"
        run_mc du minio/logs 2>/dev/null | sed 's/^/    /' || echo "    logs: (unable to get size)"
        run_mc du minio/tools 2>/dev/null | sed 's/^/    /' || echo "    tools: (unable to get size)"
        echo ""
        echo "  versitygw (destination):"
        # versitygw uses POSIX storage, so check disk usage and file count directly
        docker exec "$VERSITY_DEST" sh -c 'for dir in config logs tools; do size=$(du -sm /data/$dir 2>/dev/null | cut -f1); count=$(find /data/$dir -type f 2>/dev/null | wc -l); printf "    %sMiB\t%s files\t%s\n" "$size" "$count" "$dir"; done' 2>/dev/null || echo "    (unable to get size)"
        echo ""
        log_info "If file counts match, migration was successful!"
    fi

    echo ""
}

# Cleanup command - remove temporary containers
cmd_cleanup() {
    # Resolve volume names with prefix detection for display
    if ! volume_exists "$OLD_VOLUME"; then
        local prefixed_old
        prefixed_old=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "^.+_${OLD_VOLUME}$" | head -1)
        if [[ -n "$prefixed_old" ]]; then
            NEW_VOLUME="${prefixed_old%"${OLD_VOLUME}"}${NEW_VOLUME}"
            OLD_VOLUME="$prefixed_old"
        fi
    fi

    log_step "Cleaning up migration containers..."

    if container_exists "$MINIO_MIGRATION_CONTAINER"; then
        docker stop "$MINIO_MIGRATION_CONTAINER" 2>/dev/null || true
        docker rm "$MINIO_MIGRATION_CONTAINER" 2>/dev/null || true
        log_info "Removed temp MINIO container"
    fi

    if container_exists "$VERSITY_MIGRATION_CONTAINER"; then
        docker stop "$VERSITY_MIGRATION_CONTAINER" 2>/dev/null || true
        docker rm "$VERSITY_MIGRATION_CONTAINER" 2>/dev/null || true
        log_info "Removed temp versitygw container"
    fi

    if network_exists "$MIGRATION_NETWORK"; then
        docker network rm "$MIGRATION_NETWORK" 2>/dev/null || true
        log_info "Removed migration network"
    fi

    echo ""
    log_info "Cleanup complete"
    echo ""
    echo "Your data has been migrated to volume '$NEW_VOLUME'."
    echo ""
    echo "After verifying COSMOS 7 works correctly, you can remove the old volume:"
    echo "  docker volume rm $OLD_VOLUME"
    echo ""
}

# Main
case "${1:-help}" in
    start)
        cmd_start
        ;;
    migrate)
        cmd_migrate
        ;;
    status)
        cmd_status
        ;;
    cleanup)
        cmd_cleanup
        ;;
    help|--help|-h|*)
        usage
        ;;
esac
