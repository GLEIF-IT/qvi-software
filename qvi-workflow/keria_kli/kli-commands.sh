#!/usr/bin/env bash

# Host command adapters used by vlei-workflow.sh.

# Return success when a KLI command needs the workflow's isolated LMDB base.
kli_uses_state() {
    case "${1:-}:${2:-}" in
        version:*|nonce:*|saidify:*|time:*|challenge:generate)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# Run KLI Python with isolated state and localhost scheduler cadences.
run_local_kli_python() {
    run_interruptible_process \
        env \
        "${LOCAL_KERI_TOCK_ENV[@]}" \
        "${LOCAL_KLI_TOCK_ENV[@]}" \
        QVI_KERI_HEAD_DIR="${KLI_HEAD_DIR}" \
        "$@"
}

# Return the wallet name from a KLI-style argument list, when one is present.
kli_wallet_name() {
    while (( $# > 0 )); do
        if [[ "$1" == "--name" ]]; then
            [[ $# -ge 2 ]] || return 1
            printf '%s\n' "$2"
            return 0
        fi
        shift
    done
}

# Select the legacy GEDA runtime without hiding the choice in call sites.
kli_python_for_wallet() {
    local wallet_name=$1

    if [[ -n "${GAR1:-}" && "${wallet_name}" == "${GAR1}" ]] ||
       [[ -n "${GAR2:-}" && "${wallet_name}" == "${GAR2}" ]]; then
        printf '%s\n' "${GEDA_KLI_PYTHON}"
        return
    fi
    printf '%s\n' "${KLI_PYTHON}"
}

# Run one canonical KLI command in a normal short-lived process.
run_local_kli() {
    local wallet_name
    local python_path

    wallet_name=$(kli_wallet_name "$@" || true)
    python_path=$(kli_python_for_wallet "${wallet_name}") || return 1
    run_local_kli_python "${python_path}" "${KLI_LAUNCHER}" "$@"
}

# Run one KLI command with the correct isolated-state policy.
kli() {
    if kli_uses_state "$@"; then
        run_local_kli "$@" --base "${KLI_BASE}"
    else
        run_local_kli "$@"
    fi
}

# Start a named KLI background job whose logical name is also its resource lane.
klid() {
    local logical_name=$1
    shift
    start_workflow_job \
        "${logical_name}" "${logical_name}" kli "$@"
}

# Send one argument vector to the stateful local Signify wallet.
sig_wallet_request() {
    local request_json
    local request_timeout=$((WORKFLOW_TIMEOUT_SECONDS + 2))

    request_json=$(jq -nc --args '$ARGS.positional' -- "$@") || return 1
    curl \
        --fail-with-body \
        --silent \
        --show-error \
        --connect-timeout 1 \
        --max-time "${request_timeout}" \
        --header 'content-type: application/json' \
        --data "$(jq -nc --argjson argv "${request_json}" '{argv: $argv}')" \
        http://127.0.0.1:8923/run
}

# Wait for a group of KLI jobs under one shared deadline.
wait_kli_jobs() {
    wait_for_background_jobs "$@"
}
