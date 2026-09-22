#!/usr/bin/env bash
# Run lint + the pytest suite under coverage and emit reports.
#
# Environment switches:
#   VENV_DIR        Virtualenv to activate (default: <repo>/venv)
#   PYTEST_TARGET   Test path(s) for pytest (default: tests)
#   ALLURE_DIR      Allure results directory (default: allure-results)
#   DRY_RUN=1       Print commands without executing them
set -euo pipefail

CI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/common.sh
. "${CI_SCRIPT_DIR}/common.sh"

PYTEST_TARGET="${PYTEST_TARGET:-tests}"
ALLURE_DIR="${ALLURE_DIR:-allure-results}"

activate_venv
cd "${REPO_ROOT}"

log "running flake8 (fatal errors only)"
run flake8 . --count --exclude='./venv*' --select=E9,F63,F7,F82 --show-source --statistics

log "running pytest with coverage"
run coverage erase
# shellcheck disable=SC2086
run coverage run --source=scrapydweb -m pytest -s -vv -l \
    --disable-warnings --alluredir="${ALLURE_DIR}" ${PYTEST_TARGET}

log "coverage reports"
run coverage report
run coverage html
run coverage xml

log "test run finished"
