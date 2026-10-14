#!/usr/bin/env bash
set -e
set -E
set -o pipefail
# Create or reuse the publisher key pair without replacing existing key files.
# Example: bash ./generate_publisher_keys.sh ~/.mmp-cred --verbose

DEFAULT_CREDENTIAL_DIR="${HOME}/.mmp-cred"
CRED_DIR="${DEFAULT_CREDENTIAL_DIR}"
DIRECTORY_MODE="700"
PRIVATE_MODE="600"
PUBLIC_MODE="644"
VERBOSE="false"
HAS_DIRECTORY="false"
TEMP_DIR=""
REPORT_SEPARATOR="=============================================================="
REPORT_MODE="keys"
ERROR_REASON=""
CURRENT_OPERATION="Validate arguments"
COMPLETED_OPERATIONS=()
WARNINGS=()

usage() {
    cat <<'EOF_HELP'
--- generate_publisher_keys.sh ---
Usage: generate_publisher_keys.sh [CREDENTIAL_DIR] [OPTIONS]
  CREDENTIAL_DIR        Key directory (default: ~/.mmp-cred)
  --verbose             Log process diagnostics to stderr
  -h, --help            Show help

Create a publisher Ed25519 pair if absent; reuse an existing pair.
Restore a missing public key from the existing private key.
Reject public-only, mismatched, or invalid pairs; never overwrite key files.
Set directory permissions to 700, private key to 600, and public key to 644.
Example: bash ./generate_publisher_keys.sh ~/.mmp-cred
--- generate_publisher_keys.sh: help ---
EOF_HELP
}

log_verbose() {
    if [[ "${VERBOSE}" == "true" ]]; then
        printf '%s\n' "$@" >&2
    fi
}

fail() {
    local p_message="$1"

    ERROR_REASON="${p_message}"
    echo "${ERROR_REASON}" >&2
    exit 1
}

record_failure() {
    local p_exitCode="$1"
    local p_line="$2"

    if [[ -z "${ERROR_REASON}" ]]; then
        ERROR_REASON="${CURRENT_OPERATION} failed at line ${p_line} (exit ${p_exitCode})."
    fi
}

print_report() {
    local p_exitCode="$1"
    local result="SUCCESS"
    local operation

    if [[ "${p_exitCode}" -ne 0 ]]; then result="FAILED"; fi
    printf '\n%s\n Execution Report\n%s\n' "${REPORT_SEPARATOR}" "${REPORT_SEPARATOR}"
    printf ' status    : %s\n' "${result}"
    if [[ "${REPORT_MODE}" == "keys" ]]; then
        printf ' target    : publisher\n directory : %s\n' "${CRED_DIR}"
    fi
    if [[ "${p_exitCode}" -ne 0 ]]; then
        printf ' error     : %s\n exit code : %s\n' "${ERROR_REASON:-Execution failed.}" "${p_exitCode}"
    fi
    printf '%s\n\nCompleted:\n' "${REPORT_SEPARATOR}"
    if [[ "${#COMPLETED_OPERATIONS[@]}" -eq 0 ]]; then echo '  - None.'; fi
    for operation in "${COMPLETED_OPERATIONS[@]}"; do printf '  - %s\n' "${operation}"; done
    printf '\nManual actions required:\n'
    if [[ "${p_exitCode}" -ne 0 ]]; then
        echo '  - Resolve the reported error and rerun the script.'
    elif [[ "${REPORT_MODE}" == "help" ]]; then
        echo '  - None.'
    else
        echo '  - Run the template service with the configured Compose file.'
    fi
    if [[ "${#WARNINGS[@]}" -gt 0 ]]; then
        printf '\nWarnings:\n'
        for operation in "${WARNINGS[@]}"; do printf '  - %s\n' "${operation}"; done
    fi
    printf '%s\n' "${REPORT_SEPARATOR}"
}

finish_execution() {
    local p_exitCode="$1"

    trap - EXIT ERR
    if [[ -n "${TEMP_DIR}" ]]; then
        if rm -rf -- "${TEMP_DIR}"; then
            log_verbose "Temporary key files removed."
        else
            WARNINGS+=("Remove temporary key files manually: ${TEMP_DIR}")
        fi
    fi
    if [[ "${p_exitCode}" -eq 0 ]]; then
        print_report "${p_exitCode}"
    else
        print_report "${p_exitCode}" >&2
    fi
    exit "${p_exitCode}"
}

trap 'record_failure "$?" "${LINENO}"' ERR
trap 'finish_execution "$?"' EXIT

run_openssl() {
    local status

    log_verbose "OpenSSL operation: $1"
    # OpenSSL output can contain credential data; report only the operation on failure.
    if openssl "$@" >/dev/null 2>&1; then
        return 0
    else
        status="$?"
        ERROR_REASON="OpenSSL $1 failed (exit ${status}); check the key files and directory permissions."
        echo "${ERROR_REASON}" >&2
        return "${status}"
    fi
}

for argument in "$@"; do
    case "${argument}" in
        --verbose) VERBOSE="true" ;;
        -h|--help) REPORT_MODE="help"; usage; COMPLETED_OPERATIONS+=("Help displayed"); exit 0 ;;
        -*) usage >&2; fail "Unknown switch: ${argument}" ;;
        *)
            if [[ "${HAS_DIRECTORY}" == "true" || -z "${argument}" ]]; then
                usage >&2
                fail "Specify at most one nonempty credential directory."
            fi
            CRED_DIR="${argument}"
            HAS_DIRECTORY="true"
            ;;
    esac
done


echo "--- generate_publisher_keys.sh ---"
echo "Credentials: ${CRED_DIR}"

# ----------------------------------------------------------
# Validate existing paths before creating or publishing key files.
# ----------------------------------------------------------
PRIVATE_KEY="${CRED_DIR}/mmp_publisher"
PUBLIC_KEY="${PRIVATE_KEY}.pub"

if [[ -L "${CRED_DIR}" || ( -e "${CRED_DIR}" && ! -d "${CRED_DIR}" ) ]]; then
    fail "Credential path must be a directory without a symlink: ${CRED_DIR}"
fi
for key in "${PRIVATE_KEY}" "${PUBLIC_KEY}"; do
    if [[ -L "${key}" || ( -e "${key}" && ! -f "${key}" ) ]]; then
        fail "Key path must be a regular file without a symlink: ${key}"
    fi
done
if [[ ! -e "${PRIVATE_KEY}" && -e "${PUBLIC_KEY}" ]]; then
    fail "Public key exists without its private key; restore ${PRIVATE_KEY}."
fi
if ! command -v openssl >/dev/null 2>&1; then
    fail "OpenSSL is unavailable. Install it before generating keys."
fi

# ----------------------------------------------------------
# Stage generation and verification before publishing missing files.
# ----------------------------------------------------------
log_verbose "Credential paths and OpenSSL validated."
CURRENT_OPERATION="Prepare credential directory"
umask 077
mkdir -p -- "${CRED_DIR}"
TEMP_DIR="$(mktemp -d "${CRED_DIR}/.key-pair-XXXXXX")"
SOURCE_PRIVATE="${PRIVATE_KEY}"
ACTION="reused"
HAS_PUBLIC="false"

CURRENT_OPERATION="Generate or verify key pair"

if [[ ! -e "${PRIVATE_KEY}" ]]; then
    SOURCE_PRIVATE="${TEMP_DIR}/private"
    ACTION="created"
    run_openssl genpkey -algorithm ED25519 -out "${SOURCE_PRIVATE}"
fi
run_openssl pkey -in "${SOURCE_PRIVATE}" -pubout -out "${TEMP_DIR}/public"
if [[ -e "${PUBLIC_KEY}" ]]; then
    HAS_PUBLIC="true"
    run_openssl pkey -pubin -in "${PUBLIC_KEY}" -outform DER -out "${TEMP_DIR}/existing.der"
    run_openssl pkey -pubin -in "${TEMP_DIR}/public" -outform DER -out "${TEMP_DIR}/derived.der"
    if cmp -s "${TEMP_DIR}/existing.der" "${TEMP_DIR}/derived.der"; then
        log_verbose "Existing public key matches the private key."
    else
        STATUS="$?"
        ERROR_REASON="Existing public and private keys could not be verified (exit ${STATUS}); restore the pair."
        echo "${ERROR_REASON}" >&2
        exit "${STATUS}"
    fi
fi
log_verbose "Key pair verified."
CURRENT_OPERATION="Set credential permissions"
chmod "${DIRECTORY_MODE}" -- "${CRED_DIR}"
chmod "${PRIVATE_MODE}" -- "${SOURCE_PRIVATE}"
chmod "${PUBLIC_MODE}" -- "${TEMP_DIR}/public"

CURRENT_OPERATION="Publish key files without replacement"

# Hard links fail if another process created a key, preventing replacement.
if [[ "${ACTION}" == "created" ]]; then
    ln -T -- "${SOURCE_PRIVATE}" "${PRIVATE_KEY}"
    COMPLETED_OPERATIONS+=("Private key created: ${PRIVATE_KEY}")
else
    COMPLETED_OPERATIONS+=("Private key reused: ${PRIVATE_KEY}")
fi
if [[ "${HAS_PUBLIC}" == "false" ]]; then
    ln -T -- "${TEMP_DIR}/public" "${PUBLIC_KEY}"
    if [[ "${ACTION}" == "created" ]]; then
        COMPLETED_OPERATIONS+=("Public key created: ${PUBLIC_KEY}")
    else
        COMPLETED_OPERATIONS+=("Public key restored: ${PUBLIC_KEY}")
    fi
else
    chmod "${PUBLIC_MODE}" -- "${PUBLIC_KEY}"
    COMPLETED_OPERATIONS+=("Public key reused: ${PUBLIC_KEY}")
fi
log_verbose "Directory and key permissions configured."
