#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-sally-bootstrap-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

# shellcheck source=../vlei-workflow.sh
source "${SCRIPT_DIR}/vlei-workflow.sh"

VALID_SALLY_PREFIX=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
SALLY_OOBI_FIXTURE=valid

workflow_compose() {
    case "${SALLY_OOBI_FIXTURE}" in
        valid)
            printf 'HTTP/1.1 200 OK\r\n'
            printf 'KERI-AID: %s\r\n\r\n' "${VALID_SALLY_PREFIX}"
            ;;
        missing-header)
            printf 'HTTP/1.1 200 OK\r\n\r\n'
            ;;
        request-failure)
            return 7
            ;;
    esac
}

observed_prefix=$(sally_oobi_prefix_is_ready \
    direct-sally \
    http://127.0.0.1:9823/oobi)
[[ "${observed_prefix}" == "${VALID_SALLY_PREFIX}" ]]

SALLY_OOBI_FIXTURE=missing-header
missing_header_status=0
sally_oobi_prefix_is_ready \
    direct-sally \
    http://127.0.0.1:9823/oobi >/dev/null 2>&1 ||
    missing_header_status=$?
[[ "${missing_header_status}" -ne 0 ]]

SALLY_OOBI_FIXTURE=request-failure
request_status=0
sally_oobi_prefix_is_ready \
    direct-sally \
    http://127.0.0.1:9823/oobi >/dev/null 2>&1 ||
    request_status=$?
[[ "${request_status}" -eq 7 ]]

FAKE_BIN="${TEST_ROOT}/bin"
SALLY_ARGUMENTS="${TEST_ROOT}/sally-arguments"
mkdir -p "${FAKE_BIN}"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$@" > "${SALLY_ARGUMENTS:?}"' \
    > "${FAKE_BIN}/sally"
chmod +x "${FAKE_BIN}/sally"

PATH="${FAKE_BIN}:${PATH}" \
SALLY_ARGUMENTS="${SALLY_ARGUMENTS}" \
SALLY_KS_NAME=fixture-sally \
SALLY_ALIAS=fixture-sally \
SALLY_SALT=0AA-fixture-sally-salt \
SALLY_PASSCODE=fixture-sally-passcode \
WEBHOOK_HOST=http://callback-recorder:9923 \
GEDA_PRE=E-fixture-geda \
    bash "${SCRIPT_DIR}/direct-sally/entry-point.sh"

grep -qx 'server' "${SALLY_ARGUMENTS}"
grep -qx 'start' "${SALLY_ARGUMENTS}"
grep -qx '0AA-fixture-sally-salt' "${SALLY_ARGUMENTS}"
grep -qx 'fixture-sally-passcode' "${SALLY_ARGUMENTS}"
grep -qx 'sally-incept-no-wits.json' "${SALLY_ARGUMENTS}"
grep -qx 'http://callback-recorder:9923' "${SALLY_ARGUMENTS}"

printf 'sally-bootstrap-shell-test: PASS\n'
