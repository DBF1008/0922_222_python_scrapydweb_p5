#!/usr/bin/env python3
# coding: utf-8
"""Validate that the CI matrices cover all required test combinations.

Parses .github/workflows/tests.yml and .circleci/config.yml, normalizes the
job definitions into (python, scrapyd, git, db) combos and asserts that every
combo in REQUIRED_COMBOS is present in BOTH CI systems. Also verifies that
both configs route their steps through the shared ./test.sh entrypoint.

Usage:
    python3 ci/check_matrix.py [repo-root]

Exit code is 0 when the matrices are complete, 1 otherwise.
"""
import os
import sys
from collections import namedtuple

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required to run this check: pip install pyyaml")

Combo = namedtuple('Combo', ['python', 'scrapyd', 'git', 'db'])

BASE_PYTHONS = ['3.8', '3.9', '3.10', '3.11', '3.12', '3.13']
SCRAPYD_V143_PYTHONS = ['3.9', '3.12']
DB_VARIANTS = ['sqlite', 'postgresql', 'mysql']
DB_PYTHON = '3.10'
GIT_DBS = ['postgresql', 'mysql']

REQUIRED_COMBOS = set()
for py in BASE_PYTHONS:
    REQUIRED_COMBOS.add(Combo(py, '', False, 'none'))
for py in SCRAPYD_V143_PYTHONS:
    REQUIRED_COMBOS.add(Combo(py, '1.4.3', False, 'none'))
for db in DB_VARIANTS:
    REQUIRED_COMBOS.add(Combo(DB_PYTHON, '', False, db))
for db in GIT_DBS:
    REQUIRED_COMBOS.add(Combo(DB_PYTHON, '', True, db))

# CircleCI job types and the combo attributes they imply.
CIRCLE_JOB_KINDS = {
    'py': {},
    'py-scrapyd-v143': {'scrapyd': '1.4.3'},
    'py-sqlite': {'db': 'sqlite'},
    'py-postgresql': {'db': 'postgresql'},
    'py-mysql': {'db': 'mysql'},
}


def norm_python(value):
    return str(value)


def truthy(value):
    return str(value).lower() not in ('', '0', 'false', 'no', 'off', 'none')


def github_combos(doc):
    combos = set()
    jobs = doc.get('jobs') or {}

    matrix = (jobs.get('test', {}).get('strategy', {}) or {}).get('matrix', {}) or {}
    for py in matrix.get('python', []) or []:
        combos.add(Combo(norm_python(py), '', False, 'none'))
    for inc in matrix.get('include', []) or []:
        combos.add(Combo(
            norm_python(inc.get('python', '')),
            str(inc.get('scrapyd-version', '') or ''),
            truthy(inc.get('use-git', '')),
            str(inc.get('db', 'none') or 'none'),
        ))

    db_matrix = (jobs.get('test-db', {}).get('strategy', {}) or {}).get('matrix', {}) or {}
    pythons = [norm_python(p) for p in db_matrix.get('python', []) or []]
    git_flags = db_matrix.get('use-git', ['']) or ['']
    for py in pythons:
        for db in db_matrix.get('db', []) or []:
            for git in git_flags:
                combos.add(Combo(py, '', truthy(git), str(db)))
    for inc in db_matrix.get('include', []) or []:
        combos.add(Combo(
            norm_python(inc.get('python', '')),
            str(inc.get('scrapyd-version', '') or ''),
            truthy(inc.get('use-git', '')),
            str(inc.get('db', 'none') or 'none'),
        ))
    return combos


def circleci_combos(doc):
    combos = set()
    workflows = doc.get('workflows') or {}
    entries = (workflows.get('test', {}) or {}).get('jobs', []) or []
    for entry in entries:
        if isinstance(entry, str):
            job_name, params = entry, {}
        else:
            job_name, params = next(iter(entry.items()))
            params = params or {}
        if job_name not in CIRCLE_JOB_KINDS:
            continue  # e.g. matrix-check
        kind = CIRCLE_JOB_KINDS[job_name]
        py = params.get('version')
        if not py:
            raise ValueError("CircleCI job '%s' is missing the 'version' parameter" % params.get('name', job_name))
        combos.add(Combo(
            norm_python(py),
            kind.get('scrapyd', ''),
            truthy(params.get('use-git', '')),
            kind.get('db', 'none'),
        ))
    return combos


def format_combo(combo):
    return 'python=%s scrapyd=%s git=%s db=%s' % (
        combo.python, combo.scrapyd or 'latest', combo.git, combo.db)


def report(name, combos):
    missing = sorted(REQUIRED_COMBOS - combos, key=format_combo)
    print('== %s: %d combos detected ==' % (name, len(combos)))
    for combo in sorted(combos, key=format_combo):
        marker = 'required' if combo in REQUIRED_COMBOS else 'extra'
        print('  [%s] %s' % (marker, format_combo(combo)))
    if missing:
        print('  MISSING %d required combos:' % len(missing))
        for combo in missing:
            print('    - %s' % format_combo(combo))
    else:
        print('  OK: all %d required combos are covered' % len(REQUIRED_COMBOS))
    print()
    return not missing


def check_entrypoint(path):
    with open(path) as f:
        content = f.read()
    if './test.sh' not in content:
        print('ERROR: %s does not reference the shared ./test.sh entrypoint' % path)
        return False
    return True


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else '.')
    gha_path = os.path.join(root, '.github', 'workflows', 'tests.yml')
    circle_path = os.path.join(root, '.circleci', 'config.yml')
    test_sh = os.path.join(root, 'test.sh')

    ok = True
    if not os.access(test_sh, os.X_OK):
        print('ERROR: test.sh is missing or not executable: %s' % test_sh)
        ok = False

    with open(gha_path) as f:
        gha_doc = yaml.safe_load(f)
    with open(circle_path) as f:
        circle_doc = yaml.safe_load(f)

    ok = report('GitHub Actions (.github/workflows/tests.yml)', github_combos(gha_doc)) and ok
    ok = report('CircleCI (.circleci/config.yml)', circleci_combos(circle_doc)) and ok
    ok = check_entrypoint(gha_path) and ok
    ok = check_entrypoint(circle_path) and ok

    if ok:
        print('Matrix check passed: both CI systems cover all required combos via ./test.sh')
        return 0
    print('Matrix check FAILED')
    return 1


if __name__ == '__main__':
    sys.exit(main())
