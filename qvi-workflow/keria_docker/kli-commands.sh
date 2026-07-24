#!/usr/bin/env bash

# Compose-backed command adapters used by vlei-workflow.sh.

kli() {
    workflow_compose run --rm --no-deps -T kli "$@"
}

klid() {
    local logical_name=$1
    shift
    run_background_compose_job kli "${logical_name}" "$@"
}

sig_tsx() {
    run_background_compose_job signify signify-run "$@" ||
        return 1
    wait_for_background_job signify-run
}

wait_kli_jobs() {
    wait_for_background_jobs "$@"
}
