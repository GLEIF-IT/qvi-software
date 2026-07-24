#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_PATH="${TEST_DIR}/../vlei-workflow.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-cli-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
FAKE_BIN="${TEST_ROOT}/bin"
DOCKER_CALLED_FILE="${TEST_ROOT}/docker-called"
mkdir -p "${FAKE_BIN}"
# Expansion belongs to the generated fake executable.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    ': > "${DOCKER_CALLED_FILE:?}"' \
    'exit 99' \
    > "${FAKE_BIN}/docker"
chmod 700 "${FAKE_BIN}/docker"

run_and_capture_status() {
    local status_file=$1
    shift
    local command_status=0
    local runtime_parent="${QVI_RUNTIME_PARENT_OVERRIDE:-${TEST_ROOT}/runtime}"

    (
        cd /
        PATH="${FAKE_BIN}:${PATH}" \
        DOCKER_CALLED_FILE="${DOCKER_CALLED_FILE}" \
        QVI_RUNTIME_PARENT="${runtime_parent}" \
            bash "${SCRIPT_PATH}" "$@" >/dev/null 2>&1
    ) || command_status=$?
    printf '%s\n' "${command_status}" > "${status_file}"
}

run_and_capture_status "${TEST_ROOT}/help.status" --help
help_status=$(<"${TEST_ROOT}/help.status")
[[ "${help_status}" -eq 0 ]]

run_and_capture_status "${TEST_ROOT}/unknown.status" --not-a-real-option
unknown_status=$(<"${TEST_ROOT}/unknown.status")
[[ "${unknown_status}" -eq 2 ]]

run_and_capture_status "${TEST_ROOT}/missing.status" --timeout
missing_value_status=$(<"${TEST_ROOT}/missing.status")
[[ "${missing_value_status}" -eq 2 ]]

run_and_capture_status "${TEST_ROOT}/missing-alias.status" --alias
missing_alias_status=$(<"${TEST_ROOT}/missing-alias.status")
[[ "${missing_alias_status}" -eq 2 ]]

run_and_capture_status "${TEST_ROOT}/missing-oobi.status" --oobi
missing_oobi_status=$(<"${TEST_ROOT}/missing-oobi.status")
[[ "${missing_oobi_status}" -eq 2 ]]

run_and_capture_status "${TEST_ROOT}/zero-timeout.status" --timeout 0
zero_timeout_status=$(<"${TEST_ROOT}/zero-timeout.status")
[[ "${zero_timeout_status}" -eq 2 ]]

run_and_capture_status "${TEST_ROOT}/text-timeout.status" --timeout soon
text_timeout_status=$(<"${TEST_ROOT}/text-timeout.status")
[[ "${text_timeout_status}" -eq 2 ]]

run_and_capture_status "${TEST_ROOT}/conflict.status" --staging --production
conflict_status=$(<"${TEST_ROOT}/conflict.status")
[[ "${conflict_status}" -eq 2 ]]

run_and_capture_status "${TEST_ROOT}/alias-without-alternate.status" --alias verifier
alias_without_alternate_status=$(<"${TEST_ROOT}/alias-without-alternate.status")
[[ "${alias_without_alternate_status}" -eq 2 ]]

run_and_capture_status "${TEST_ROOT}/oobi-without-alternate.status" \
    --oobi http://example.test/oobi
oobi_without_alternate_status=$(<"${TEST_ROOT}/oobi-without-alternate.status")
[[ "${oobi_without_alternate_status}" -eq 2 ]]

blocked_runtime_parent="${TEST_ROOT}/blocked-runtime-parent"
printf 'not a directory\n' > "${blocked_runtime_parent}"
QVI_RUNTIME_PARENT_OVERRIDE="${blocked_runtime_parent}"
run_and_capture_status "${TEST_ROOT}/runtime-create-failure.status" --keep-runtime
unset QVI_RUNTIME_PARENT_OVERRIDE
runtime_create_failure_status=$(<"${TEST_ROOT}/runtime-create-failure.status")
runtime_create_failure_was_preserved=false
[[ "${runtime_create_failure_status}" -ne 0 ]] &&
    runtime_create_failure_was_preserved=true
if [[ "${runtime_create_failure_was_preserved}" == false ]]; then
    printf 'FAIL: runtime creation failure was reported as success\n' >&2
    exit 1
fi

runtime_was_created=false
[[ -d "${TEST_ROOT}/runtime" ]] && runtime_was_created=true
if [[ "${runtime_was_created}" == true ]]; then
    printf 'FAIL: invalid/help-only CLI parsing created runtime state\n' >&2
    exit 1
fi

docker_was_called=false
[[ -e "${DOCKER_CALLED_FILE}" ]] && docker_was_called=true
if [[ "${docker_was_called}" == true ]]; then
    printf 'FAIL: invalid/help-only CLI parsing invoked Docker\n' >&2
    exit 1
fi

printf 'vlei-workflow-cli-test: PASS\n'
