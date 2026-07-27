#!/usr/bin/env bash

# Contract tests for the local workflow's dependency bootstrap.

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

# Require the published Sally release instead of an arbitrary local checkout.
test_sally_release_pin() {
    local bootstrap_source

    bootstrap_source=$(<"${BOOTSTRAP_FILE}")
    [[ "${bootstrap_source}" == *'SALLY_VERSION=1.0.5'* ]] ||
        fail_test 'bootstrap does not pin Sally 1.0.5'
    [[ "${bootstrap_source}" == *'"sally==${SALLY_VERSION}"'* ]] ||
        fail_test 'bootstrap does not install Sally from PyPI'
    [[ "${bootstrap_source}" != *'LOCAL_SALLY_DIR'* ]] ||
        fail_test 'bootstrap still depends on a local Sally checkout'
}

test_geda_keripy_install_source
test_sally_release_pin
printf 'bootstrap contract passed\n'
