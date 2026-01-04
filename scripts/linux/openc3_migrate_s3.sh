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
# - Docker must be running
# - openc3-cosmos-init image must be built (contains mc)

set -e

# Configuration
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

# Auto-detect Docker network and MINIO container
detect_docker_environment() {
    # Find the MINIO container first (look for minio in the name)
    MINIO_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i minio | head -1)
    if [ -z "$MINIO_CONTAINER" ]; then
        echo -e "${RED}Error: Could not find running MINIO container${NC}"
        echo "Make sure COSMOS is running: ./openc3.sh run"
        exit 1
    fi
    echo -e "${GREEN}✓ Found MINIO container: ${MINIO_CONTAINER}${NC}"

    # Get the network that the MINIO container is connected to
    DOCKER_NETWORK=$(docker inspect --format '{{range $net, $config := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' "$MINIO_CONTAINER" | grep -v '^$' | head -1)
    if [ -z "$DOCKER_NETWORK" ]; then
        echo -e "${RED}Error: Could not determine network for MINIO container${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Found Docker network: ${DOCKER_NETWORK}${NC}"

    # Get the service name from container labels (works with docker compose)
    MINIO_SERVICE=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}' "$MINIO_CONTAINER" 2>/dev/null)
    if [ -z "$MINIO_SERVICE" ]; then
        # Fallback: use container name
        MINIO_SERVICE="$MINIO_CONTAINER"
    fi
    echo -e "${GREEN}✓ MINIO service name: ${MINIO_SERVICE}${NC}"
}

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

# Docker image containing mc
MC_IMAGE="openc3inc/openc3-cosmos-init:latest"

# Run mc commands via docker (must call detect_docker_environment first)
run_mc() {
    docker run --rm \
        --network "${DOCKER_NETWORK}" \
        -e "MC_HOST_openc3minio=http://${MINIO_USER}:${MINIO_PASS}@${MINIO_SERVICE}:9000" \
        -e "MC_HOST_openc3s3=http://${MINIO_USER}:${MINIO_PASS}@openc3-s3-migration:9000" \
        "${MC_IMAGE}" \
        mc "$@"
}

check_mc_image() {
    if ! docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -q "openc3inc/openc3-cosmos-init:latest"; then
        echo -e "${RED}Error: openc3-cosmos-init image not found${NC}"
        echo ""
        echo "Build the image first:"
        echo "  ./openc3.sh build"
        exit 1
    fi
}

check_minio_running() {
    # Run health check from inside the Docker network
    # Try service name first, then container name as fallback
    # Accept any HTTP response (including 403) as "running"
    echo "Checking MINIO connectivity..."

    for host in "${MINIO_SERVICE}" "${MINIO_CONTAINER}"; do
        HTTP_CODE=$(docker run --rm --network "${DOCKER_NETWORK}" "${MC_IMAGE}" \
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://${host}:9000/" 2>/dev/null)
        if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            echo -e "${GREEN}✓ MINIO is reachable at ${host}:9000 (HTTP ${HTTP_CODE})${NC}"
            MINIO_SERVICE="${host}"
            return 0
        fi
    done

    echo -e "${RED}Error: MINIO is not responding${NC}"
    echo "Tried: ${MINIO_SERVICE}:9000 and ${MINIO_CONTAINER}:9000"
    echo "Make sure COSMOS is running: ./openc3.sh run"
    exit 1
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
        --network "${DOCKER_NETWORK}" \
        -p "${VERSITY_PORT}:9000" \
        -v "${NEW_VOLUME}:/data" \
        -e "ROOT_ACCESS_KEY=${MINIO_USER}" \
        -e "ROOT_SECRET_KEY=${MINIO_PASS}" \
        openc3inc/openc3-s3:latest

    # Wait for versitygw to be ready (403 is expected for unauthenticated requests)
    echo "Waiting for versitygw to be ready..."
    for i in {1..30}; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${VERSITY_URL}/" 2>/dev/null)
        if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            echo -e "${GREEN}✓ versitygw is ready at ${VERSITY_URL} (HTTP ${HTTP_CODE})${NC}"
            return 0
        fi
        sleep 1
    done

    echo -e "${RED}Error: versitygw failed to start${NC}"
    docker logs openc3-s3-migration
    exit 1
}

migrate_data() {
    echo ""
    echo "=========================================="
    echo "Starting data migration from MINIO to versitygw"
    echo "=========================================="
    echo ""

    check_mc_image
    check_minio_running

    # Check if versitygw migration container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^openc3-s3-migration$"; then
        echo -e "${RED}Error: Migration container is not running${NC}"
        echo "Start it first with: $0 start"
        exit 1
    fi

    # List buckets in MINIO
    echo ""
    echo "Buckets in MINIO:"
    run_mc ls openc3minio/
    echo ""

    # Get list of buckets
    BUCKETS=$(run_mc ls openc3minio/ --json 2>/dev/null | grep -o '"key":"[^"]*"' | cut -d'"' -f4 | tr -d '/')

    if [ -z "$BUCKETS" ]; then
        echo -e "${YELLOW}No buckets found in MINIO${NC}"
        return 0
    fi

    # Create buckets and mirror data
    for bucket in $BUCKETS; do
        echo ""
        echo -e "${YELLOW}Processing bucket: ${bucket}${NC}"

        # Create bucket in versitygw if it doesn't exist
        if ! run_mc ls "openc3s3/${bucket}" > /dev/null 2>&1; then
            echo "  Creating bucket: ${bucket}"
            run_mc mb "openc3s3/${bucket}" || true
        fi

        # Mirror data
        echo "  Mirroring data..."
        run_mc mirror --preserve --overwrite "openc3minio/${bucket}" "openc3s3/${bucket}"

        echo -e "${GREEN}  ✓ Bucket ${bucket} migrated${NC}"
    done

    # Fix permissions on the new volume to match the host user ID
    # The openc3.sh script sets OPENC3_USER_ID to `id -u` for rootful Docker
    HOST_UID=$(id -u)
    HOST_GID=$(id -g)
    echo ""
    echo "Fixing permissions on ${NEW_VOLUME} for host user ${HOST_UID}:${HOST_GID}..."
    docker run --rm -v "${NEW_VOLUME}:/data" alpine chown -R "${HOST_UID}:${HOST_GID}" /data
    echo -e "${GREEN}✓ Permissions fixed${NC}"

    echo ""
    echo -e "${GREEN}=========================================="
    echo "Migration complete!"
    echo "==========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Stop all services: ./openc3.sh stop"
    echo "  2. Start COSMOS with versitygw: ./openc3.sh run"
    echo "  3. Verify everything works and old data is accessible"
    echo "  4. Cleanup temp container: $0 cleanup"
    echo ""
}

show_status() {
    check_mc_image

    echo ""
    echo "=========================================="
    echo "Migration Status"
    echo "=========================================="
    echo ""

    # Check MINIO
    echo "MINIO (source):"
    MINIO_REACHABLE=false
    for host in "${MINIO_SERVICE}" "${MINIO_CONTAINER}"; do
        HTTP_CODE=$(docker run --rm --network "${DOCKER_NETWORK}" "${MC_IMAGE}" \
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://${host}:9000/" 2>/dev/null)
        if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            echo -e "  ${GREEN}✓ Running at ${host}:9000${NC}"
            MINIO_SERVICE="${host}"
            MINIO_REACHABLE=true
            MINIO_BUCKETS=$(run_mc ls openc3minio/ 2>/dev/null | awk '{print $NF}' | tr '\n' ' ')
            echo -e "  Buckets: ${MINIO_BUCKETS}"
            break
        fi
    done
    if [ "$MINIO_REACHABLE" = "false" ]; then
        echo -e "  ${RED}✗ Not running${NC}"
    fi

    echo ""

    # Check versitygw
    echo "versitygw (destination):"
    if docker ps --format '{{.Names}}' | grep -q "^openc3-s3-migration$"; then
        echo -e "  ${GREEN}✓ Migration container running${NC}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${VERSITY_URL}/" 2>/dev/null)
        if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            VERSITY_BUCKETS=$(run_mc ls openc3s3/ 2>/dev/null | awk '{print $NF}' | tr '\n' ' ')
            echo -e "  Buckets: ${VERSITY_BUCKETS}"
            # Compare buckets
            if [ "$MINIO_REACHABLE" = "true" ] && [ "$MINIO_BUCKETS" = "$VERSITY_BUCKETS" ]; then
                echo -e "  ${GREEN}✓ All buckets migrated successfully${NC}"
            elif [ -n "$VERSITY_BUCKETS" ]; then
                echo -e "  ${YELLOW}○ Bucket list differs from source${NC}"
            fi
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
        check_mc_image
        detect_docker_environment
        check_minio_running
        start_versitygw
        ;;
    migrate)
        detect_docker_environment
        migrate_data
        ;;
    status)
        detect_docker_environment
        show_status
        ;;
    cleanup)
        cleanup
        ;;
    help|--help|-h|*)
        usage
        ;;
esac
