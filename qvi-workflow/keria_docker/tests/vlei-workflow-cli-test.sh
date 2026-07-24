#!/usr/bin/env bash
set -Eeuo pipefail

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

    (
        cd /
        PATH="${FAKE_BIN}:${PATH}" \
        DOCKER_CALLED_FILE="${DOCKER_CALLED_FILE}" \
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

docker_was_called=false
[[ -e "${DOCKER_CALLED_FILE}" ]] && docker_was_called=true
if [[ "${docker_was_called}" == true ]]; then
    printf 'FAIL: invalid/help-only CLI parsing invoked Docker\n' >&2
    exit 1
fi

custom_env="${TEST_ROOT}/custom.env"
cp "${SCRIPT_PATH%/*}/keria-signify-docker.env" "${custom_env}"
custom_help_status=0
QVI_WORKFLOW_ENV_FILE="${custom_env}" \
    bash "${SCRIPT_PATH}" --help >/dev/null ||
    custom_help_status=$?
[[ "${custom_help_status}" -eq 0 ]]

printf 'vlei-workflow-cli-test: PASS\n'
