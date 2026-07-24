#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qvi-sally-bootstrap-test.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

# The driver has a guarded main, so sourcing it exposes the OOBI predicate
# without starting Docker.
# shellcheck source=../vlei-workflow.sh
source "${SCRIPT_DIR}/vlei-workflow.sh"

QVI_RUNTIME_PARENT="${TEST_ROOT}/runtimes"
QVI_PROOF_ROOT="${TEST_ROOT}/proofs"
create_workflow_runtime
initial_runtime="${WORKFLOW_RUN_DIR}"
prepare_compose_lifecycle >/dev/null

initial_compose_environment_is_complete=false
initial_participant_configuration_is_valid=false
compose_cleanup_was_armed=false
temporary_configuration_was_retained=false

grep -q "^WORKFLOW_CONFIG_DIR=${WORKFLOW_CONFIG_DIR}$" "${COMPOSE_ENV_FILE}" &&
    grep -q '^DIRECT_SALLY_SALT=$' "${COMPOSE_ENV_FILE}" &&
    initial_compose_environment_is_complete=true
jq -e '
    .environment == "docker-tsx" and
    ([.participants[].salt] | all(. == ""))
' "${PARTICIPANT_CONFIG_FILE}" >/dev/null &&
    initial_participant_configuration_is_valid=true
[[ "${WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST}" == true ]] &&
    compose_cleanup_was_armed=true
[[ -e "${COMPOSE_ENV_FILE}.tmp" ||
   -e "${PARTICIPANT_CONFIG_FILE}.tmp" ]] &&
    temporary_configuration_was_retained=true

if [[ "${initial_compose_environment_is_complete}" == false ||
      "${initial_participant_configuration_is_valid}" == false ||
      "${compose_cleanup_was_armed}" == false ||
      "${temporary_configuration_was_retained}" == true ]]; then
    printf 'FAIL: pre-salt runtime configuration is not interruption-safe\n' >&2
    exit 1
fi
remove_owned_runtime "${initial_runtime}"

writable_witness_mount_count=$(grep -Ec \
    '/witnesses-(gar|qar|person):/keripy/scripts/keri/cf/main$' \
    "${SCRIPT_DIR}/docker-compose-keria_signify_qvi.yaml")
writable_keria_mount_count=$(grep -Ec \
    '/keria/keria[123]\.json:/keria/config/keri/cf/keria\.json$' \
    "${SCRIPT_DIR}/docker-compose-keria_signify_qvi.yaml")
writable_sally_config_mount_count=$(grep -Ec \
    '/direct-sally/keri/cf/direct-sally\.json:/sally/conf/keri/cf/direct-sally\.json$' \
    "${SCRIPT_DIR}/docker-compose-keria_signify_qvi.yaml")
writable_kli_config_mount_count=$(grep -Ec \
    'WORKFLOW_CONFIG_DIR[^}]*}:/config$' \
    "${SCRIPT_DIR}/docker-compose-keria_signify_qvi.yaml")
witness_mounts_are_writable=false
keri_config_mounts_are_writable=false
[[ "${writable_witness_mount_count}" -eq 3 ]] &&
    witness_mounts_are_writable=true
[[ "${writable_keria_mount_count}" -eq 3 &&
   "${writable_sally_config_mount_count}" -eq 1 &&
   "${writable_kli_config_mount_count}" -eq 2 ]] &&
    keri_config_mounts_are_writable=true
if [[ "${witness_mounts_are_writable}" == false ||
      "${keri_config_mounts_are_writable}" == false ]]; then
    printf 'FAIL: KERI configs must use their writable runtime copies\n' >&2
    exit 1
fi

VALID_SALLY_PREFIX=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
SALLY_OOBI_FIXTURE=valid

workflow_compose() {
    case "${SALLY_OOBI_FIXTURE}" in
        valid)
            printf 'HTTP/1.1 200 OK\r\n'
            printf 'Content-Type: application/json+cesr\r\n'
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
valid_header_was_accepted=false
[[ "${observed_prefix}" == "${VALID_SALLY_PREFIX}" ]] &&
    valid_header_was_accepted=true
if [[ "${valid_header_was_accepted}" == false ]]; then
    printf 'FAIL: valid Sally KERI-AID header was not accepted\n' >&2
    exit 1
fi

SALLY_OOBI_FIXTURE=missing-header
missing_header_was_rejected=false
sally_oobi_prefix_is_ready \
    direct-sally \
    http://127.0.0.1:9823/oobi >/dev/null 2>&1 ||
    missing_header_was_rejected=true
if [[ "${missing_header_was_rejected}" == false ]]; then
    printf 'FAIL: missing Sally KERI-AID header was accepted\n' >&2
    exit 1
fi

SALLY_OOBI_FIXTURE=request-failure
request_failure_status=0
sally_oobi_prefix_is_ready \
    direct-sally \
    http://127.0.0.1:9823/oobi >/dev/null 2>&1 ||
    request_failure_status=$?
request_failure_was_preserved=false
[[ "${request_failure_status}" -eq 7 ]] &&
    request_failure_was_preserved=true
if [[ "${request_failure_was_preserved}" == false ]]; then
    printf 'FAIL: Sally OOBI request failure status was not preserved\n' >&2
    exit 1
fi

FAKE_BIN="${TEST_ROOT}/bin"
SALLY_ARGUMENTS="${TEST_ROOT}/sally-arguments"
ENTRYPOINT_OUTPUT="${TEST_ROOT}/entrypoint-output"
mkdir -p "${FAKE_BIN}"

# Expansion belongs to the generated fake executable.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$@" > "${SALLY_ARGUMENTS:?}"' \
    > "${FAKE_BIN}/sally"
chmod 700 "${FAKE_BIN}/sally"

PATH="${FAKE_BIN}:${PATH}" \
SALLY_ARGUMENTS="${SALLY_ARGUMENTS}" \
SALLY_KS_NAME=fixture-sally \
SALLY_ALIAS=fixture-sally \
SALLY_SALT=0AA-fixture-sally-salt \
SALLY_PASSCODE=fixture-sally-passcode \
WEBHOOK_HOST=http://hook:9923 \
GEDA_PRE=E-fixture-geda \
    bash "${SCRIPT_DIR}/direct-sally/entry-point.sh" \
    > "${ENTRYPOINT_OUTPUT}" 2>&1

native_server_start_was_used=false
salt_was_forwarded=false
inception_file_was_forwarded=false
entrypoint_was_quiet=false

grep -qx 'server' "${SALLY_ARGUMENTS}" &&
    grep -qx 'start' "${SALLY_ARGUMENTS}" &&
    native_server_start_was_used=true
grep -qx '0AA-fixture-sally-salt' "${SALLY_ARGUMENTS}" &&
    salt_was_forwarded=true
grep -qx 'sally-incept-no-wits.json' "${SALLY_ARGUMENTS}" &&
    inception_file_was_forwarded=true
[[ ! -s "${ENTRYPOINT_OUTPUT}" ]] &&
    entrypoint_was_quiet=true

if [[ "${native_server_start_was_used}" == false ||
      "${salt_was_forwarded}" == false ||
      "${inception_file_was_forwarded}" == false ||
      "${entrypoint_was_quiet}" == false ]]; then
    printf 'FAIL: direct Sally did not use the quiet native bootstrap contract\n' >&2
    exit 1
fi

printf 'sally-bootstrap-shell-test: PASS\n'
