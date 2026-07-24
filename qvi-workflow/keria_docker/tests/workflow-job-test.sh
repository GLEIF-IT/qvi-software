#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)
WORKFLOW_REPOSITORY_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)

# shellcheck source=../lib/workflow-runtime.sh
source "${SCRIPT_DIR}/lib/workflow-runtime.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-job-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

assert_true() {
    local description=$1
    shift
    local assertion_passed=false

    "$@" && assertion_passed=true
    if [[ "${assertion_passed}" == false ]]; then
        printf 'FAIL: %s\n' "${description}" >&2
        return 1
    fi
}

mock_removal_file() {
    local container_id=$1
    printf '%s/removed-%s\n' "${TEST_ROOT}" "${container_id}"
}

QVI_RUNTIME_PARENT="${TEST_ROOT}/runtimes"
QVI_PROOF_ROOT="${TEST_ROOT}/proofs"
create_workflow_runtime
WORKFLOW_TIMEOUT_SECONDS=0

MOCK_CONTAINER_ID=cid-success
MOCK_EXIT_STATUS=0
MOCK_PROJECT_LABEL="${COMPOSE_PROJECT_NAME}"
MOCK_RUNNING_STATE=false
MOCK_LOG_LINE='PASSCODE=not-a-real-job-secret'

workflow_compose() {
    local compose_command=${1:-}

    case "${compose_command}" in
        run)
            printf '%s\n' "${MOCK_CONTAINER_ID}"
            ;;
        *)
            return 1
            ;;
    esac
}

docker() {
    local docker_command=${1:-}
    local format=""
    local container_id=""

    shift
    case "${docker_command}" in
        inspect)
            format=${2:-}
            container_id=${3:-}
            case "${format}" in
                *com.docker.compose.project*)
                    printf '%s\n' "${MOCK_PROJECT_LABEL}"
                    ;;
                *State.Running*)
                    printf '%s\n' "${MOCK_RUNNING_STATE}"
                    ;;
                *State.ExitCode*)
                    printf '%s\n' "${MOCK_EXIT_STATUS}"
                    ;;
                *)
                    printf 'Unexpected inspect format for %s: %s\n' \
                        "${container_id}" "${format}" >&2
                    return 1
                    ;;
            esac
            ;;
        logs)
            printf '%s\n' "${MOCK_LOG_LINE}"
            ;;
        rm)
            container_id=${2:-}
            : > "$(mock_removal_file "${container_id}")"
            ;;
        *)
            printf 'Unexpected Docker command: %s\n' "${docker_command}" >&2
            return 1
            ;;
    esac
}

run_detached_compose_job kli success-job /run/qvi/success.sh
wait_for_compose_job success-job
assert_true \
    "successful detached job container is removed" \
    test -f \
    "$(mock_removal_file cid-success)"

job_log_retained_secret=false
grep -q 'not-a-real-job-secret' "${WORKFLOW_LOG_DIR}/success-job.log" &&
    job_log_retained_secret=true
if [[ "${job_log_retained_secret}" == true ]]; then
    printf 'FAIL: detached job log retained a fixture secret\n' >&2
    exit 1
fi

success_record_is_present=false
jq -es \
    'any(.[]; .type == "kli-job" and .name == "success-job" and .exitStatus == 0)' \
    "${PROOF_MANIFEST}" >/dev/null &&
    success_record_is_present=true
if [[ "${success_record_is_present}" == false ]]; then
    printf 'FAIL: successful detached job was not recorded\n' >&2
    exit 1
fi

MOCK_CONTAINER_ID=cid-failed
MOCK_EXIT_STATUS=42
run_detached_compose_job kli failed-job /run/qvi/failed.sh
failed_job_status=0
failed_job_was_rejected=false
wait_for_compose_job failed-job || failed_job_status=$?
[[ "${failed_job_status}" -ne 0 ]] && failed_job_was_rejected=true
if [[ "${failed_job_was_rejected}" == false ]]; then
    printf 'FAIL: nonzero detached job was accepted\n' >&2
    exit 1
fi
failed_record_is_present=false
jq -es \
    'any(.[]; .type == "kli-job" and .name == "failed-job" and .exitStatus == 42)' \
    "${PROOF_MANIFEST}" >/dev/null &&
    failed_record_is_present=true
if [[ "${failed_record_is_present}" == false ]]; then
    printf 'FAIL: nonzero detached job status was not recorded\n' >&2
    exit 1
fi

MOCK_CONTAINER_ID=cid-timeout
MOCK_EXIT_STATUS=0
MOCK_RUNNING_STATE=true
run_detached_compose_job kli timeout-job /run/qvi/timeout.sh
timed_out_job_status=0
timed_out_job_was_rejected=false
wait_for_compose_job timeout-job || timed_out_job_status=$?
[[ "${timed_out_job_status}" -ne 0 ]] && timed_out_job_was_rejected=true
if [[ "${timed_out_job_was_rejected}" == false ]]; then
    printf 'FAIL: timed-out detached job was accepted\n' >&2
    exit 1
fi
timeout_record_is_present=false
jq -es \
    'any(.[]; .type == "kli-job" and .name == "timeout-job" and .exitStatus == 124)' \
    "${PROOF_MANIFEST}" >/dev/null &&
    timeout_record_is_present=true
if [[ "${timeout_record_is_present}" == false ]]; then
    printf 'FAIL: detached job timeout was not recorded as 124\n' >&2
    exit 1
fi
assert_true \
    "timed-out detached job container is force-removed" \
    test -f \
    "$(mock_removal_file cid-timeout)"

MOCK_CONTAINER_ID=cid-wrong-project
MOCK_RUNNING_STATE=false
MOCK_PROJECT_LABEL=another-project
wrong_project_status=0
wrong_project_was_rejected=false
run_detached_compose_job kli wrong-project /run/qvi/wrong-project.sh ||
    wrong_project_status=$?
[[ "${wrong_project_status}" -ne 0 ]] && wrong_project_was_rejected=true
if [[ "${wrong_project_was_rejected}" == false ]]; then
    printf 'FAIL: detached job with wrong Compose project was accepted\n' >&2
    exit 1
fi

MOCK_PROJECT_LABEL="${COMPOSE_PROJECT_NAME}"
unsafe_name_status=0
unsafe_name_was_rejected=false
run_detached_compose_job kli '../unsafe-job' /run/qvi/unsafe.sh ||
    unsafe_name_status=$?
[[ "${unsafe_name_status}" -ne 0 ]] && unsafe_name_was_rejected=true
if [[ "${unsafe_name_was_rejected}" == false ]]; then
    printf 'FAIL: path-unsafe detached job name was accepted\n' >&2
    exit 1
fi

printf 'workflow-job-test: PASS\n'
