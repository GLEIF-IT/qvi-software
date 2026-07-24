#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)

# shellcheck source=../lib/workflow-runtime.sh
source "${SCRIPT_DIR}/lib/workflow-runtime.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-job-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

WORKFLOW_JOB_DIR="${TEST_ROOT}/jobs"
WORKFLOW_LOG_DIR="${TEST_ROOT}/logs"
WORKFLOW_TIMEOUT_SECONDS=1
mkdir -p "${WORKFLOW_JOB_DIR}" "${WORKFLOW_LOG_DIR}"

MOCK_CONTAINER_ID=cid-success
MOCK_EXIT_STATUS=0
MOCK_RUNNING_STATE=false

workflow_compose() {
    [[ "${1:-}" == run ]] || return 1
    printf '%s\n' "${MOCK_CONTAINER_ID}"
}

docker() {
    local command=$1
    shift
    case "${command}" in
        inspect)
            if [[ "$*" == *State.Running* ]]; then
                printf '%s\n' "${MOCK_RUNNING_STATE}"
            else
                printf '%s\n' "${MOCK_EXIT_STATUS}"
            fi
            ;;
        logs)
            printf 'job log for %s with public-demo-passcode\n' "${1}"
            ;;
        rm)
            local last_argument=""
            for last_argument in "$@"; do
                :
            done
            printf '%s\n' "${last_argument}" > "${TEST_ROOT}/removed"
            ;;
        *)
            return 1
            ;;
    esac
}

run_detached_compose_job kli success fixture arguments
wait_for_compose_job success
grep -q 'public-demo-passcode' "${WORKFLOW_LOG_DIR}/success.log"
grep -q '^cid-success$' "${TEST_ROOT}/removed"

MOCK_CONTAINER_ID=cid-failure
MOCK_EXIT_STATUS=42
run_detached_compose_job kli failure fixture arguments
failure_status=0
wait_for_compose_job failure >/dev/null 2>&1 || failure_status=$?
[[ "${failure_status}" -ne 0 ]]

MOCK_CONTAINER_ID=cid-timeout
MOCK_EXIT_STATUS=0
MOCK_RUNNING_STATE=true
run_detached_compose_job kli timeout fixture arguments
timeout_status=0
wait_for_compose_job timeout >/dev/null 2>&1 || timeout_status=$?
[[ "${timeout_status}" -ne 0 ]]

printf 'workflow-job-test: PASS\n'
