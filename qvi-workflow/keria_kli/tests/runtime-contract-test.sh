#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORKFLOW_DIR=$(cd "${TEST_DIR}/.." && pwd -P)
SCRIPT_DIR="${WORKFLOW_DIR}"

# shellcheck source=../lib/workflow-runtime.sh
source "${WORKFLOW_DIR}/lib/workflow-runtime.sh"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

reset_job_registry() {
    WORKFLOW_JOB_NAMES=("")
    WORKFLOW_JOB_PIDS=("")
    WORKFLOW_JOB_STDOUTS=("")
    WORKFLOW_JOB_STDERRS=("")
    WORKFLOW_JOB_RESOURCES=("")
    WORKFLOW_JOB_STARTS=("")
    WORKFLOW_JOB_RESULTS=("")
    WORKFLOW_COMPLETED_JOB_NAMES=("")
    WORKFLOW_COMPLETED_JOB_RESULTS=("")
}

test_background_job_contract() {
    local test_runtime
    local elapsed
    local started_at

    test_runtime=$(mktemp -d)
    trap 'rm -rf "${test_runtime}"' RETURN
    WORKFLOW_LOG_DIR="${test_runtime}/logs"
    WORKFLOW_RESULT_DIR="${test_runtime}/results"
    WORKFLOW_TIMING_FILE="${test_runtime}/timings.jsonl"
    WORKFLOW_TIMEOUT_SECONDS=5
    mkdir -p "${WORKFLOW_LOG_DIR}" "${WORKFLOW_RESULT_DIR}"
    : > "${WORKFLOW_TIMING_FILE}"
    reset_job_registry

    timed_job() {
        sleep 2
    }
    started_at=$(date +%s)
    start_workflow_job timed-a actor-a timed_job
    start_workflow_job timed-b actor-b timed_job
    wait_for_background_jobs timed-a timed-b
    elapsed=$(( $(date +%s) - started_at ))
    [[ "${elapsed}" -lt 4 ]] ||
        fail_test 'disjoint jobs did not execute concurrently'
    [[ "$(jq -s 'length' "${WORKFLOW_TIMING_FILE}")" -eq 2 ]] ||
        fail_test 'background job timings were not recorded'
    [[ "$(find "${WORKFLOW_RESULT_DIR}" -type f -name '*.json' |
        wc -l |
        tr -d '[:space:]')" -eq 2 ]] ||
        fail_test 'background job result files were not recorded'
    jq -e -s \
        'all(.[]; .status == 0 and (.stdoutLog | type == "string"))' \
        "${WORKFLOW_RESULT_DIR}"/*.json >/dev/null ||
        fail_test 'background job results have the wrong contract'
    load_workflow_job_result timed-a |
        jq -e '.name == "timed-a" and .status == 0' >/dev/null ||
        fail_test 'completed background job result could not be loaded'

    run_workflow_command command contract-probe actor-probe true
    jq -e -s \
        'any(.[]; .kind == "command" and
            .name == "contract-probe" and
            .status == 0)' \
        "${WORKFLOW_TIMING_FILE}" >/dev/null ||
        fail_test 'foreground command timing was not recorded'

    reset_job_registry
    start_workflow_job conflict-a shared timed_job
    if start_workflow_job conflict-b shared timed_job; then
        fail_test 'resource-conflicting job was accepted'
    fi
    cancel_all_workflow_jobs

    reset_job_registry
    failing_job() { return 7; }
    slow_job() { sleep 10; }
    started_at=$(date +%s)
    start_workflow_job failing actor-a failing_job
    start_workflow_job slow actor-b slow_job
    if wait_for_background_jobs failing slow; then
        fail_test 'failed job group reported success'
    fi
    elapsed=$(( $(date +%s) - started_at ))
    [[ "${elapsed}" -lt 5 ]] ||
        fail_test 'failed job did not cancel its sibling promptly'

    reset_job_registry
    WORKFLOW_TIMEOUT_SECONDS=1
    start_workflow_job deadline-a actor-a slow_job
    start_workflow_job deadline-b actor-b slow_job
    started_at=$(date +%s)
    if wait_for_background_jobs deadline-a deadline-b; then
        fail_test 'deadline-expired job group reported success'
    else
        [[ "$?" -eq 124 ]] ||
            fail_test 'deadline-expired job group returned the wrong status'
    fi
    elapsed=$(( $(date +%s) - started_at ))
    [[ "${elapsed}" -lt 5 ]] ||
        fail_test 'job group did not enforce one bounded deadline'

    trap - RETURN
    rm -rf "${test_runtime}"
}

test_signal_cleanup_contract() {
    local marker
    local signal_status=0

    marker=$(mktemp)
    (
        workflow_cleanup() {
            printf 'cleanup:%s\n' "$1" > "${marker}"
            return "$1"
        }
        install_workflow_traps
        handle_workflow_signal TERM
    ) || signal_status=$?

    [[ "${signal_status}" -eq 143 ]] ||
        fail_test 'TERM did not retain its signal exit status'
    [[ "$(cat "${marker}")" == 'cleanup:143' ]] ||
        fail_test 'TERM did not run workflow cleanup exactly once'
    rm -f "${marker}"
}

test_background_job_contract
test_signal_cleanup_contract
printf 'local workflow runtime contract passed\n'
