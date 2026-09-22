#!/usr/bin/env bash
# test.sh - unified test entry for ScrapydWeb.
#
# Single reusable entrypoint shared by GitHub Actions (.github/workflows/tests.yml),
# CircleCI (.circleci/config.yml) and local development. All install / scrapyd /
# test / report logic lives here so the CI configs stay thin declarative matrices.
#
# Usage:
#   ./test.sh install                 Create venv and install dependencies
#   ./test.sh env <variant>           Print env exports for none|sqlite|postgresql|mysql
#   ./test.sh wait-db                 Wait for the DATABASE_URL host:port (no-op for sqlite)
#   ./test.sh scrapyd                 Write scrapyd.conf and launch Scrapyd with auth
#   ./test.sh test                    Run flake8 + coverage/pytest
#   ./test.sh report                  Coverage report/html/xml (+ coveralls when configured)
#   ./test.sh allure                  Generate the Allure report (requires ALLURE_VERSION)
#   ./test.sh check                   Validate CI matrix coverage (ci/check_matrix.py)
#   ./test.sh all                     install + wait-db + scrapyd + test + report
#
# Configuration via environment variables:
#   PYTHON                    Python interpreter used to create the venv (default: python3)
#   VENV_DIR                  Virtualenv directory; empty string = use current env (default: venv)
#   VENV_SYSTEM_SITE_PACKAGES Set to 1 to create the venv with --system-site-packages
#   SKIP_PIP_INSTALL          Set to 1 to skip pip installs (offline/air-gapped runs)
#   USE_GIT                   Set to 1 to install Scrapy/Scrapyd/LogParser from git HEAD
#   SCRAPYD_VERSION           Pin scrapyd to this version (e.g. 1.4.3); empty = latest
#   SCRAPYD_PORT              Scrapyd port (default: 6800)
#   SCRAPYD_AUTH              Scrapyd credentials as user:pass (default: admin:12345)
#   SCRAPYD_RUN_DIR           Directory holding scrapyd.conf and logs (default: $HOME)
#   RUN_FLAKE8                Set to 0 to skip the flake8 step (default: 1)
#   TEST_ARGS                 Arguments passed to pytest (default: tests)
#   ALLURE_VERSION            Allure CLI version to install/use; empty = skip allure
#   ALLURE_RESULTS_DIR        Allure results dir (default: allure-results)
#   ALLURE_REPORT_DIR         Allure report dir (default: allure-report)
#   DRY_RUN                   Set to 1 to print mutating commands without executing them
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PYTHON="${PYTHON:-python3}"
VENV_DIR="${VENV_DIR-venv}"
VENV_SYSTEM_SITE_PACKAGES="${VENV_SYSTEM_SITE_PACKAGES:-}"
SKIP_PIP_INSTALL="${SKIP_PIP_INSTALL:-}"
USE_GIT="${USE_GIT:-}"
SCRAPYD_VERSION="${SCRAPYD_VERSION:-}"
SCRAPYD_PORT="${SCRAPYD_PORT:-6800}"
SCRAPYD_AUTH="${SCRAPYD_AUTH:-admin:12345}"
SCRAPYD_RUN_DIR="${SCRAPYD_RUN_DIR:-$HOME}"
RUN_FLAKE8="${RUN_FLAKE8:-1}"
TEST_ARGS="${TEST_ARGS:-tests}"
ALLURE_VERSION="${ALLURE_VERSION:-}"
ALLURE_RESULTS_DIR="${ALLURE_RESULTS_DIR:-allure-results}"
ALLURE_REPORT_DIR="${ALLURE_REPORT_DIR:-allure-report}"
DRY_RUN="${DRY_RUN:-}"

PYBIN=""

log()  { echo "[test.sh] $*"; }
warn() { echo "[test.sh] WARNING: $*" >&2; }
err()  { echo "[test.sh] ERROR: $*" >&2; }

is_truthy() {
    case "${1:-}" in
        ""|0|false|False|FALSE|no|No|NO|off) return 1 ;;
        *) return 0 ;;
    esac
}

run() {
    if is_truthy "$DRY_RUN"; then
        echo "[test.sh] DRY_RUN: $*"
    else
        "$@"
    fi
}

resolve_python() {
    if [ -n "$VENV_DIR" ] && [ -x "$VENV_DIR/bin/python" ]; then
        PYBIN="$VENV_DIR/bin/python"
    else
        PYBIN="$PYTHON"
    fi
}

wait_for_port() {
    # wait_for_port <host> <port> <timeout-seconds>
    "$PYBIN" - "$1" "$2" "$3" <<'EOF'
import socket
import sys
import time

host, port, timeout = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
deadline = time.time() + timeout
while time.time() < deadline:
    try:
        socket.create_connection((host, port), timeout=1).close()
    except OSError:
        time.sleep(1)
    else:
        sys.exit(0)
sys.exit(1)
EOF
}

cmd_install() {
    if [ -n "$VENV_DIR" ] && [ ! -x "$VENV_DIR/bin/python" ]; then
        flags=()
        if is_truthy "$VENV_SYSTEM_SITE_PACKAGES"; then
            flags+=(--system-site-packages)
        fi
        log "Creating virtualenv: $VENV_DIR"
        run "$PYTHON" -m venv ${flags[@]+"${flags[@]}"} "$VENV_DIR"
    fi
    resolve_python
    log "Using python: $PYBIN ($("$PYBIN" --version 2>&1))"
    if is_truthy "$SKIP_PIP_INSTALL"; then
        warn "SKIP_PIP_INSTALL is set; skipping pip installs"
        return 0
    fi
    run "$PYBIN" -m pip install -r "$ROOT_DIR/requirements.txt"
    run "$PYBIN" -m pip install -r "$ROOT_DIR/requirements-tests.txt"
    if is_truthy "$USE_GIT"; then
        log "Installing Scrapy, Scrapyd and LogParser from git HEAD"
        run "$PYBIN" -m pip install -U git+https://github.com/scrapy/scrapy.git
        run "$PYBIN" -m pip install -U git+https://github.com/scrapy/scrapyd.git
        run "$PYBIN" -m pip install -U git+https://github.com/my8100/logparser.git
    fi
    if [ -n "$SCRAPYD_VERSION" ]; then
        log "Pinning scrapyd==$SCRAPYD_VERSION"
        run "$PYBIN" -m pip install "scrapyd==$SCRAPYD_VERSION"
    fi
    run "$PYBIN" -m pip list
}

cmd_env() {
    # Prints export lines for the requested variant. Usage: eval "$(./test.sh env sqlite)"
    # Note: run from the repository root so sqlite paths point into the checkout.
    variant="${1:-none}"
    case "$variant" in
        none|sqlite|postgresql|mysql)
            ;;
        *)
            err "unknown env variant: $variant (expected none|sqlite|postgresql|mysql)"
            exit 2
            ;;
    esac
    echo "export SCRAPYDWEB_TESTMODE=True"
    case "$variant" in
        none)
            ;;
        sqlite)
            echo "export DATA_PATH='$PWD/scrapydweb_data'"
            echo "export DATABASE_URL='sqlite:///$PWD/scrapydweb_database'"
            ;;
        postgresql)
            echo "export DATABASE_URL='postgresql://circleci:passw0rd@localhost:5432'"
            ;;
        mysql)
            echo "export DATABASE_URL='mysql://root:rootpw@127.0.0.1:3306'"
            ;;
    esac
}

cmd_wait_db() {
    resolve_python
    database_url="${DATABASE_URL:-}"
    case "$database_url" in
        mysql://*|postgres://*|postgresql://*) ;;
        *)
            log "No external DATABASE_URL set; nothing to wait for"
            return 0
            ;;
    esac
    host_port="$("$PYBIN" -c "
import re, sys
m = re.match(r'(?:mysql|postgres(?:ql)?)://[^@]*@([^:/]+):(\d+)', sys.argv[1])
print('%s %s' % m.groups() if m else '')
" "$database_url")"
    if [ -z "$host_port" ]; then
        warn "Could not parse host:port from DATABASE_URL; skipping wait"
        return 0
    fi
    log "Waiting for database at $host_port"
    # shellcheck disable=SC2086
    if wait_for_port $host_port 60; then
        log "Database is ready"
    else
        err "Timed out waiting for database at $host_port"
        exit 1
    fi
}

cmd_scrapyd() {
    resolve_python
    username="${SCRAPYD_AUTH%%:*}"
    password="${SCRAPYD_AUTH#*:}"
    mkdir -p "$SCRAPYD_RUN_DIR" "$HOME/logs"
    printf '[scrapyd]\nusername = %s\npassword = %s\n' "$username" "$password" > "$SCRAPYD_RUN_DIR/scrapyd.conf"
    log "Wrote $SCRAPYD_RUN_DIR/scrapyd.conf"
    if [ -n "$VENV_DIR" ] && [ -x "$VENV_DIR/bin/scrapyd" ]; then
        scrapyd_bin="$VENV_DIR/bin/scrapyd"
    elif command -v scrapyd >/dev/null 2>&1; then
        scrapyd_bin="scrapyd"
    else
        scrapyd_bin="$PYBIN -m scrapyd"
    fi
    log "Launching Scrapyd on 127.0.0.1:$SCRAPYD_PORT ($scrapyd_bin)"
    if is_truthy "$DRY_RUN"; then
        echo "[test.sh] DRY_RUN: (cd $SCRAPYD_RUN_DIR && nohup $scrapyd_bin > scrapyd.log 2>&1 &)"
        return 0
    fi
    (cd "$SCRAPYD_RUN_DIR" && nohup $scrapyd_bin > scrapyd.log 2>&1 &)
    if wait_for_port 127.0.0.1 "$SCRAPYD_PORT" 30; then
        log "Scrapyd is up"
    else
        err "Scrapyd failed to start; last log lines:"
        tail -n 20 "$SCRAPYD_RUN_DIR/scrapyd.log" >&2 || true
        exit 1
    fi
}

cmd_test() {
    cd "$ROOT_DIR"
    resolve_python
    if is_truthy "$RUN_FLAKE8"; then
        if "$PYBIN" -m flake8 --version >/dev/null 2>&1; then
            "$PYBIN" -m flake8 . --count --exclude="./${VENV_DIR:-venv}*,./.venv*" \
                --select=E9,F63,F7,F82 --show-source --statistics
        else
            warn "flake8 not installed; skipping lint step"
        fi
    fi
    pytest_args=(-s -vv -l --disable-warnings)
    if "$PYBIN" -c "import allure_pytest" >/dev/null 2>&1; then
        pytest_args+=(--alluredir="$ALLURE_RESULTS_DIR")
    else
        warn "allure-pytest not installed; running without --alluredir"
    fi
    # shellcheck disable=SC2206
    test_args=($TEST_ARGS)
    if "$PYBIN" -m coverage --version >/dev/null 2>&1; then
        "$PYBIN" -m coverage erase
        "$PYBIN" -m coverage run --source=scrapydweb -m pytest "${pytest_args[@]}" "${test_args[@]}"
    else
        warn "coverage not installed; running pytest directly"
        "$PYBIN" -m pytest "${pytest_args[@]}" "${test_args[@]}"
    fi
}

cmd_report() {
    cd "$ROOT_DIR"
    resolve_python
    log "DATA_PATH: ${DATA_PATH:-<unset>}"
    log "DATABASE_URL: ${DATABASE_URL:-<unset>}"
    if "$PYBIN" -m coverage --version >/dev/null 2>&1; then
        "$PYBIN" -m coverage report || warn "coverage report failed"
        "$PYBIN" -m coverage html || warn "coverage html failed"
        "$PYBIN" -m coverage xml || warn "coverage xml failed"
    else
        warn "coverage not installed; skipping coverage reports"
    fi
    if [ -d "$ALLURE_RESULTS_DIR" ]; then
        log "Allure results available in $ALLURE_RESULTS_DIR"
    fi
    if is_truthy "${CIRCLECI:-}" || [ -n "${COVERALLS_REPO_TOKEN:-}" ]; then
        if "$PYBIN" -m coveralls --version >/dev/null 2>&1; then
            "$PYBIN" -m coveralls || warn "coveralls upload failed"
        else
            warn "coveralls not installed; skipping upload"
        fi
    fi
}

cmd_allure() {
    cd "$ROOT_DIR"
    if [ -z "$ALLURE_VERSION" ]; then
        log "ALLURE_VERSION not set; skipping Allure report"
        return 0
    fi
    if [ ! -d "$ALLURE_RESULTS_DIR" ]; then
        warn "$ALLURE_RESULTS_DIR not found; skipping Allure report"
        return 0
    fi
    if ! command -v java >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            log "Installing a JDK for Allure"
            run sudo apt-get update
            run sudo apt-get install -y default-jdk
        else
            err "java is required to generate the Allure report"
            exit 1
        fi
    fi
    if command -v allure >/dev/null 2>&1; then
        allure_bin="allure"
    else
        allure_home="$HOME/.allure/allure-$ALLURE_VERSION"
        if [ ! -x "$allure_home/bin/allure" ]; then
            log "Downloading Allure $ALLURE_VERSION"
            run curl -L "https://github.com/allure-framework/allure2/releases/download/$ALLURE_VERSION/allure-commandline-$ALLURE_VERSION.zip" -o /tmp/allure.zip
            run mkdir -p "$HOME/.allure"
            run unzip -o /tmp/allure.zip -d "$HOME/.allure"
        fi
        allure_bin="$allure_home/bin/allure"
    fi
    run "$allure_bin" generate --report-dir "$ALLURE_REPORT_DIR" "$ALLURE_RESULTS_DIR"
    log "Allure report generated in $ALLURE_REPORT_DIR"
}

cmd_check() {
    resolve_python
    if ! "$PYBIN" -c "import yaml" >/dev/null 2>&1; then
        if is_truthy "$SKIP_PIP_INSTALL"; then
            err "PyYAML is required for the matrix check (pip install pyyaml)"
            exit 1
        fi
        run "$PYBIN" -m pip install pyyaml
    fi
    "$PYBIN" "$ROOT_DIR/ci/check_matrix.py" "$ROOT_DIR"
}

cmd_all() {
    cmd_install
    cmd_wait_db
    cmd_scrapyd
    cmd_test
    cmd_report
}

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
    command="${1:-}"
    case "$command" in
        install)  cmd_install ;;
        env)      shift; cmd_env "$@" ;;
        wait-db)  cmd_wait_db ;;
        scrapyd)  cmd_scrapyd ;;
        test)     cmd_test ;;
        report)   cmd_report ;;
        allure)   cmd_allure ;;
        check)    cmd_check ;;
        all)      cmd_all ;;
        ""|-h|--help|help) usage ;;
        *)
            err "unknown command: $command"
            usage
            exit 2
            ;;
    esac
}

main "$@"
