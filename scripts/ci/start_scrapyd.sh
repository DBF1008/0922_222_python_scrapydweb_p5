#!/usr/bin/env bash
# Launch a local Scrapyd daemon with basic auth for the test suite.
#
# Environment switches (see common.sh for defaults):
#   SCRAPYD_HOST / SCRAPYD_PORT       Bind check target (default 127.0.0.1:6800)
#   SCRAPYD_USERNAME / SCRAPYD_PASSWORD  Credentials written to scrapyd.conf
#   SCRAPYD_CONF / SCRAPYD_LOG        Config and log file locations
#   VENV_DIR                          Virtualenv providing the scrapyd binary
#   DRY_RUN=1                         Print commands without executing them
set -euo pipefail

CI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/common.sh
. "${CI_SCRIPT_DIR}/common.sh"

activate_venv

log "writing scrapyd config to ${SCRAPYD_CONF}"
if [ "${DRY_RUN}" = "1" ]; then
    log "dry-run: would write [scrapyd] auth ${SCRAPYD_USERNAME}/*** to ${SCRAPYD_CONF}"
else
    printf '[scrapyd]\nusername = %s\npassword = %s\n' \
        "${SCRAPYD_USERNAME}" "${SCRAPYD_PASSWORD}" > "${SCRAPYD_CONF}"
    cat "${SCRAPYD_CONF}"
fi

log "starting scrapyd (log: ${SCRAPYD_LOG})"
if [ "${DRY_RUN}" = "1" ]; then
    log "dry-run: would run 'nohup scrapyd > ${SCRAPYD_LOG} 2>&1 &'"
else
    # Scrapyd reads scrapyd.conf from the current directory.
    cd "$(dirname "${SCRAPYD_CONF}")"
    nohup "${VENV_DIR}/bin/scrapyd" > "${SCRAPYD_LOG}" 2>&1 &
    cd - > /dev/null
fi

"${CI_SCRIPT_DIR}/wait_for_service.sh" "${SCRAPYD_HOST}" "${SCRAPYD_PORT}" 30

if [ "${DRY_RUN}" != "1" ]; then
    cat "${SCRAPYD_LOG}" || true
fi
log "scrapyd is up at ${SCRAPYD_HOST}:${SCRAPYD_PORT}"
