#!/usr/bin/env bash

# Compose-backed command adapters used by vlei-workflow.sh.

kli() {
    workflow_compose run --rm --no-deps -T kli "$@"
}

klid() {
    local logical_name=$1
    shift
    run_detached_compose_job kli "${logical_name}" "$@"
}

kli2() {
    workflow_compose run --rm --no-deps -T kli2 "$@"
}

kli2d() {
    local logical_name=$1
    shift
    run_detached_compose_job kli2 "${logical_name}" "$@"
}

sig_tsx() {
    workflow_compose run --rm --no-deps -T signify "$@"
}

wait_kli_jobs() {
    wait_for_compose_jobs "$@"
}
