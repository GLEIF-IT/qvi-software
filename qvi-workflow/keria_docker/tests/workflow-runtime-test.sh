#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SOURCE_DIR=$(cd "${TEST_DIR}/.." && pwd -P)

# shellcheck source=../lib/workflow-runtime.sh
source "${SOURCE_DIR}/lib/workflow-runtime.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-runtime-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

SCRIPT_DIR="${TEST_ROOT}/workflow"
DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/compose.yaml"
WORKFLOW_ENV_FILE="${SCRIPT_DIR}/demo.env"
WORKFLOW_TIMEOUT_SECONDS=1
KEEP_RUNTIME=false
mkdir -p \
    "${SCRIPT_DIR}/config" \
    "${SCRIPT_DIR}/acdc-info/rules" \
    "${SCRIPT_DIR}/direct-sally/keri/cf"
printf 'services: {}\n' > "${DOCKER_COMPOSE_FILE}"
printf 'ENVIRONMENT=docker-tsx\n' > "${WORKFLOW_ENV_FILE}"
printf '{}\n' > "${SCRIPT_DIR}/direct-sally/keri/cf/direct-sally.json"
printf '{}\n' > "${SCRIPT_DIR}/direct-sally/sally-incept-no-wits.json"
printf '{}\n' > "${SCRIPT_DIR}/acdc-info/rules/rules.json"

COMPOSE_STATUS=0
COMPOSE_CALLS="${TEST_ROOT}/compose-calls"
workflow_compose() {
    printf '%s\n' "$*" >> "${COMPOSE_CALLS}"
    return "${COMPOSE_STATUS}"
}
print_red() {
    printf '%s\n' "$*" >&2
}
print_yellow() {
    printf '%s\n' "$*" >&2
}

mkdir -p "${SCRIPT_DIR}/runtime"
printf 'stale\n' > "${SCRIPT_DIR}/runtime/stale"
create_workflow_runtime

[[ "${WORKFLOW_RUN_DIR}" == "${SCRIPT_DIR}/runtime" ]]
[[ ! -e "${WORKFLOW_RUN_DIR}/stale" ]]
[[ -f "${WORKFLOW_CONFIG_DIR}/direct-sally/keri/cf/direct-sally.json" ]]
[[ -f "${KLI_DATA_DIR}/rules/rules.json" ]]
[[ -f "${SALLY_CALLBACK_FILE}" ]]
grep -q '^down --volumes --remove-orphans$' "${COMPOSE_CALLS}"

always_pending() {
    printf 'still pending\n'
    return 1
}

immediately_ready() {
    local expected_argument=$1

    printf 'ready with %s\n' "${expected_argument}"
}

immediate_output=$(poll_until \
    "immediate fixture" \
    0 \
    immediately_ready \
    "forwarded argument")
[[ "${immediate_output}" == "ready with forwarded argument" ]]

retry_then_ready() {
    local attempt_file=$1
    local expected_argument=$2
    local attempt_number=0

    [[ "${expected_argument}" == "forwarded argument" ]] || return 1
    if [[ -f "${attempt_file}" ]]; then
        attempt_number=$(<"${attempt_file}")
    fi
    attempt_number=$((attempt_number + 1))
    printf '%s\n' "${attempt_number}" > "${attempt_file}"

    if [[ "${attempt_number}" -lt 2 ]]; then
        printf 'attempt %s is pending\n' "${attempt_number}"
        return 1
    fi

    printf 'ready on attempt %s\n' "${attempt_number}"
}

retry_count_file="${TEST_ROOT}/poll-attempts"
retry_output=$(poll_until \
    "retry fixture" \
    2 \
    retry_then_ready \
    "${retry_count_file}" \
    "forwarded argument")
[[ "${retry_output}" == "ready on attempt 2" ]]
[[ "$(<"${retry_count_file}")" -eq 2 ]]

timeout_output="${TEST_ROOT}/timeout-output"
timeout_status=0
poll_until "fixture state" 0 always_pending \
    >/dev/null 2>"${timeout_output}" || timeout_status=$?
[[ "${timeout_status}" -ne 0 ]]
grep -q 'Last observation: still pending' "${timeout_output}"

KEEP_RUNTIME=true
retained_status=0
workflow_cleanup 31 >/dev/null 2>&1 || retained_status=$?
[[ "${retained_status}" -eq 31 ]]
[[ -d "${WORKFLOW_RUN_DIR}" ]]

KEEP_RUNTIME=false
cleanup_status=0
workflow_cleanup 37 >/dev/null 2>&1 || cleanup_status=$?
[[ "${cleanup_status}" -eq 37 ]]
[[ ! -e "${WORKFLOW_RUN_DIR}" ]]

create_workflow_runtime
COMPOSE_STATUS=73
cleanup_status=0
workflow_cleanup 0 >/dev/null 2>&1 || cleanup_status=$?
[[ "${cleanup_status}" -eq 73 ]]
[[ ! -e "${WORKFLOW_RUN_DIR}" ]]

printf 'workflow-runtime-test: PASS\n'
