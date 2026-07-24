#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)

# The driver has a guarded main, so sourcing it exposes its JSON boundaries.
# shellcheck source=../vlei-workflow.sh
source "${SCRIPT_DIR}/vlei-workflow.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-proof-boundary-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

SIG_TSX_MODE=success
sig_tsx() {
    case "${SIG_TSX_MODE}" in
        success)
            printf ' { "ok": true, "status": "complete", "value": "EValue" } \n'
            ;;
        malformed)
            printf 'not-json\n'
            ;;
        failure)
            return 47
            ;;
    esac
}

normalized_result=$(run_signify_json fixture.ts)
[[ "${normalized_result}" == \
    '{"ok":true,"status":"complete","value":"EValue"}' ]]

SIG_TSX_MODE=failure
producer_status=0
run_signify_json fixture.ts >/dev/null 2>&1 ||
    producer_status=$?
[[ "${producer_status}" -eq 47 ]]

SIG_TSX_MODE=malformed
malformed_status=0
run_signify_json fixture.ts >/dev/null 2>&1 ||
    malformed_status=$?
[[ "${malformed_status}" -ne 0 ]]

workflow_compose() {
    return 53
}

adapter_status=0
run_workflow_contract contact-binding \
    --alias QAR1 \
    --expected-prefix EQar1 >/dev/null 2>&1 ||
    adapter_status=$?
[[ "${adapter_status}" -eq 53 ]]

PROOF_RECORDS_FILE="${TEST_ROOT}/proof.jsonl"
append_proof_record() {
    printf '%s\n' "$1" >> "${PROOF_RECORDS_FILE}"
}

issuance_result=$(
    jq -cn '{
        ok: true,
        status: "converged",
        observations: [{said: "ECredential"}]
    }'
)
record_qvi_issuance_result OOR "${issuance_result}"
[[ "${LAST_ISSUED_CREDENTIAL_SAID}" == ECredential ]]

proof_shape=$(
    jq -r \
        '[.type, .event, .story, .observations[0].said] |
         @tsv' \
        "${PROOF_RECORDS_FILE}"
)
[[ "${proof_shape}" == \
    $'credential\tissuance\tOOR-issued\tECredential' ]]

WORKFLOW_CONFIG_DIR="${TEST_ROOT}/config"
mkdir -p "${WORKFLOW_CONFIG_DIR}"
printf '%s\n' \
    '{"aids":[],"wits":[],"isith":"2","nsith":"2"}' \
    > "${WORKFLOW_CONFIG_DIR}/template-multi-sig-incept-config.jq"
create_multisig_icp_config EAid1 EAid2 EWitness >/dev/null
multisig_config_shape=$(
    jq -c \
        '{aids, wits, isith, nsith}' \
        "${WORKFLOW_CONFIG_DIR}/multi-sig-incept-config.json"
)
[[ "${multisig_config_shape}" == \
    '{"aids":["EAid1","EAid2"],"wits":["EWitness"],"isith":"2","nsith":"2"}' ]]

CHALLENGE_DIGEST=$(
    printf '%064d' 0 |
        tr '0' 'a'
)
record_challenge_receipt \
    GAR1-QAR1 \
    'gar1->qar1' \
    EGar1 \
    EQar1 \
    keria \
    EResponse
challenge_proof_shape=$(
    tail -1 "${PROOF_RECORDS_FILE}" |
        jq -c \
            '{
                type,
                relationship,
                direction,
                verifierType,
                responseExnSaid,
                challengeDigest
            }'
)
[[ "${challenge_proof_shape}" == \
    '{"type":"challenge","relationship":"GAR1-QAR1","direction":"gar1->qar1","verifierType":"keria","responseExnSaid":"EResponse","challengeDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' ]]

printf 'qvi-proof-contract-test: PASS\n'
