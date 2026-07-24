#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)

# The driver has a guarded main, so sourcing it exposes only domain functions.
# shellcheck source=../vlei-workflow.sh
source "${SCRIPT_DIR}/vlei-workflow.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-proof-contract-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

QVI_PRE="E-QVI"
QAR1_PRE="E-QAR-1"
QAR2_PRE="E-QAR-2"
QAR3_PRE="E-QAR-3"
PERSON_PRE="E-PERSON"
LEAF_SCHEMA="E-LEAF-SCHEMA"
CREDENTIAL_SAID="E-CREDENTIAL"
ISSUED_TEL_DIGEST="E-ISSUED-TEL"
REVOKED_TEL_DIGEST="E-REVOKED-TEL"
PROOF_RECORDS_FILE="${TEST_ROOT}/proof-records.jsonl"
FAILURE_LOG="${TEST_ROOT}/failures.log"

append_proof_record() {
    local record=$1
    local record_is_valid=false

    printf '%s\n' "${record}" | jq -e 'type == "object"' >/dev/null &&
        record_is_valid=true
    if [[ "${record_is_valid}" == false ]]; then
        return 1
    fi

    printf '%s\n' "${record}" >> "${PROOF_RECORDS_FILE}"
}

fail_workflow() {
    printf '%s\n' "$*" >> "${FAILURE_LOG}"
    exit 1
}

assert_revocation_is_accepted() {
    local description=$1
    local fixture=$2
    local result_was_accepted=false

    qvi_revocation_result_is_exact \
        "${fixture}" \
        "${CREDENTIAL_SAID}" \
        "${QVI_PRE}" \
        "${QAR1_PRE}" \
        "${QAR2_PRE}" \
        "${QAR3_PRE}" \
        "${LEAF_SCHEMA}" \
        "${PERSON_PRE}" &&
        result_was_accepted=true
    if [[ "${result_was_accepted}" == false ]]; then
        printf 'FAIL: accepted revocation fixture was rejected: %s\n' \
            "${description}" >&2
        return 1
    fi
}

assert_revocation_is_rejected() {
    local description=$1
    local fixture=$2
    local result_was_rejected=false

    qvi_revocation_result_is_exact \
        "${fixture}" \
        "${CREDENTIAL_SAID}" \
        "${QVI_PRE}" \
        "${QAR1_PRE}" \
        "${QAR2_PRE}" \
        "${QAR3_PRE}" \
        "${LEAF_SCHEMA}" \
        "${PERSON_PRE}" >/dev/null 2>&1 ||
        result_was_rejected=true
    if [[ "${result_was_rejected}" == false ]]; then
        printf 'FAIL: adversarial revocation fixture was accepted: %s\n' \
            "${description}" >&2
        return 1
    fi
}

proof_record_count() {
    if [[ ! -f "${PROOF_RECORDS_FILE}" ]]; then
        printf '0\n'
        return
    fi

    wc -l < "${PROOF_RECORDS_FILE}" | tr -d '[:space:]'
}

assert_issuance_is_accepted() {
    local description=$1
    local fixture=$2
    local count_before
    local count_after
    local one_record_was_appended=false

    count_before=$(proof_record_count)
    record_qvi_issuance_result \
        "fixture" \
        "${fixture}" \
        "${LEAF_SCHEMA}" \
        "${PERSON_PRE}"
    count_after=$(proof_record_count)

    [[ "${count_after}" -eq $((count_before + 1)) ]] &&
        one_record_was_appended=true
    if [[ "${one_record_was_appended}" == false ]]; then
        printf 'FAIL: valid issuance did not append one proof record: %s\n' \
            "${description}" >&2
        return 1
    fi
}

assert_issuance_is_rejected() {
    local description=$1
    local fixture=$2
    local count_before
    local count_after
    local validation_failed=false
    local invalid_record_was_not_appended=false

    count_before=$(proof_record_count)
    (
        record_qvi_issuance_result \
            "fixture" \
            "${fixture}" \
            "${LEAF_SCHEMA}" \
            "${PERSON_PRE}"
    ) >/dev/null 2>&1 || validation_failed=true
    count_after=$(proof_record_count)

    [[ "${count_after}" -eq "${count_before}" ]] &&
        invalid_record_was_not_appended=true
    if [[ "${validation_failed}" == false ]]; then
        printf 'FAIL: adversarial issuance fixture was accepted: %s\n' \
            "${description}" >&2
        return 1
    fi
    if [[ "${invalid_record_was_not_appended}" == false ]]; then
        printf 'FAIL: rejected issuance appended proof evidence: %s\n' \
            "${description}" >&2
        return 1
    fi
}

build_revoked_fixture() {
    jq -cn \
        --arg said "${CREDENTIAL_SAID}" \
        --arg issuer "${QVI_PRE}" \
        --arg schema "${LEAF_SCHEMA}" \
        --arg issuee "${PERSON_PRE}" \
        --arg qar1 "${QAR1_PRE}" \
        --arg qar2 "${QAR2_PRE}" \
        --arg qar3 "${QAR3_PRE}" \
        --arg issued "${ISSUED_TEL_DIGEST}" \
        --arg revoked "${REVOKED_TEL_DIGEST}" \
        '
          [$qar1, $qar2, $qar3] as $qars |
          def observations($sequence; $prior; $current):
            [$qars[] |
              {
                observerAid: .,
                said: $said,
                issuer: $issuer,
                schema: $schema,
                issuee: $issuee,
                registry: "E-REGISTRY",
                statusSequence: $sequence,
                priorTelDigest: $prior,
                currentTelDigest: $current
              }];
          def fanout($inner):
            [$qars[] as $sender |
             $qars[] |
             select(. != $sender) |
             {
               sender: $sender,
               recipient: .,
               exnSaid: ("E-EXN-" + $sender + "-" + .),
               innerExchangeSaid: $inner
             }];
          def terminal_operations:
            [$qars | to_entries[] |
              {
                name: "group.E-REVOCATION-ANCHOR",
                done: true,
                result: {
                  kind: "event",
                  said: "E-REVOCATION-ANCHOR",
                  prefix: $issuer,
                  sequence: "7"
                }
              }];
          {
            status: "revoked",
            credentialSaid: $said,
            qviPrefix: $issuer,
            revocationTimestamp: "2026-07-23T12:00:00Z",
            revocationTelDigest: $revoked,
            before: observations("0"; null; $issued),
            after: observations("1"; $issued; $revoked),
            operationNames: [
              "group.E-REVOCATION-ANCHOR",
              "group.E-REVOCATION-ANCHOR",
              "group.E-REVOCATION-ANCHOR"
            ],
            operationEvidence: terminal_operations,
            coordinationReceipts: fanout($revoked)
          }
        '
}

build_already_revoked_fixture() {
    build_revoked_fixture |
        jq -c \
            '
              .status = "already-revoked" |
              .before = .after |
              .operationNames = [] |
              .operationEvidence = [] |
              .coordinationReceipts = []
            '
}

build_issuance_fixture() {
    jq -cn \
        --arg said "${CREDENTIAL_SAID}" \
        --arg issuer "${QVI_PRE}" \
        --arg schema "${LEAF_SCHEMA}" \
        --arg issuee "${PERSON_PRE}" \
        --arg qar1 "${QAR1_PRE}" \
        --arg qar2 "${QAR2_PRE}" \
        --arg qar3 "${QAR3_PRE}" \
        --arg issued "${ISSUED_TEL_DIGEST}" \
        '
          [$qar1, $qar2, $qar3] as $qars |
          def fanout($inner; $label):
            [$qars[] as $sender |
             $qars[] |
             select(. != $sender) |
             {
               sender: $sender,
               recipient: .,
               exnSaid: ("E-" + $label + "-" + $sender + "-" + .),
               innerExchangeSaid: $inner
             }];
          def terminal_operations:
            [$qars | to_entries[] |
              {
                name: ("credential." + $said),
                done: true,
                result: {
                  kind: "credential",
                  said: $said,
                  prefix: $issuer,
                  schema: $schema
                }
              }];
          {
            status: "converged",
            credentialSaid: $said,
            observations:
              [$qars[] |
                {
                  observerAid: .,
                  said: $said,
                  issuer: $issuer,
                  schema: $schema,
                  issuee: $issuee,
                  registry: "E-REGISTRY",
                  statusSequence: "0",
                  priorTelDigest: null,
                  currentTelDigest: $issued
                }],
            operationEvidence: terminal_operations,
            issuanceReceipts: fanout($issued; "ISSUE"),
            coordinationReceipts: fanout("E-GRANT"; "GRANT")
          }
        '
}

valid_revocation=$(build_revoked_fixture)
assert_revocation_is_accepted "new revocation convergence" "${valid_revocation}"

already_revoked=$(build_already_revoked_fixture)
assert_revocation_is_accepted "idempotent already-revoked convergence" "${already_revoked}"

divergent_identity=$(printf '%s\n' "${valid_revocation}" |
    jq -c '.before[1].issuer = "E-OTHER-ISSUER"')
assert_revocation_is_rejected "divergent credential identity" "${divergent_identity}"

duplicate_observer=$(printf '%s\n' "${valid_revocation}" |
    jq -c --arg qar2 "${QAR2_PRE}" '.before[2].observerAid = $qar2')
assert_revocation_is_rejected "duplicate observer" "${duplicate_observer}"

missing_observer=$(printf '%s\n' "${valid_revocation}" |
    jq -c 'del(.after[2])')
assert_revocation_is_rejected "missing observer" "${missing_observer}"

wrong_tel_linkage=$(printf '%s\n' "${valid_revocation}" |
    jq -c '.after[1].priorTelDigest = "E-WRONG-TEL"')
assert_revocation_is_rejected "wrong prior TEL linkage" "${wrong_tel_linkage}"

missing_revocation_exn=$(printf '%s\n' "${valid_revocation}" |
    jq -c 'del(.coordinationReceipts[0].exnSaid)')
assert_revocation_is_rejected "missing revocation EXN SAID" "${missing_revocation_exn}"

missing_revocation_inner_said=$(printf '%s\n' "${valid_revocation}" |
    jq -c 'del(.coordinationReceipts[0].innerExchangeSaid)')
assert_revocation_is_rejected \
    "missing revocation embedded event digest" \
    "${missing_revocation_inner_said}"

missing_revocation_operation=$(printf '%s\n' "${valid_revocation}" |
    jq -c 'del(.operationEvidence[2])')
assert_revocation_is_rejected \
    "missing terminal revocation operation" \
    "${missing_revocation_operation}"

pending_revocation_operation=$(printf '%s\n' "${valid_revocation}" |
    jq -c '.operationEvidence[1].done = false')
assert_revocation_is_rejected \
    "pending revocation operation reported as terminal" \
    "${pending_revocation_operation}"

failed_revocation_operation=$(printf '%s\n' "${valid_revocation}" |
    jq -c \
      '.operationEvidence[1] = {
        name: "op-2",
        done: true,
        error: {code: 500, message: "failed"}
      }')
assert_revocation_is_rejected \
    "failed revocation operation reported as complete" \
    "${failed_revocation_operation}"

wrong_revocation_operation_name=$(printf '%s\n' "${valid_revocation}" |
    jq -c '.operationNames[1] = "group.E-WRONG-ANCHOR"')
assert_revocation_is_rejected \
    "wrong member-local revocation operation" \
    "${wrong_revocation_operation_name}"

valid_issuance=$(build_issuance_fixture)
assert_issuance_is_accepted "three-QAR issuance convergence" "${valid_issuance}"

issuance_identity_mismatch=$(printf '%s\n' "${valid_issuance}" |
    jq -c '.observations[1].issuee = "E-OTHER-PERSON"')
assert_issuance_is_rejected \
    "divergent issuance identity" \
    "${issuance_identity_mismatch}"

issuance_receipt_mismatch=$(printf '%s\n' "${valid_issuance}" |
    jq -c '.issuanceReceipts[0].sender = "E-UNAUTHORIZED-SENDER"')
assert_issuance_is_rejected \
    "unauthorized issuance receipt sender" \
    "${issuance_receipt_mismatch}"

missing_issuance_exn=$(printf '%s\n' "${valid_issuance}" |
    jq -c 'del(.issuanceReceipts[0].exnSaid)')
assert_issuance_is_rejected \
    "missing issuance EXN SAID" \
    "${missing_issuance_exn}"

missing_issuance_inner_said=$(printf '%s\n' "${valid_issuance}" |
    jq -c 'del(.issuanceReceipts[0].innerExchangeSaid)')
assert_issuance_is_rejected \
    "missing issuance embedded event digest" \
    "${missing_issuance_inner_said}"

wrong_issuance_operation_name=$(printf '%s\n' "${valid_issuance}" |
    jq -c '.operationEvidence[1].name = "credential.E-WRONG"')
assert_issuance_is_rejected \
    "wrong member-local issuance operation" \
    "${wrong_issuance_operation_name}"

missing_issuance_operation=$(printf '%s\n' "${valid_issuance}" |
    jq -c 'del(.operationEvidence[2])')
assert_issuance_is_rejected \
    "missing terminal issuance operation" \
    "${missing_issuance_operation}"

pending_issuance_operation=$(printf '%s\n' "${valid_issuance}" |
    jq -c '.operationEvidence[1].done = false')
assert_issuance_is_rejected \
    "pending issuance operation reported as terminal" \
    "${pending_issuance_operation}"

failed_issuance_operation=$(printf '%s\n' "${valid_issuance}" |
    jq -c \
      '.operationEvidence[1] = {
        name: "op-2",
        done: true,
        error: {code: 500, message: "failed"}
      }')
assert_issuance_is_rejected \
    "failed issuance operation reported as complete" \
    "${failed_issuance_operation}"

missing_grant_exn=$(printf '%s\n' "${valid_issuance}" |
    jq -c 'del(.coordinationReceipts[0].exnSaid)')
assert_issuance_is_rejected \
    "missing grant EXN SAID" \
    "${missing_grant_exn}"

missing_grant_inner_said=$(printf '%s\n' "${valid_issuance}" |
    jq -c 'del(.coordinationReceipts[0].innerExchangeSaid)')
assert_issuance_is_rejected \
    "missing grant embedded event digest" \
    "${missing_grant_inner_said}"

recorded_proof_is_exact=false
jq -e \
    '
      length == 1 and
      .[0].type == "credential" and
      .[0].event == "issuance" and
      .[0].story == "fixture-issued" and
      .[0].credentialSaid == "E-CREDENTIAL"
    ' \
    --slurp \
    "${PROOF_RECORDS_FILE}" >/dev/null &&
    recorded_proof_is_exact=true
if [[ "${recorded_proof_is_exact}" == false ]]; then
    printf 'FAIL: accepted issuance proof record was not exact\n' >&2
    exit 1
fi

valid_inception_submission=$(jq -cn \
    --arg prefix "${QVI_PRE}" \
    --arg qar1 "${QAR1_PRE}" \
    --arg qar2 "${QAR2_PRE}" \
    --arg qar3 "${QAR3_PRE}" \
    '
      [$qar1, $qar2, $qar3] as $qars |
      {
        status: "inception-submitted",
        msPrefix: $prefix,
        operationNames: [
          ("group." + $prefix),
          ("group." + $prefix),
          ("group." + $prefix)
        ],
        coordinationReceipts:
          [$qars[] as $sender |
           $qars[] |
           select(. != $sender) |
           {
             sender: $sender,
             recipient: .,
             exnSaid: ("E-EXN-" + $sender + "-" + .),
             innerExchangeSaid: $prefix
           }]
      }
    ')
valid_inception_was_accepted=false
qvi_inception_submission_is_exact \
    "${valid_inception_submission}" \
    "${QVI_PRE}" \
    "${QAR1_PRE}" \
    "${QAR2_PRE}" \
    "${QAR3_PRE}" &&
    valid_inception_was_accepted=true
if [[ "${valid_inception_was_accepted}" == false ]]; then
    printf 'FAIL: valid per-agent delegated inception was rejected\n' >&2
    exit 1
fi

wrong_operation_name=$(printf '%s\n' "${valid_inception_submission}" |
    jq -c '.operationNames[1] = "group.E-WRONG-PREFIX"')
wrong_operation_was_rejected=false
qvi_inception_submission_is_exact \
    "${wrong_operation_name}" \
    "${QVI_PRE}" \
    "${QAR1_PRE}" \
    "${QAR2_PRE}" \
    "${QAR3_PRE}" >/dev/null 2>&1 ||
    wrong_operation_was_rejected=true
if [[ "${wrong_operation_was_rejected}" == false ]]; then
    printf 'FAIL: delegated inception accepted a wrong group operation\n' >&2
    exit 1
fi

ENDROLE_ARTIFACT="${TEST_ROOT}/qvi-endrole-artifact.json"
valid_endrole_operations=$(jq -cn \
    --arg prefix "${QVI_PRE}" \
    '
      [
        ("endrole." + $prefix + ".agent.E-AGENT-1"),
        ("endrole." + $prefix + ".agent.E-AGENT-2"),
        ("endrole." + $prefix + ".agent.E-AGENT-3")
      ] as $logicalOperations |
      {
        operationNames:
          ($logicalOperations + $logicalOperations + $logicalOperations)
      }
    ')
printf '%s\n' "${valid_endrole_operations}" > "${ENDROLE_ARTIFACT}"

member_scoped_endroles_were_accepted=false
qvi_endrole_operation_names_are_exact \
    "${ENDROLE_ARTIFACT}" \
    "${QVI_PRE}" \
    E-AGENT-1 \
    E-AGENT-2 \
    E-AGENT-3 &&
    member_scoped_endroles_were_accepted=true
if [[ "${member_scoped_endroles_were_accepted}" == false ]]; then
    printf 'FAIL: valid member-scoped end-role operations were rejected\n' >&2
    exit 1
fi

unbalanced_endrole_operations=$(printf '%s\n' "${valid_endrole_operations}" |
    jq -c '.operationNames[8] = .operationNames[0]')
printf '%s\n' "${unbalanced_endrole_operations}" > "${ENDROLE_ARTIFACT}"
unbalanced_endroles_were_rejected=false
qvi_endrole_operation_names_are_exact \
    "${ENDROLE_ARTIFACT}" \
    "${QVI_PRE}" \
    E-AGENT-1 \
    E-AGENT-2 \
    E-AGENT-3 >/dev/null 2>&1 ||
    unbalanced_endroles_were_rejected=true
if [[ "${unbalanced_endroles_were_rejected}" == false ]]; then
    printf 'FAIL: unbalanced member-scoped end-role operations were accepted\n' >&2
    exit 1
fi

valid_registry_result='{
  "operationNames": [
    "registry.E-REGISTRY",
    "registry.E-REGISTRY",
    "registry.E-REGISTRY"
  ]
}'
member_scoped_registry_was_accepted=false
qvi_registry_operation_names_are_exact \
    "${valid_registry_result}" \
    E-REGISTRY &&
    member_scoped_registry_was_accepted=true
if [[ "${member_scoped_registry_was_accepted}" == false ]]; then
    printf 'FAIL: valid member-scoped registry operations were rejected\n' >&2
    exit 1
fi

wrong_registry_result=$(printf '%s\n' "${valid_registry_result}" |
    jq -c '.operationNames[2] = "registry.E-WRONG"')
wrong_registry_was_rejected=false
qvi_registry_operation_names_are_exact \
    "${wrong_registry_result}" \
    E-REGISTRY >/dev/null 2>&1 ||
    wrong_registry_was_rejected=true
if [[ "${wrong_registry_was_rejected}" == false ]]; then
    printf 'FAIL: wrong member-scoped registry operation was accepted\n' >&2
    exit 1
fi

KLI_CONTACTS_FIXTURE='{"alias":"responder","id":"E-RESPONDER"}
{"alias":"unrelated","id":"E-UNRELATED"}'
kli() {
    printf '%s\n' "${KLI_CONTACTS_FIXTURE}"
}

verify_kli_contact_binding \
    verifier \
    fixture-passcode \
    responder \
    E-RESPONDER

mismatched_contact_was_rejected=false
(
    verify_kli_contact_binding \
        verifier \
        fixture-passcode \
        responder \
        E-WRONG-PREFIX
) >/dev/null 2>&1 ||
    mismatched_contact_was_rejected=true
if [[ "${mismatched_contact_was_rejected}" == false ]]; then
    printf 'FAIL: KLI contact verification accepted the wrong prefix\n' >&2
    exit 1
fi

printf 'qvi-proof-contract-test: PASS\n'
