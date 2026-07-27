#!/usr/bin/env bash

SCRIPT_DIR="${WORKFLOW_ROOT_DIR}/keria_kli"
WORKFLOW_ENV_FILE="${SCRIPT_DIR}/local-workflow.env"

set -a
# shellcheck source=../keria_kli/local-workflow.env
source "${WORKFLOW_ENV_FILE}"
set +a
# shellcheck source=../keria_kli/color-printing.sh
source "${SCRIPT_DIR}/color-printing.sh"
# shellcheck source=../keria_kli/lib/workflow-runtime.sh
source "${SCRIPT_DIR}/lib/workflow-runtime.sh"

QVI_SIGNIFY_DIR="${WORKFLOW_ROOT_DIR}/sig_ts_wallets/src"
QVI_DATA_DIR="${SCRIPT_DIR}/runtime/qvi_data"
QVI_PARTICIPANT_CONFIG="${SCRIPT_DIR}/runtime/config/participants.json"
WIT_HOST_GAR=http://127.0.0.1:5642
WIT_HOST_QAR=http://127.0.0.1:5643
CONT_CONFIG_DIR="${SCRIPT_DIR}/runtime/config"
KLI_COMMAND_CONFIG_DIR="${SCRIPT_DIR}/runtime/config"
KLI_COMMAND_DATA_DIR="${SCRIPT_DIR}/runtime/acdc-info"

backend_required_commands() {
    printf '%s\n' jq curl awk sed wc lsof nohup pgrep
}

backend_prepare() {
    local dependency

    for dependency in \
        "${GEDA_KLI_PYTHON}" \
        "${KLI_PYTHON}" \
        "${KLI_LAUNCHER}" \
        "${KERIA_PYTHON}" \
        "${KERIA_LAUNCHER}" \
        "${WITNESS_PYTHON}" \
        "${SALLY_PYTHON}" \
        "${SALLY_LAUNCHER}" \
        "${VLEI_BIN}" \
        "${TSX_BIN}" \
        "${SIGNAL_RESET_LAUNCHER}"; do
        if [[ ! -x "${dependency}" ]]; then
            printf 'Missing local dependency: %s\n' "${dependency}" >&2
            printf 'Run %s/bootstrap-local.sh first\n' "${SCRIPT_DIR}" >&2
            return 1
        fi
    done
}

backend_start_foundation() {
    start_local_foundation_services
}

backend_start_sally() {
    start_local_sally "$1"
}

backend_preflight_versions() {
    start_job preflight-signify preflight_signify_versions || return 1
    start_job preflight-keria preflight_keria_versions || return 1
    start_job preflight-witnesses \
        preflight_local_keripy "${WITNESS_PYTHON}" witnesses || return 1
    start_job preflight-geda-kli \
        preflight_python_package "${GEDA_KLI_PYTHON}" keri 1.1.42 ||
        return 1
    start_job preflight-kli \
        preflight_local_keripy "${KLI_PYTHON}" kli || return 1
    wait_jobs \
        preflight-signify preflight-keria preflight-witnesses \
        preflight-geda-kli preflight-kli
}

backend_supports_parallel_foundation_reads() {
    return 0
}

backend_sally_logs() {
    tail -n 500 "${SALLY_LOG_FILE}"
}
