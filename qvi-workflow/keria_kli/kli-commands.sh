#!/usr/bin/env bash

# Host command adapters used by vlei-workflow.sh.

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

run_local_kli() {
    QVI_KERI_HEAD_DIR="${KLI_HEAD_DIR}" \
        "${KLI_PYTHON}" "${KLI_LAUNCHER}" "$@"
}

kli() {
    local command_name="kli:${1:-unknown}"

    # Include a nested subcommand such as "challenge:verify", but do not turn
    # the first option of a flat command into part of its timing label.
    case "${2:-}" in
        ""|-*) ;;
        *) command_name="${command_name}:${2}" ;;
    esac

    if kli_uses_state "$@"; then
        run_workflow_command \
            command "${command_name}" "" \
            run_local_kli "$@" --base "${KLI_BASE}"
    else
        run_workflow_command \
            command "${command_name}" "" \
            run_local_kli "$@"
    fi
}

klid() {
    local logical_name=$1
    shift
    start_workflow_job \
        "${logical_name}" "${logical_name}" kli "$@"
}

sig_tsx() {
    QVI_OPERATION_TIMEOUT_SECONDS="${WORKFLOW_TIMEOUT_SECONDS}" \
        "${TSX_BIN}" "$@"
}

wait_kli_jobs() {
    wait_for_background_jobs "$@"
}
