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
    VGW_IAM_DIR="${VGW_IAM_DIR:-/data/.iam}"

    # Create IAM directory if it doesn't exist
    mkdir -p "${VGW_IAM_DIR}"

    # Pre-create ScriptRunner user account if credentials are provided and different from root
    # versitygw expects accounts in a users.json file with accessAccounts structure
    if [ -n "${OPENC3_SR_BUCKET_USERNAME}" ] && [ -n "${OPENC3_SR_BUCKET_PASSWORD}" ]; then
        if [ "${OPENC3_SR_BUCKET_USERNAME}" != "${ROOT_ACCESS_KEY}" ]; then
            USERS_FILE="${VGW_IAM_DIR}/users.json"
            if [ ! -f "${USERS_FILE}" ]; then
                echo "Creating ScriptRunner IAM account: ${OPENC3_SR_BUCKET_USERNAME}"
                cat > "${USERS_FILE}" << EOF
{
  "accessAccounts": {
    "${OPENC3_SR_BUCKET_USERNAME}": {
      "Access": "${OPENC3_SR_BUCKET_USERNAME}",
      "Secret": "${OPENC3_SR_BUCKET_PASSWORD}",
      "Role": "user",
      "UserID": 1001,
      "GroupID": 1001,
      "ProjectID": 0
    }
  }
}
EOF
            fi
        fi
    fi

    # Build the command
    if [ "${1}" = "versitygw" ]; then
        shift
    fi

    # If no arguments provided, use defaults with IAM enabled
    # Note: --iam-dir is a global option that must come BEFORE the backend command
    if [ $# -eq 0 ]; then
        set -- versitygw --iam-dir "${VGW_IAM_DIR}" "${VGW_BACKEND}" "${VGW_BACKEND_ARG}"
    else
        set -- versitygw "$@"
    fi
fi

exec "$@"
