#!/usr/bin/env bash
set -e
set -o pipefail
# Download the client or publisher image used by this kit's Compose files.
# Requires Docker access; the private publisher image also requires docker login.
# Example: ./pull-images.sh client --tag v0.0.1

IMAGE_BASE="jetseaaiusvfleet/bundle-tools"
IMAGE_TAG="latest"
VARIANT=""
VERBOSE="false"

usage() {
    cat <<'EOF_HELP'
--- pull-images.sh ---
Usage: pull-images.sh client|publish [OPTIONS]
  client                Pull the public client image
  publish               Pull the private publisher image; run docker login first
  -t, --tag TAG         Image tag to pull (default: latest)
  --verbose             Log detailed Docker pull diagnostics to stderr
  -h, --help            Show help

Downloads the selected image and tag to the local Docker Engine.
Does not start containers or modify the Compose files. Runs from any directory.
Example: ./pull-images.sh client --tag v0.0.1
--- pull-images.sh: help ---
EOF_HELP
}

log_verbose() {
    if [[ "${VERBOSE}" == "true" ]]; then
        printf '%s\n' "$@" >&2
    fi
}

log_output() {
    local line

    while IFS= read -r line; do log_verbose "${line}"; done
}

# ----------------------------------------------------------
# Validate the selected role before downloading anything.
# ----------------------------------------------------------
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        client|publish)
            if [[ -n "${VARIANT}" ]]; then
                echo "Select exactly one image: client or publish." >&2
                usage >&2
                exit 1
            fi
            VARIANT="$1"
            ;;
        -t|--tag)
            if [[ "$#" -lt 2 ]]; then
                echo "Missing value for $1: specify an image tag." >&2
                usage >&2
                exit 1
            fi
            IMAGE_TAG="$2"
            shift
            ;;
        --tag=*) IMAGE_TAG="${1#--tag=}" ;;
        --verbose) VERBOSE="true" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done
if [[ -z "${VARIANT}" ]]; then
    echo "Required argument: client or publish." >&2
    usage >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is unavailable. Install Docker and add it to PATH." >&2
    exit 1
fi
IMAGE="${IMAGE_BASE}-${VARIANT}:${IMAGE_TAG}"

trap 'STATUS="$?"; if [[ "${STATUS}" -eq 0 ]]; then
    echo "--- pull-images.sh: complete ---"
else
    echo "--- pull-images.sh: failed; use --verbose for diagnostics ---" >&2
fi' EXIT

echo "--- pull-images.sh ---"
echo "Image: ${IMAGE}"

# ----------------------------------------------------------
# Pull only the selected image; authentication stays with Docker.
# ----------------------------------------------------------
echo "Pulling ${IMAGE}..."
if ! docker pull "${IMAGE}" 2>&1 | log_output; then
    echo "Pull failed: ${IMAGE}. Check Docker access and your network connection." >&2
    if [[ "${VARIANT}" == "publish" ]]; then
        echo "Run docker login with an account authorized to pull the private publisher image." >&2
    fi
    exit 1
fi
echo "Downloaded ${IMAGE}"
