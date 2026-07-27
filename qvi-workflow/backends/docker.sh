#!/usr/bin/env bash

SCRIPT_DIR="${WORKFLOW_ROOT_DIR}/keria_docker"
DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-keria_signify_qvi.yaml"
WORKFLOW_ENV_FILE="${SCRIPT_DIR}/keria-signify-docker.env"

set -a
# shellcheck source=../keria_docker/keria-signify-docker.env
source "${WORKFLOW_ENV_FILE}"
set +a
# shellcheck source=../keria_docker/color-printing.sh
source "${SCRIPT_DIR}/color-printing.sh"
# shellcheck source=../keria_docker/lib/workflow-runtime.sh
source "${SCRIPT_DIR}/lib/workflow-runtime.sh"

QVI_SIGNIFY_DIR=/vlei-workflow/src
QVI_DATA_DIR=/vlei-workflow/qvi_data
QVI_PARTICIPANT_CONFIG=/vlei-workflow/participants.json
WIT_HOST_GAR=http://witnesses:5642
WIT_HOST_QAR=http://witnesses:5643
CONT_CONFIG_DIR=/config
KLI_COMMAND_CONFIG_DIR=/config
KLI_COMMAND_DATA_DIR=/acdc-info

sig_wallet_request() {
    sig_tsx "${QVI_SIGNIFY_DIR}/sig-wallet.ts" "$@"
}

backend_required_commands() {
    printf '%s\n' docker jq curl awk sed wc pgrep
}

backend_prepare() {
    workflow_compose build signify callback-recorder
}

backend_start_foundation() {
    local -a services=(
        vlei-server callback-recorder witnesses
        keria1 keria2 keria3 kli signify
    )
    if [[ "${WORKFLOW_SCENARIO}" == qar-replacement-regression ]]; then
        services+=(keria4)
    fi
    workflow_compose up \
        --detach \
        --wait \
        --wait-timeout "${WORKFLOW_TIMEOUT_SECONDS}" \
        "${services[@]}"
}

backend_start_sally() {
    [[ -n "$1" ]] || return 1
    workflow_compose up \
        --detach \
        --wait \
        --wait-timeout "${WORKFLOW_TIMEOUT_SECONDS}" \
        sally
}

backend_supports_parallel_foundation_reads() {
    return 1
}

docker_python_package() {
    local service_name=$1
    local package_name=$2
    local expected_version=$3
    local check='from importlib.metadata import version; import sys; actual=version(sys.argv[1]); expected=sys.argv[2]; print(f"{sys.argv[1]}={actual}"); raise SystemExit(0 if actual == expected else 1)'

    workflow_compose exec -T "${service_name}" \
        python -c "${check}" "${package_name}" "${expected_version}"
}

docker_keria_versions() {
    workflow_compose exec -T keria1 python -c \
        'from importlib.metadata import version; import sys; expected={"keria":"0.4.0","keri":"1.2.12"}; actual={name:version(name) for name in expected}; print(actual); raise SystemExit(0 if actual == expected else 1)'
}

docker_kli_version() {
    local version
    version=$(kli version) || return 1
    [[ "${version}" == *"1.1.32"* ]]
}

backend_preflight_versions() {
    start_job preflight-signify preflight_signify_versions || return 1
    start_job preflight-keria docker_keria_versions || return 1
    start_job preflight-witnesses \
        docker_python_package witnesses keri 1.3.1 || return 1
    start_job preflight-kli docker_kli_version || return 1
    wait_jobs \
        preflight-signify preflight-keria \
        preflight-witnesses preflight-kli
}

backend_sally_logs() {
    local submitted_after=$1
    workflow_compose logs \
        --no-color \
        --timestamps \
        --since "${submitted_after}" \
        sally 2>&1
}
