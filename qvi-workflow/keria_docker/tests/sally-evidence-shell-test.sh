#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_PATH="${TEST_DIR}/../vlei-workflow.sh"
EVIDENCE_SCRIPT="${TEST_DIR}/../proof_hook/evidence.py"
FIXTURE_DIR="${TEST_DIR}/../proof_hook/tests/fixtures"

# The driver has a guarded main, so sourcing it exposes only domain functions.
# shellcheck source=../vlei-workflow.sh
source "${SCRIPT_PATH}"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-sally-shell-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

WORKFLOW_LOG_DIR="${TEST_ROOT}/runtime-logs"
WORKFLOW_PROOF_DIR="${TEST_ROOT}/proof"
mkdir -p "${WORKFLOW_LOG_DIR}" "${WORKFLOW_PROOF_DIR}"
SALLY_CALLBACK_FILE="${WORKFLOW_PROOF_DIR}/sally-callbacks.jsonl"
DIRECT_SALLY_LOG_FILE="${WORKFLOW_PROOF_DIR}/direct-sally.log"
PROOF_MANIFEST="${WORKFLOW_PROOF_DIR}/manifest.jsonl"
cp "${FIXTURE_DIR}/callbacks.jsonl" "${SALLY_CALLBACK_FILE}"
: > "${DIRECT_SALLY_LOG_FILE}"
: > "${PROOF_MANIFEST}"

COMPOSE_LOG_MODE=success
workflow_compose() {
    local compose_command=${1:-}
    local argument
    local translated_arguments=()

    case "${compose_command}" in
        exec)
            shift 5
            for argument in "$@"; do
                case "${argument}" in
                    /proof/sally-callbacks.jsonl)
                        translated_arguments[${#translated_arguments[@]}]="${SALLY_CALLBACK_FILE}"
                        ;;
                    /proof/direct-sally.log)
                        translated_arguments[${#translated_arguments[@]}]="${DIRECT_SALLY_LOG_FILE}"
                        ;;
                    *)
                        translated_arguments[${#translated_arguments[@]}]="${argument}"
                        ;;
                esac
            done
            python3 "${EVIDENCE_SCRIPT}" "${translated_arguments[@]}"
            ;;
        logs)
            if [[ "${COMPOSE_LOG_MODE}" == fail ]]; then
                printf 'mock Compose log capture failed\n' >&2
                return 73
            fi
            printf '%s\n' \
                '2026-07-23T17:00:03Z direct-sally PASSCODE=not-a-real-sally-secret' \
                '2026-07-23T17:00:03Z revoked credential EOorCredential being presented'
            ;;
        *)
            printf 'Unexpected Compose command: %s\n' "${compose_command}" >&2
            return 1
            ;;
    esac
}

active_result=""
active_status=0
active_result=$(sally_active_evidence_is_ready \
    2026-07-23T17:00:00Z \
    EQviCredential \
    EQviSchema \
    EQviHolder \
    EQviIssuer) || active_status=$?
[[ "${active_status}" -eq 0 ]]
active_result_is_exact=false
printf '%s\n' "${active_result}" |
    jq -e \
        '
          .ok == true and
          .evidence.action == "iss" and
          .evidence.credential == "EQviCredential" and
          .evidence.holder == "EQviHolder" and
          .evidence.issuer == "EQviIssuer"
        ' >/dev/null &&
    active_result_is_exact=true
if [[ "${active_result_is_exact}" == false ]]; then
    printf 'FAIL: exact active Sally evidence was not accepted\n' >&2
    exit 1
fi

record_sally_evidence "${active_result}" "QVI"
active_record_was_written=false
jq -es \
    'any(.[]; .type == "sally-evidence" and .story == "QVI" and .credential == "EQviCredential")' \
    "${PROOF_MANIFEST}" >/dev/null &&
    active_record_was_written=true
if [[ "${active_record_was_written}" == false ]]; then
    printf 'FAIL: active Sally evidence was not recorded\n' >&2
    exit 1
fi

wrong_holder_output=""
wrong_holder_status=0
wrong_holder_output=$(sally_active_evidence_is_ready \
    2026-07-23T17:00:00Z \
    EQviCredential \
    EQviSchema \
    EWrongHolder \
    EQviIssuer 2>&1) || wrong_holder_status=$?
wrong_holder_was_rejected=false
[[ "${wrong_holder_status}" -ne 0 ]] && wrong_holder_was_rejected=true
if [[ "${wrong_holder_was_rejected}" == false ]]; then
    printf 'FAIL: wrong Sally holder was accepted\n' >&2
    exit 1
fi
wrong_holder_diagnostic_is_exact=false
printf '%s\n' "${wrong_holder_output}" |
    grep -q 'data.recipient mismatch' &&
    wrong_holder_diagnostic_is_exact=true
if [[ "${wrong_holder_diagnostic_is_exact}" == false ]]; then
    printf 'FAIL: wrong-holder evidence omitted its exact diagnostic\n' >&2
    exit 1
fi

polling_output="${TEST_ROOT}/sally-timeout.txt"
polling_status=0
wait_until \
    "wrong-holder Sally fixture" \
    1 \
    sally_active_evidence_is_ready \
    2026-07-23T17:00:00Z \
    EQviCredential \
    EQviSchema \
    EWrongHolder \
    EQviIssuer > /dev/null 2> "${polling_output}" ||
    polling_status=$?
polling_timed_out=false
[[ "${polling_status}" -ne 0 ]] && polling_timed_out=true
if [[ "${polling_timed_out}" == false ]]; then
    printf 'FAIL: Sally mismatch did not time out\n' >&2
    exit 1
fi
timeout_included_last_evidence_error=false
grep -q 'data.recipient mismatch' "${polling_output}" &&
    timeout_included_last_evidence_error=true
if [[ "${timeout_included_last_evidence_error}" == false ]]; then
    printf 'FAIL: Sally timeout omitted the last evidence error. Output: %s\n' \
        "$(<"${polling_output}")" >&2
    exit 1
fi

capture_direct_sally_logs 2026-07-23T17:00:00Z
retained_log_contains_secret=false
grep -q 'not-a-real-sally-secret' "${DIRECT_SALLY_LOG_FILE}" &&
    retained_log_contains_secret=true
if [[ "${retained_log_contains_secret}" == true ]]; then
    printf 'FAIL: retained Sally log contains a fixture secret\n' >&2
    exit 1
fi
raw_log_still_exists=false
[[ -e "${WORKFLOW_LOG_DIR}/direct-sally.raw.log" ]] &&
    raw_log_still_exists=true
if [[ "${raw_log_still_exists}" == true ]]; then
    printf 'FAIL: unredacted Sally log remained in the private runtime\n' >&2
    exit 1
fi

OOR_SCHEMA=EOorSchema
revoked_result=""
revoked_status=0
revoked_result=$(sally_revoked_oor_evidence_is_ready \
    2026-07-23T17:00:02Z \
    EOorCredential \
    ELegalEntity \
    2026-07-23T17:00:03.000000+00:00) || revoked_status=$?
[[ "${revoked_status}" -eq 0 ]]
revoked_result_is_exact=false
printf '%s\n' "${revoked_result}" |
    jq -e \
        '
          .ok == true and
          .evidence.action == "rev" and
          .evidence.credential == "EOorCredential" and
          .evidence.sallyVersion == "1.0.2"
        ' >/dev/null &&
    revoked_result_is_exact=true
if [[ "${revoked_result_is_exact}" == false ]]; then
    printf 'FAIL: exact revoked-OOR Sally evidence was not accepted\n' >&2
    exit 1
fi

wrong_revocation_status=0
sally_revoked_oor_evidence_is_ready \
    2026-07-23T17:00:02Z \
    EOorCredential \
    ELegalEntity \
    2026-07-23T17:00:09Z >/dev/null 2>&1 ||
    wrong_revocation_status=$?
wrong_revocation_was_rejected=false
[[ "${wrong_revocation_status}" -ne 0 ]] &&
    wrong_revocation_was_rejected=true
if [[ "${wrong_revocation_was_rejected}" == false ]]; then
    printf 'FAIL: wrong OOR revocation timestamp was accepted\n' >&2
    exit 1
fi

ECR_SCHEMA=EEcrSchema
no_ecr_result=""
no_ecr_status=0
no_ecr_result=$(no_ecr_callback_window_is_complete \
    2026-07-23T17:00:00Z \
    EEcrCredential \
    0) || no_ecr_status=$?
[[ "${no_ecr_status}" -eq 0 ]]
no_ecr_result_is_exact=false
printf '%s\n' "${no_ecr_result}" |
    jq -e '.ok == true and .evidence.action == "none"' >/dev/null &&
    no_ecr_result_is_exact=true
if [[ "${no_ecr_result_is_exact}" == false ]]; then
    printf 'FAIL: clean no-ECR callback evidence was not accepted\n' >&2
    exit 1
fi

ECR_SCHEMA=EOorSchema
forbidden_callback_status=0
no_ecr_callback_window_is_complete \
    2026-07-23T17:00:00Z \
    EOorCredential \
    0 >/dev/null 2>&1 ||
    forbidden_callback_status=$?
forbidden_callback_was_rejected=false
[[ "${forbidden_callback_status}" -ne 0 ]] &&
    forbidden_callback_was_rejected=true
if [[ "${forbidden_callback_was_rejected}" == false ]]; then
    printf 'FAIL: current forbidden callback was accepted as absent\n' >&2
    exit 1
fi

printf 'prior-redacted-evidence\n' > "${DIRECT_SALLY_LOG_FILE}"
COMPOSE_LOG_MODE=fail
failed_capture_status=0
capture_direct_sally_logs 2026-07-23T17:00:00Z ||
    failed_capture_status=$?
failed_capture_was_rejected=false
[[ "${failed_capture_status}" -eq 73 ]] && failed_capture_was_rejected=true
if [[ "${failed_capture_was_rejected}" == false ]]; then
    printf 'FAIL: failed Sally log capture did not preserve Compose status\n' >&2
    exit 1
fi
prior_evidence_was_preserved=false
grep -qx 'prior-redacted-evidence' "${DIRECT_SALLY_LOG_FILE}" &&
    prior_evidence_was_preserved=true
if [[ "${prior_evidence_was_preserved}" == false ]]; then
    printf 'FAIL: failed Sally capture replaced prior sanitized evidence\n' >&2
    exit 1
fi

printf 'sally-evidence-shell-test: PASS\n'
