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
        create_geda_multisig() {
            GEDA_PRE=E-GEDA
            export GEDA_PRE
            order+=" geda"
        }
        create_geda_reg() { order+=" registry"; }
        start_sally() {
            [[ -n "${GEDA_PRE:-}" ]] || return 1
            order+=" sally"
        }
        resolve_oobis() { order+=" resolve"; }
        challenge_response() { return 0; }
        qars_resolve_geda_oobi() { return 0; }
        establish_qvi() { order+=" qvi"; }

        geda_delegation_to_qvi
        [[ "${order}" == " geda registry sally resolve qvi" ]]
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
printf 'workflow contract passed\n'
