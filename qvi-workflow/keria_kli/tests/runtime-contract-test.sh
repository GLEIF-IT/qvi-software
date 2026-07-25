#!/usr/bin/env bash

# Contract tests for the local workflow runtime's jobs, deadlines, and signals.

set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORKFLOW_DIR=$(cd "${TEST_DIR}/.." && pwd -P)
SCRIPT_DIR="${WORKFLOW_DIR}"

# shellcheck source=../lib/workflow-runtime.sh
source "${WORKFLOW_DIR}/lib/workflow-runtime.sh"

# Fail immediately with one readable assertion message.
fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Retained cleanup accepts the TypeScript daemon but rejects unrelated commands.
workflow_command_is_owned \
    "node ${WORKFLOW_DIR}/../sig_ts_wallets/node_modules/.bin/tsx ${WORKFLOW_DIR}/../sig_ts_wallets/src/wallet-server.ts"
if workflow_command_is_owned "/usr/bin/python /tmp/unrelated.py"; then
    fail_test "Unrelated process was accepted as workflow-owned"
fi

# Return the background-job registries to their Bash 3.2-safe sentinel state.
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

# Return the managed-process registries to their Bash 3.2-safe sentinel state.
reset_process_registry() {
    WORKFLOW_PROCESS_NAMES=("")
    WORKFLOW_PROCESS_PIDS=("")
    WORKFLOW_PROCESS_LOGS=("")
}

# Wait briefly for an interruptible fixture to announce it has started.
wait_for_fixture_ready() {
    local ready_file=$1
    local deadline=$((SECONDS + 3))

    while [[ ! -f "${ready_file}" ]]; do
        [[ "${SECONDS}" -ge "${deadline}" ]] &&
            fail_test 'interruptible fixture did not become ready'
        sleep 0.1
    done
}

# Prove concurrency, conflicts, result loading, fail-fast, and common deadlines.
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

# Prove the top-level signal trap records SIGINT before running cleanup once.
test_signal_cleanup_contract() {
    local marker
    local signal_status=0

    marker=$(mktemp)
    (
        workflow_cleanup() {
            printf 'cleanup:%s:%s\n' \
                "$1" "${WORKFLOW_CLEANUP_SIGNAL}" > "${marker}"
            return "$1"
        }
        install_workflow_traps
        handle_workflow_signal INT
    ) || signal_status=$?

    [[ "${signal_status}" -eq 130 ]] ||
        fail_test 'SIGINT did not retain its signal exit status'
    [[ "$(cat "${marker}")" == 'cleanup:130:INT' ]] ||
        fail_test 'SIGINT did not run workflow cleanup exactly once'
    rm -f "${marker}"
}

# Prove SIGINT reaches both direct services and Python nested under a shell job.
test_keyboard_interrupt_propagation() {
    local test_runtime
    local managed_ready
    local managed_cleanup
    local job_ready
    local job_cleanup
    local result_file

    test_runtime=$(mktemp -d)
    trap 'rm -rf "${test_runtime}"' RETURN
    WORKFLOW_LOG_DIR="${test_runtime}/logs"
    WORKFLOW_RESULT_DIR="${test_runtime}/results"
    WORKFLOW_PID_DIR="${test_runtime}/pids"
    WORKFLOW_TIMING_FILE="${test_runtime}/timings.jsonl"
    mkdir -p \
        "${WORKFLOW_LOG_DIR}" \
        "${WORKFLOW_RESULT_DIR}" \
        "${WORKFLOW_PID_DIR}"
    # The no-op redirection creates an empty timing stream for the fixture run.
    : > "${WORKFLOW_TIMING_FILE}"

    managed_ready="${test_runtime}/managed.ready"
    managed_cleanup="${test_runtime}/managed.cleanup"
    reset_process_registry
    start_managed_process \
        interruptible-managed \
        python3 "${TEST_DIR}/interruptible-process.py" \
        "${managed_ready}" "${managed_cleanup}"
    wait_for_fixture_ready "${managed_ready}"
    stop_all_managed_processes INT
    [[ "$(cat "${managed_cleanup}")" == 'keyboard-interrupt' ]] ||
        fail_test 'managed Python process did not receive KeyboardInterrupt'

    job_ready="${test_runtime}/job.ready"
    job_cleanup="${test_runtime}/job.cleanup"
    reset_job_registry
    interruptible_job() {
        run_interruptible_process \
            python3 "${TEST_DIR}/interruptible-process.py" \
            "${job_ready}" "${job_cleanup}"
    }
    start_workflow_job interruptible-job actor-a interruptible_job
    wait_for_fixture_ready "${job_ready}"
    cancel_all_workflow_jobs INT
    [[ "$(cat "${job_cleanup}")" == 'keyboard-interrupt' ]] ||
        fail_test 'nested job process did not receive KeyboardInterrupt'
    result_file=$(workflow_job_result_file interruptible-job)
    [[ "$(jq -r '.status' "${result_file}")" -eq 130 ]] ||
        fail_test 'SIGINT-cancelled job did not record status 130'

    trap - RETURN
    rm -rf "${test_runtime}"
}

test_background_job_contract
test_signal_cleanup_contract
test_keyboard_interrupt_propagation
printf 'local workflow runtime contract passed\n'
