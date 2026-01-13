#!/bin/bash
#
# Benchmark script for openc3_migrate_s3.sh
#
# Tests migration performance with different data sizes:
# - 100MB
# - 1GB
# - 10GB
#
# Prerequisites:
# - COSMOS must be running: ./openc3.sh run
# - Migration container must be started: ./openc3_migrate_s3.sh start

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output (using $'...' syntax for portability)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

# Configuration
MINIO_USER="${OPENC3_BUCKET_USERNAME:-openc3minio}"
MINIO_PASS="${OPENC3_BUCKET_PASSWORD:-openc3miniopassword}"
MC_IMAGE="openc3inc/openc3-cosmos-init:latest"
BENCHMARK_BUCKET="benchmark-test"

# Auto-detect Docker network and MINIO container
detect_docker_environment() {
    MINIO_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i minio | head -1)
    if [ -z "$MINIO_CONTAINER" ]; then
        echo "${RED}Error: Could not find running MINIO container${NC}"
        echo "Make sure COSMOS is running: ./openc3.sh run"
        exit 1
    fi

    DOCKER_NETWORK=$(docker inspect --format '{{range $net, $config := .NetworkSettings.Networks}}{{$net}}{{"\n"}}{{end}}' "$MINIO_CONTAINER" | grep -v '^$' | head -1)
    if [ -z "$DOCKER_NETWORK" ]; then
        echo "${RED}Error: Could not determine network for MINIO container${NC}"
        exit 1
    fi

    MINIO_SERVICE=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}' "$MINIO_CONTAINER" 2>/dev/null)
    if [ -z "$MINIO_SERVICE" ]; then
        MINIO_SERVICE="$MINIO_CONTAINER"
    fi
}

run_mc() {
    docker run --rm \
        --network "${DOCKER_NETWORK}" \
        -e "MC_HOST_openc3minio=http://${MINIO_USER}:${MINIO_PASS}@${MINIO_SERVICE}:9000" \
        -e "MC_HOST_openc3s3=http://${MINIO_USER}:${MINIO_PASS}@openc3-buckets-migration:9000" \
        "${MC_IMAGE}" \
        mc "$@"
}

# Generate test data and upload to MINIO
# Args: $1 = size in MB
# Default file size is 50MB (matching the default log cycle size)
# Can be overridden with --file-size option
FILE_SIZE_MB=${FILE_SIZE_MB:-50}

generate_test_data() {
    local size_mb=$1
    local num_files=$((size_mb / FILE_SIZE_MB))

    echo "${CYAN}Generating ${size_mb}MB of test data (${num_files} files of ${FILE_SIZE_MB}MB each)...${NC}"

    # Create bucket if it doesn't exist
    run_mc mb "openc3minio/${BENCHMARK_BUCKET}" 2>/dev/null || true

    # Generate and upload files using dd inside docker
    for i in $(seq 1 $num_files); do
        local filename="testfile_${size_mb}mb_${i}.bin"
        echo "  Creating and uploading ${filename}..."

        # Generate random data and pipe directly to mc
        docker run --rm \
            --network "${DOCKER_NETWORK}" \
            -e "MC_HOST_openc3minio=http://${MINIO_USER}:${MINIO_PASS}@${MINIO_SERVICE}:9000" \
            "${MC_IMAGE}" \
            sh -c "dd if=/dev/urandom bs=1M count=${FILE_SIZE_MB} 2>/dev/null | mc pipe openc3minio/${BENCHMARK_BUCKET}/${filename}"
    done

    echo "${GREEN}✓ Test data uploaded${NC}"
}

# Clean up test data from both MINIO and versitygw
cleanup_test_data() {
    echo "${YELLOW}Cleaning up test data...${NC}"

    # Remove from MINIO
    run_mc rb --force "openc3minio/${BENCHMARK_BUCKET}" 2>/dev/null || true

    # Remove from versitygw
    run_mc rb --force "openc3s3/${BENCHMARK_BUCKET}" 2>/dev/null || true

    echo "${GREEN}✓ Test data cleaned up${NC}"
}

# Get current time in seconds with decimal precision
# Works on both Linux and macOS
get_time() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: use perl for sub-second precision
        perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
    else
        # Linux: date supports nanoseconds
        date +%s.%N
    fi
}

# Run migration and measure time
# Returns: time in seconds (to stdout)
run_migration_benchmark() {
    echo "${CYAN}Running migration...${NC}" >&2

    # Create bucket in versitygw
    run_mc mb "openc3s3/${BENCHMARK_BUCKET}" >/dev/null 2>&1 || true

    # Time the mirror operation
    local start_time=$(get_time)

    run_mc mirror --preserve --overwrite "openc3minio/${BENCHMARK_BUCKET}" "openc3s3/${BENCHMARK_BUCKET}" >&2

    local end_time=$(get_time)
    local duration=$(echo "$end_time - $start_time" | bc)

    # Only the duration goes to stdout (for capture)
    echo "$duration"
}

# Calculate transfer rate
calc_rate() {
    local size_mb=$1
    local duration=$2

    # Handle empty or zero duration
    if [ -z "$duration" ] || [ "$duration" = "0" ]; then
        echo "N/A"
        return
    fi

    # Check if duration is a valid number
    if ! echo "$duration" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        echo "N/A"
        return
    fi

    local rate=$(echo "scale=2; $size_mb / $duration" | bc 2>/dev/null)
    if [ -z "$rate" ]; then
        echo "N/A"
    else
        echo "$rate"
    fi
}

# Format duration
format_duration() {
    local seconds=$1

    # Handle empty or invalid input
    if [ -z "$seconds" ] || ! echo "$seconds" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        echo "N/A"
        return
    fi

    if (( $(echo "$seconds < 60" | bc -l) )); then
        printf "%.2f seconds" "$seconds"
    elif (( $(echo "$seconds < 3600" | bc -l) )); then
        local mins=$(echo "scale=0; $seconds / 60" | bc)
        local secs=$(echo "scale=2; $seconds - ($mins * 60)" | bc)
        printf "%d min %.2f sec" "$mins" "$secs"
    else
        local hours=$(echo "scale=0; $seconds / 3600" | bc)
        local mins=$(echo "scale=0; ($seconds - $hours * 3600) / 60" | bc)
        local secs=$(echo "scale=2; $seconds - ($hours * 3600) - ($mins * 60)" | bc)
        printf "%d hr %d min %.2f sec" "$hours" "$mins" "$secs"
    fi
}

# Run a single benchmark
run_benchmark() {
    local size_mb=$1
    local label=$2
    local num_files=$((size_mb / FILE_SIZE_MB))

    echo ""
    echo "${YELLOW}=========================================="
    echo "Benchmark: ${label}"
    echo "==========================================${NC}"
    echo ""

    # Generate test data
    generate_test_data "$size_mb"

    # Run migration and capture duration
    local duration=$(run_migration_benchmark)

    # Calculate rate
    local rate=$(calc_rate "$size_mb" "$duration")
    local formatted_duration=$(format_duration "$duration")

    # Clean up
    cleanup_test_data

    echo ""
    echo "${GREEN}Results for ${label}:${NC}"
    echo "  Data size:     ${size_mb} MB (${num_files} x ${FILE_SIZE_MB}MB files)"
    echo "  Duration:      ${formatted_duration}"
    echo "  Transfer rate: ${rate} MB/s"
    echo ""

    # Return values for summary
    BENCHMARK_RESULTS+=("${label}|${size_mb}|${num_files}|${duration}|${rate}")
}

usage() {
    echo "Usage: $0 [--file-size MB] [all|100mb|1gb|10gb|custom SIZE_MB]"
    echo ""
    echo "Benchmark the S3 migration script with different data sizes."
    echo ""
    echo "Options:"
    echo "  --file-size MB   Set the size of each test file (default: 50MB)"
    echo ""
    echo "Commands:"
    echo "  all              Run all benchmarks (100MB, 1GB, 10GB)"
    echo "  100mb            Run 100MB benchmark only"
    echo "  1gb              Run 1GB benchmark only"
    echo "  10gb             Run 10GB benchmark only"
    echo "  custom SIZE_MB   Run custom benchmark (SIZE in MB)"
    echo ""
    echo "Prerequisites:"
    echo "  1. COSMOS must be running: ./openc3.sh run"
    echo "  2. Migration container must be started: ./openc3_migrate_s3.sh start"
    echo ""
    echo "Examples:"
    echo "  $0 all                       # Run all benchmarks with 50MB files"
    echo "  $0 --file-size 10 all        # Run all benchmarks with 10MB files"
    echo "  $0 --file-size 100 1gb       # Test 1GB with 100MB files"
    echo "  $0 custom 500                # Test 500MB with default 50MB files"
    echo ""
    exit 0
}

print_summary() {
    echo ""
    echo "${GREEN}=========================================="
    echo "BENCHMARK SUMMARY"
    echo "==========================================${NC}"
    echo ""
    echo "File size: ${FILE_SIZE_MB}MB per file"
    echo ""
    printf "%-15s %10s %10s %15s %12s\n" "Test" "Size (MB)" "Files" "Duration" "Rate (MB/s)"
    printf "%-15s %10s %10s %15s %12s\n" "---------------" "----------" "----------" "---------------" "------------"

    for result in "${BENCHMARK_RESULTS[@]}"; do
        IFS='|' read -r label size_mb num_files duration rate <<< "$result"
        formatted=$(format_duration "$duration")
        printf "%-15s %10s %10s %15s %12s\n" "$label" "$size_mb" "$num_files" "$formatted" "$rate"
    done

    echo ""

    # Estimate times for larger datasets based on measured rate
    if [ ${#BENCHMARK_RESULTS[@]} -gt 0 ]; then
        # Use the largest test's rate for estimation
        local last_index=$((${#BENCHMARK_RESULTS[@]} - 1))
        local last_result="${BENCHMARK_RESULTS[$last_index]}"
        IFS='|' read -r label size_mb num_files duration rate <<< "$last_result"

        echo "${CYAN}Estimated times based on measured rate (${rate} MB/s):${NC}"
        for estimate_gb in 50 100 500 1000; do
            local estimate_mb=$((estimate_gb * 1024))
            local est_seconds=$(echo "scale=2; $estimate_mb / $rate" | bc)
            local est_formatted=$(format_duration "$est_seconds")
            printf "  %4d GB: %s\n" "$estimate_gb" "$est_formatted"
        done
        echo ""
    fi
}

# Check prerequisites
check_prerequisites() {
    echo "${CYAN}Checking prerequisites...${NC}"

    # Check for bc command
    if ! command -v bc &> /dev/null; then
        echo "${RED}Error: 'bc' command not found. Install it first.${NC}"
        exit 1
    fi

    # Validate FILE_SIZE_MB
    if ! [[ "$FILE_SIZE_MB" =~ ^[0-9]+$ ]] || [ "$FILE_SIZE_MB" -lt 1 ]; then
        echo "${RED}Error: --file-size must be a positive integer${NC}"
        exit 1
    fi

    # Check Docker
    if ! docker ps &> /dev/null; then
        echo "${RED}Error: Docker is not running${NC}"
        exit 1
    fi

    detect_docker_environment
    echo "${GREEN}✓ MINIO container: ${MINIO_CONTAINER}${NC}"
    echo "${GREEN}✓ Docker network: ${DOCKER_NETWORK}${NC}"

    # Check migration container
    if ! docker ps --format '{{.Names}}' | grep -q "^openc3-buckets-migration$"; then
        echo "${RED}Error: Migration container is not running${NC}"
        echo "Start it first with: ./openc3_migrate_s3.sh start"
        exit 1
    fi
    echo "${GREEN}✓ Migration container is running${NC}"

    # Check mc image
    if ! docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -q "openc3inc/openc3-cosmos-init:latest"; then
        echo "${RED}Error: openc3-cosmos-init image not found${NC}"
        echo "Build the image first: ./openc3.sh build"
        exit 1
    fi
    echo "${GREEN}✓ MC image available${NC}"
    echo "${GREEN}✓ File size: ${FILE_SIZE_MB}MB per file${NC}"

    echo ""
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file-size)
            FILE_SIZE_MB="$2"
            shift 2
            ;;
        --file-size=*)
            FILE_SIZE_MB="${1#*=}"
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Main
BENCHMARK_RESULTS=()

case "${1:-help}" in
    all)
        check_prerequisites
        echo "${GREEN}Running all benchmarks...${NC}"
        run_benchmark 100 "100MB"
        run_benchmark 1000 "1GB"
        run_benchmark 10000 "10GB"
        print_summary
        ;;
    100mb)
        check_prerequisites
        run_benchmark 100 "100MB"
        print_summary
        ;;
    1gb)
        check_prerequisites
        run_benchmark 1000 "1GB"
        print_summary
        ;;
    10gb)
        check_prerequisites
        run_benchmark 10000 "10GB"
        print_summary
        ;;
    custom)
        if [ -z "$2" ]; then
            echo "${RED}Error: custom requires SIZE_MB argument${NC}"
            echo "Usage: $0 custom SIZE_MB"
            exit 1
        fi
        check_prerequisites
        run_benchmark "$2" "Custom ${2}MB"
        print_summary
        ;;
    help|--help|-h|*)
        usage
        ;;
esac
