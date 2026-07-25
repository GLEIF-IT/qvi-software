#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORKFLOW_DIR=$(cd "${TEST_DIR}/.." && pwd -P)

# shellcheck source=../vlei-workflow.sh
source "${WORKFLOW_DIR}/vlei-workflow.sh"

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
    [[ "$(find "${WORKFLOW_RESULT_DIR}" -type f -name '*.json' | wc -l | tr -d '[:space:]')" -eq 2 ]] ||
        fail_test 'background job result files were not recorded'
    jq -e -s \
        'all(.[]; .status == 0 and (.stdoutLog | type == "string"))' \
        "${WORKFLOW_RESULT_DIR}"/*.json >/dev/null ||
        fail_test 'background job result files have the wrong contract'
    load_workflow_job_result timed-a |
        jq -e '.name == "timed-a" and .status == 0' >/dev/null ||
        fail_test 'completed background job result could not be loaded'
    run_workflow_command command contract-probe actor-probe true
    jq -e -s \
        'any(.[]; .kind == "command" and .name == "contract-probe" and .status == 0)' \
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
}

test_delegation_queries_are_actor_disjoint() {
    local approval_source

    approval_source=$(declare -f approve_qvi_delegation)
    [[ "${approval_source}" == *"query-qvi-for-gar1 gar1"* &&
       "${approval_source}" == *"query-qvi-for-gar2 gar2"* ]] ||
        fail_test 'GEDA participant queries do not use independent GAR lanes'
    [[ "${approval_source}" == *"wait_for_background_jobs query-qvi-for-gar1 query-qvi-for-gar2"* ]] ||
        fail_test 'GEDA participant query lanes do not share one deadline'
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

test_challenge_matrix_contract() {
    local relationship
    local workflow_source="${WORKFLOW_DIR}/vlei-workflow.sh"

    for relationship in \
        GAR1-GAR2 LAR1-LAR2 QAR1-QAR2 QAR1-QAR3 \
        QAR2-QAR3 GAR1-QAR1 QAR1-LAR1 QAR1-Person; do
        grep -F "\"${relationship}|" "${workflow_source}" >/dev/null ||
            fail_test "missing challenge relationship ${relationship}"
    done
    grep -F \
        'Completed 16 directed responses across 8 trust relationships' \
        "${workflow_source}" >/dev/null ||
        fail_test 'challenge completion contract is not 16 directions'
}

test_final_revocation_wave_is_actor_disjoint() {
    local optimized_source
    local transmit_source
    local refresh_line
    local presentation_line

    optimized_source=$(declare -f optimized_leaf_credential_pipeline)
    transmit_source=$(declare -f transmit_revoked_oor_to_sally)
    refresh_line=$(printf '%s\n' "${optimized_source}" |
        grep -n 'refresh_person_revoked_oor_state' |
        tail -n 1 |
        cut -d: -f1)
    presentation_line=$(printf '%s\n' "${optimized_source}" |
        grep -n 'present-revoked-oor person,direct-sally' |
        tail -n 1 |
        cut -d: -f1)

    [[ -n "${refresh_line}" && -n "${presentation_line}" &&
       "${refresh_line}" -lt "${presentation_line}" ]] ||
        fail_test 'holder refresh is not complete before the final revocation wave'
    [[ "${transmit_source}" != *"--actor qvi"* ]] ||
        fail_test 'revoked-OOR presentation still mutates the QVI in the ECR revocation wave'
}

test_rotation_failure_reaches_main_flow() {
    local marker
    marker=$(mktemp)
    : > "${marker}"

    (
        setup() { return 0; }
        QVI_PRE=E-QVI
        GEDA_PRE=E-GEDA
        create_qvi_multisig() { return 0; }
        approve_qvi_delegation() { return 0; }
        run_qvi_json() {
            local action=$1
            shift
            case "${action}" in
                ms-rotate-submit)
                    printf '{"event":{"groupPrefix":"E-QVI"}}\n'
                    ;;
                ms-rotate-complete)
                    if [[ " $* " == *" --expected-sequence 2 "* ]]; then
                        return 1
                    fi
                    ;;
                *) return 0 ;;
            esac
        }
        rotate_qvi_with_joining_member() { return 0; }
        authorize_qvi_multisig_agent_endpoint_role() { return 0; }
        resolve_qvi_oobi() { return 0; }
        geda_delegation_to_qvi() { establish_qvi || return 1; }
        qvi_credential() {
            printf 'entered\n' > "${marker}"
            return 0
        }

        main_flow
    ) && fail_test 'main_flow reported success after the sequence-2 assertion failed'

    [[ ! -s "${marker}" ]] ||
        fail_test 'credential issuance ran after the rotation failure'
    rm -f "${marker}"
}

test_every_mode_uses_shared_qvi_lifecycle() {
    local mode
    local marker
    marker=$(mktemp)
    : > "${marker}"

    (
        setup() { return 0; }
        establish_qvi() {
            printf '%s\n' "${CURRENT_MODE}" >> "${marker}"
        }
        geda_delegation_to_qvi() { establish_qvi || return 1; }
        qvi_credential() { return 0; }
        le_creation_and_granting() { return 0; }
        le_sally_presentation() { return 0; }
        oor_auth_and_oor_cred() { return 0; }
        person_present_oor_cred_to_sally() { return 0; }
        revoke_oor_credential() { return 0; }
        present_revoked_oor_to_sally() { return 0; }
        ecr_auth_and_ecr_cred() { return 0; }
        revoke_ecr_credential() { return 0; }
        optimized_leaf_credential_pipeline() { return 0; }
        present_le_gleif_staging() { return 0; }
        present_le_gleif_production() { return 0; }
        present_le_to_alternate() { return 0; }
        pause() { return 0; }
        end_workflow() { return 0; }

        for mode in default staging production alternate; do
            CURRENT_MODE=${mode}
            export CURRENT_MODE
            case "${mode}" in
                default) main_flow ;;
                staging) present_to_staging ;;
                production) present_to_production ;;
                alternate)
                    present_to_alternate_sally
                    ;;
            esac
        done
    ) || fail_test 'a workflow mode bypassed or failed the shared lifecycle'

    [[ "$(wc -l < "${marker}" | tr -d '[:space:]')" == 4 ]] ||
        fail_test 'not all four keria_docker modes used establish_qvi'
    rm -f "${marker}"
}

test_sally_startup_contract() {
    local foundation_arguments=""
    local order=""

    workflow_compose() {
        foundation_arguments+=" $*"
    }
    start_foundation_services
    [[ "${foundation_arguments}" != *"direct-sally"* ]] ||
        fail_test 'foundation startup included Sally'

    (
        create_foundational_multisigs_parallel() {
            GEDA_PRE=E-GEDA
            LE_PRE=E-LE
            export GEDA_PRE
            order+=" geda"
        }
        capture_foundational_group_oobis() { order+=" oobis"; }
        create_foundational_state_parallel() {
            [[ -n "${GEDA_PRE:-}" ]] || return 1
            order+=" registry+sally"
        }
        resolve_oobis() { order+=" resolve"; }
        challenge_response() { return 0; }
        establish_qvi() { order+=" qvi"; }
        create_qvi_reg() { order+=" qvi-registry"; }

        geda_delegation_to_qvi
        [[ "${order}" == \
            " geda oobis registry+sally resolve qvi qvi-registry" ]]
    ) || fail_test 'Sally did not start exactly once after GEDA creation'

    if find "${WORKFLOW_DIR}/config" -name '*.json' -print0 |
        xargs -0 jq -e '
            [
                .. |
                objects |
                (.iurls? // []), (.durls? // []) |
                .[] |
                select(type == "string" and test("sally"; "i"))
            ] |
            length > 0
        ' >/dev/null; then
        fail_test 'a bootstrap iurls/durls list contains a Sally URL'
    fi
}

test_rotation_failure_reaches_main_flow
test_every_mode_uses_shared_qvi_lifecycle
test_sally_startup_contract
test_background_job_contract
test_signal_cleanup_contract
test_challenge_matrix_contract
test_final_revocation_wave_is_actor_disjoint
test_delegation_queries_are_actor_disjoint
printf 'workflow contract passed\n'
