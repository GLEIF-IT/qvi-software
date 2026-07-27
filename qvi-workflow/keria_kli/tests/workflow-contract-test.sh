#!/usr/bin/env bash

# Contract tests for the canonical local workflow's visible protocol ordering.

set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORKFLOW_DIR=$(cd "${TEST_DIR}/.." && pwd -P)

# shellcheck source=../vlei-workflow.sh
source "${WORKFLOW_DIR}/vlei-workflow.sh"
# shellcheck source=../kli-commands.sh
source "${WORKFLOW_DIR}/kli-commands.sh"

# Fail immediately with one readable assertion message.
fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Keep the two GEDA observers independent while they refresh QVI key state.
test_delegation_queries_are_actor_disjoint() {
    local approval_source

    approval_source=$(declare -f approve_qvi_delegation)
    [[ "${approval_source}" == *"query-qvi-for-gar1 gar1"* &&
       "${approval_source}" == *"query-qvi-for-gar2 gar2"* ]] ||
        fail_test 'GEDA participant queries do not use independent GAR lanes'
    [[ "${approval_source}" == *"wait_for_background_jobs query-qvi-for-gar1 query-qvi-for-gar2"* ]] ||
        fail_test 'GEDA participant query lanes do not share one deadline'
}

# Require every directed exchange in the canonical challenge matrix.
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

# Require the leaf pipeline to overlap only state and exchange lanes.
test_leaf_pipeline_state_exchange_waves() {
    local jobs=""
    local waves=""

    prepare_oor_auth_data() { return 0; }
    prepare_ecr_auth_data() { return 0; }
    create_oor_auth_credential() { return 0; }
    grant_oor_auth_credential() { return 0; }
    create_ecr_auth_credential() { return 0; }
    load_oor_auth_credential_said() { OOR_AUTH_SAID=E-OOR-AUTH; }
    load_ecr_auth_credential_said() { ECR_AUTH_SAID=E-ECR-AUTH; }
    prepare_oor_auth_edge() { return 0; }
    prepare_ecr_auth_edge() { return 0; }
    prepare_oor_cred_data() { return 0; }
    prepare_ecr_cred_data() { return 0; }
    load_qvi_issuance_result() {
        case "$1" in
            oor) OOR_CRED_SAID=E-OOR ;;
            ecr) ECR_CRED_SAID=E-ECR ;;
            *) return 1 ;;
        esac
    }
    pause() { return 0; }
    start_workflow_job() {
        jobs+="$1:$2:$3"$'\n'
    }
    wait_for_background_jobs() {
        waves+="$*"$'\n'
    }

    optimized_leaf_credential_pipeline ||
        fail_test 'optimized leaf pipeline did not construct its job waves'

    local expected_jobs=$(
        cat <<'EOF'
admit-oor-auth:qvi-exchange:admit_oor_auth_credential
grant-ecr-auth:le-exchange:grant_ecr_auth_credential
issue-oor:qvi-state:create_oor_credential
admit-ecr-auth:qvi-exchange:admit_ecr_auth_credential
grant-oor:qvi-exchange:grant_oor_credential
issue-ecr:qvi-state:create_ecr_credential
admit-present-active-oor:person,sally:admit_and_present_active_oor
grant-ecr:qvi-exchange:grant_ecr_credential
admit-ecr:person:admit_ecr_credential
revoke-oor:qvi-state:revoke_oor_credential
present-revoked-oor:qvi-exchange,person,sally:present_revoked_oor_to_sally
revoke-ecr:qvi-state:revoke_ecr_credential
EOF
    )
    [[ "${jobs%$'\n'}" == "${expected_jobs}" ]] ||
        fail_test 'leaf jobs do not preserve the state/exchange lane boundary'

    local expected_waves=$(
        cat <<'EOF'
admit-oor-auth grant-ecr-auth
issue-oor admit-ecr-auth
grant-oor issue-ecr
admit-present-active-oor grant-ecr
admit-ecr revoke-oor
present-revoked-oor revoke-ecr
EOF
    )
    [[ "${waves%$'\n'}" == "${expected_waves}" ]] ||
        fail_test 'leaf state/exchange jobs do not share the intended deadlines'
}

# Ensure a failed intermediate rotation prevents credential issuance.
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
        refresh_geda_for_qvi_members() { return 0; }
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

# Require every presentation mode to use the same QVI lifecycle.
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
        fail_test 'not all four keria_kli modes used establish_qvi'
    rm -f "${marker}"
}

# Require Sally to start only after the GEDA exists and never as a bootstrap.
test_sally_startup_contract() {
    local foundation_arguments=""
    local order=""

    start_local_foundation_services() {
        foundation_arguments+=" called"
    }
    start_foundation_services
    [[ "${foundation_arguments}" == " called" ]] ||
        fail_test 'foundation startup did not use the local service manager'

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

# Keep the legacy GEDA CLI isolated from every v1.2.x wallet.
test_kli_runtime_selection() {
    local original_gar1=${GAR1}
    local original_gar2=${GAR2}

    GEDA_KLI_PYTHON=/runtime/geda-kli/python
    KLI_PYTHON=/runtime/kli/python
    GAR1=gar-one
    GAR2=gar-two

    [[ "$(kli_python_for_wallet "${GAR1}")" == "${GEDA_KLI_PYTHON}" ]] ||
        fail_test 'GAR1 did not select the GEDA KLI runtime'
    [[ "$(kli_python_for_wallet "${GAR2}")" == "${GEDA_KLI_PYTHON}" ]] ||
        fail_test 'GAR2 did not select the GEDA KLI runtime'
    [[ "$(kli_python_for_wallet lar-one)" == "${KLI_PYTHON}" ]] ||
        fail_test 'a non-GEDA wallet selected the legacy KLI runtime'

    GAR1=${original_gar1}
    GAR2=${original_gar2}
}

test_rotation_failure_reaches_main_flow
test_every_mode_uses_shared_qvi_lifecycle
test_sally_startup_contract
test_challenge_matrix_contract
test_leaf_pipeline_state_exchange_waves
test_delegation_queries_are_actor_disjoint
test_kli_runtime_selection
printf 'workflow contract passed\n'
