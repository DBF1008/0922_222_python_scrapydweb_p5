#!/usr/bin/env bash
# Unified entry point for running the ScrapydWeb test suite,
# used identically by GitHub Actions, CircleCI and local development.
#
# Usage:
#   ./test.sh                 # full run: install deps, launch scrapyd, run tests
#   SKIP_INSTALL=1 ./test.sh  # reuse an existing venv
#   DRY_RUN=1 ./test.sh       # print the plan without executing anything
#
# Environment switches (all optional):
#   PYTHON_BIN       Interpreter for the venv, e.g. python3.12 (default: python3)
#   VENV_DIR         Virtualenv location (default: <repo>/venv)
#   USE_GIT=1        Install Scrapy/Scrapyd/LogParser from git masters
#   SCRAPYD_VERSION  Pin scrapyd, e.g. SCRAPYD_VERSION=1.4.3
#   DATABASE_URL     e.g. sqlite:////tmp/db, postgresql://u:p@host:5432, mysql://u:p@host:3306
#   DATA_PATH        Custom data directory for ScrapydWeb
#   PYTEST_TARGET    Limit the pytest selection (default: tests)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DIR="${REPO_ROOT}/scripts/ci"
# shellcheck source=scripts/ci/common.sh
. "${CI_DIR}/common.sh"

export SCRAPYDWEB_TESTMODE=True
export DATA_PATH="${DATA_PATH:-}"
export DATABASE_URL="${DATABASE_URL:-}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"

log "repo: ${REPO_ROOT}"
log "python: ${PYTHON_BIN} | venv: ${VENV_DIR}"
log "USE_GIT=${USE_GIT:-0} SCRAPYD_VERSION=${SCRAPYD_VERSION:-<latest>}"
log "DATA_PATH=${DATA_PATH:-<default>} DATABASE_URL=${DATABASE_URL:-<default sqlite>}"

# The test suite expects ~/logs to exist (LOCAL_SCRAPYD_LOGS_DIR).
run mkdir -p "${HOME}/logs"

# Wait for external database services derived from DATABASE_URL.
case "${DATABASE_URL}" in
    postgres*|mysql*)
        db_hostport="$(printf '%s' "${DATABASE_URL}" | sed -E 's#^[a-z]+://([^@]*@)?([^/:]+)(:([0-9]+))?.*#\2 \4#')"
        db_host="$(printf '%s' "${db_hostport}" | awk '{print $1}')"
        db_port="$(printf '%s' "${db_hostport}" | awk '{print $2}')"
        if [ -z "${db_port}" ]; then
            case "${DATABASE_URL}" in
                postgres*) db_port=5432 ;;
                mysql*)    db_port=3306 ;;
            esac
        fi
        "${CI_DIR}/wait_for_service.sh" "${db_host}" "${db_port}" 60
        ;;
esac

if [ "${SKIP_INSTALL}" = "1" ]; then
    log "SKIP_INSTALL=1, reusing existing venv"
else
    "${CI_DIR}/install_deps.sh"
fi

"${CI_DIR}/start_scrapyd.sh"
"${CI_DIR}/run_tests.sh"

log "all done"
