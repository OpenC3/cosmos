#!/bin/bash
#
# Migration script to transfer data from old MINIO volume to new S3 (versitygw)
#
# This script:
# 1. Starts a temporary MINIO container using the old openc3-bucket-v volume
# 2. Uses mc to mirror all data from MINIO to the running openc3-s3 (versitygw)
# 3. Provides instructions for completing the migration
#
# Prerequisites:
# - COSMOS 7 must be running with openc3-s3 (versitygw)
# - Docker must be running
# - The old openc3-bucket-v volume must exist
# - openc3-cosmos-init image must be built (contains mc)
#
# Migration workflow:
# 1. Stop COSMOS 6
# 2. Upgrade to COSMOS 7 and start: ./openc3.sh run
# 3. Run this migration script to copy data from old volume to new S3

set -e

# Configuration
MINIO_USER="${OPENC3_BUCKET_USERNAME:-openc3minio}"
MINIO_PASS="${OPENC3_BUCKET_PASSWORD:-openc3miniopassword}"
MINIO_PORT="9002"
MINIO_URL="http://localhost:${MINIO_PORT}"
OLD_VOLUME="openc3-bucket-v"
NEW_VOLUME="openc3-s3-v"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Auto-detect Docker network and S3 container
detect_docker_environment() {
    # Find the openc3-s3 container (versitygw)
    S3_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E 'openc3-s3|s3' | grep -v migration | head -1)
    if [ -z "$S3_CONTAINER" ]; then
        echo -e "${RED}Error: Could not find running openc3-s3 container${NC}"
        echo "Make sure COSMOS 7 is running: ./openc3.sh run"
        exit 1
    fi
    echo -e "${GREEN}✓ Found S3 container: ${S3_CONTAINER}${NC}"

    # Get the network that the S3 container is connected to
    DOCKER_NETWORK=$(docker inspect --format '{{range $net, $config := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' "$S3_CONTAINER" | grep -v '^$' | head -1)
    if [ -z "$DOCKER_NETWORK" ]; then
        echo -e "${RED}Error: Could not determine network for S3 container${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Found Docker network: ${DOCKER_NETWORK}${NC}"

    # Get the service name from container labels (works with docker compose)
    S3_SERVICE=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}' "$S3_CONTAINER" 2>/dev/null)
    if [ -z "$S3_SERVICE" ]; then
        # Fallback: use container name
        S3_SERVICE="$S3_CONTAINER"
    fi
    echo -e "${GREEN}✓ S3 service name: ${S3_SERVICE}${NC}"
}

usage() {
    echo "Usage: $0 [start|migrate|status|cleanup|help]"
    echo ""
    echo "Migrate data from old MINIO volume (openc3-bucket-v) to new S3 (openc3-s3-v)."
    echo ""
    echo "Commands:"
    echo "  start     Start temporary MINIO on port 9002 using old volume for migration"
    echo "  migrate   Mirror data from MINIO to S3 (versitygw) using mc"
    echo "  status    Check migration status and bucket contents"
    echo "  cleanup   Remove temporary MINIO container (after successful migration)"
    echo "  help      Show this help message"
    echo ""
    echo "Migration workflow:"
    echo "  1. Stop COSMOS 6"
    echo "  2. Upgrade to COSMOS 7 and start: ./openc3.sh run"
    echo "  3. Start temporary MINIO: $0 start"
    echo "  4. Migrate data: $0 migrate"
    echo "  5. Verify data: $0 status"
    echo "  6. Cleanup temp container: $0 cleanup"
    echo "  7. (Optional) Remove old volume: docker volume rm openc3-bucket-v"
    echo ""
    exit 0
}

# Docker image containing mc
MC_IMAGE="openc3inc/openc3-cosmos-init:latest"

# Run mc commands via docker (must call detect_docker_environment first)
run_mc() {
    docker run --rm \
        --network "${DOCKER_NETWORK}" \
        -e "MC_HOST_openc3minio=http://${MINIO_USER}:${MINIO_PASS}@openc3-minio-migration:9000" \
        -e "MC_HOST_openc3s3=http://${MINIO_USER}:${MINIO_PASS}@${S3_SERVICE}:9000" \
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

check_s3_running() {
    # Run health check from inside the Docker network
    echo "Checking S3 (versitygw) connectivity..."

    for host in "${S3_SERVICE}" "${S3_CONTAINER}"; do
        HTTP_CODE=$(docker run --rm --network "${DOCKER_NETWORK}" "${MC_IMAGE}" \
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://${host}:9000/" 2>/dev/null)
        if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            echo -e "${GREEN}✓ S3 (versitygw) is reachable at ${host}:9000 (HTTP ${HTTP_CODE})${NC}"
            S3_SERVICE="${host}"
            return 0
        fi
    done

    echo -e "${RED}Error: S3 (versitygw) is not responding${NC}"
    echo "Tried: ${S3_SERVICE}:9000 and ${S3_CONTAINER}:9000"
    echo "Make sure COSMOS 7 is running: ./openc3.sh run"
    exit 1
}

check_old_volume_exists() {
    if ! docker volume ls --format '{{.Name}}' | grep -q "^${OLD_VOLUME}$"; then
        echo -e "${RED}Error: Old MINIO volume '${OLD_VOLUME}' not found${NC}"
        echo ""
        echo "This volume should exist from your COSMOS 6 installation."
        echo "If you haven't run COSMOS 6 before, there's nothing to migrate."
        exit 1
    fi
    echo -e "${GREEN}✓ Found old MINIO volume: ${OLD_VOLUME}${NC}"
}

start_minio() {
    echo "Starting temporary MINIO container for migration..."

    # Check if old volume exists
    check_old_volume_exists

    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^openc3-minio-migration$"; then
        echo -e "${YELLOW}Migration container already exists. Checking status...${NC}"
        if docker ps --format '{{.Names}}' | grep -q "^openc3-minio-migration$"; then
            echo -e "${GREEN}✓ Migration container is already running${NC}"
            return 0
        else
            echo "Starting existing container..."
            docker start openc3-minio-migration
            sleep 2
            return 0
        fi
    fi

    # Start MINIO on temporary port using the old volume
    echo "Starting MINIO on port ${MINIO_PORT} with old volume..."
    docker run -d \
        --name openc3-minio-migration \
        --network "${DOCKER_NETWORK}" \
        -p "${MINIO_PORT}:9000" \
        -v "${OLD_VOLUME}:/data" \
        -e "MINIO_ROOT_USER=${MINIO_USER}" \
        -e "MINIO_ROOT_PASSWORD=${MINIO_PASS}" \
        ghcr.io/openc3/openc3-minio:latest \
        server --address ":9000" --console-address ":9001" /data

    # Wait for MINIO to be ready (403 is expected for unauthenticated requests)
    echo "Waiting for MINIO to be ready..."
    for i in {1..30}; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${MINIO_URL}/" 2>/dev/null)
        if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            echo -e "${GREEN}✓ MINIO is ready at ${MINIO_URL} (HTTP ${HTTP_CODE})${NC}"
            return 0
        fi
        sleep 1
    done

    echo -e "${RED}Error: MINIO failed to start${NC}"
    docker logs openc3-minio-migration
    exit 1
}

migrate_data() {
    echo ""
    echo "=========================================="
    echo "Starting data migration from MINIO to S3"
    echo "=========================================="
    echo ""

    check_mc_image
    check_s3_running

    # Check if MINIO migration container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^openc3-minio-migration$"; then
        echo -e "${RED}Error: Migration MINIO container is not running${NC}"
        echo "Start it first with: $0 start"
        exit 1
    fi

    # List buckets in MINIO
    echo ""
    echo "Buckets in MINIO (source):"
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

        # Create bucket in S3 if it doesn't exist
        if ! run_mc ls "openc3s3/${bucket}" > /dev/null 2>&1; then
            echo "  Creating bucket: ${bucket}"
            run_mc mb "openc3s3/${bucket}" || true
        fi

        # Mirror data
        echo "  Mirroring data..."
        run_mc mirror --preserve --overwrite "openc3minio/${bucket}" "openc3s3/${bucket}"

        echo -e "${GREEN}  ✓ Bucket ${bucket} migrated${NC}"
    done

    echo ""
    echo -e "${GREEN}=========================================="
    echo "Migration complete!"
    echo "==========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify your data: $0 status"
    echo "  2. Cleanup temp container: $0 cleanup"
    echo "  3. (Optional) Remove old volume: docker volume rm ${OLD_VOLUME}"
    echo ""
}

show_status() {
    check_mc_image

    echo ""
    echo "=========================================="
    echo "Migration Status"
    echo "=========================================="
    echo ""

    # Check S3 (versitygw)
    echo "S3/versitygw (destination - COSMOS 7):"
    S3_REACHABLE=false
    for host in "${S3_SERVICE}" "${S3_CONTAINER}"; do
        HTTP_CODE=$(docker run --rm --network "${DOCKER_NETWORK}" "${MC_IMAGE}" \
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://${host}:9000/" 2>/dev/null)
        if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            echo -e "  ${GREEN}✓ Running at ${host}:9000${NC}"
            S3_SERVICE="${host}"
            S3_REACHABLE=true
            S3_BUCKETS=$(run_mc ls openc3s3/ 2>/dev/null | awk '{print $NF}' | tr '\n' ' ')
            echo -e "  Buckets: ${S3_BUCKETS}"
            break
        fi
    done
    if [ "$S3_REACHABLE" = "false" ]; then
        echo -e "  ${RED}✗ Not running${NC}"
        echo "  Make sure COSMOS 7 is running: ./openc3.sh run"
    fi

    echo ""

    # Check temporary MINIO
    echo "MINIO (source - temporary migration container):"
    if docker ps --format '{{.Names}}' | grep -q "^openc3-minio-migration$"; then
        echo -e "  ${GREEN}✓ Migration container running${NC}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${MINIO_URL}/" 2>/dev/null)
        if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
            MINIO_BUCKETS=$(run_mc ls openc3minio/ 2>/dev/null | awk '{print $NF}' | tr '\n' ' ')
            echo -e "  Buckets: ${MINIO_BUCKETS}"
            # Compare buckets
            if [ "$S3_REACHABLE" = "true" ] && [ "$MINIO_BUCKETS" = "$S3_BUCKETS" ]; then
                echo -e "  ${GREEN}✓ All buckets migrated successfully${NC}"
            elif [ -n "$S3_BUCKETS" ]; then
                echo -e "  ${YELLOW}○ Bucket list differs - verify migration${NC}"
            fi
        fi
    else
        echo -e "  ${YELLOW}○ Migration container not running${NC}"
        echo "  Start it with: $0 start"
    fi

    echo ""

    # Check volumes
    echo "Docker volumes:"
    echo "  ${OLD_VOLUME} (old MINIO data):"
    if docker volume ls --format '{{.Name}}' | grep -q "^${OLD_VOLUME}$"; then
        echo -e "    ${GREEN}✓ exists${NC}"
    else
        echo -e "    ${YELLOW}○ not found${NC}"
    fi
    echo "  ${NEW_VOLUME} (new S3 data):"
    if docker volume ls --format '{{.Name}}' | grep -q "^${NEW_VOLUME}$"; then
        echo -e "    ${GREEN}✓ exists${NC}"
    else
        echo -e "    ${YELLOW}○ not found${NC}"
    fi
    echo ""
}

cleanup() {
    echo "Cleaning up migration container..."

    if docker ps -a --format '{{.Names}}' | grep -q "^openc3-minio-migration$"; then
        docker stop openc3-minio-migration 2>/dev/null || true
        docker rm openc3-minio-migration 2>/dev/null || true
        echo -e "${GREEN}✓ Migration container removed${NC}"
    else
        echo "Migration container not found"
    fi

    echo ""
    echo "Migration cleanup complete."
    echo ""
    echo "Your data has been migrated to the new S3 volume '${NEW_VOLUME}'."
    echo "COSMOS 7 is already using this volume."
    echo ""
    echo "After verifying everything works, you can optionally remove the old MINIO volume:"
    echo "  docker volume rm ${OLD_VOLUME}"
    echo ""
}

# Main
case "${1:-help}" in
    start)
        check_mc_image
        detect_docker_environment
        check_s3_running
        start_minio
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
