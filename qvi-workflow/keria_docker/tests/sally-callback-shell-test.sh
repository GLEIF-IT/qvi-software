#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)

# shellcheck source=../vlei-workflow.sh
source "${SCRIPT_DIR}/vlei-workflow.sh"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-callback-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

SALLY_CALLBACK_FILE="${TEST_ROOT}/sally-callbacks.jsonl"
printf '%s\n' \
    '{"receivedAt":"2026-07-24T12:00:00Z","action":"iss","data":{"credential":"EActive"}}' \
    '{"receivedAt":"2026-07-24T12:01:00Z","action":"rev","data":{"credential":"ERevoked"}}' \
    > "${SALLY_CALLBACK_FILE}"

active_callback=$(callback_was_recorded iss EActive)
[[ "${active_callback}" == *'"credential":"EActive"'* ]]

wrong_said_status=0
callback_was_recorded iss EWrong >/dev/null 2>&1 ||
    wrong_said_status=$?
[[ "${wrong_said_status}" -ne 0 ]]

workflow_compose() {
    [[ "${1:-}" == logs ]] || return 1
    printf '%s\n' \
        '2026-07-24T12:01:01Z revoked credential ERevoked being presented'
}

revoked_oor_was_rejected_and_reported \
    2026-07-24T12:00:30Z \
    ERevoked >/dev/null

missing_rejection_status=0
revoked_oor_was_rejected_and_reported \
    2026-07-24T12:00:30Z \
    EWrong >/dev/null ||
    missing_rejection_status=$?
[[ "${missing_rejection_status}" -ne 0 ]]

printf 'sally-callback-shell-test: PASS\n'
