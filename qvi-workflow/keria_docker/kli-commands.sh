#!/usr/bin/env bash

# Compose-backed command adapters used by vlei-workflow.sh.

kli() {
    local command_name="kli:${1:-unknown}"

    # Include a nested subcommand such as "challenge:verify", but do not turn
    # the first option of a flat command into part of its timing label.
    case "${2:-}" in
        ""|-*) ;;
        *) command_name="${command_name}:${2}" ;;
    esac

    run_workflow_command \
        command "${command_name}" "" \
        workflow_compose exec -T kli kli "$@"
}

klid() {
    local logical_name=$1
    shift
    start_workflow_job \
        "${logical_name}" "${logical_name}" kli "$@"
}

sig_tsx() {
    workflow_compose exec -T signify tsx "$@"
}

wait_kli_jobs() {
    wait_for_background_jobs "$@"
}
