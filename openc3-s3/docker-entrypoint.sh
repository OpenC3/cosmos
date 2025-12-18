#!/bin/sh
#
# Docker entrypoint for versitygw S3 gateway

# If command starts with an option or is "versitygw", set up the full command
if [ "${1}" = "versitygw" ] || [ "${1#-}" != "$1" ]; then
    # Default port to 9000 for compatibility with existing OPENC3 configuration
    VGW_PORT="${VGW_PORT:-:9000}"
    export VGW_PORT

    # Map MINIO-style credentials to versitygw credentials if not already set
    if [ -z "${ROOT_ACCESS_KEY}" ] && [ -n "${MINIO_ROOT_USER}" ]; then
        export ROOT_ACCESS_KEY="${MINIO_ROOT_USER}"
    fi
    if [ -z "${ROOT_SECRET_KEY}" ] && [ -n "${MINIO_ROOT_PASSWORD}" ]; then
        export ROOT_SECRET_KEY="${MINIO_ROOT_PASSWORD}"
    fi

    # Default backend is posix with /data directory
    VGW_BACKEND="${VGW_BACKEND:-posix}"
    VGW_BACKEND_ARG="${VGW_BACKEND_ARG:-/data}"

    # Build the command
    if [ "${1}" = "versitygw" ]; then
        shift
    fi

    # If no arguments provided, use defaults
    if [ $# -eq 0 ]; then
        set -- versitygw "${VGW_BACKEND}" "${VGW_BACKEND_ARG}"
    else
        set -- versitygw "$@"
    fi
fi

exec "$@"
