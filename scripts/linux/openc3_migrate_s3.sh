#!/bin/bash
#
# Migration script to transfer data from MINIO to versitygw (openc3-s3)
#
# This script:
# 1. Starts versitygw on a temporary port (9002) with a new volume
# 2. Uses mc to mirror all data from MINIO to versitygw
# 3. Provides instructions for completing the migration
#
# Prerequisites:
# - MINIO (openc3-minio) must be running
# - mc (MINIO client) must be installed
# - Docker must be running

set -e

# Configuration
MINIO_URL="${OPENC3_BUCKET_URL:-http://localhost:9000}"
MINIO_USER="${OPENC3_BUCKET_USERNAME:-openc3minio}"
MINIO_PASS="${OPENC3_BUCKET_PASSWORD:-openc3miniopassword}"
VERSITY_PORT="9002"
VERSITY_URL="http://localhost:${VERSITY_PORT}"
NEW_VOLUME="openc3-s3-v"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [start|migrate|status|cleanup|help]"
    echo ""
    echo "Migrate data from MINIO (openc3-bucket-v) to versitygw (openc3-s3-v)."
    echo ""
    echo "Commands:"
    echo "  start     Start versitygw on temporary port (9002) for migration"
    echo "  migrate   Mirror data from MINIO to versitygw using mc"
    echo "  status    Check migration status and bucket contents"
    echo "  cleanup   Remove temporary versitygw container (after successful migration)"
    echo "  help      Show this help message"
    echo ""
    echo "Migration workflow:"
    echo "  1. Ensure MINIO is running: ./openc3.sh run"
    echo "  2. Start temporary versitygw: $0 start"
    echo "  3. Migrate data: $0 migrate"
    echo "  4. Verify data: $0 status"
    echo "  5. Stop all services: ./openc3.sh stop"
    echo "  6. Cleanup temp container: $0 cleanup"
    echo "  7. Start with versitygw: ./openc3.sh run"
    echo ""
    echo "The compose.yaml is already configured to use the new volume (openc3-s3-v)."
    echo ""
    exit 0
}

check_mc() {
    if ! command -v mc &> /dev/null; then
        echo -e "${RED}Error: mc (MINIO client) is not installed${NC}"
        echo ""
        echo "Install mc:"
        echo "  macOS:  brew install minio/stable/mc"
        echo "  Linux:  wget https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && sudo mv mc /usr/local/bin/"
        exit 1
    fi
}

check_minio_running() {
    if ! curl -sf "${MINIO_URL}/minio/health/live" > /dev/null 2>&1; then
        echo -e "${RED}Error: MINIO is not running at ${MINIO_URL}${NC}"
        echo "Start MINIO first with: ./openc3.sh run"
        exit 1
    fi
    echo -e "${GREEN}✓ MINIO is running at ${MINIO_URL}${NC}"
}

start_versitygw() {
    echo "Starting temporary versitygw container for migration..."

    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^openc3-s3-migration$"; then
        echo -e "${YELLOW}Migration container already exists. Checking status...${NC}"
        if docker ps --format '{{.Names}}' | grep -q "^openc3-s3-migration$"; then
            echo -e "${GREEN}✓ Migration container is already running${NC}"
            return 0
        else
            echo "Starting existing container..."
            docker start openc3-s3-migration
            sleep 2
            return 0
        fi
    fi

    # Create new volume if it doesn't exist
    if ! docker volume ls --format '{{.Name}}' | grep -q "^${NEW_VOLUME}$"; then
        echo "Creating new volume: ${NEW_VOLUME}"
        docker volume create "${NEW_VOLUME}"
    fi

    # Build the openc3-s3 image if it doesn't exist
    if ! docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -q "openc3inc/openc3-s3:latest"; then
        echo "Building openc3-s3 image..."
        cd "${PROJECT_DIR}"
        docker compose -f compose-build.yaml build openc3-s3
    fi

    # Start versitygw on temporary port
    echo "Starting versitygw on port ${VERSITY_PORT}..."
    docker run -d \
        --name openc3-s3-migration \
        --network openc3-cosmos-network \
        -p "${VERSITY_PORT}:9000" \
        -v "${NEW_VOLUME}:/data" \
        -e "ROOT_ACCESS_KEY=${MINIO_USER}" \
        -e "ROOT_SECRET_KEY=${MINIO_PASS}" \
        openc3inc/openc3-s3:latest

    # Wait for versitygw to be ready
    echo "Waiting for versitygw to be ready..."
    for i in {1..30}; do
        if curl -sf "${VERSITY_URL}/" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ versitygw is ready at ${VERSITY_URL}${NC}"
            return 0
        fi
        sleep 1
    done

    echo -e "${RED}Error: versitygw failed to start${NC}"
    docker logs openc3-s3-migration
    exit 1
}

configure_mc() {
    echo "Configuring mc aliases..."

    # Configure MINIO alias
    mc alias set openc3-minio "${MINIO_URL}" "${MINIO_USER}" "${MINIO_PASS}" --api S3v4 2>/dev/null || true
    echo -e "${GREEN}✓ Configured openc3-minio alias${NC}"

    # Configure versitygw alias
    mc alias set openc3-s3 "${VERSITY_URL}" "${MINIO_USER}" "${MINIO_PASS}" --api S3v4 2>/dev/null || true
    echo -e "${GREEN}✓ Configured openc3-s3 alias${NC}"
}

migrate_data() {
    echo ""
    echo "=========================================="
    echo "Starting data migration from MINIO to versitygw"
    echo "=========================================="
    echo ""

    check_mc
    check_minio_running

    # Check if versitygw migration container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^openc3-s3-migration$"; then
        echo -e "${RED}Error: Migration container is not running${NC}"
        echo "Start it first with: $0 start"
        exit 1
    fi

    configure_mc

    # List buckets in MINIO
    echo ""
    echo "Buckets in MINIO:"
    mc ls openc3-minio/
    echo ""

    # Get list of buckets
    BUCKETS=$(mc ls openc3-minio/ --json 2>/dev/null | grep -o '"key":"[^"]*"' | cut -d'"' -f4 | tr -d '/')

    if [ -z "$BUCKETS" ]; then
        echo -e "${YELLOW}No buckets found in MINIO${NC}"
        return 0
    fi

    # Create buckets and mirror data
    for bucket in $BUCKETS; do
        echo ""
        echo -e "${YELLOW}Processing bucket: ${bucket}${NC}"

        # Create bucket in versitygw if it doesn't exist
        if ! mc ls "openc3-s3/${bucket}" > /dev/null 2>&1; then
            echo "  Creating bucket: ${bucket}"
            mc mb "openc3-s3/${bucket}" || true
        fi

        # Mirror data
        echo "  Mirroring data..."
        mc mirror --preserve --overwrite "openc3-minio/${bucket}" "openc3-s3/${bucket}"

        echo -e "${GREEN}  ✓ Bucket ${bucket} migrated${NC}"
    done

    echo ""
    echo -e "${GREEN}=========================================="
    echo "Migration complete!"
    echo "==========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify data: $0 status"
    echo "  2. Stop all services: ./openc3.sh stop"
    echo "  3. Cleanup temp container: $0 cleanup"
    echo "  4. Start with versitygw: ./openc3.sh run"
    echo ""
    echo "The compose.yaml is already configured to use the new volume (${NEW_VOLUME})."
    echo ""
}

show_status() {
    check_mc

    echo ""
    echo "=========================================="
    echo "Migration Status"
    echo "=========================================="
    echo ""

    # Check MINIO
    echo "MINIO (source):"
    if curl -sf "${MINIO_URL}/minio/health/live" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Running at ${MINIO_URL}${NC}"
        configure_mc 2>/dev/null
        echo "  Buckets:"
        mc ls openc3-minio/ 2>/dev/null | sed 's/^/    /'
    else
        echo -e "  ${RED}✗ Not running${NC}"
    fi

    echo ""

    # Check versitygw
    echo "versitygw (destination):"
    if docker ps --format '{{.Names}}' | grep -q "^openc3-s3-migration$"; then
        echo -e "  ${GREEN}✓ Migration container running${NC}"
        if curl -sf "${VERSITY_URL}/" > /dev/null 2>&1; then
            echo "  Buckets:"
            mc ls openc3-s3/ 2>/dev/null | sed 's/^/    /'
        fi
    else
        echo -e "  ${YELLOW}○ Migration container not running${NC}"
    fi

    echo ""

    # Check volumes
    echo "Docker volumes:"
    echo "  openc3-bucket-v (MINIO):"
    docker volume ls --format '  {{.Name}}' | grep openc3-bucket-v || echo "    (not found)"
    echo "  ${NEW_VOLUME} (versitygw):"
    docker volume ls --format '  {{.Name}}' | grep "${NEW_VOLUME}" || echo "    (not found)"
    echo ""
}

cleanup() {
    echo "Cleaning up migration container..."

    if docker ps -a --format '{{.Names}}' | grep -q "^openc3-s3-migration$"; then
        docker stop openc3-s3-migration 2>/dev/null || true
        docker rm openc3-s3-migration 2>/dev/null || true
        echo -e "${GREEN}✓ Migration container removed${NC}"
    else
        echo "Migration container not found"
    fi

    # Remove mc aliases
    mc alias rm openc3-minio 2>/dev/null || true
    mc alias rm openc3-s3 2>/dev/null || true

    echo ""
    echo "Note: The new volume '${NEW_VOLUME}' has been preserved with your migrated data."
    echo ""
    echo "The compose.yaml is already configured to use '${NEW_VOLUME}'."
    echo "You can now start COSMOS with versitygw:"
    echo "  ./openc3.sh run"
    echo ""
    echo "After verifying everything works, you can optionally remove the old MINIO volume:"
    echo "  docker volume rm openc3-bucket-v"
    echo ""
}

# Main
case "${1:-help}" in
    start)
        check_mc
        check_minio_running
        start_versitygw
        ;;
    migrate)
        migrate_data
        ;;
    status)
        show_status
        ;;
    cleanup)
        cleanup
        ;;
    help|--help|-h|*)
        usage
        ;;
esac
