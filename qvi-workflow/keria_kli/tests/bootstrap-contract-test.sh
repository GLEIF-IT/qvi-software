#!/usr/bin/env bash

# Contract tests for the local workflow's source-based dependency bootstrap.

set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORKFLOW_DIR=$(cd "${TEST_DIR}/.." && pwd -P)
BOOTSTRAP_FILE="${WORKFLOW_DIR}/bootstrap-local.sh"

# Fail immediately with one readable assertion message.
fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Keep maintained GEDA KERIpy source outside disposable workflow dependencies.
test_geda_keripy_install_source() {
    local bootstrap_source

    bootstrap_source=$(<"${BOOTSTRAP_FILE}")
    [[ "${bootstrap_source}" == *'--editable "${GEDA_KERIPY_DIR}"'* ]] ||
        fail_test 'GEDA KLI does not install the maintained KERIpy worktree'
    [[ "${bootstrap_source}" != *'keripy-geda'* ]] ||
        fail_test 'GEDA KLI still installs a disposable .deps checkout'
}

# Accept either packaging format used by maintained local Sally checkouts.
test_sally_source_layouts() {
    local bootstrap_source

    bootstrap_source=$(<"${BOOTSTRAP_FILE}")
    [[ "${bootstrap_source}" == \
       *'! -f "${LOCAL_SALLY_DIR}/pyproject.toml" &&'* ]] ||
        fail_test 'bootstrap does not recognize a Sally pyproject'
    [[ "${bootstrap_source}" == \
       *'! -f "${LOCAL_SALLY_DIR}/setup.py"'* ]] ||
        fail_test 'bootstrap does not recognize a Sally setup.py project'
}

test_geda_keripy_install_source
test_sally_source_layouts
printf 'bootstrap contract passed\n'
