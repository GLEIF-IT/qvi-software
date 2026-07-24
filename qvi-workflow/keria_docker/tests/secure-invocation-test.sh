#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)
WORKFLOW_REPOSITORY_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)

# shellcheck source=../lib/workflow-runtime.sh
source "${SCRIPT_DIR}/lib/workflow-runtime.sh"
# shellcheck source=../kli-commands.sh
source "${SCRIPT_DIR}/kli-commands.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-secure-invocation-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

file_mode() {
    local path=$1
    local observed_mode=""
    local stat_status=0

    observed_mode=$(stat -f '%Lp' "${path}" 2>/dev/null) || stat_status=$?
    if [[ "${stat_status}" -ne 0 ]]; then
        observed_mode=$(stat -c '%a' "${path}")
    fi
    printf '%s\n' "${observed_mode}"
}

QVI_RUNTIME_PARENT="${TEST_ROOT}/runtimes"
QVI_PROOF_ROOT="${TEST_ROOT}/proofs"
create_workflow_runtime

CAPTURED_COMPOSE_ARGS="${TEST_ROOT}/compose-args"
MOCK_COMPOSE_STATUS=0
workflow_compose() {
    printf '%s\n' "$@" > "${CAPTURED_COMPOSE_ARGS}"
    return "${MOCK_COMPOSE_STATUS}"
}

fixture_secret=not-a-real-private-passcode
run_secure_compose_command \
    kli \
    kli \
    status \
    --name fixture \
    --passcode "${fixture_secret}"

docker_argv_contains_secret=false
grep -q "${fixture_secret}" "${CAPTURED_COMPOSE_ARGS}" &&
    docker_argv_contains_secret=true
if [[ "${docker_argv_contains_secret}" == true ]]; then
    printf 'FAIL: protected command value appeared in Compose argv\n' >&2
    exit 1
fi

invocation_file_still_exists=false
[[ -e "${SECURE_INVOCATION_HOST_PATH}" ]] &&
    invocation_file_still_exists=true
if [[ "${invocation_file_still_exists}" == true ]]; then
    printf 'FAIL: completed secure invocation file was retained\n' >&2
    exit 1
fi

create_secure_invocation \
    kli \
    status \
    --name fixture \
    --passcode "${fixture_secret}"
invocation_mode=$(file_mode "${SECURE_INVOCATION_HOST_PATH}")
[[ "${invocation_mode}" == 600 ]]
invocation_contains_secret=false
grep -q "${fixture_secret}" "${SECURE_INVOCATION_HOST_PATH}" &&
    invocation_contains_secret=true
if [[ "${invocation_contains_secret}" == false ]]; then
    printf 'FAIL: secure invocation fixture was not written to its protected file\n' >&2
    exit 1
fi
rm -f "${SECURE_INVOCATION_HOST_PATH}"

MOCK_COMPOSE_STATUS=29
failed_invocation_status=0
run_secure_compose_command \
    kli \
    kli \
    status \
    --name fixture \
    --passcode "${fixture_secret}" ||
    failed_invocation_status=$?
[[ "${failed_invocation_status}" -eq 29 ]]
failed_invocation_file_still_exists=false
[[ -e "${SECURE_INVOCATION_HOST_PATH}" ]] &&
    failed_invocation_file_still_exists=true
if [[ "${failed_invocation_file_still_exists}" == true ]]; then
    printf 'FAIL: failed secure invocation file was retained\n' >&2
    exit 1
fi

printf 'secure-invocation-test: PASS\n'
