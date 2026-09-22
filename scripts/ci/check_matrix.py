#!/usr/bin/env python3
"""Self-check for the CI matrices and the reusable test entry points.

Validates that:
  1. Both CI matrices (GitHub Actions and CircleCI) cover all required combinations
     (base tests per Python version, scrapyd-v143, git deps, sqlite/postgresql/mysql).
  2. Every matrix leg only uses env switches that test.sh actually consumes.
  3. Both CI configs route test execution through ./test.sh.
  4. All shell entry points pass `bash -n` syntax checking.

Exits non-zero (with a readable report) when anything is missing,
so the matrix can never silently drop a key combination.
"""
import os
import re
import subprocess
import sys
from itertools import product

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORKFLOW_PATH = os.path.join(REPO_ROOT, '.github', 'workflows', 'tests.yml')
CIRCLECI_PATH = os.path.join(REPO_ROOT, '.circleci', 'config.yml')
TEST_SH = os.path.join(REPO_ROOT, 'test.sh')
CI_DIR = os.path.join(REPO_ROOT, 'scripts', 'ci')

# Python versions that must each have a plain "base" leg.
REQUIRED_BASE_PYTHONS = ['3.8', '3.9', '3.10', '3.11', '3.12', '3.13']
# Python versions that must also run against the legacy scrapyd pin.
REQUIRED_SCRAPYD_V143_PYTHONS = ['3.9', '3.12']
# Database variants that must appear at least once.
REQUIRED_DB_VARIANTS = ['sqlite', 'postgresql', 'mysql']
# Variant names that must appear at least once (dependency variants).
REQUIRED_VARIANTS = ['git-postgresql', 'git-mysql']

# Env switches a matrix leg may set; each must be consumed by test.sh.
KNOWN_SWITCHES = {
    'USE_GIT': r'USE_GIT',
    'SCRAPYD_VERSION': r'SCRAPYD_VERSION',
    'DATABASE_URL': r'DATABASE_URL',
    'DATA_PATH': r'DATA_PATH',
}

failures = []


def check(ok, message):
    print('%s %s' % ('PASS' if ok else 'FAIL', message))
    if not ok:
        failures.append(message)


def load_github_matrix():
    with open(WORKFLOW_PATH, encoding='utf-8') as f:
        workflow = yaml.safe_load(f)
    # YAML 1.1 parses the literal key `on` as True; tolerate both.
    if 'on' not in workflow and True not in workflow:
        check(False, 'workflow has no `on:` trigger section')
    try:
        includes = workflow['jobs']['test']['strategy']['matrix']['include']
    except KeyError:
        check(False, 'workflow jobs.test.strategy.matrix.include is missing')
        return []
    check(bool(includes), 'github: matrix include list is non-empty')
    return [
        dict(python=str(leg.get('python', '')), variant=leg.get('variant', ''),
             use_git=str(leg.get('use_git', '')),
             scrapyd_version=str(leg.get('scrapyd_version', '')),
             database_url=str(leg.get('database_url', '')))
        for leg in includes
    ]


def infer_circleci_variant(params):
    use_git = str(params.get('use-git', ''))
    database_url = str(params.get('database-url', ''))
    if use_git == '1' and 'postgresql' in database_url:
        return 'git-postgresql'
    if use_git == '1' and 'mysql' in database_url:
        return 'git-mysql'
    if params.get('scrapyd-version'):
        return 'scrapyd-v143'
    if 'sqlite' in database_url:
        return 'sqlite'
    if 'postgresql' in database_url:
        return 'postgresql'
    if 'mysql' in database_url:
        return 'mysql'
    return 'base'


def load_circleci_matrix():
    with open(CIRCLECI_PATH, encoding='utf-8') as f:
        config = yaml.safe_load(f)
    try:
        jobs = config['workflows']['test']['jobs']
    except KeyError:
        check(False, 'circleci: workflows.test.jobs is missing')
        return []
    legs = []
    for entry in jobs:
        if not isinstance(entry, dict) or 'test' not in entry:
            continue
        spec = entry['test'] or {}
        matrix = (spec.get('matrix') or {}).get('parameters') or {}
        if matrix:
            keys = sorted(matrix)
            for combo in product(*(matrix[k] for k in keys)):
                params = dict(zip(keys, combo))
                params.setdefault('python', spec.get('python', ''))
                legs.append(params)
        else:
            legs.append(spec)
    result = [
        dict(python=str(leg.get('python', '')), variant=infer_circleci_variant(leg),
             use_git=str(leg.get('use-git', '')),
             scrapyd_version=str(leg.get('scrapyd-version', '')),
             database_url=str(leg.get('database-url', '')))
        for leg in legs
    ]
    check(bool(result), 'circleci: expanded matrix is non-empty')
    return result


def check_matrix_coverage(label, legs):
    by_variant = {}
    for leg in legs:
        by_variant.setdefault(leg['variant'], []).append(leg['python'])

    for py in REQUIRED_BASE_PYTHONS:
        check(py in by_variant.get('base', []),
              '%s: base tests run on Python %s' % (label, py))

    for py in REQUIRED_SCRAPYD_V143_PYTHONS:
        check(py in by_variant.get('scrapyd-v143', []),
              '%s: scrapyd-v143 variant runs on Python %s' % (label, py))

    for variant in REQUIRED_DB_VARIANTS + REQUIRED_VARIANTS:
        check(by_variant.get(variant),
              '%s: variant %r is present in the matrix' % (label, variant))

    for leg in legs:
        variant = leg['variant']
        if variant in ('postgresql', 'mysql', 'git-postgresql', 'git-mysql'):
            check(bool(leg['database_url']),
                  '%s: leg %s/%s sets database_url' % (label, leg['python'], variant))
        if variant.startswith('git'):
            check(leg['use_git'] in ('1', 'true', 'True'),
                  '%s: leg %s/%s enables use_git' % (label, leg['python'], variant))
        if variant == 'scrapyd-v143':
            check(leg['scrapyd_version'] == '1.4.3',
                  '%s: leg %s/%s pins scrapyd_version=1.4.3' % (label, leg['python'], variant))


def check_switches_consumed():
    with open(TEST_SH, encoding='utf-8') as f:
        entry = f.read()
    scripts = ''
    for name in os.listdir(CI_DIR):
        if name.endswith('.sh'):
            with open(os.path.join(CI_DIR, name), encoding='utf-8') as f:
                scripts += f.read()
    for switch, pattern in sorted(KNOWN_SWITCHES.items()):
        check(re.search(pattern, entry) or re.search(pattern, scripts),
              'env switch %s is consumed by test.sh or scripts/ci' % switch)
    for path, label in [(WORKFLOW_PATH, 'github'), (CIRCLECI_PATH, 'circleci')]:
        with open(path, encoding='utf-8') as f:
            check('./test.sh' in f.read(),
                  '%s: config routes test execution through ./test.sh' % label)


def check_shell_syntax():
    scripts = [TEST_SH]
    scripts += [os.path.join(CI_DIR, n) for n in sorted(os.listdir(CI_DIR)) if n.endswith('.sh')]
    for script in scripts:
        result = subprocess.run(['bash', '-n', script], capture_output=True, text=True)
        rel = os.path.relpath(script, REPO_ROOT)
        check(result.returncode == 0,
              'bash -n %s%s' % (rel, ('\n' + result.stderr.strip()) if result.stderr else ''))


def main():
    github_legs = load_github_matrix()
    if github_legs:
        check_matrix_coverage('github', github_legs)
    circleci_legs = load_circleci_matrix()
    if circleci_legs:
        check_matrix_coverage('circleci', circleci_legs)
    check_switches_consumed()
    check_shell_syntax()

    print()
    if failures:
        print('%d check(s) FAILED' % len(failures))
        return 1
    print('All matrix and entry-point checks passed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
