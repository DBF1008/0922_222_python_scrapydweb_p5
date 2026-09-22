#!/usr/bin/env bash
# Wait until a TCP service accepts connections.
#
# Usage: wait_for_service.sh <host> <port> [timeout_seconds]
#
# Pure-bash implementation (via /dev/tcp) so it works without nc.
# Honors DRY_RUN=1 like the other CI scripts.
set -euo pipefail

CI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/common.sh
. "${CI_SCRIPT_DIR}/common.sh"

HOST="${1:?usage: wait_for_service.sh <host> <port> [timeout_seconds]}"
PORT="${2:?usage: wait_for_service.sh <host> <port> [timeout_seconds]}"
TIMEOUT="${3:-30}"

if [ "${DRY_RUN}" = "1" ]; then
    log "dry-run: would wait up to ${TIMEOUT}s for ${HOST}:${PORT}"
    exit 0
fi

log "waiting for ${HOST}:${PORT} (timeout ${TIMEOUT}s)"
elapsed=0
until (exec 3<>"/dev/tcp/${HOST}/${PORT}") 2>/dev/null; do
    elapsed=$((elapsed + 1))
    if [ "${elapsed}" -ge "${TIMEOUT}" ]; then
        die "timed out waiting to reach ${HOST}:${PORT} after ${TIMEOUT}s"
    fi
    printf '.'
    sleep 1
done
log "${HOST}:${PORT} is reachable"
