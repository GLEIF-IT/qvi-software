#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)
WORKFLOW_REPOSITORY_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)

# shellcheck source=../lib/workflow-runtime.sh
source "${SCRIPT_DIR}/lib/workflow-runtime.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-runtime-test.XXXXXX")
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

assert_false() {
    local description=$1
    shift
    local assertion_failed=false

    "$@" || assertion_failed=true
    if [[ "${assertion_failed}" == false ]]; then
        printf 'FAIL: %s\n' "${description}" >&2
        return 1
    fi
}

assert_file_is_absent() {
    local path=$1
    [[ ! -e "${path}" ]]
}

assert_directory_is_empty() {
    local path=$1
    local first_entry=""

    first_entry=$(find "${path}" -mindepth 1 -maxdepth 1 -print -quit)
    [[ -z "${first_entry}" ]]
}

always_pending() {
    printf 'still pending: exact fixture state\n'
    return 1
}

blocking_predicate() {
    printf 'entered blocking predicate\n'
    while true; do
        :
    done
}

QVI_RUNTIME_PARENT="${TEST_ROOT}/runtimes"
QVI_PROOF_ROOT="${TEST_ROOT}/proofs"
mkdir -p "${QVI_RUNTIME_PARENT}"
assert_true \
    "scoped temporary parent is accepted" \
    runtime_parent_path_is_safe \
    "${QVI_RUNTIME_PARENT}"
assert_false \
    "filesystem root cannot be a runtime parent" \
    runtime_parent_path_is_safe \
    /
assert_false \
    "home directory cannot be a runtime parent" \
    runtime_parent_path_is_safe \
    "${HOME}"
assert_false \
    "repository root cannot be a runtime parent" \
    runtime_parent_path_is_safe \
    "${WORKFLOW_REPOSITORY_ROOT}"
create_workflow_runtime
owned_runtime="${WORKFLOW_RUN_DIR}"

assert_true "new runtime is sentinel-owned" runtime_path_is_owned "${owned_runtime}"
assert_false "filesystem root is never owned" runtime_path_is_owned /
assert_false "home directory is never owned" runtime_path_is_owned "${HOME}"
assert_false \
    "repository root is never owned" \
    runtime_path_is_owned \
    "${WORKFLOW_REPOSITORY_ROOT}"
assert_true \
    "stale source temp-data is not copied into a new run" \
    assert_directory_is_empty \
    "${KLI_DATA_DIR}/temp-data"
assert_true \
    "generated multisig config is not copied into a new run" \
    assert_file_is_absent \
    "${WORKFLOW_CONFIG_DIR}/multi-sig-incept-config.json"
remove_owned_runtime "${owned_runtime}"
assert_true "owned runtime is removed" assert_file_is_absent "${owned_runtime}"

unowned_runtime="${WORKFLOW_RUNTIME_PARENT}/run.unowned"
mkdir -p "${unowned_runtime}"
assert_false "missing sentinel blocks cleanup" remove_owned_runtime "${unowned_runtime}"
assert_true "unowned runtime survives cleanup refusal" test -d "${unowned_runtime}"

outside_runtime="${TEST_ROOT}/outside"
mkdir -p "${outside_runtime}"
printf '%s\n' "${WORKFLOW_RUNTIME_SENTINEL_VALUE}" \
    > "${outside_runtime}/${WORKFLOW_RUNTIME_SENTINEL_NAME}"
escape_link="${WORKFLOW_RUNTIME_PARENT}/run.escape"
ln -s "${outside_runtime}" "${escape_link}"
assert_false "symlink escape blocks cleanup" remove_owned_runtime "${escape_link}"
assert_true "symlink escape target survives cleanup refusal" test -d "${outside_runtime}"

nested_runtime="${unowned_runtime}/run.nested"
mkdir -p "${nested_runtime}"
printf '%s\n' "${WORKFLOW_RUNTIME_SENTINEL_VALUE}" \
    > "${nested_runtime}/${WORKFLOW_RUNTIME_SENTINEL_NAME}"
assert_false \
    "a nested path cannot impersonate an owned run root" \
    remove_owned_runtime \
    "${nested_runtime}"
assert_true \
    "nested path survives cleanup refusal" \
    test -d \
    "${nested_runtime}"

sentinel_target="${TEST_ROOT}/sentinel-target"
printf '%s\n' "${WORKFLOW_RUNTIME_SENTINEL_VALUE}" > "${sentinel_target}"
linked_sentinel_runtime="${WORKFLOW_RUNTIME_PARENT}/run.linked-sentinel"
mkdir -p "${linked_sentinel_runtime}"
ln -s \
    "${sentinel_target}" \
    "${linked_sentinel_runtime}/${WORKFLOW_RUNTIME_SENTINEL_NAME}"
assert_false \
    "a linked sentinel cannot establish runtime ownership" \
    remove_owned_runtime \
    "${linked_sentinel_runtime}"

redacted_output=$(redact_stream < "${TEST_DIR}/fixtures/redaction-input.txt")
secret_was_retained=false
printf '%s\n' "${redacted_output}" | grep -q 'not-a-real' && secret_was_retained=true
if [[ "${secret_was_retained}" == true ]]; then
    printf 'FAIL: redaction retained a fixture secret\n' >&2
    exit 1
fi

QVI_RUNTIME_PARENT="${TEST_ROOT}/proof-runtimes"
QVI_PROOF_ROOT="${TEST_ROOT}/proofs"
create_workflow_runtime
proof_runtime="${WORKFLOW_RUN_DIR}"
append_proof_record '{"type":"runtime","composeProject":"qvi-test"}'
append_proof_record '{"type":"challenge","direction":"left->right"}'
append_proof_record '{"type":"kli-job","name":"gar1","exitStatus":0}'
append_proof_record '{"type":"qvi-operation","operation":"inception"}'
write_proof_summary passed 7
summary_matches_manifest=false
jq -e \
    '
      .status == "passed" and
      .durationSeconds == 7 and
      .runtime.composeProject == "qvi-test" and
      (.challenges | length) == 1 and
      (.detachedJobs | length) == 1 and
      (.qviOperations | length) == 1 and
      .qviOperations[0].operation == "inception"
    ' "${PROOF_SUMMARY}" >/dev/null &&
    summary_matches_manifest=true
if [[ "${summary_matches_manifest}" == false ]]; then
    printf 'FAIL: proof summary did not preserve the recorded evidence\n' >&2
    exit 1
fi
assert_false \
    "proof manifest rejects non-object records" \
    append_proof_record \
    '["not-an-object"]'
assert_false \
    "proof manifest rejects secret-bearing fields" \
    append_proof_record \
    '{"type":"fixture","participantSalt":"not-a-real-secret"}'
append_proof_record \
    '{"type":"challenge","challengeDigest":"0123456789abcdef"}'
registered_secret="not-a-real-registered-secret"
register_proof_secret_values "${registered_secret}"
assert_false \
    "proof manifest rejects registered secrets under generic keys" \
    append_proof_record \
    '{"type":"fixture","details":"not-a-real-registered-secret"}'
registered_secret_was_redacted=false
printf 'generic=%s\n' "${registered_secret}" |
    redact_stream |
    grep -q 'generic=<redacted>' &&
    registered_secret_was_redacted=true
if [[ "${registered_secret_was_redacted}" == false ]]; then
    printf 'FAIL: registered secret value was not redacted\n' >&2
    exit 1
fi
remove_owned_runtime "${proof_runtime}"

polling_diagnostic="${TEST_ROOT}/polling-diagnostic.txt"
polling_timed_out=false
wait_until \
    "the focused polling fixture" \
    0 \
    always_pending > /dev/null 2> "${polling_diagnostic}" ||
    polling_timed_out=true
if [[ "${polling_timed_out}" == false ]]; then
    printf 'FAIL: pending predicate did not time out\n' >&2
    exit 1
fi
last_observation_was_reported=false
grep -q 'Last observation: still pending: exact fixture state' \
    "${polling_diagnostic}" &&
    last_observation_was_reported=true
if [[ "${last_observation_was_reported}" == false ]]; then
    printf 'FAIL: polling timeout omitted the last observed state\n' >&2
    exit 1
fi

blocking_started_at=$(date +%s)
blocking_timed_out=false
wait_until \
    "the blocked predicate fixture" \
    1 \
    blocking_predicate >/dev/null 2>&1 ||
    blocking_timed_out=true
blocking_duration=$(( $(date +%s) - blocking_started_at ))
if [[ "${blocking_timed_out}" == false ||
      "${blocking_duration}" -gt 3 ]]; then
    printf 'FAIL: blocked predicate escaped the hard deadline\n' >&2
    exit 1
fi

(
    QVI_RUNTIME_PARENT="${TEST_ROOT}/retained-runtimes"
    QVI_PROOF_ROOT="${TEST_ROOT}/retained-proofs"
    KEEP_RUNTIME=true
    DOCKER_COMPOSE_FILE="${TEST_ROOT}/unused-compose.yaml"
    START_TIME=$(date +%s)
    create_workflow_runtime
    retained_runtime="${WORKFLOW_RUN_DIR}"
    CHALLENGE_WORD_FILE="${WORKFLOW_SECRET_DIR}/challenge-fixture.words"
    retained_fixture_secret="never retain these fixture words"
    printf '%s\n' "${retained_fixture_secret}" > "${CHALLENGE_WORD_FILE}"
    register_proof_secret_values "${retained_fixture_secret}"
    printf 'job output: %s\n' "${retained_fixture_secret}" \
        > "${WORKFLOW_LOG_DIR}/gar1.log"
    # Called indirectly by archive_failure_diagnostics.
    # shellcheck disable=SC2329
    workflow_compose() {
        return 1
    }

    retained_cleanup_status=0
    workflow_cleanup 31 >/dev/null 2>&1 ||
        retained_cleanup_status=$?
    [[ "${retained_cleanup_status}" -eq 31 ]]
    assert_true \
        "keep-runtime retains the private runtime" \
        test -d \
        "${retained_runtime}"
    assert_true \
        "keep-runtime still removes transient challenge words" \
        assert_file_is_absent \
        "${WORKFLOW_SECRET_DIR}/challenge-fixture.words"
    archived_job_log="${WORKFLOW_PROOF_DIR}/kli-job-gar1.log"
    assert_true \
        "failure diagnostics retain detached KLI logs" \
        test -f \
        "${archived_job_log}"
    archived_job_log_is_redacted=false
    grep -q 'job output: <redacted>' "${archived_job_log}" &&
        archived_job_log_is_redacted=true
    if [[ "${archived_job_log_is_redacted}" == false ]]; then
        printf 'FAIL: archived detached job log retained a secret\n' >&2
        exit 1
    fi
    KEEP_RUNTIME=false
    remove_owned_runtime "${retained_runtime}"
)

(
    QVI_RUNTIME_PARENT="${TEST_ROOT}/failed-cleanup-runtimes"
    QVI_PROOF_ROOT="${TEST_ROOT}/failed-cleanup-proofs"
    KEEP_RUNTIME=false
    WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST=true
    create_workflow_runtime
    failed_cleanup_runtime="${WORKFLOW_RUN_DIR}"
    # Called directly by workflow_cleanup.
    # shellcheck disable=SC2329
    workflow_compose() {
        return 73
    }

    failed_cleanup_status=0
    workflow_cleanup 0 >/dev/null 2>&1 ||
        failed_cleanup_status=$?
    [[ "${failed_cleanup_status}" -eq 1 ]]
    assert_true \
        "cleanup failure promotes a successful story to failure" \
        assert_file_is_absent \
        "${failed_cleanup_runtime}"
    cleanup_summary_marks_failure=false
    jq -e '.status == "failed"' "${PROOF_SUMMARY}" >/dev/null &&
        cleanup_summary_marks_failure=true
    if [[ "${cleanup_summary_marks_failure}" == false ]]; then
        printf 'FAIL: cleanup failure did not rewrite the proof summary\n' >&2
        exit 1
    fi
)

set +e
(
    QVI_RUNTIME_PARENT="${TEST_ROOT}/exit-runtimes"
    QVI_PROOF_ROOT="${TEST_ROOT}/exit-proofs"
    KEEP_RUNTIME=false
    create_workflow_runtime
    # Called indirectly by workflow_cleanup.
    # shellcheck disable=SC2329
    docker() {
        return 0
    }
    install_workflow_traps
    exit 37
)
exit_status=$?
set -e
[[ "${exit_status}" -eq 37 ]]
assert_true \
    "EXIT cleanup preserves status and removes owned runtime" \
    assert_directory_is_empty \
    "${TEST_ROOT}/exit-runtimes"

for signal_expectation in INT:130 TERM:143 HUP:129; do
    signal_name=${signal_expectation%%:*}
    expected_signal_status=${signal_expectation##*:}
    set +e
    (
        trap - EXIT
        handle_workflow_signal "${signal_name}"
    )
    observed_signal_status=$?
    set -e
    [[ "${observed_signal_status}" -eq "${expected_signal_status}" ]]
done

signal_ready_file="${TEST_ROOT}/signal-ready"
set +e
(
    QVI_RUNTIME_PARENT="${TEST_ROOT}/signal-runtimes"
    QVI_PROOF_ROOT="${TEST_ROOT}/signal-proofs"
    KEEP_RUNTIME=false
    DOCKER_COMPOSE_FILE="${TEST_ROOT}/unused-compose.yaml"
    START_TIME=$(date +%s)
    create_workflow_runtime
    # Called indirectly by workflow_cleanup.
    # shellcheck disable=SC2329
    docker() {
        return 0
    }
    install_workflow_traps
    : > "${signal_ready_file}"
    while true; do
        sleep 1
    done
) &
signal_process_id=$!
set -e

signal_process_is_ready=false
signal_wait_attempt=0
while [[ "${signal_process_is_ready}" == false && "${signal_wait_attempt}" -lt 50 ]]; do
    [[ -f "${signal_ready_file}" ]] && signal_process_is_ready=true
    if [[ "${signal_process_is_ready}" == false ]]; then
        sleep 0.1
    fi
    signal_wait_attempt=$((signal_wait_attempt + 1))
done
if [[ "${signal_process_is_ready}" == false ]]; then
    signal_kill_status=0
    printf 'FAIL: signal test process did not become ready\n' >&2
    kill -KILL "${signal_process_id}" 2>/dev/null ||
        signal_kill_status=$?
    if [[ "${signal_kill_status}" -ne 0 ]]; then
        printf 'Unable to stop the failed signal-test process\n' >&2
    fi
    exit 1
fi

kill -TERM "${signal_process_id}"
set +e
wait "${signal_process_id}"
signal_exit_status=$?
set -e
[[ "${signal_exit_status}" -eq 143 ]]
assert_true \
    "TERM cleanup preserves status and removes owned runtime" \
    assert_directory_is_empty \
    "${TEST_ROOT}/signal-runtimes"

printf 'workflow-runtime-test: PASS\n'
