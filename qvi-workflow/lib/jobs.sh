#!/usr/bin/env bash

# Minimal fixed-wave job lifecycle for the shared workflow.

JOB_NAMES=("")
JOB_PIDS=("")
JOB_STDOUTS=("")
JOB_STDERRS=("")
: "${JOB_POLL_SECONDS:=0.01}"

job_process_is_running() {
    local pid=$1
    local state=""

    kill -0 "${pid}" 2>/dev/null || return 1
    state=$(ps -p "${pid}" -o stat= 2>/dev/null || true)
    [[ -n "${state}" && "${state}" != Z* ]]
}

signal_job_tree() {
    local signal_name=$1
    local parent_pid=$2
    local child_pid

    while IFS= read -r child_pid; do
        [[ -n "${child_pid}" ]] || continue
        signal_job_tree "${signal_name}" "${child_pid}"
    done < <(pgrep -P "${parent_pid}" 2>/dev/null || true)
    kill "-${signal_name}" "${parent_pid}" 2>/dev/null || true
}

job_index() {
    local requested_name=$1
    local index

    for ((index = 1; index < ${#JOB_NAMES[@]}; index += 1)); do
        if [[ "${JOB_NAMES[$index]:-}" == "${requested_name}" ]]; then
            printf '%s\n' "${index}"
            return 0
        fi
    done
    return 1
}

start_job() {
    local name=$1
    shift
    local stdout_file="${WORKFLOW_LOG_DIR}/${name}.stdout.log"
    local stderr_file="${WORKFLOW_LOG_DIR}/${name}.stderr.log"
    local index

    if job_index "${name}" >/dev/null; then
        printf 'Job name is already active: %s\n' "${name}" >&2
        return 1
    fi
    if [[ $# -eq 0 ]]; then
        printf 'Job %s has no command\n' "${name}" >&2
        return 1
    fi

    ("$@") >"${stdout_file}" 2>"${stderr_file}" &
    index=${#JOB_NAMES[@]}
    JOB_NAMES[$index]=${name}
    JOB_PIDS[$index]=$!
    JOB_STDOUTS[$index]=${stdout_file}
    JOB_STDERRS[$index]=${stderr_file}
}

replay_job_logs() {
    local index=$1
    local stdout_file=${JOB_STDOUTS[$index]}
    local stderr_file=${JOB_STDERRS[$index]}

    [[ ! -s "${stdout_file}" ]] || cat "${stdout_file}"
    [[ ! -s "${stderr_file}" ]] || cat "${stderr_file}" >&2
}

finish_job() {
    local index=$1
    local status=0

    if wait "${JOB_PIDS[$index]}"; then
        status=0
    else
        status=$?
    fi
    replay_job_logs "${index}"
    JOB_NAMES[$index]=""
    JOB_PIDS[$index]=""
    JOB_STDOUTS[$index]=""
    JOB_STDERRS[$index]=""
    return "${status}"
}

cancel_jobs() {
    local index
    local pid

    for ((index = 1; index < ${#JOB_NAMES[@]}; index += 1)); do
        [[ -n "${JOB_NAMES[$index]:-}" ]] || continue
        pid=${JOB_PIDS[$index]}
        if job_process_is_running "${pid}"; then
            signal_job_tree TERM "${pid}"
        fi
    done
    for ((index = 1; index < ${#JOB_NAMES[@]}; index += 1)); do
        [[ -n "${JOB_NAMES[$index]:-}" ]] || continue
        wait "${JOB_PIDS[$index]}" 2>/dev/null || true
        replay_job_logs "${index}"
        JOB_NAMES[$index]=""
        JOB_PIDS[$index]=""
        JOB_STDOUTS[$index]=""
        JOB_STDERRS[$index]=""
    done
}

wait_jobs() {
    local deadline=$((SECONDS + WORKFLOW_TIMEOUT_SECONDS))
    local -a pending_names=("$@")
    local requested_name
    local pending_index
    local index
    local remaining=${#pending_names[@]}
    local status

    while ((remaining > 0)); do
        for pending_index in "${!pending_names[@]}"; do
            requested_name=${pending_names[$pending_index]}
            [[ -n "${requested_name}" ]] || continue
            index=$(job_index "${requested_name}") || {
                printf 'Unknown active job: %s\n' "${requested_name}" >&2
                cancel_jobs
                return 1
            }
            if job_process_is_running "${JOB_PIDS[$index]}"; then
                continue
            fi
            status=0
            finish_job "${index}" || status=$?
            if [[ "${status}" -ne 0 ]]; then
                printf 'Job %s failed with status %s\n' \
                    "${requested_name}" "${status}" >&2
                cancel_jobs
                return "${status}"
            fi
            pending_names[$pending_index]=""
            remaining=$((remaining - 1))
        done
        ((remaining == 0)) && return 0
        if [[ "${SECONDS}" -ge "${deadline}" ]]; then
            printf 'Jobs exceeded the common %ss deadline: %s\n' \
                "${WORKFLOW_TIMEOUT_SECONDS}" "$*" >&2
            cancel_jobs
            return 124
        fi
        sleep "${JOB_POLL_SECONDS}"
    done
}
