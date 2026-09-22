#!/usr/bin/env bash
# Common helpers shared by all CI unit scripts.
# Sourced by the other scripts; not meant to be executed directly.

set -euo pipefail

# Resolve repo root no matter where the script is invoked from.
CI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${CI_SCRIPT_DIR}/../.." && pwd)"

# Shared configuration (overridable via environment).
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-${REPO_ROOT}/venv}"
SCRAPYD_HOST="${SCRAPYD_HOST:-127.0.0.1}"
SCRAPYD_PORT="${SCRAPYD_PORT:-6800}"
SCRAPYD_USERNAME="${SCRAPYD_USERNAME:-admin}"
SCRAPYD_PASSWORD="${SCRAPYD_PASSWORD:-12345}"
SCRAPYD_LOG="${SCRAPYD_LOG:-${HOME}/scrapyd.log}"
SCRAPYD_CONF="${SCRAPYD_CONF:-${HOME}/scrapyd.conf}"
# Set DRY_RUN=1 to print commands without executing them (offline testing).
DRY_RUN="${DRY_RUN:-0}"

log()  { printf '\033[1;34m[ci]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ci][warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ci][error]\033[0m %s\n' "$*" >&2; exit 1; }

run() {
    if [ "${DRY_RUN}" = "1" ]; then
        printf '\033[1;36m[dry-run]\033[0m %s\n' "$*"
    else
        "$@"
    fi
}

activate_venv() {
    if [ "${DRY_RUN}" = "1" ]; then
        log "dry-run: would activate venv at ${VENV_DIR}"
        return 0
    fi
    [ -f "${VENV_DIR}/bin/activate" ] || die "venv not found at ${VENV_DIR}; run scripts/ci/install_deps.sh first"
    # shellcheck disable=SC1090
    . "${VENV_DIR}/bin/activate"
    log "activated venv: $(which python) ($(python --version 2>&1))"
}
