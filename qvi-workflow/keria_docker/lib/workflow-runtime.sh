#!/usr/bin/env bash

# Small, sourceable runtime helpers for the local QVI demonstration.
#
# The workflow deliberately supports one run at a time. Docker Compose owns the
# network and named volumes; generated files live in the visible runtime/
# directory beside the driver.

# Bash 3.2 treats an empty indexed array as unset under `set -u`. Keep index
# zero as an inert sentinel so the job registry remains safe on macOS Bash.
WORKFLOW_JOB_NAMES=("")
WORKFLOW_JOB_PIDS=("")
WORKFLOW_JOB_STDOUTS=("")
WORKFLOW_JOB_STDERRS=("")
WORKFLOW_JOB_RESOURCES=("")
WORKFLOW_JOB_STARTS=("")
WORKFLOW_JOB_RESULTS=("")
WORKFLOW_COMPLETED_JOB_NAMES=("")
WORKFLOW_COMPLETED_JOB_RESULTS=("")

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
    WORKFLOW_RESULT_DIR="${WORKFLOW_RUN_DIR}/results"
    SALLY_CALLBACK_FILE="${WORKFLOW_RUN_DIR}/sally-callbacks.jsonl"
    WORKFLOW_TIMING_FILE="${WORKFLOW_RUN_DIR}/workflow-timings.jsonl"

    export WORKFLOW_RUN_DIR WORKFLOW_CONFIG_DIR KLI_DATA_DIR
    export LOCAL_QVI_DATA_DIR KEYSTORE_DIR WORKFLOW_LOG_DIR WORKFLOW_RESULT_DIR
    export SALLY_CALLBACK_FILE WORKFLOW_TIMING_FILE

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
        "${WORKFLOW_RESULT_DIR}"

    cp -R "${SCRIPT_DIR}/config/." "${WORKFLOW_CONFIG_DIR}/"
    rm -f \
        "${WORKFLOW_CONFIG_DIR}/multi-sig-incept-config.json" \
        "${WORKFLOW_CONFIG_DIR}/multi-sig-delegated-incept-config.json" \
        "${WORKFLOW_CONFIG_DIR}/single-sig-incept-config.json"
    cp -R "${SCRIPT_DIR}/acdc-info/rules/." "${KLI_DATA_DIR}/rules/"

    mkdir -p "${WORKFLOW_CONFIG_DIR}/sally/keri/cf"
    cp \
        "${SCRIPT_DIR}/sally/keri/cf/sally.json" \
        "${WORKFLOW_CONFIG_DIR}/sally/keri/cf/sally.json"
    cp \
        "${SCRIPT_DIR}/sally/sally-incept-no-wits.json" \
        "${WORKFLOW_CONFIG_DIR}/sally/sally-incept-no-wits.json"

    jq -n \
        --arg qar1Name "${QAR1}" \
        --arg qar1Salt "${QAR1_SALT}" \
        --arg qar2Name "${QAR2}" \
        --arg qar2Salt "${QAR2_SALT}" \
        --arg qar3Name "${QAR3}" \
        --arg qar3Salt "${QAR3_SALT}" \
        --arg qar4Name "${QAR4}" \
        --arg qar4Salt "${QAR4_SALT}" \
        --arg personName "${PERSON}" \
        --arg personSalt "${PERSON_SALT}" \
        --arg qviName "${QVI_NAME}" \
        '{
            services: {
                vleiServerUrl: "http://vlei-server:7723",
                witnesses: [
                    {
                        id: "BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha",
                        url: "http://gar-witnesses:5642"
                    },
                    {
                        id: "BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM",
                        url: "http://qar-witnesses:5643"
                    },
                    {
                        id: "BIKKuvBwpmDVA4Ds-EpL5bt9OqPzWPja2LigFYZN2YfX",
                        url: "http://person-witnesses:5644"
                    }
                ]
            },
            participants: {
                qar1: {
                    name: $qar1Name,
                    salt: $qar1Salt,
                    adminUrl: "http://keria1:3901",
                    bootUrl: "http://keria1:3903",
                    oobiUrl: "http://keria1:3902"
                },
                qar2: {
                    name: $qar2Name,
                    salt: $qar2Salt,
                    adminUrl: "http://keria2:3901",
                    bootUrl: "http://keria2:3903",
                    oobiUrl: "http://keria2:3902"
                },
                qar3: {
                    name: $qar3Name,
                    salt: $qar3Salt,
                    adminUrl: "http://keria3:3901",
                    bootUrl: "http://keria3:3903",
                    oobiUrl: "http://keria3:3902"
                },
                qar4: {
                    name: $qar4Name,
                    salt: $qar4Salt,
                    adminUrl: "http://keria4:3901",
                    bootUrl: "http://keria4:3903",
                    oobiUrl: "http://keria4:3902"
                },
                person: {
                    name: $personName,
                    salt: $personSalt,
                    adminUrl: "http://keria1:3901",
                    bootUrl: "http://keria1:3903",
                    oobiUrl: "http://keria1:3902"
                }
            },
            qvi: {
                name: $qviName,
                initialMembers: ["qar1", "qar2", "qar3"],
                finalMembers: ["qar1", "qar2", "qar4"],
                signingThreshold: ["1/3", "1/3", "1/3"],
                nextThreshold: ["1/3", "1/3", "1/3"]
            }
        }' > "${WORKFLOW_CONFIG_DIR}/participants.json"

    : > "${SALLY_CALLBACK_FILE}"
    : > "${WORKFLOW_TIMING_FILE}"
}

record_workflow_timing() {
    local kind=$1
    local name=$2
    local started_at=$3
    local finished_at=$4
    local status=$5
    local resources=${6:-}

    [[ -n "${WORKFLOW_TIMING_FILE:-}" ]] || return 0
    jq -nc \
        --arg kind "${kind}" \
        --arg name "${name}" \
        --arg resources "${resources}" \
        --argjson startedAt "${started_at}" \
        --argjson finishedAt "${finished_at}" \
        --argjson duration "$((finished_at - started_at))" \
        --argjson status "${status}" \
        '{
            kind: $kind,
            name: $name,
            resources: ($resources | split(",") | map(select(length > 0))),
            startedAt: $startedAt,
            finishedAt: $finishedAt,
            durationSeconds: $duration,
            status: $status
        }' >> "${WORKFLOW_TIMING_FILE}"
}

run_workflow_phase() {
    local phase_name=$1
    shift
    local started_at
    local finished_at
    local phase_status=0

    started_at=$(date +%s)
    "$@" || phase_status=$?
    finished_at=$(date +%s)
    record_workflow_timing \
        phase "${phase_name}" "${started_at}" "${finished_at}" "${phase_status}"
    return "${phase_status}"
}

run_workflow_command() {
    local kind=$1
    local command_name=$2
    local resources=$3
    shift 3
    local started_at
    local finished_at
    local command_status=0

    started_at=$(date +%s)
    "$@" || command_status=$?
    finished_at=$(date +%s)
    record_workflow_timing \
        "${kind}" "${command_name}" "${started_at}" "${finished_at}" \
        "${command_status}" "${resources}"
    return "${command_status}"
}

print_workflow_timing_summary() {
    [[ -s "${WORKFLOW_TIMING_FILE:-}" ]] || return 0

    print_lcyan "Workflow critical-path timing summary:"
    jq -sr '
        (map(.startedAt) | min) as $started |
        (map(.finishedAt) | max) as $finished |
        "total\tworkflow\t\($finished - $started)s",
        (
            map(select(.kind == "phase")) |
            sort_by(.startedAt) |
            .[] |
            "phase\t\(.name)\t\(.durationSeconds)s\tstatus=\(.status)"
        ),
        (
            map(select(.kind == "job")) |
            sort_by(.durationSeconds) |
            reverse |
            .[0:10] |
            .[] |
            "slow-job\t\(.name)\t\(.durationSeconds)s\tstatus=\(.status)"
        ),
        (
            map(select(.kind == "command")) |
            sort_by(.durationSeconds) |
            reverse |
            .[0:15] |
            .[] |
            "slow-command\t\(.name)\t\(.durationSeconds)s\tstatus=\(.status)"
        )
    ' "${WORKFLOW_TIMING_FILE}" |
        while IFS= read -r timing_line; do
            print_lcyan "  ${timing_line}"
        done
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
        vlei-server callback-recorder sally \
        keria1 keria2 keria3 keria4 >&2 || true

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

    cancel_all_workflow_jobs

    workflow_compose down --volumes --remove-orphans || cleanup_status=$?
    rm -rf "${WORKFLOW_RUN_DIR}"

    if [[ "${original_status}" -ne 0 ]]; then
        return "${original_status}"
    fi
    return "${cleanup_status}"
}

handle_workflow_exit() {
    local original_status=$?
    local final_status=0

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

poll_until() {
    local description=$1
    local timeout_seconds=$2
    local predicate_name=$3
    shift 3

    local deadline=$((SECONDS + timeout_seconds))
    local predicate_output=""
    local last_observation="<none>"
    local predicate_succeeded=false
    local deadline_reached=false

    while true; do
        predicate_output=""
        predicate_succeeded=false

        # The named workflow predicate runs in command substitution so its
        # output can become either the successful result or the final
        # diagnostic. It therefore runs in a subshell and must not communicate
        # through shell-variable side effects. Predicates must also bound their
        # own external I/O; poll_until only controls when another poll begins.
        predicate_output=$(
            "${predicate_name}" "$@" 2>&1
        ) && predicate_succeeded=true

        if [[ -n "${predicate_output}" ]]; then
            last_observation="${predicate_output}"
        fi

        if [[ "${predicate_succeeded}" == true ]]; then
            if [[ -n "${predicate_output}" ]]; then
                printf '%s\n' "${predicate_output}"
            fi
            return 0
        fi

        deadline_reached=false
        [[ "${SECONDS}" -ge "${deadline}" ]] &&
            deadline_reached=true
        if [[ "${deadline_reached}" == true ]]; then
            break
        fi

        sleep 1
    done

    printf 'Timed out after %ss waiting for %s. Last observation: %s\n' \
        "${timeout_seconds}" "${description}" "${last_observation}" >&2
    return 1
}

background_job_has_stopped() {
    local pid=$1
    if kill -0 "${pid}" 2>/dev/null; then
        printf 'process %s is still running\n' "${pid}"
        return 1
    fi
}

workflow_resources_overlap() {
    local left=$1
    local right=$2
    local left_resource
    local right_resource
    local old_ifs=${IFS}

    IFS=,
    for left_resource in ${left}; do
        for right_resource in ${right}; do
            if [[ -n "${left_resource}" &&
                  "${left_resource}" == "${right_resource}" ]]; then
                IFS=${old_ifs}
                return 0
            fi
        done
    done
    IFS=${old_ifs}
    return 1
}

register_background_job() {
    local logical_name=$1
    local resources=$2
    local stdout_log=$3
    local stderr_log=$4
    local result_file=$5
    local pid=$6

    local existing_name
    local existing_resources
    local index
    local job_index=${#WORKFLOW_JOB_NAMES[@]}

    for index in "${!WORKFLOW_JOB_NAMES[@]}"; do
        existing_name=${WORKFLOW_JOB_NAMES[${index}]}
        if [[ "${existing_name}" == "${logical_name}" ]]; then
            printf 'Background job %s is already active\n' "${logical_name}" >&2
            return 1
        fi
        existing_resources=${WORKFLOW_JOB_RESOURCES[${index}]:-}
        if workflow_resources_overlap "${resources}" "${existing_resources}"; then
            printf 'Background job %s conflicts with active job %s on resources %s / %s\n' \
                "${logical_name}" "${existing_name}" \
                "${resources}" "${existing_resources}" >&2
            return 1
        fi
    done

    WORKFLOW_JOB_NAMES[${job_index}]="${logical_name}"
    WORKFLOW_JOB_PIDS[${job_index}]="${pid}"
    WORKFLOW_JOB_STDOUTS[${job_index}]="${stdout_log}"
    WORKFLOW_JOB_STDERRS[${job_index}]="${stderr_log}"
    WORKFLOW_JOB_RESOURCES[${job_index}]="${resources}"
    WORKFLOW_JOB_STARTS[${job_index}]="$(date +%s)"
    WORKFLOW_JOB_RESULTS[${job_index}]="${result_file}"
}

start_workflow_job() {
    local logical_name=$1
    local resources=$2
    shift 2

    local artifact_stem
    local stdout_log
    local stderr_log
    local result_file
    local pid

    artifact_stem="${logical_name}-$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}"
    stdout_log="${WORKFLOW_LOG_DIR}/${artifact_stem}.out.log"
    stderr_log="${WORKFLOW_LOG_DIR}/${artifact_stem}.err.log"
    result_file="${WORKFLOW_RESULT_DIR}/${artifact_stem}.json"

    # Validate conflicts before launching so a rejected job cannot escape the
    # workflow registry.
    local existing_resources
    local index
    for index in "${!WORKFLOW_JOB_NAMES[@]}"; do
        [[ -n "${WORKFLOW_JOB_NAMES[${index}]:-}" ]] || continue
        existing_resources=${WORKFLOW_JOB_RESOURCES[${index}]:-}
        if [[ "${WORKFLOW_JOB_NAMES[${index}]}" == "${logical_name}" ]] ||
           workflow_resources_overlap "${resources}" "${existing_resources}"; then
            printf 'Cannot start background job %s with resources %s\n' \
                "${logical_name}" "${resources}" >&2
            return 1
        fi
    done

    "$@" >"${stdout_log}" 2>"${stderr_log}" &
    pid=$!
    register_background_job \
        "${logical_name}" "${resources}" \
        "${stdout_log}" "${stderr_log}" "${result_file}" "${pid}"
}

run_background_compose_job() {
    local service_name=$1
    local logical_name=$2
    local resources=$3
    shift 3

    start_workflow_job \
        "${logical_name}" "${resources}" \
        workflow_compose exec -T "${service_name}" "$@"
}

find_workflow_job_index() {
    local logical_name=$1
    local index

    for index in "${!WORKFLOW_JOB_NAMES[@]}"; do
        if [[ "${WORKFLOW_JOB_NAMES[${index}]:-}" == "${logical_name}" ]]; then
            printf '%s\n' "${index}"
            return 0
        fi
    done
    return 1
}

finish_workflow_job() {
    local job_index=$1
    local exit_status=$2
    local logical_name=${WORKFLOW_JOB_NAMES[${job_index}]}
    local stdout_log=${WORKFLOW_JOB_STDOUTS[${job_index}]}
    local stderr_log=${WORKFLOW_JOB_STDERRS[${job_index}]}
    local resources=${WORKFLOW_JOB_RESOURCES[${job_index}]:-}
    local started_at=${WORKFLOW_JOB_STARTS[${job_index}]}
    local result_file=${WORKFLOW_JOB_RESULTS[${job_index}]}
    local finished_at

    finished_at=$(date +%s)
    [[ -f "${stdout_log}" ]] && cat "${stdout_log}"
    [[ -f "${stderr_log}" ]] && cat "${stderr_log}" >&2
    record_workflow_timing \
        job "${logical_name}" "${started_at}" "${finished_at}" \
        "${exit_status}" "${resources}"
    jq -n \
        --arg name "${logical_name}" \
        --arg resources "${resources}" \
        --arg stdoutLog "${stdout_log}" \
        --arg stderrLog "${stderr_log}" \
        --argjson startedAt "${started_at}" \
        --argjson finishedAt "${finished_at}" \
        --argjson durationSeconds "$((finished_at - started_at))" \
        --argjson status "${exit_status}" \
        '{
            name: $name,
            resources: ($resources | split(",") | map(select(length > 0))),
            startedAt: $startedAt,
            finishedAt: $finishedAt,
            durationSeconds: $durationSeconds,
            status: $status,
            stdoutLog: $stdoutLog,
            stderrLog: $stderrLog
        }' > "${result_file}"

    local completed_index=${#WORKFLOW_COMPLETED_JOB_NAMES[@]}
    WORKFLOW_COMPLETED_JOB_NAMES[${completed_index}]="${logical_name}"
    WORKFLOW_COMPLETED_JOB_RESULTS[${completed_index}]="${result_file}"

    unset "WORKFLOW_JOB_NAMES[${job_index}]"
    unset "WORKFLOW_JOB_PIDS[${job_index}]"
    unset "WORKFLOW_JOB_STDOUTS[${job_index}]"
    unset "WORKFLOW_JOB_STDERRS[${job_index}]"
    unset "WORKFLOW_JOB_RESOURCES[${job_index}]"
    unset "WORKFLOW_JOB_STARTS[${job_index}]"
    unset "WORKFLOW_JOB_RESULTS[${job_index}]"
}

workflow_job_result_file() {
    local logical_name=$1
    local index

    # Return the most recent result when a logical name is reused in a later
    # conflict-free wave.
    for ((index=${#WORKFLOW_COMPLETED_JOB_NAMES[@]} - 1; index >= 1; index--)); do
        if [[ "${WORKFLOW_COMPLETED_JOB_NAMES[${index}]:-}" == "${logical_name}" ]]; then
            printf '%s\n' "${WORKFLOW_COMPLETED_JOB_RESULTS[${index}]}"
            return 0
        fi
    done
    printf 'No completed background job result is registered as %s\n' \
        "${logical_name}" >&2
    return 1
}

load_workflow_job_result() {
    local logical_name=$1
    local result_file

    result_file=$(workflow_job_result_file "${logical_name}") || return 1
    jq -e '.' "${result_file}"
}

cancel_all_workflow_jobs() {
    local index
    local pid
    local active_jobs_found=false

    for index in "${!WORKFLOW_JOB_NAMES[@]}"; do
        [[ -n "${WORKFLOW_JOB_NAMES[${index}]:-}" ]] || continue
        active_jobs_found=true
        pid=${WORKFLOW_JOB_PIDS[${index}]}
        kill "${pid}" 2>/dev/null || true
    done
    [[ "${active_jobs_found}" == true ]] || return 0
    sleep 1
    for index in "${!WORKFLOW_JOB_NAMES[@]}"; do
        [[ -n "${WORKFLOW_JOB_NAMES[${index}]:-}" ]] || continue
        pid=${WORKFLOW_JOB_PIDS[${index}]}
        kill -9 "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
        finish_workflow_job "${index}" 143
    done
}

wait_for_background_job() {
    local logical_name=$1
    wait_for_background_jobs "${logical_name}"
}

wait_for_background_jobs() {
    local requested_names=("$@")
    local deadline=$((SECONDS + WORKFLOW_TIMEOUT_SECONDS))
    local remaining=${#requested_names[@]}
    local logical_name
    local job_index
    local pid
    local exit_status
    local made_progress

    for logical_name in "${requested_names[@]}"; do
        find_workflow_job_index "${logical_name}" >/dev/null || {
            printf 'No background job is registered as %s\n' "${logical_name}" >&2
            return 1
        }
    done

    while [[ "${remaining}" -gt 0 ]]; do
        made_progress=false
        for logical_name in "${requested_names[@]}"; do
            job_index=$(find_workflow_job_index "${logical_name}") || continue
            pid=${WORKFLOW_JOB_PIDS[${job_index}]}
            if kill -0 "${pid}" 2>/dev/null; then
                continue
            fi

            exit_status=0
            wait "${pid}" || exit_status=$?
            finish_workflow_job "${job_index}" "${exit_status}"
            remaining=$((remaining - 1))
            made_progress=true
            if [[ "${exit_status}" -ne 0 ]]; then
                printf 'Background job %s failed with status %s\n' \
                    "${logical_name}" "${exit_status}" >&2
                cancel_all_workflow_jobs
                return "${exit_status}"
            fi
        done

        [[ "${remaining}" -eq 0 ]] && break
        if [[ "${SECONDS}" -ge "${deadline}" ]]; then
            printf 'Timed out after %ss waiting for background job group: %s\n' \
                "${WORKFLOW_TIMEOUT_SECONDS}" "${requested_names[*]}" >&2
            cancel_all_workflow_jobs
            return 124
        fi
        [[ "${made_progress}" == true ]] || sleep 1
    done
}
