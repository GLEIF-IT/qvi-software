#!/usr/bin/env bash

# Small, sourceable runtime helpers for the local QVI demonstration.
#
# The workflow deliberately supports one run at a time. Docker Compose owns the
# network and named volumes; generated files live in the visible runtime/
# directory beside the driver.

WORKFLOW_CLEANING_UP=false
WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST=false

workflow_compose() {
    docker compose \
        --project-directory "${SCRIPT_DIR}" \
        --env-file "${WORKFLOW_ENV_FILE}" \
        -f "${DOCKER_COMPOSE_FILE}" \
        "$@"
}

create_workflow_runtime() {
    WORKFLOW_RUN_DIR="${SCRIPT_DIR}/runtime"
    WORKFLOW_CONFIG_DIR="${WORKFLOW_RUN_DIR}/config"
    KLI_DATA_DIR="${WORKFLOW_RUN_DIR}/acdc-info"
    LOCAL_QVI_DATA_DIR="${WORKFLOW_RUN_DIR}/qvi_data"
    KEYSTORE_DIR="${WORKFLOW_RUN_DIR}/keystores"
    WORKFLOW_LOG_DIR="${WORKFLOW_RUN_DIR}/logs"
    WORKFLOW_JOB_DIR="${WORKFLOW_RUN_DIR}/jobs"
    SALLY_CALLBACK_FILE="${WORKFLOW_RUN_DIR}/sally-callbacks.jsonl"

    export WORKFLOW_RUN_DIR WORKFLOW_CONFIG_DIR KLI_DATA_DIR
    export LOCAL_QVI_DATA_DIR KEYSTORE_DIR WORKFLOW_LOG_DIR WORKFLOW_JOB_DIR
    export SALLY_CALLBACK_FILE

    # A retained --keep-runtime run is intentionally replaced by the next run.
    workflow_compose down --volumes --remove-orphans >/dev/null 2>&1 || true
    rm -rf "${WORKFLOW_RUN_DIR}"

    mkdir -p \
        "${WORKFLOW_CONFIG_DIR}" \
        "${KLI_DATA_DIR}/rules" \
        "${KLI_DATA_DIR}/temp-data" \
        "${LOCAL_QVI_DATA_DIR}" \
        "${KEYSTORE_DIR}" \
        "${WORKFLOW_LOG_DIR}" \
        "${WORKFLOW_JOB_DIR}"

    cp -R "${SCRIPT_DIR}/config/." "${WORKFLOW_CONFIG_DIR}/"
    rm -f \
        "${WORKFLOW_CONFIG_DIR}/multi-sig-incept-config.json" \
        "${WORKFLOW_CONFIG_DIR}/multi-sig-delegated-incept-config.json" \
        "${WORKFLOW_CONFIG_DIR}/single-sig-incept-config.json"
    cp -R "${SCRIPT_DIR}/acdc-info/rules/." "${KLI_DATA_DIR}/rules/"

    mkdir -p "${WORKFLOW_CONFIG_DIR}/direct-sally/keri/cf"
    cp \
        "${SCRIPT_DIR}/direct-sally/keri/cf/direct-sally.json" \
        "${WORKFLOW_CONFIG_DIR}/direct-sally/keri/cf/direct-sally.json"
    cp \
        "${SCRIPT_DIR}/direct-sally/sally-incept-no-wits.json" \
        "${WORKFLOW_CONFIG_DIR}/direct-sally/sally-incept-no-wits.json"

    : > "${SALLY_CALLBACK_FILE}"
    WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST=true
}

print_failure_diagnostics() {
    local compose_status=0

    print_red "Compose status at failure:"
    workflow_compose ps >&2 || compose_status=$?
    if [[ "${compose_status}" -ne 0 ]]; then
        print_red "Unable to read Compose status"
    fi

    print_red "Recent Compose logs:"
    workflow_compose logs \
        --no-color \
        --tail 200 \
        vlei-server callback-recorder direct-sally keria1 keria2 keria3 >&2 || true

    local job_log
    for job_log in "${WORKFLOW_LOG_DIR}"/*.log; do
        [[ -f "${job_log}" ]] || continue
        printf '\n--- %s ---\n' "${job_log##*/}" >&2
        tail -n 100 "${job_log}" >&2
    done
}

workflow_cleanup() {
    local original_status=$1
    local cleanup_status=0
    local workflow_failed=false
    local runtime_should_be_kept=false

    [[ "${original_status}" -ne 0 ]] && workflow_failed=true
    [[ "${KEEP_RUNTIME:-false}" == true ]] && runtime_should_be_kept=true

    if [[ "${runtime_should_be_kept}" == true ]]; then
        print_yellow "Runtime retained at ${WORKFLOW_RUN_DIR}"
        print_yellow "Teardown: cd ${SCRIPT_DIR} && docker compose --env-file ${WORKFLOW_ENV_FILE} -f ${DOCKER_COMPOSE_FILE} down -v --remove-orphans"
        return "${original_status}"
    fi

    if [[ "${workflow_failed}" == true ]]; then
        print_failure_diagnostics
    fi

    if [[ "${WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST}" == true ]]; then
        workflow_compose down --volumes --remove-orphans || cleanup_status=$?
    fi
    rm -rf "${WORKFLOW_RUN_DIR}"

    if [[ "${original_status}" -ne 0 ]]; then
        return "${original_status}"
    fi
    return "${cleanup_status}"
}

handle_workflow_exit() {
    local original_status=$?
    local final_status=0

    if [[ "${WORKFLOW_CLEANING_UP}" == true ]]; then
        return
    fi
    WORKFLOW_CLEANING_UP=true
    trap - EXIT INT TERM HUP

    workflow_cleanup "${original_status}" || final_status=$?
    exit "${final_status}"
}

handle_workflow_signal() {
    local signal_name=$1
    local signal_status=1

    case "${signal_name}" in
        INT) signal_status=130 ;;
        TERM) signal_status=143 ;;
        HUP) signal_status=129 ;;
    esac
    exit "${signal_status}"
}

install_workflow_traps() {
    trap 'handle_workflow_exit' EXIT
    trap 'handle_workflow_signal INT' INT
    trap 'handle_workflow_signal TERM' TERM
    trap 'handle_workflow_signal HUP' HUP
}

wait_until() {
    local description=$1
    local timeout_seconds=$2
    local predicate_name=$3
    shift 3

    local deadline=$(( $(date +%s) + timeout_seconds ))
    local attempt_number=0
    local output_file=""
    local status_file=""
    local predicate_process_id=""
    local predicate_finished=false
    local predicate_output=""
    local predicate_status=1
    local last_observation="<none>"
    local predicate_succeeded=false
    local timeout_elapsed=false

    while [[ "${timeout_elapsed}" == false ]]; do
        attempt_number=$((attempt_number + 1))
        output_file="${WORKFLOW_LOG_DIR:-${TMPDIR:-/tmp}}/wait-${$}-${attempt_number}.out"
        status_file="${WORKFLOW_LOG_DIR:-${TMPDIR:-/tmp}}/wait-${$}-${attempt_number}.status"
        : > "${output_file}"
        : > "${status_file}"

        predicate_status=0
        predicate_finished=false
        (
            local completed_status=0
            "${predicate_name}" "$@" || completed_status=$?
            printf '%s\n' "${completed_status}" > "${status_file}"
            exit "${completed_status}"
        ) > "${output_file}" 2>&1 &
        predicate_process_id=$!

        while [[ "${predicate_finished}" == false &&
                 "${timeout_elapsed}" == false ]]; do
            [[ -s "${status_file}" ]] && predicate_finished=true
            [[ $(date +%s) -gt "${deadline}" ]] && timeout_elapsed=true
            if [[ "${predicate_finished}" == false &&
                  "${timeout_elapsed}" == false ]]; then
                sleep 0.1
            fi
        done

        if [[ "${predicate_finished}" == true ]]; then
            wait "${predicate_process_id}" || predicate_status=$?
        else
            kill "${predicate_process_id}" >/dev/null 2>&1 || true
            wait "${predicate_process_id}" >/dev/null 2>&1 || true
            predicate_status=124
        fi
        predicate_output=$(<"${output_file}")
        rm -f "${output_file}" "${status_file}"
        [[ -n "${predicate_output}" ]] &&
            last_observation="${predicate_output}"

        predicate_succeeded=false
        [[ "${predicate_status}" -eq 0 ]] && predicate_succeeded=true
        if [[ "${predicate_succeeded}" == true ]]; then
            [[ -n "${predicate_output}" ]] &&
                printf '%s\n' "${predicate_output}"
            return 0
        fi

        [[ $(date +%s) -gt "${deadline}" ]] && timeout_elapsed=true
        if [[ "${timeout_elapsed}" == false ]]; then
            sleep 1
        fi
    done

    printf 'Timed out after %ss waiting for %s. Last observation: %s\n' \
        "${timeout_seconds}" "${description}" "${last_observation}" >&2
    return 1
}

http_request() {
    curl \
        --connect-timeout "${HTTP_CONNECT_TIMEOUT:-5}" \
        --max-time "${HTTP_REQUEST_TIMEOUT:-15}" \
        "$@"
}

compose_container_has_stopped() {
    local container_id=$1
    local running_state=""

    running_state=$(docker inspect \
        --format '{{.State.Running}}' \
        "${container_id}" 2>/dev/null) || return 1
    if [[ "${running_state}" == false ]]; then
        return 0
    fi

    printf 'container %s is still running\n' "${container_id}"
    return 1
}

run_detached_compose_job() {
    local service_name=$1
    local logical_name=$2
    shift 2

    local container_id=""
    local job_file="${WORKFLOW_JOB_DIR}/${logical_name}.id"
    local job_already_exists=false

    [[ -e "${job_file}" ]] && job_already_exists=true
    if [[ "${job_already_exists}" == true ]]; then
        printf 'Detached job %s is already active\n' "${logical_name}" >&2
        return 1
    fi

    container_id=$(workflow_compose run \
        --detach \
        --no-deps \
        "${service_name}" "$@") || return $?
    if [[ -z "${container_id}" ]]; then
        printf 'Compose returned no container ID for %s\n' "${logical_name}" >&2
        return 1
    fi

    printf '%s\n' "${container_id}" > "${job_file}"
}

wait_for_compose_job() {
    local logical_name=$1
    local job_file="${WORKFLOW_JOB_DIR}/${logical_name}.id"
    local job_log="${WORKFLOW_LOG_DIR}/${logical_name}.log"
    local container_id=""
    local exit_status=125
    local wait_succeeded=false
    local job_succeeded=false

    if [[ ! -f "${job_file}" ]]; then
        printf 'No detached job is registered as %s\n' "${logical_name}" >&2
        return 1
    fi
    container_id=$(<"${job_file}")

    wait_until \
        "detached KLI job ${logical_name}" \
        "${WORKFLOW_TIMEOUT_SECONDS}" \
        compose_container_has_stopped \
        "${container_id}" >/dev/null &&
        wait_succeeded=true

    docker logs "${container_id}" 2>&1 | tee "${job_log}" || true
    if [[ "${wait_succeeded}" == true ]]; then
        exit_status=$(docker inspect \
            --format '{{.State.ExitCode}}' \
            "${container_id}") || exit_status=125
    else
        exit_status=124
    fi

    [[ "${wait_succeeded}" == true && "${exit_status}" -eq 0 ]] &&
        job_succeeded=true
    docker rm --force "${container_id}" >/dev/null 2>&1 || true
    rm -f "${job_file}"

    if [[ "${job_succeeded}" == false ]]; then
        printf 'Detached KLI job %s failed with status %s\n' \
            "${logical_name}" "${exit_status}" >&2
        return 1
    fi
}

wait_for_compose_jobs() {
    local logical_name
    local all_jobs_succeeded=true

    for logical_name in "$@"; do
        wait_for_compose_job "${logical_name}" ||
            all_jobs_succeeded=false
    done
    [[ "${all_jobs_succeeded}" == true ]]
}
