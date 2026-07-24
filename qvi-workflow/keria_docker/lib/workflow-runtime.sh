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
    SALLY_CALLBACK_FILE="${WORKFLOW_RUN_DIR}/sally-callbacks.jsonl"

    export WORKFLOW_RUN_DIR WORKFLOW_CONFIG_DIR KLI_DATA_DIR
    export LOCAL_QVI_DATA_DIR KEYSTORE_DIR WORKFLOW_LOG_DIR
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
        "${WORKFLOW_LOG_DIR}"

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
        vlei-server callback-recorder direct-sally \
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

run_background_compose_job() {
    local service_name=$1
    local logical_name=$2
    shift 2

    local existing_name
    local stdout_log="${WORKFLOW_LOG_DIR}/${logical_name}.out.log"
    local stderr_log="${WORKFLOW_LOG_DIR}/${logical_name}.err.log"
    local job_index=${#WORKFLOW_JOB_NAMES[@]}

    for existing_name in "${WORKFLOW_JOB_NAMES[@]}"; do
        if [[ "${existing_name}" == "${logical_name}" ]]; then
            printf 'Background job %s is already active\n' "${logical_name}" >&2
            return 1
        fi
    done

    workflow_compose run --rm --no-deps -T \
        "${service_name}" "$@" >"${stdout_log}" 2>"${stderr_log}" &
    WORKFLOW_JOB_NAMES[${job_index}]="${logical_name}"
    WORKFLOW_JOB_PIDS[${job_index}]=$!
    WORKFLOW_JOB_STDOUTS[${job_index}]="${stdout_log}"
    WORKFLOW_JOB_STDERRS[${job_index}]="${stderr_log}"
}

wait_for_background_job() {
    local logical_name=$1
    local job_index=-1
    local index
    local pid=""
    local stdout_log=""
    local stderr_log=""
    local exit_status=125
    local wait_completed=false

    for index in "${!WORKFLOW_JOB_NAMES[@]}"; do
        if [[ "${WORKFLOW_JOB_NAMES[${index}]}" == "${logical_name}" ]]; then
            job_index=${index}
            break
        fi
    done
    if [[ "${job_index}" -lt 0 ]]; then
        printf 'No background job is registered as %s\n' "${logical_name}" >&2
        return 1
    fi

    pid=${WORKFLOW_JOB_PIDS[${job_index}]}
    stdout_log=${WORKFLOW_JOB_STDOUTS[${job_index}]}
    stderr_log=${WORKFLOW_JOB_STDERRS[${job_index}]}
    poll_until \
        "background Compose job ${logical_name}" \
        "${WORKFLOW_TIMEOUT_SECONDS}" \
        background_job_has_stopped \
        "${pid}" >/dev/null &&
        wait_completed=true

    if [[ "${wait_completed}" == false ]]; then
        kill "${pid}" 2>/dev/null || true
        sleep 1
        kill -9 "${pid}" 2>/dev/null || true
        exit_status=124
        wait "${pid}" 2>/dev/null || true
    elif wait "${pid}"; then
        exit_status=0
    else
        exit_status=$?
    fi

    [[ -f "${stdout_log}" ]] && cat "${stdout_log}"
    [[ -f "${stderr_log}" ]] && cat "${stderr_log}" >&2
    unset "WORKFLOW_JOB_NAMES[${job_index}]"
    unset "WORKFLOW_JOB_PIDS[${job_index}]"
    unset "WORKFLOW_JOB_STDOUTS[${job_index}]"
    unset "WORKFLOW_JOB_STDERRS[${job_index}]"

    if [[ "${exit_status}" -ne 0 ]]; then
        printf 'Background Compose job %s failed with status %s\n' \
            "${logical_name}" "${exit_status}" >&2
        return "${exit_status}"
    fi
}

wait_for_background_jobs() {
    local logical_name
    local all_jobs_succeeded=true

    for logical_name in "$@"; do
        wait_for_background_job "${logical_name}" ||
            all_jobs_succeeded=false
    done
    [[ "${all_jobs_succeeded}" == true ]]
}
