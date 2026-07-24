#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)

# shellcheck source=../vlei-workflow.sh
source "${SCRIPT_DIR}/vlei-workflow.sh"

SIG_TSX_MODE=success
sig_tsx() {
    case "${SIG_TSX_MODE}" in
        success)
            printf ' { "ok": true, "credentialSaid": "ECredential" } \n'
            ;;
        malformed)
            printf 'not-json\n'
            ;;
        failure)
            return 47
            ;;
    esac
}

result=$(run_signify_json fixture.ts)
[[ "${result}" == '{"ok":true,"credentialSaid":"ECredential"}' ]]

record_qvi_issuance_result "${result}"
[[ "${LAST_ISSUED_CREDENTIAL_SAID}" == ECredential ]]

SIG_TSX_MODE=failure
failure_status=0
run_signify_json fixture.ts >/dev/null 2>&1 || failure_status=$?
[[ "${failure_status}" -eq 47 ]]

SIG_TSX_MODE=malformed
malformed_status=0
run_signify_json fixture.ts >/dev/null 2>&1 || malformed_status=$?
[[ "${malformed_status}" -ne 0 ]]

printf 'signify-runner-shell-test: PASS\n'
