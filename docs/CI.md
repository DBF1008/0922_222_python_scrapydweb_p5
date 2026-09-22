# CI architecture

The CI setup is built around a single idea: **all logic lives in reusable
shell entry points, and every CI platform just calls `./test.sh`.**

## Layout

| Path | Purpose |
| --- | --- |
| `test.sh` | Unified entry point: install deps, wait for DB, launch Scrapyd, run tests |
| `scripts/ci/common.sh` | Shared helpers, defaults and `DRY_RUN` support |
| `scripts/ci/install_deps.sh` | Create the venv and install requirements (`USE_GIT`, `SCRAPYD_VERSION`) |
| `scripts/ci/wait_for_service.sh` | Wait for a TCP host:port (databases, Scrapyd) |
| `scripts/ci/start_scrapyd.sh` | Write `scrapyd.conf` with auth and launch Scrapyd |
| `scripts/ci/run_tests.sh` | flake8 + pytest under coverage + reports |
| `scripts/ci/check_matrix.py` | Self-check that both CI matrices keep all required combinations |
| `.github/workflows/tests.yml` | GitHub Actions matrix (primary, GitHub-native) |
| `.circleci/config.yml` | CircleCI matrix (thin wrapper around `./test.sh`) |

## Matrix

Both CI platforms cover the same combinations, enforced by
`scripts/ci/check_matrix.py`:

- **base**: Python 3.8 – 3.13 with released dependencies
- **scrapyd-v143**: `scrapyd==1.4.3` on Python 3.9 and 3.12
- **git-postgresql / git-mysql**: Scrapy, Scrapyd and LogParser installed
  from git masters, against PostgreSQL / MySQL
- **sqlite / postgresql / mysql**: database backend variants
  (`DATA_PATH` + `DATABASE_URL`)

## Environment switches

| Variable | Effect |
| --- | --- |
| `PYTHON_BIN` | Interpreter used to build the venv (default `python3`) |
| `VENV_DIR` | Virtualenv location (default `<repo>/venv`) |
| `USE_GIT=1` | Install Scrapy/Scrapyd/LogParser from git masters |
| `SCRAPYD_VERSION` | Pin scrapyd, e.g. `1.4.3` |
| `DATABASE_URL` | `sqlite:///...`, `postgresql://...` or `mysql://...`; TCP services are waited on automatically |
| `DATA_PATH` | Custom ScrapydWeb data directory |
| `PYTEST_TARGET` | Restrict the pytest selection (default `tests`) |
| `SKIP_INSTALL=1` | Reuse an existing venv |
| `DRY_RUN=1` | Print the plan without executing anything (offline testing) |

## Local usage

```bash
./test.sh                                          # full local run
PYTHON_BIN=python3.12 SCRAPYD_VERSION=1.4.3 ./test.sh
USE_GIT=1 DATABASE_URL=mysql://root:rootpw@127.0.0.1:3306 ./test.sh
SKIP_INSTALL=1 PYTEST_TARGET=tests/test_api.py ./test.sh
DRY_RUN=1 ./test.sh                                # preview the plan
```

## Self-check

`python scripts/ci/check_matrix.py` runs as the `matrix-check` job in
GitHub Actions (gating the test matrix) and can be run locally at any time.
It fails when:

- a required combination disappears from either CI matrix,
- a matrix leg uses an env switch that `test.sh` does not consume,
- a CI config stops routing tests through `./test.sh`,
- any shell entry point fails `bash -n`.
