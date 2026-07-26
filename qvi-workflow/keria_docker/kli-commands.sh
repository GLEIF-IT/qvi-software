#!/usr/bin/env bash

# Compose-backed command adapters used by vlei-workflow.sh.

kli() {
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
