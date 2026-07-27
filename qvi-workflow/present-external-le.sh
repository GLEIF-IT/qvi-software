#!/usr/bin/env bash
# Present an LE credential from one kept canonical workflow run.

set -Eeuo pipefail

WORKFLOW_ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORKFLOW_BACKEND=local
WORKFLOW_TIMEOUT_SECONDS=120
ARTIFACT_DIR=""
EXTERNAL_ALIAS=""
EXTERNAL_OOBI=""

usage() {
    printf 'Usage: %s --artifacts DIR --alias ALIAS --oobi OOBI [options]\n' \
        "${0##*/}"
    printf '%s\n' \
        "Options:" \
        "      --backend NAME    local (default) or docker" \
        "      --timeout SECONDS Shared command deadline" \
        "  -h, --help            Display this help message"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --artifacts)
                [[ $# -ge 2 && -n "${2:-}" ]] || return 2
                ARTIFACT_DIR=$2
                shift 2
                ;;
            --alias)
                [[ $# -ge 2 && -n "${2:-}" ]] || return 2
                EXTERNAL_ALIAS=$2
                shift 2
                ;;
            --oobi)
                [[ $# -ge 2 && -n "${2:-}" ]] || return 2
                EXTERNAL_OOBI=$2
                shift 2
                ;;
            --backend)
                [[ $# -ge 2 && ("$2" == local || "$2" == docker) ]] ||
                    return 2
                WORKFLOW_BACKEND=$2
                shift 2
                ;;
            --timeout)
                [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || return 2
                WORKFLOW_TIMEOUT_SECONDS=$2
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown option: %s\n' "$1" >&2
                return 2
                ;;
        esac
    done
    [[ -n "${ARTIFACT_DIR}" &&
       -n "${EXTERNAL_ALIAS}" &&
       -n "${EXTERNAL_OOBI}" ]]
}

fail() {
    printf 'External LE presentation: %s\n' "$*" >&2
    exit 1
}

parse_arguments "$@" || {
    usage >&2
    exit 2
}

# shellcheck source=./backends/local.sh
# shellcheck source=./backends/docker.sh
source "${WORKFLOW_ROOT_DIR}/backends/${WORKFLOW_BACKEND}.sh"
# shellcheck source=./lib/jobs.sh
source "${WORKFLOW_ROOT_DIR}/lib/jobs.sh"

[[ -d "${ARTIFACT_DIR}" ]] ||
    fail "artifact directory does not exist: ${ARTIFACT_DIR}"
ARTIFACT_DIR=$(cd "${ARTIFACT_DIR}" && pwd -P)
[[ -f "${ARTIFACT_DIR}/backend.json" &&
   -f "${ARTIFACT_DIR}/config/participants.json" &&
   -f "${ARTIFACT_DIR}/le-issuance.json" ]] ||
    fail "directory is not a kept completed workflow artifact"
[[ "$(jq -r '.backend' "${ARTIFACT_DIR}/backend.json")" == "${WORKFLOW_BACKEND}" ]] ||
    fail "artifact backend does not match --backend ${WORKFLOW_BACKEND}"
jq -e '.qvi.finalMembers == ["qar1", "qar2", "qar3"]' \
    "${ARTIFACT_DIR}/config/participants.json" >/dev/null ||
    fail "artifact is not from the canonical same-roster workflow"

WORKFLOW_RUN_DIR=${ARTIFACT_DIR}
WORKFLOW_CONFIG_DIR="${ARTIFACT_DIR}/config"
KLI_DATA_DIR="${ARTIFACT_DIR}/acdc-info"
WORKFLOW_LOG_DIR="${ARTIFACT_DIR}/logs/external-presentation"
WORKFLOW_PID_DIR="${ARTIFACT_DIR}/pids"
KERI_HEAD_DIR="${ARTIFACT_DIR}/state"
KLI_HEAD_DIR=${KERI_HEAD_DIR}
KLI_BASE=kli
mkdir -p "${WORKFLOW_LOG_DIR}" "${WORKFLOW_PID_DIR}"
export WORKFLOW_RUN_DIR WORKFLOW_CONFIG_DIR KLI_DATA_DIR WORKFLOW_LOG_DIR
export WORKFLOW_PID_DIR KERI_HEAD_DIR KLI_HEAD_DIR KLI_BASE

# shellcheck source=./keria_kli/kli-commands.sh
# shellcheck source=./keria_docker/kli-commands.sh
source "${SCRIPT_DIR}/kli-commands.sh"

cleanup_external_services() {
    local original_status=$?
    trap - EXIT INT TERM HUP
    cancel_jobs
    if [[ "${WORKFLOW_BACKEND}" == local ]]; then
        stop_all_managed_processes TERM || true
    else
        workflow_compose stop kli witnesses vlei-server >/dev/null 2>&1 || true
    fi
    exit "${original_status}"
}

trap cleanup_external_services EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [[ "${WORKFLOW_BACKEND}" == local ]]; then
    [[ -d "${KERI_HEAD_DIR}" ]] ||
        fail "local KLI state is missing from the artifact directory"
    for port in 5642 5643 5644; do
        [[ -z "$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null || true)" ]] ||
            fail "required local witness port ${port} is already in use"
    done
    start_managed_process \
        witnesses \
        env \
        "${LOCAL_KERI_TOCK_ENV[@]}" \
        PYTHONUNBUFFERED=1 \
        PYTHONWARNINGS=ignore::SyntaxWarning \
        "${WITNESS_PYTHON}" \
        "${SCRIPT_DIR}/local-witnesses.py" \
        --head-dir "${KERI_HEAD_DIR}" \
        --base witnesses \
        --config-dir "${WORKFLOW_CONFIG_DIR}/witnesses"
    wait_for_managed_process witnesses http://127.0.0.1:5642/oobi >/dev/null
    wait_for_managed_process witnesses http://127.0.0.1:5643/oobi >/dev/null
    wait_for_managed_process witnesses http://127.0.0.1:5644/oobi >/dev/null
else
    [[ "${ARTIFACT_DIR}" == "${SCRIPT_DIR}/runtime" ]] ||
        fail "Docker artifacts must remain at ${SCRIPT_DIR}/runtime"
    state_volume=$(jq -r '.stateVolume' "${ARTIFACT_DIR}/backend.json")
    docker volume inspect "${state_volume}" >/dev/null 2>&1 ||
        fail "kept Docker KLI state volume is missing: ${state_volume}"
    workflow_compose up \
        --detach \
        --wait \
        --wait-timeout "${WORKFLOW_TIMEOUT_SECONDS}" \
        vlei-server witnesses kli
fi

LE_CRED_SAID=$(jq -r '.credentialSaid' "${ARTIFACT_DIR}/le-issuance.json")
[[ -n "${LE_CRED_SAID}" && "${LE_CRED_SAID}" != null ]] ||
    fail "LE issuance artifact has no credential SAID"

kli oobi resolve \
    --name "${LAR1}" \
    --passcode "${LAR1_PASSCODE}" \
    --oobi-alias "${EXTERNAL_ALIAS}" \
    --oobi "${EXTERNAL_OOBI}"
kli oobi resolve \
    --name "${LAR2}" \
    --passcode "${LAR2_PASSCODE}" \
    --oobi-alias "${EXTERNAL_ALIAS}" \
    --oobi "${EXTERNAL_OOBI}"

grant_time=$(kli time | tr -d '[:space:]')
klid external-lar1 ipex grant \
    --name "${LAR1}" \
    --alias "${LE_NAME}" \
    --passcode "${LAR1_PASSCODE}" \
    --said "${LE_CRED_SAID}" \
    --recipient "${EXTERNAL_ALIAS}" \
    --time "${grant_time}"
klid external-lar2 ipex join \
    --name "${LAR2}" \
    --passcode "${LAR2_PASSCODE}" \
    --auto
wait_kli_jobs external-lar1 external-lar2

printf 'Presented LE credential %s to %s\n' \
    "${LE_CRED_SAID}" "${EXTERNAL_ALIAS}"
