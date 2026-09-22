#!/usr/bin/env bash
# Create the test virtualenv and install dependencies.
#
# Environment switches:
#   PYTHON_BIN        Python interpreter used to build the venv (default: python3)
#   VENV_DIR          Virtualenv location (default: <repo>/venv)
#   USE_GIT=1         Install Scrapy/Scrapyd/LogParser from their git masters
#   SCRAPYD_VERSION   Pin scrapyd to a specific release, e.g. "1.4.3"
#   DRY_RUN=1         Print commands without executing them
set -euo pipefail

CI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/common.sh
. "${CI_SCRIPT_DIR}/common.sh"

USE_GIT="${USE_GIT:-0}"
SCRAPYD_VERSION="${SCRAPYD_VERSION:-}"

log "creating virtualenv at ${VENV_DIR} with ${PYTHON_BIN}"
if [ "${DRY_RUN}" = "1" ]; then
    log "dry-run: ${PYTHON_BIN} -m venv ${VENV_DIR}"
else
    "${PYTHON_BIN}" -m venv "${VENV_DIR}"
fi

activate_venv

log "installing runtime and test requirements"
run pip install --upgrade pip
run pip install -r "${REPO_ROOT}/requirements.txt"
run pip install -r "${REPO_ROOT}/requirements-tests.txt"

if [ "${USE_GIT}" = "1" ]; then
    log "installing Scrapy, Scrapyd and LogParser from git"
    run pip install -U git+https://github.com/scrapy/scrapy.git
    run pip install -U git+https://github.com/scrapy/scrapyd.git
    run pip install -U git+https://github.com/my8100/logparser.git
fi

if [ -n "${SCRAPYD_VERSION}" ]; then
    log "pinning scrapyd==${SCRAPYD_VERSION}"
    run pip install "scrapyd==${SCRAPYD_VERSION}"
fi

run pip list
log "dependencies installed"
