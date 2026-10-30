#!/usr/bin/env bash

# Runtime, concurrency, and managed-process helpers for the local QVI workflow.

WORKFLOW_PROCESS_NAMES=("")
WORKFLOW_PROCESS_PIDS=("")
WORKFLOW_PROCESS_LOGS=("")
WORKFLOW_CLEANUP_SIGNAL=""
# Local predicates and child-process checks are cheap. Observe them often
# enough that the harness does not hide sub-second protocol completion.
WORKFLOW_POLL_INTERVAL_SECONDS=0.01

# Resolve the workflow-owned local executables once for every driver command.
VENV_DIR="${SCRIPT_DIR}/.venvs"
DEPENDENCY_DIR="${SCRIPT_DIR}/.deps"
KERI_WORKSPACE_DIR=${KERI_WORKSPACE_DIR:-$(cd "${SCRIPT_DIR}/../../../.." && pwd -P)}
LOCAL_KERIPY_DIR=${LOCAL_KERIPY_DIR:-"${KERI_WORKSPACE_DIR}/core/python/keripy"}
GEDA_KLI_PYTHON="${VENV_DIR}/geda-kli/bin/python"
KLI_PYTHON="${VENV_DIR}/kli/bin/python"
KLI_LAUNCHER="${SCRIPT_DIR}/local-kli.py"
KERIA_PYTHON="${VENV_DIR}/keria/bin/python"
KERIA_LAUNCHER="${SCRIPT_DIR}/local-keria.py"
WITNESS_PYTHON="${VENV_DIR}/witnesses/bin/python"
SALLY_PYTHON="${VENV_DIR}/sally/bin/python"
SALLY_LAUNCHER="${SCRIPT_DIR}/local-sally.py"
VLEI_BIN="${VENV_DIR}/vlei/bin/vLEI-server"
TSX_BIN="${SCRIPT_DIR}/../sig_ts_wallets/node_modules/.bin/tsx"
WALLET_SERVER="${SCRIPT_DIR}/../sig_ts_wallets/src/wallet-server.ts"
SIGNAL_RESET_LAUNCHER="${SCRIPT_DIR}/run-with-signals.py"

export GEDA_KLI_PYTHON KLI_PYTHON KLI_LAUNCHER
export KERIA_PYTHON KERIA_LAUNCHER WITNESS_PYTHON
export SALLY_PYTHON SALLY_LAUNCHER VLEI_BIN TSX_BIN WALLET_SERVER
export SIGNAL_RESET_LAUNCHER KERI_WORKSPACE_DIR LOCAL_KERIPY_DIR

# Run every configurable v1.2.x KERI doer at one 1/32-second scheduler tick.
LOCAL_KERI_TOCK_ENV=(
    KERI_WITNESS_MSG_TOCK=0.03125
    KERI_WITNESS_ESCROW_TOCK=0.03125
    KERI_WITNESS_CUE_TOCK=0.03125
    KERI_INDIRECTOR_MSG_TOCK=0.03125
    KERI_INDIRECTOR_CUE_TOCK=0.03125
    KERI_INDIRECTOR_ESCROW_TOCK=0.03125
    KERI_MAILBOX_POLL_TOCK=0.03125
    KERI_MAILBOX_MSG_TOCK=0.03125
    KERI_MAILBOX_ESCROW_TOCK=0.03125
    KERI_POLLER_EVENT_TOCK=0.03125
    KERI_RECEIPT_INTERCEPT_TOCK=0.03125
    KERI_REACTOR_MSG_TOCK=0.03125
    KERI_REACTOR_CUE_TOCK=0.03125
    KERI_REACTOR_ESCROW_TOCK=0.03125
    KERI_REACTANT_MSG_TOCK=0.03125
    KERI_REACTANT_CUE_TOCK=0.03125
    KERI_REACTANT_ESCROW_TOCK=0.03125
    KERI_RESPONDANT_CUE_TOCK=0.03125
    KERI_WITNESS_RECEIPTOR_TOCK=0.03125
    KERI_WITNESS_INQUISITOR_TOCK=0.03125
    KERI_WITNESS_PUBLISHER_TOCK=0.03125
)

# KLI command counselors are short-lived and process one event. Keeping this
# cadence out of LOCAL_KERI_TOCK_ENV avoids burdening always-on KERIA agents.
LOCAL_KLI_TOCK_ENV=(
    KERI_COUNSELOR_ESCROW_TOCK=0.03125
    KERI_VDR_ESCROW_TOCK=0.03125
)

# Report whether a PID still represents a running, non-zombie process.
workflow_process_is_running() {
    local pid=$1
    local process_state=""

    kill -0 "${pid}" 2>/dev/null || return 1
    process_state=$(ps -p "${pid}" -o stat= 2>/dev/null || true)
    [[ -n "${process_state}" && "${process_state}" != Z* ]]
}

# Deliver a signal to descendants before their supervising shell process.
signal_workflow_process_tree() {
    local signal_name=$1
    local parent_pid=$2
    local child_pid

    # Background shell functions can hide the actual KLI or Python process one
    # level below the registered PID, so signal the full owned process tree.
    while IFS= read -r child_pid; do
        [[ -n "${child_pid}" ]] || continue
        signal_workflow_process_tree "${signal_name}" "${child_pid}"
    done < <(pgrep -P "${parent_pid}" 2>/dev/null || true)

    kill "-${signal_name}" "${parent_pid}" 2>/dev/null || true
}

# Convert a trapped signal name to the conventional shell exit status.
workflow_signal_status() {
    case "$1" in
        HUP) printf '129\n' ;;
        INT) printf '130\n' ;;
        TERM) printf '143\n' ;;
        *) printf '1\n' ;;
    esac
}

# Run a command with terminal signals restored after Bash backgrounding.
run_interruptible_process() {
    "${KERIA_PYTHON}" "${SIGNAL_RESET_LAUNCHER}" "$@"
}

# Return success only for commands launched from workflow-owned source or venvs.
workflow_command_is_owned() {
    local command_line=$1

    case "${command_line}" in
        *"${SCRIPT_DIR}/.venvs/"*|\
        *"${SCRIPT_DIR}/local-witnesses.py"*|\
        *"${SCRIPT_DIR}/../callback_recorder/recorder.py"*|\
        *"${SCRIPT_DIR}/../sig_ts_wallets/"*)
            return 0
            ;;
    esac
    return 1
}

# Stop a previously retained process only when its command belongs to this workflow.
stop_process_from_pid_file() {
    local pid_file=$1
    local pid=""
    local command_line=""

    [[ -f "${pid_file}" ]] || return 0
    pid=$(cat "${pid_file}")
    [[ "${pid}" =~ ^[1-9][0-9]*$ ]] || return 0
    workflow_process_is_running "${pid}" || return 0

    command_line=$(ps -p "${pid}" -o command= 2>/dev/null || true)
    if ! workflow_command_is_owned "${command_line}"; then
        printf 'Refusing to stop PID %s from %s; command is %s\n' \
            "${pid}" "${pid_file}" "${command_line}" >&2
        return 1
    fi
    kill -TERM "${pid}" 2>/dev/null || true
}

# Stop services left behind by an interrupted earlier run.
stop_retained_local_processes() {
    local pid_file
    local stop_status=0

    [[ -d "${SCRIPT_DIR}/runtime/pids" ]] || return 0
    for pid_file in "${SCRIPT_DIR}"/runtime/pids/*.pid; do
        [[ -f "${pid_file}" ]] || continue
        stop_process_from_pid_file "${pid_file}" || stop_status=$?
    done
    return "${stop_status}"
}

# Recreate isolated state, generated configs, logs, and callback files.
create_workflow_runtime() {
    WORKFLOW_RUN_DIR="${SCRIPT_DIR}/runtime"
    WORKFLOW_CONFIG_DIR="${WORKFLOW_RUN_DIR}/config"
    KLI_DATA_DIR="${WORKFLOW_RUN_DIR}/acdc-info"
    LOCAL_QVI_DATA_DIR="${WORKFLOW_RUN_DIR}/qvi_data"
    KEYSTORE_DIR="${WORKFLOW_RUN_DIR}/keystores"
    WORKFLOW_LOG_DIR="${WORKFLOW_RUN_DIR}/logs"
    WORKFLOW_PID_DIR="${WORKFLOW_RUN_DIR}/pids"
    KERI_HEAD_DIR="${WORKFLOW_RUN_DIR}/state"
    KLI_HEAD_DIR="${KERI_HEAD_DIR}"
    KLI_BASE=kli
    WITNESS_BASE=witnesses
    SALLY_BASE=sally
    SALLY_CALLBACK_FILE="${WORKFLOW_RUN_DIR}/sally-callbacks.jsonl"
    SALLY_LOG_FILE="${WORKFLOW_LOG_DIR}/sally.log"

    export WORKFLOW_RUN_DIR WORKFLOW_CONFIG_DIR KLI_DATA_DIR
    export LOCAL_QVI_DATA_DIR KEYSTORE_DIR WORKFLOW_LOG_DIR
    export WORKFLOW_PID_DIR KERI_HEAD_DIR KLI_HEAD_DIR KLI_BASE
    export WITNESS_BASE SALLY_BASE
    export SALLY_CALLBACK_FILE
    export SALLY_LOG_FILE

    # Kept artifacts from the previous run are intentionally replaced.
    stop_retained_local_processes
    rm -rf "${WORKFLOW_RUN_DIR}"

    mkdir -p \
        "${WORKFLOW_CONFIG_DIR}" \
        "${KLI_DATA_DIR}/rules" \
        "${KLI_DATA_DIR}/temp-data" \
        "${LOCAL_QVI_DATA_DIR}" \
        "${KEYSTORE_DIR}" \
        "${WORKFLOW_LOG_DIR}" \
        "${WORKFLOW_PID_DIR}" \
        "${KERI_HEAD_DIR}"

    cp -R "${SCRIPT_DIR}/config/." "${WORKFLOW_CONFIG_DIR}/"
    rm -f \
        "${WORKFLOW_CONFIG_DIR}/multi-sig-incept-config.json" \
        "${WORKFLOW_CONFIG_DIR}/multi-sig-delegated-incept-config.json" \
        "${WORKFLOW_CONFIG_DIR}/single-sig-incept-config.json"
    cp -R "${SCRIPT_DIR}/acdc-info/rules/." "${KLI_DATA_DIR}/rules/"
    jq -n --arg backend local '{backend: $backend}' \
        > "${WORKFLOW_RUN_DIR}/backend.json"

    mkdir -p "${WORKFLOW_CONFIG_DIR}/witnesses/keri/cf"
    cp "${SCRIPT_DIR}"/config/witnesses/*.json \
        "${WORKFLOW_CONFIG_DIR}/witnesses/keri/cf/"

    mkdir -p \
        "${WORKFLOW_CONFIG_DIR}/sally/keri/cf/${SALLY_BASE}"
    cp \
        "${SCRIPT_DIR}/sally/keri/cf/sally.json" \
        "${WORKFLOW_CONFIG_DIR}/sally/keri/cf/${SALLY_BASE}/sally.json"
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
                vleiServerUrl: "http://127.0.0.1:7723",
                witnesses: [
                    {
                        id: "BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha",
                        url: "http://127.0.0.1:5642"
                    },
                    {
                        id: "BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM",
                        url: "http://127.0.0.1:5643"
                    },
                    {
                        id: "BIKKuvBwpmDVA4Ds-EpL5bt9OqPzWPja2LigFYZN2YfX",
                        url: "http://127.0.0.1:5644"
                    }
                ]
            },
            participants: {
                qar1: {
                    name: $qar1Name,
                    salt: $qar1Salt,
                    adminUrl: "http://127.0.0.1:3901",
                    bootUrl: "http://127.0.0.1:3903",
                    oobiUrl: "http://127.0.0.1:3902"
                },
                qar2: {
                    name: $qar2Name,
                    salt: $qar2Salt,
                    adminUrl: "http://127.0.0.1:4901",
                    bootUrl: "http://127.0.0.1:4903",
                    oobiUrl: "http://127.0.0.1:4902"
                },
                qar3: {
                    name: $qar3Name,
                    salt: $qar3Salt,
                    adminUrl: "http://127.0.0.1:5901",
                    bootUrl: "http://127.0.0.1:5903",
                    oobiUrl: "http://127.0.0.1:5902"
                },
                qar4: {
                    name: $qar4Name,
                    salt: $qar4Salt,
                    adminUrl: "http://127.0.0.1:6901",
                    bootUrl: "http://127.0.0.1:6903",
                    oobiUrl: "http://127.0.0.1:6902"
                },
                person: {
                    name: $personName,
                    salt: $personSalt,
                    adminUrl: "http://127.0.0.1:7901",
                    bootUrl: "http://127.0.0.1:7903",
                    oobiUrl: "http://127.0.0.1:7902"
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

    create_local_keria_configs

    # `:` is a no-op; redirecting it creates or truncates the callback file.
    : > "${SALLY_CALLBACK_FILE}"
}

# Write one KERIA config whose top-level agency name matches `keria start --name`.
write_local_keria_config() {
    local config_file=$1
    local agency_name=$2
    local http_port=$3

    jq -n \
        --arg agencyName "${agency_name}" \
        --arg curl "http://127.0.0.1:${http_port}/" \
        '{
            dt: "2024-12-31T14:06:30.123456+00:00",
            ($agencyName): {
                dt: "2024-12-31T14:06:30.123456+00:00",
                curls: [$curl]
            },
            # Wallet setup introduces the one witness each participant uses.
            # Keeping agency bootstrap empty avoids resolving both witnesses
            # independently in all five KERIA stores.
            iurls: []
        }' > "${config_file}"
}

# Generate distinct agency configs for the five isolated local KERIA instances.
create_local_keria_configs() {
    local config_dir="${WORKFLOW_CONFIG_DIR}/keria/keri/cf"

    mkdir -p "${config_dir}"
    write_local_keria_config \
        "${config_dir}/qar1.json" keria-qar1 3902
    write_local_keria_config \
        "${config_dir}/qar2.json" keria-qar2 4902
    write_local_keria_config \
        "${config_dir}/qar3.json" keria-qar3 5902
    write_local_keria_config \
        "${config_dir}/qar4.json" keria-qar4 6902
    write_local_keria_config \
        "${config_dir}/person.json" keria-person 7902

}

# Return the registry index for a named managed process.
managed_process_index() {
    local process_name=$1
    local index

    for index in "${!WORKFLOW_PROCESS_NAMES[@]}"; do
        if [[ "${WORKFLOW_PROCESS_NAMES[${index}]:-}" == "${process_name}" ]]; then
            printf '%s\n' "${index}"
            return 0
        fi
    done
    return 1
}

# Launch and register a long-running local service with a dedicated log and PID file.
start_managed_process() {
    local process_name=$1
    shift
    local process_log="${WORKFLOW_LOG_DIR}/${process_name}.log"
    local process_pid
    local process_index

    if managed_process_index "${process_name}" >/dev/null; then
        printf 'Managed process %s is already registered\n' \
            "${process_name}" >&2
        return 1
    fi

    # nohup supports retained runs; the launcher restores SIGINT after Bash
    # suppresses it for background commands.
    nohup \
        "${KERIA_PYTHON}" "${SIGNAL_RESET_LAUNCHER}" "$@" \
        > "${process_log}" 2>&1 &
    process_pid=$!
    process_index=${#WORKFLOW_PROCESS_NAMES[@]}
    WORKFLOW_PROCESS_NAMES[${process_index}]="${process_name}"
    WORKFLOW_PROCESS_PIDS[${process_index}]="${process_pid}"
    WORKFLOW_PROCESS_LOGS[${process_index}]="${process_log}"
    printf '%s\n' "${process_pid}" > "${WORKFLOW_PID_DIR}/${process_name}.pid"
}

# Check both process liveness and its HTTP readiness endpoint.
managed_process_is_ready() {
    local process_name=$1
    local health_url=$2
    local process_index
    local process_pid

    process_index=$(managed_process_index "${process_name}") || return 1
    process_pid=${WORKFLOW_PROCESS_PIDS[${process_index}]}
    if ! kill -0 "${process_pid}" 2>/dev/null; then
        printf '%s exited before becoming ready\n' "${process_name}"
        return 1
    fi

    curl \
        --fail \
        --silent \
        --show-error \
        --connect-timeout 1 \
        --max-time 2 \
        "${health_url}" >/dev/null
}

# Wait for a managed process to answer its readiness endpoint.
wait_for_managed_process() {
    local process_name=$1
    local health_url=$2

    poll_until \
        "${process_name} at ${health_url}" \
        "${LOCAL_SERVICE_TIMEOUT_SECONDS:-15}" \
        managed_process_is_ready \
        "${process_name}" \
        "${health_url}" >/dev/null
}

# Start one isolated KERIA agency for the given participant role and port set.
start_local_keria() {
    local role=$1
    local agency_name=$2
    local admin_port=$3
    local http_port=$4
    local boot_port=$5

    start_managed_process \
        "keria-${role}" \
        env \
        "${LOCAL_KERI_TOCK_ENV[@]}" \
        KERI_AGENT_CORS=True \
        KERIA_RELEASER_TIMEOUT=3600 \
        PYTHONUNBUFFERED=1 \
        PYTHONWARNINGS=ignore::SyntaxWarning \
        QVI_KERI_HEAD_DIR="${KERI_HEAD_DIR}" \
        "${KERIA_PYTHON}" "${KERIA_LAUNCHER}" start \
        --admin-http-port "${admin_port}" \
        --http "${http_port}" \
        --boot "${boot_port}" \
        --name "${agency_name}" \
        --base "keria-${role}" \
        --config-dir "${WORKFLOW_CONFIG_DIR}/keria" \
        --config-file "${role}" \
        --loglevel INFO
}

# Fail before startup when any workflow-owned TCP port already has a listener.
assert_local_ports_available() {
    local -a ports=(
        3901 3902 3903
        4901 4902 4903
        5901 5902 5903
        7901 7902 7903
        5642 5643 5644
        7723 8923 9823 9923
    )
    local port
    local listener=""

    if [[ "${WORKFLOW_SCENARIO}" == qar-replacement-regression ]]; then
        ports+=(6901 6902 6903)
    fi
    for port in "${ports[@]}"; do
        listener=$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null || true)
        if [[ -n "${listener}" ]]; then
            printf 'Local workflow port %s is already used by PID %s\n' \
                "${port}" "${listener}" >&2
            return 1
        fi
    done
}

# Start and await schemas, callback recorder, witnesses, and all KERIA agencies.
start_local_foundation_services() {
    assert_local_ports_available || return 1

    start_managed_process \
        vlei-server \
        env PYTHONUNBUFFERED=1 PYTHONWARNINGS=ignore::SyntaxWarning \
        "${VLEI_BIN}" \
        --schema-dir "${DEPENDENCY_DIR}/vlei/schema/acdc" \
        --cred-dir "${DEPENDENCY_DIR}/vlei/samples/acdc" \
        --oobi-dir "${DEPENDENCY_DIR}/vlei/samples/oobis" \
        --loglevel INFO
    start_managed_process \
        callback-recorder \
        env \
        PYTHONUNBUFFERED=1 \
        QVI_CALLBACKS_PATH="${SALLY_CALLBACK_FILE}" \
        QVI_CALLBACK_PORT=9923 \
        "${KERIA_PYTHON}" \
        "${SCRIPT_DIR}/../callback_recorder/recorder.py"
    start_managed_process \
        witnesses \
        env \
        "${LOCAL_KERI_TOCK_ENV[@]}" \
        PYTHONUNBUFFERED=1 \
        PYTHONWARNINGS=ignore::SyntaxWarning \
        "${WITNESS_PYTHON}" \
        "${SCRIPT_DIR}/local-witnesses.py" \
        --head-dir "${WORKFLOW_RUN_DIR}/state" \
        --base witnesses \
        --config-dir "${WORKFLOW_CONFIG_DIR}/witnesses"
    start_managed_process \
        signify-wallet \
        env \
        QVI_OPERATION_TIMEOUT_SECONDS="${WORKFLOW_TIMEOUT_SECONDS}" \
        QVI_WALLET_PORT=8923 \
        "${TSX_BIN}" "${WALLET_SERVER}"

    # KERIA startup does not require the other local HTTP services to be ready.
    # Start all agencies now so their Python imports overlap the readiness waits.
    start_local_keria qar1 keria-qar1 3901 3902 3903 || return 1
    start_local_keria qar2 keria-qar2 4901 4902 4903 || return 1
    start_local_keria qar3 keria-qar3 5901 5902 5903 || return 1
    if [[ "${WORKFLOW_SCENARIO}" == qar-replacement-regression ]]; then
        start_local_keria qar4 keria-qar4 6901 6902 6903 || return 1
    fi
    start_local_keria person keria-person 7901 7902 7903 || return 1

    wait_for_managed_process \
        vlei-server \
        "http://127.0.0.1:7723/oobi/EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao" ||
        return 1
    wait_for_managed_process \
        callback-recorder http://127.0.0.1:9923/health ||
        return 1
    wait_for_managed_process witnesses http://127.0.0.1:5642/oobi ||
        return 1
    wait_for_managed_process witnesses http://127.0.0.1:5643/oobi ||
        return 1
    wait_for_managed_process witnesses http://127.0.0.1:5644/oobi ||
        return 1
    wait_for_managed_process \
        signify-wallet http://127.0.0.1:8923/health ||
        return 1

    wait_for_managed_process \
        keria-qar1 http://127.0.0.1:3902/spec.yaml || return 1
    wait_for_managed_process \
        keria-qar2 http://127.0.0.1:4902/spec.yaml || return 1
    wait_for_managed_process \
        keria-qar3 http://127.0.0.1:5902/spec.yaml || return 1
    if [[ "${WORKFLOW_SCENARIO}" == qar-replacement-regression ]]; then
        wait_for_managed_process \
            keria-qar4 http://127.0.0.1:6902/spec.yaml || return 1
    fi
    wait_for_managed_process \
        keria-person http://127.0.0.1:7902/spec.yaml
}

# Start direct-mode Sally after the GEDA identifier is available for authorization.
start_local_sally() {
    local geda_prefix=$1

    start_managed_process \
        sally \
        env \
        "${LOCAL_KERI_TOCK_ENV[@]}" \
        PYTHONUNBUFFERED=1 \
        PYTHONWARNINGS=ignore::SyntaxWarning \
        QVI_KERI_HEAD_DIR="${KERI_HEAD_DIR}" \
        "${SALLY_PYTHON}" "${SALLY_LAUNCHER}" server start \
        --direct \
        --http 9823 \
        --name "${SALLY_KS_NAME}" \
        --base "${SALLY_BASE}" \
        --alias "${SALLY_ALIAS}" \
        --salt "${SALLY_SALT}" \
        --passcode "${SALLY_PASSCODE}" \
        --config-dir "${WORKFLOW_CONFIG_DIR}/sally" \
        --config-file sally.json \
        --incept-file sally-incept-no-wits.json \
        --web-hook "${WEBHOOK_HOST}" \
        --auth "${geda_prefix}" \
        --retry-delay 1 \
        --loglevel INFO
    wait_for_managed_process sally http://127.0.0.1:9823/health
}

# Print bounded tails from local service and background-job logs after failure.
print_failure_diagnostics() {
    local job_log
    local process_log

    print_red "Recent local service logs:"
    for process_log in "${WORKFLOW_LOG_DIR}"/*.log; do
        [[ -f "${process_log}" ]] || continue
        case "${process_log}" in
            *.out.log|*.err.log) continue ;;
        esac
        printf '\n--- %s ---\n' "${process_log##*/}" >&2
        tail -n 100 "${process_log}" >&2
    done

    print_red "Recent workflow job logs:"
    for job_log in "${WORKFLOW_LOG_DIR}"/*.log; do
        [[ -f "${job_log}" ]] || continue
        case "${job_log}" in
            *.out.log|*.err.log) ;;
            *) continue ;;
        esac
        printf '\n--- %s ---\n' "${job_log##*/}" >&2
        tail -n 100 "${job_log}" >&2
    done
}

# Report whether any registered managed process remains alive.
managed_processes_are_running() {
    local index
    local process_pid

    for index in "${!WORKFLOW_PROCESS_NAMES[@]}"; do
        [[ -n "${WORKFLOW_PROCESS_NAMES[${index}]:-}" ]] || continue
        process_pid=${WORKFLOW_PROCESS_PIDS[${index}]}
        if workflow_process_is_running "${process_pid}"; then
            return 0
        fi
    done
    return 1
}

# Give registered processes a short common grace period to stop.
wait_for_managed_processes_to_stop() {
    local timeout_seconds=$1
    local deadline=$((SECONDS + timeout_seconds))

    while managed_processes_are_running; do
        [[ "${SECONDS}" -ge "${deadline}" ]] && return 1
        sleep 0.1
    done
}

# Stop every managed service, preserving SIGINT for HIO KeyboardInterrupt cleanup.
stop_all_managed_processes() {
    local signal_name=${1:-TERM}
    local index
    local process_pid

    # First, give every service the original signal. SIGINT is important here:
    # HIO translates it into KeyboardInterrupt and runs its normal shutdown.
    for index in "${!WORKFLOW_PROCESS_NAMES[@]}"; do
        [[ -n "${WORKFLOW_PROCESS_NAMES[${index}]:-}" ]] || continue
        process_pid=${WORKFLOW_PROCESS_PIDS[${index}]}
        signal_workflow_process_tree "${signal_name}" "${process_pid}"
    done

    # Escalate an unresponsive SIGINT/HUP process to TERM only after all
    # services shared the same five-second cleanup window.
    if ! wait_for_managed_processes_to_stop 5; then
        if [[ "${signal_name}" != TERM ]]; then
            for index in "${!WORKFLOW_PROCESS_NAMES[@]}"; do
                [[ -n "${WORKFLOW_PROCESS_NAMES[${index}]:-}" ]] || continue
                process_pid=${WORKFLOW_PROCESS_PIDS[${index}]}
                signal_workflow_process_tree TERM "${process_pid}"
            done
            wait_for_managed_processes_to_stop 1 || true
        fi
    fi

    # KILL is the final bounded fallback. Always wait so Bash reaps each child.
    for index in "${!WORKFLOW_PROCESS_NAMES[@]}"; do
        [[ -n "${WORKFLOW_PROCESS_NAMES[${index}]:-}" ]] || continue
        process_pid=${WORKFLOW_PROCESS_PIDS[${index}]}
        if workflow_process_is_running "${process_pid}"; then
            signal_workflow_process_tree KILL "${process_pid}"
        fi
        wait "${process_pid}" 2>/dev/null || true
    done
}

# Cancel active work, stop services, then preserve or remove artifacts.
workflow_cleanup() {
    local original_status=$1
    local cleanup_status=0
    local workflow_failed=false
    local artifacts_should_be_kept=false

    [[ "${original_status}" -ne 0 ]] && workflow_failed=true
    [[ "${KEEP_ARTIFACTS:-false}" == true ]] && artifacts_should_be_kept=true

    if [[ "${workflow_failed}" == true &&
          -z "${WORKFLOW_CLEANUP_SIGNAL}" ]]; then
        print_failure_diagnostics
    fi

    cancel_jobs

    stop_all_managed_processes "${WORKFLOW_CLEANUP_SIGNAL:-TERM}" ||
        cleanup_status=$?
    if [[ "${artifacts_should_be_kept}" == true ]]; then
        print_yellow "Artifacts retained at ${WORKFLOW_RUN_DIR}"
    else
        rm -rf "${WORKFLOW_RUN_DIR}"
    fi

    if [[ "${original_status}" -ne 0 ]]; then
        return "${original_status}"
    fi
    return "${cleanup_status}"
}

# Run cleanup exactly once from the EXIT trap and preserve the originating status.
handle_workflow_exit() {
    local original_status=$?
    local final_status=0

    trap - EXIT INT TERM HUP

    workflow_cleanup "${original_status}" || final_status=$?
    exit "${final_status}"
}

# Record the received signal so cleanup can propagate it to every owned process.
handle_workflow_signal() {
    local signal_name=$1
    local signal_status

    WORKFLOW_CLEANUP_SIGNAL="${signal_name}"
    signal_status=$(workflow_signal_status "${signal_name}")
    exit "${signal_status}"
}

# Install workflow-wide exit and signal traps.
install_workflow_traps() {
    trap 'handle_workflow_exit' EXIT
    trap 'handle_workflow_signal INT' INT
    trap 'handle_workflow_signal TERM' TERM
    trap 'handle_workflow_signal HUP' HUP
}

# Poll a named predicate until success or a shared absolute deadline.
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

        sleep "${WORKFLOW_POLL_INTERVAL_SECONDS}"
    done

    printf 'Timed out after %ss waiting for %s. Last observation: %s\n' \
        "${timeout_seconds}" "${description}" "${last_observation}" >&2
    return 1
}
