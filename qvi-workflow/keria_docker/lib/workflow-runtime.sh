#!/usr/bin/env bash

# Runtime support for vlei-workflow.sh.  This file intentionally uses only
# Bash 3.2 features so the workflow runs with the Bash shipped by macOS.

WORKFLOW_RUNTIME_SENTINEL_NAME=".qvi-workflow-owned"
WORKFLOW_RUNTIME_SENTINEL_VALUE="qvi-workflow-private-runtime-v1"
WORKFLOW_CLEANING_UP=false
WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST=false
WORKFLOW_JOB_SEQUENCE=0

runtime_canonical_path() {
    local candidate_path=$1
    local canonical_path

    canonical_path=$(cd "${candidate_path}" 2>/dev/null && pwd -P)
    printf '%s\n' "${canonical_path}"
}

runtime_parent_path_is_safe() {
    local candidate_path=$1
    local canonical_candidate=""
    local canonical_home=""
    local canonical_repository_root=""
    local candidate_is_safe=true
    local home_is_available=false
    local repository_root_is_available=false

    canonical_candidate=$(runtime_canonical_path "${candidate_path}") ||
        candidate_is_safe=false
    [[ -n "${HOME:-}" ]] && home_is_available=true
    if [[ "${home_is_available}" == true ]]; then
        canonical_home=$(runtime_canonical_path "${HOME}") ||
            candidate_is_safe=false
    fi
    [[ -n "${WORKFLOW_REPOSITORY_ROOT:-}" ]] &&
        repository_root_is_available=true
    if [[ "${repository_root_is_available}" == true ]]; then
        canonical_repository_root=$(runtime_canonical_path "${WORKFLOW_REPOSITORY_ROOT}") ||
            candidate_is_safe=false
    fi

    [[ -n "${canonical_candidate}" ]] || candidate_is_safe=false
    [[ "${canonical_candidate}" != "/" ]] || candidate_is_safe=false
    [[ -z "${canonical_home}" || "${canonical_candidate}" != "${canonical_home}" ]] ||
        candidate_is_safe=false
    [[ "${canonical_candidate}" != "${SCRIPT_DIR}" ]] || candidate_is_safe=false
    [[ -z "${canonical_repository_root}" ||
       "${canonical_candidate}" != "${canonical_repository_root}" ]] ||
        candidate_is_safe=false

    [[ "${candidate_is_safe}" == true ]]
}

runtime_path_is_owned() {
    local candidate_path=$1
    local canonical_candidate=""
    local canonical_candidate_parent=""
    local canonical_home=""
    local canonical_parent=""
    local canonical_repository_root=""
    local candidate_name=""
    local candidate_path_was_resolved=false
    local candidate_is_symlink=false
    local home_is_available=false
    local repository_root_is_available=false
    local sentinel_path=""
    local sentinel_value=""
    local sentinel_exists=false
    local sentinel_is_regular_file=false
    local path_is_safe=true

    [[ -L "${candidate_path}" ]] && candidate_is_symlink=true
    canonical_candidate=$(runtime_canonical_path "${candidate_path}") || path_is_safe=false
    canonical_parent=$(runtime_canonical_path "${WORKFLOW_RUNTIME_PARENT}") || path_is_safe=false
    [[ -n "${HOME:-}" ]] && home_is_available=true
    if [[ "${home_is_available}" == true ]]; then
        canonical_home=$(runtime_canonical_path "${HOME}") || path_is_safe=false
    fi
    [[ -n "${WORKFLOW_REPOSITORY_ROOT:-}" ]] &&
        repository_root_is_available=true
    if [[ "${repository_root_is_available}" == true ]]; then
        canonical_repository_root=$(runtime_canonical_path "${WORKFLOW_REPOSITORY_ROOT}") ||
            path_is_safe=false
    fi
    [[ -n "${canonical_candidate}" ]] && candidate_path_was_resolved=true
    if [[ "${candidate_path_was_resolved}" == true ]]; then
        canonical_candidate_parent=$(dirname "${canonical_candidate}")
        candidate_name=$(basename "${canonical_candidate}")
    fi

    [[ -n "${canonical_candidate}" ]] || path_is_safe=false
    [[ "${candidate_is_symlink}" == false ]] || path_is_safe=false
    [[ "${canonical_candidate}" != "/" ]] || path_is_safe=false
    [[ -z "${canonical_home}" || "${canonical_candidate}" != "${canonical_home}" ]] ||
        path_is_safe=false
    [[ "${canonical_candidate}" != "${SCRIPT_DIR}" ]] || path_is_safe=false
    [[ -z "${canonical_repository_root}" ||
       "${canonical_candidate}" != "${canonical_repository_root}" ]] ||
        path_is_safe=false
    [[ "${canonical_candidate_parent}" == "${canonical_parent}" ]] ||
        path_is_safe=false
    case "${candidate_name}" in
        run.*) ;;
        *) path_is_safe=false ;;
    esac

    sentinel_path="${canonical_candidate}/${WORKFLOW_RUNTIME_SENTINEL_NAME}"
    [[ -f "${sentinel_path}" ]] && sentinel_exists=true
    [[ "${sentinel_exists}" == true && ! -L "${sentinel_path}" ]] &&
        sentinel_is_regular_file=true
    [[ "${sentinel_exists}" == true ]] || path_is_safe=false
    [[ "${sentinel_is_regular_file}" == true ]] || path_is_safe=false
    if [[ "${sentinel_is_regular_file}" == true ]]; then
        sentinel_value=$(<"${sentinel_path}")
        [[ "${sentinel_value}" == "${WORKFLOW_RUNTIME_SENTINEL_VALUE}" ]] || path_is_safe=false
    fi

    [[ "${path_is_safe}" == true ]]
}

create_workflow_runtime() {
    local run_identifier
    local runtime_parent_is_safe=false

    WORKFLOW_RUNTIME_PARENT=${QVI_RUNTIME_PARENT:-"${TMPDIR:-/tmp}/qvi-workflow"}
    mkdir -p "${WORKFLOW_RUNTIME_PARENT}"
    WORKFLOW_RUNTIME_PARENT=$(cd "${WORKFLOW_RUNTIME_PARENT}" && pwd -P)
    runtime_parent_path_is_safe "${WORKFLOW_RUNTIME_PARENT}" &&
        runtime_parent_is_safe=true
    if [[ "${runtime_parent_is_safe}" == false ]]; then
        printf 'Refusing unsafe workflow runtime parent: %s\n' \
            "${WORKFLOW_RUNTIME_PARENT}" >&2
        return 1
    fi
    chmod 700 "${WORKFLOW_RUNTIME_PARENT}"

    WORKFLOW_RUN_DIR=$(mktemp -d "${WORKFLOW_RUNTIME_PARENT}/run.XXXXXX")
    WORKFLOW_RUN_DIR=$(cd "${WORKFLOW_RUN_DIR}" && pwd -P)
    chmod 700 "${WORKFLOW_RUN_DIR}"
    printf '%s\n' "${WORKFLOW_RUNTIME_SENTINEL_VALUE}" \
        > "${WORKFLOW_RUN_DIR}/${WORKFLOW_RUNTIME_SENTINEL_NAME}"
    chmod 600 "${WORKFLOW_RUN_DIR}/${WORKFLOW_RUNTIME_SENTINEL_NAME}"

    WORKFLOW_CONFIG_DIR="${WORKFLOW_RUN_DIR}/config"
    KLI_DATA_DIR="${WORKFLOW_RUN_DIR}/acdc-info"
    LOCAL_QVI_DATA_DIR="${WORKFLOW_RUN_DIR}/qvi_data"
    KEYSTORE_DIR="${WORKFLOW_RUN_DIR}/keystores"
    WORKFLOW_SECRET_DIR="${WORKFLOW_RUN_DIR}/secrets"
    WORKFLOW_LOG_DIR="${WORKFLOW_RUN_DIR}/logs"
    WORKFLOW_JOB_DIR="${WORKFLOW_RUN_DIR}/jobs"

    mkdir -p \
        "${WORKFLOW_CONFIG_DIR}" \
        "${KLI_DATA_DIR}" \
        "${LOCAL_QVI_DATA_DIR}" \
        "${KEYSTORE_DIR}" \
        "${WORKFLOW_SECRET_DIR}" \
        "${WORKFLOW_LOG_DIR}" \
        "${WORKFLOW_JOB_DIR}"
    chmod 700 \
        "${WORKFLOW_CONFIG_DIR}" \
        "${KLI_DATA_DIR}" \
        "${LOCAL_QVI_DATA_DIR}" \
        "${KEYSTORE_DIR}" \
        "${WORKFLOW_SECRET_DIR}" \
        "${WORKFLOW_LOG_DIR}" \
        "${WORKFLOW_JOB_DIR}"

    cp -R "${SCRIPT_DIR}/config/." "${WORKFLOW_CONFIG_DIR}/"
    mkdir -p "${WORKFLOW_CONFIG_DIR}/direct-sally/keri/cf"
    cp \
        "${SCRIPT_DIR}/direct-sally/keri/cf/direct-sally.json" \
        "${WORKFLOW_CONFIG_DIR}/direct-sally/keri/cf/direct-sally.json"
    cp \
        "${SCRIPT_DIR}/direct-sally/sally-incept-no-wits.json" \
        "${WORKFLOW_CONFIG_DIR}/direct-sally/sally-incept-no-wits.json"
    chmod 600 \
        "${WORKFLOW_CONFIG_DIR}/direct-sally/keri/cf/direct-sally.json" \
        "${WORKFLOW_CONFIG_DIR}/direct-sally/sally-incept-no-wits.json"
    rm -f \
        "${WORKFLOW_CONFIG_DIR}/multi-sig-incept-config.json" \
        "${WORKFLOW_CONFIG_DIR}/multi-sig-delegated-incept-config.json" \
        "${WORKFLOW_CONFIG_DIR}/single-sig-incept-config.json"
    mkdir -p "${KLI_DATA_DIR}/rules" "${KLI_DATA_DIR}/temp-data"
    cp -R "${SCRIPT_DIR}/acdc-info/rules/." "${KLI_DATA_DIR}/rules/"

    PARTICIPANT_CONFIG_FILE="${WORKFLOW_SECRET_DIR}/participants.json"
    COMPOSE_ENV_FILE="${WORKFLOW_SECRET_DIR}/compose.env"
    PROOF_SECRET_VALUES_FILE="${WORKFLOW_SECRET_DIR}/proof-secret-values"
    : > "${PARTICIPANT_CONFIG_FILE}"
    : > "${COMPOSE_ENV_FILE}"
    : > "${PROOF_SECRET_VALUES_FILE}"
    chmod 600 \
        "${PARTICIPANT_CONFIG_FILE}" \
        "${COMPOSE_ENV_FILE}" \
        "${PROOF_SECRET_VALUES_FILE}"

    run_identifier=$(basename "${WORKFLOW_RUN_DIR}" | tr '.[:upper:]' '-[:lower:]')
    COMPOSE_PROJECT_NAME="qvi-${run_identifier}"
    export COMPOSE_PROJECT_NAME
    export WORKFLOW_RUN_DIR WORKFLOW_CONFIG_DIR KLI_DATA_DIR LOCAL_QVI_DATA_DIR
    export KEYSTORE_DIR PARTICIPANT_CONFIG_FILE COMPOSE_ENV_FILE WORKFLOW_SECRET_DIR
    export PROOF_SECRET_VALUES_FILE

    QVI_PROOF_ROOT=${QVI_PROOF_ROOT:-"${SCRIPT_DIR}/proofs"}
    WORKFLOW_PROOF_DIR="${QVI_PROOF_ROOT}/${run_identifier}"
    mkdir -p "${WORKFLOW_PROOF_DIR}"
    chmod 700 "${WORKFLOW_PROOF_DIR}"
    PROOF_MANIFEST="${WORKFLOW_PROOF_DIR}/manifest.jsonl"
    PROOF_SUMMARY="${WORKFLOW_PROOF_DIR}/summary.json"
    : > "${PROOF_MANIFEST}"
    : > "${PROOF_SUMMARY}"
    chmod 600 "${PROOF_MANIFEST}" "${PROOF_SUMMARY}"
    SALLY_CALLBACK_FILE="${WORKFLOW_PROOF_DIR}/sally-callbacks.jsonl"
    DIRECT_SALLY_LOG_FILE="${WORKFLOW_PROOF_DIR}/direct-sally.log"
    : > "${SALLY_CALLBACK_FILE}"
    : > "${DIRECT_SALLY_LOG_FILE}"
    chmod 600 "${SALLY_CALLBACK_FILE}" "${DIRECT_SALLY_LOG_FILE}"

    WORKFLOW_UID=$(id -u)
    WORKFLOW_GID=$(id -g)
    export WORKFLOW_PROOF_DIR PROOF_MANIFEST PROOF_SUMMARY
    export SALLY_CALLBACK_FILE DIRECT_SALLY_LOG_FILE WORKFLOW_UID WORKFLOW_GID
}

register_proof_secret_values() {
    local secret_value
    local secret_value_is_valid=false
    local secret_file_is_available=false

    [[ -n "${PROOF_SECRET_VALUES_FILE:-}" &&
       -f "${PROOF_SECRET_VALUES_FILE:-}" ]] &&
        secret_file_is_available=true
    if [[ "${secret_file_is_available}" == false ]]; then
        printf 'Proof secret registry is unavailable.\n' >&2
        return 1
    fi

    for secret_value in "$@"; do
        secret_value_is_valid=false
        [[ -n "${secret_value}" &&
           "${#secret_value}" -ge 8 ]] &&
            secret_value_is_valid=true
        if [[ "${secret_value_is_valid}" == false ]]; then
            printf 'Refusing to register an empty or short proof secret.\n' >&2
            return 1
        fi
        printf '%s\n' "${secret_value}" >> "${PROOF_SECRET_VALUES_FILE}"
    done
}

proof_record_contains_registered_secret() {
    local record_json=$1
    local secret_value
    local secret_file_is_available=false
    local registered_secret_was_found=false

    [[ -n "${PROOF_SECRET_VALUES_FILE:-}" &&
       -f "${PROOF_SECRET_VALUES_FILE:-}" ]] &&
        secret_file_is_available=true
    if [[ "${secret_file_is_available}" == false ]]; then
        return 1
    fi

    while IFS= read -r secret_value; do
        [[ -n "${secret_value}" &&
           "${record_json}" == *"${secret_value}"* ]] &&
            registered_secret_was_found=true
    done < "${PROOF_SECRET_VALUES_FILE}"

    [[ "${registered_secret_was_found}" == true ]]
}

append_proof_record() {
    local record_json=$1
    local record_is_valid=false
    local record_contains_secret=false

    printf '%s\n' "${record_json}" |
        jq -e '
            type == "object" and
            (
                [
                    paths as $path |
                    $path[-1] |
                    select(type == "string") |
                    ascii_downcase |
                    select(
                        test("(salt|passcode|seed|words)$") or
                        . == "challenge"
                    )
                ] |
                length == 0
            )
        ' >/dev/null 2>&1 &&
        record_is_valid=true
    proof_record_contains_registered_secret "${record_json}" &&
        record_contains_secret=true
    if [[ "${record_contains_secret}" == true ]]; then
        record_is_valid=false
    fi
    if [[ "${record_is_valid}" == false ]]; then
        printf 'Refusing to append an invalid proof record\n' >&2
        return 1
    fi

    printf '%s\n' "${record_json}" | jq -c '.' >> "${PROOF_MANIFEST}"
}

write_proof_summary() {
    local workflow_status=$1
    local duration_seconds=$2
    local temporary_summary="${PROOF_SUMMARY}.tmp"
    local summary_was_written=false

    jq -s \
        --arg status "${workflow_status}" \
        --argjson durationSeconds "${duration_seconds}" \
        '{
            status: $status,
            durationSeconds: $durationSeconds,
            runtime: ([.[] | select(.type == "runtime")] | last),
            dependencies: [.[] | select(.type == "dependency")],
            detachedJobs: [.[] | select(.type == "kli-job")],
            challenges: [.[] | select(.type == "challenge")],
            qviState: ([.[] | select(.type == "qvi-state")] | last),
            qviOperations: [.[] | select(.type == "qvi-operation")],
            credentials: [.[] | select(.type == "credential")],
            sallyEvidence: [.[] | select(.type == "sally-evidence")]
        }' \
        "${PROOF_MANIFEST}" > "${temporary_summary}" &&
        summary_was_written=true
    if [[ "${summary_was_written}" == false ]]; then
        rm -f "${temporary_summary}"
        return 1
    fi

    chmod 600 "${temporary_summary}"
    mv "${temporary_summary}" "${PROOF_SUMMARY}"
}

remove_owned_runtime() {
    local candidate_path=$1
    local runtime_is_owned=false

    runtime_path_is_owned "${candidate_path}" && runtime_is_owned=true
    if [[ "${runtime_is_owned}" == false ]]; then
        printf 'Refusing to remove unowned runtime path: %s\n' "${candidate_path}" >&2
        return 1
    fi

    rm -rf -- "${candidate_path}"
}

workflow_compose() {
    docker compose \
        --project-name "${COMPOSE_PROJECT_NAME}" \
        --env-file "${COMPOSE_ENV_FILE}" \
        --file "${DOCKER_COMPOSE_FILE}" \
        "$@"
}

redact_registered_secret_values() {
    local output_line=""
    local redacted_line=""
    local secret_value=""
    local secret_file_is_available=false

    [[ -n "${PROOF_SECRET_VALUES_FILE:-}" &&
       -f "${PROOF_SECRET_VALUES_FILE:-}" ]] &&
        secret_file_is_available=true

    while IFS= read -r output_line || [[ -n "${output_line}" ]]; do
        redacted_line=${output_line}
        if [[ "${secret_file_is_available}" == true ]]; then
            while IFS= read -r secret_value; do
                if [[ -n "${secret_value}" ]]; then
                    redacted_line=${redacted_line//"${secret_value}"/<redacted>}
                fi
            done < "${PROOF_SECRET_VALUES_FILE}"
        fi
        printf '%s\n' "${redacted_line}"
    done
}

redact_stream() {
    sed -E \
        -e 's/((SALT|PASSCODE|SEED|WORDS|CHALLENGE)[A-Za-z0-9_]*[=:])[[:space:]]*[^[:space:]]+/\1<redacted>/Ig' \
        -e 's/("(salt|passcode|seed|words|challenge)"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"<redacted>"/Ig' \
        -e 's/(--(salt|passcode|seed|words)([=[:space:]]+))[^[:space:]]+/\1<redacted>/Ig' \
        -e 's/(--words-file([=[:space:]]+))[^[:space:]]+/\1<redacted>/Ig' |
        redact_registered_secret_values
}

retained_proof_contains_registered_secret() {
    local proof_file
    local proof_line=""
    local secret_value=""
    local proof_directory_is_available=false
    local secret_file_is_available=false
    local registered_secret_was_found=false

    [[ -n "${WORKFLOW_PROOF_DIR:-}" &&
       -d "${WORKFLOW_PROOF_DIR:-}" ]] &&
        proof_directory_is_available=true
    [[ -n "${PROOF_SECRET_VALUES_FILE:-}" &&
       -f "${PROOF_SECRET_VALUES_FILE:-}" ]] &&
        secret_file_is_available=true
    if [[ "${proof_directory_is_available}" == false ||
          "${secret_file_is_available}" == false ]]; then
        return 1
    fi

    for proof_file in "${WORKFLOW_PROOF_DIR}"/*; do
        [[ -f "${proof_file}" ]] || continue
        while IFS= read -r proof_line || [[ -n "${proof_line}" ]]; do
            while IFS= read -r secret_value; do
                [[ -n "${secret_value}" &&
                   "${proof_line}" == *"${secret_value}"* ]] &&
                    registered_secret_was_found=true
            done < "${PROOF_SECRET_VALUES_FILE}"
        done < "${proof_file}"
    done

    [[ "${registered_secret_was_found}" == true ]]
}

redact_retained_proof_files() {
    local proof_file
    local redacted_file
    local proof_directory_is_available=false
    local redaction_succeeded=false

    [[ -n "${WORKFLOW_PROOF_DIR:-}" &&
       -d "${WORKFLOW_PROOF_DIR:-}" ]] &&
        proof_directory_is_available=true
    if [[ "${proof_directory_is_available}" == false ]]; then
        return 1
    fi

    for proof_file in "${WORKFLOW_PROOF_DIR}"/*; do
        [[ -f "${proof_file}" ]] || continue
        redacted_file="${proof_file}.redacted"
        redaction_succeeded=false
        redact_stream < "${proof_file}" > "${redacted_file}" &&
            redaction_succeeded=true
        if [[ "${redaction_succeeded}" == false ]]; then
            rm -f "${redacted_file}"
            return 1
        fi
        chmod 600 "${redacted_file}"
        mv "${redacted_file}" "${proof_file}"
    done
}

archive_failure_diagnostics() {
    local status=$1
    local duration_seconds=0
    local compose_status_file="${WORKFLOW_PROOF_DIR}/compose-status.txt"
    local compose_logs_file="${WORKFLOW_PROOF_DIR}/compose.log"
    local partial_manifest="${WORKFLOW_PROOF_DIR}/partial-manifest.jsonl"
    local compose_status_was_captured=false
    local compose_logs_were_captured=false
    local failure_record_was_written=false
    local partial_manifest_was_copied=false
    local proof_manifest_exists=false
    local start_time_is_available=false
    local summary_was_written=false
    local job_log
    local archived_job_log

    workflow_compose ps --all 2>&1 |
        redact_stream > "${compose_status_file}" &&
        compose_status_was_captured=true
    if [[ "${compose_status_was_captured}" == false ]]; then
        printf 'Compose status was unavailable during failure cleanup.\n' \
            >> "${compose_status_file}"
    fi

    workflow_compose logs --no-color 2>&1 |
        redact_stream > "${compose_logs_file}" &&
        compose_logs_were_captured=true
    if [[ "${compose_logs_were_captured}" == false ]]; then
        printf 'Compose logs were unavailable during failure cleanup.\n' \
            >> "${compose_logs_file}"
    fi

    for job_log in "${WORKFLOW_LOG_DIR}"/*.log; do
        [[ -f "${job_log}" ]] || continue
        archived_job_log="${WORKFLOW_PROOF_DIR}/kli-job-$(basename "${job_log}")"
        redact_stream < "${job_log}" > "${archived_job_log}"
        chmod 600 "${archived_job_log}"
    done

    [[ -f "${PROOF_MANIFEST}" ]] && proof_manifest_exists=true
    if [[ "${proof_manifest_exists}" == true ]]; then
        cp "${PROOF_MANIFEST}" "${partial_manifest}" &&
            partial_manifest_was_copied=true
        if [[ "${partial_manifest_was_copied}" == false ]]; then
            printf 'Unable to preserve the partial proof manifest.\n' >&2
        fi
    fi

    append_proof_record \
        "$(jq -cn --argjson exitStatus "${status}" \
            '{type:"workflow",status:"failed",exitStatus:$exitStatus}')" &&
        failure_record_was_written=true
    if [[ "${failure_record_was_written}" == false ]]; then
        printf 'Unable to append the workflow failure proof record.\n' >&2
    fi

    [[ "${START_TIME:-0}" -gt 0 ]] && start_time_is_available=true
    if [[ "${start_time_is_available}" == true ]]; then
        duration_seconds=$(( $(date +%s) - START_TIME ))
    fi

    write_proof_summary failed "${duration_seconds}" &&
        summary_was_written=true
    if [[ "${summary_was_written}" == false ]]; then
        printf 'Unable to write the workflow failure summary.\n' >&2
    fi

    return 0
}

remove_transient_challenge_words() {
    local challenge_file="${CHALLENGE_WORD_FILE:-}"
    local challenge_file_directory=""
    local canonical_secret_directory=""
    local challenge_file_is_present=false
    local challenge_file_is_scoped=false

    [[ -n "${challenge_file}" && -f "${challenge_file}" ]] &&
        challenge_file_is_present=true
    if [[ "${challenge_file_is_present}" == false ]]; then
        return 0
    fi

    challenge_file_directory=$(cd "$(dirname "${challenge_file}")" && pwd -P)
    canonical_secret_directory=$(runtime_canonical_path "${WORKFLOW_SECRET_DIR:-}") ||
        canonical_secret_directory=""
    [[ -n "${canonical_secret_directory}" &&
       "${challenge_file_directory}" == "${canonical_secret_directory}" ]] &&
        challenge_file_is_scoped=true
    if [[ "${challenge_file_is_scoped}" == false ]]; then
        printf 'Refusing to remove an unscoped challenge file: %s\n' \
            "${challenge_file}" >&2
        return 1
    fi

    rm -f "${challenge_file}"
    CHALLENGE_WORD_FILE=""
}

record_cleanup_failure() {
    local cleanup_exit_status=$1
    local duration_seconds=0
    local proof_is_available=false
    local start_time_is_available=false
    local failure_record_was_written=false
    local summary_was_written=false

    [[ -n "${PROOF_MANIFEST:-}" &&
       -f "${PROOF_MANIFEST:-}" &&
       -n "${PROOF_SUMMARY:-}" ]] &&
        proof_is_available=true
    if [[ "${proof_is_available}" == false ]]; then
        return 0
    fi

    [[ "${START_TIME:-0}" -gt 0 ]] && start_time_is_available=true
    if [[ "${start_time_is_available}" == true ]]; then
        duration_seconds=$(( $(date +%s) - START_TIME ))
    fi

    append_proof_record "$(jq -cn \
        --argjson exitStatus "${cleanup_exit_status}" \
        '{type:"workflow",status:"failed",phase:"cleanup",exitStatus:$exitStatus}')" &&
        failure_record_was_written=true
    if [[ "${failure_record_was_written}" == false ]]; then
        printf 'Unable to record cleanup failure in the proof manifest.\n' >&2
    fi

    write_proof_summary failed "${duration_seconds}" &&
        summary_was_written=true
    if [[ "${summary_was_written}" == false ]]; then
        printf 'Unable to rewrite the proof summary after cleanup failure.\n' >&2
    fi
}

workflow_cleanup() {
    local original_status=$1
    local compose_cleanup_succeeded=false
    local runtime_is_available=false
    local runtime_cleanup_succeeded=false
    local transient_challenge_was_removed=false
    local compose_is_available=false
    local proof_output_is_available=false
    local retention_metadata_is_available=false
    local runtime_should_be_retained=false
    local workflow_failed=false
    local compose_cleanup_is_needed=false
    local cleanup_failed=false
    local cleanup_status=${original_status}

    [[ "${WORKFLOW_CLEANING_UP}" == false ]] || return "${original_status}"
    WORKFLOW_CLEANING_UP=true

    [[ -n "${WORKFLOW_RUN_DIR:-}" && -d "${WORKFLOW_RUN_DIR:-}" ]] &&
        runtime_is_available=true
    [[ -n "${WORKFLOW_PROOF_DIR:-}" && -d "${WORKFLOW_PROOF_DIR:-}" ]] &&
        proof_output_is_available=true
    command -v docker >/dev/null 2>&1 && compose_is_available=true
    [[ "${original_status}" -ne 0 ]] && workflow_failed=true

    remove_transient_challenge_words &&
        transient_challenge_was_removed=true
    if [[ "${transient_challenge_was_removed}" == false ]]; then
        printf 'Transient challenge-word cleanup failed.\n' >&2
        cleanup_failed=true
    fi

    if [[ "${workflow_failed}" == true &&
          "${runtime_is_available}" == true &&
          "${proof_output_is_available}" == true ]]; then
        archive_failure_diagnostics "${original_status}"
    fi

    [[ "${KEEP_RUNTIME:-false}" == true &&
       "${runtime_is_available}" == true ]] &&
        runtime_should_be_retained=true
    if [[ "${runtime_should_be_retained}" == true ]]; then
        printf 'Runtime retained at %s\n' "${WORKFLOW_RUN_DIR}"
        if [[ "${WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST}" == true ]]; then
            [[ -n "${COMPOSE_PROJECT_NAME:-}" &&
               -s "${COMPOSE_ENV_FILE:-}" &&
               -n "${DOCKER_COMPOSE_FILE:-}" ]] &&
                retention_metadata_is_available=true
            if [[ "${retention_metadata_is_available}" == true ]]; then
                printf 'Teardown with: docker compose --project-name %q --env-file %q --file %q down --volumes --remove-orphans\n' \
                    "${COMPOSE_PROJECT_NAME}" "${COMPOSE_ENV_FILE}" "${DOCKER_COMPOSE_FILE}"
            else
                printf 'Compose teardown metadata was not completed before the failure.\n'
                cleanup_failed=true
            fi
        else
            printf 'Compose was not used; no teardown is required.\n'
        fi
        if [[ "${original_status}" -eq 0 &&
              "${cleanup_failed}" == true ]]; then
            cleanup_status=1
            record_cleanup_failure "${cleanup_status}"
        fi
        WORKFLOW_CLEANING_UP=false
        return "${cleanup_status}"
    fi

    [[ "${WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST}" == true && "${compose_is_available}" == true ]] &&
        compose_cleanup_is_needed=true
    if [[ "${WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST}" == true &&
          "${compose_is_available}" == false ]]; then
        printf 'Docker is unavailable; Compose project %s could not be torn down\n' \
            "${COMPOSE_PROJECT_NAME:-<unknown>}" >&2
        cleanup_failed=true
    fi
    if [[ "${compose_cleanup_is_needed}" == true ]]; then
        workflow_compose down --volumes --remove-orphans >/dev/null 2>&1 &&
            compose_cleanup_succeeded=true
        if [[ "${compose_cleanup_succeeded}" == false ]]; then
            printf 'Compose teardown failed for project %s\n' \
                "${COMPOSE_PROJECT_NAME}" >&2
            cleanup_failed=true
        fi
    fi
    if [[ "${runtime_is_available}" == true ]]; then
        remove_owned_runtime "${WORKFLOW_RUN_DIR}" &&
            runtime_cleanup_succeeded=true
        if [[ "${runtime_cleanup_succeeded}" == false ]]; then
            printf 'Private runtime cleanup failed for %s\n' \
                "${WORKFLOW_RUN_DIR}" >&2
            cleanup_failed=true
        fi
    fi

    if [[ "${original_status}" -eq 0 &&
          "${cleanup_failed}" == true ]]; then
        cleanup_status=1
        record_cleanup_failure "${cleanup_status}"
    fi
    WORKFLOW_CLEANING_UP=false
    return "${cleanup_status}"
}

handle_workflow_exit() {
    local original_status=$?
    local cleanup_status=0

    trap - EXIT INT TERM HUP
    workflow_cleanup "${original_status}" || cleanup_status=$?
    exit "${cleanup_status}"
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

wait_until() {
    local description=$1
    local timeout_seconds=$2
    local predicate_name=$3
    shift 3

    local current_time
    local deadline
    local last_predicate_output=""
    local predicate_output=""
    local predicate_status=1
    local predicate_cleanup_failed=false
    local predicate_succeeded=false
    local predicate_termination_status=0
    local predicate_finished=false
    local predicate_status_file=""
    local predicate_status_was_recorded=false
    local predicate_timed_out=false
    local predicate_process_id=""
    local predicate_wait_status=0
    local predicate_output_file=""
    local timeout_has_elapsed=false
    local wait_output_root="${WORKFLOW_LOG_DIR:-${TMPDIR:-/tmp}}"
    local workflow_log_directory_is_available=false

    [[ -n "${WORKFLOW_LOG_DIR:-}" &&
       -d "${WORKFLOW_LOG_DIR:-}" ]] &&
        workflow_log_directory_is_available=true
    if [[ "${workflow_log_directory_is_available}" == false ]]; then
        wait_output_root=${TMPDIR:-/tmp}
    fi

    deadline=$(( $(date +%s) + timeout_seconds ))
    while true; do
        predicate_status=0
        predicate_succeeded=false
        predicate_finished=false
        predicate_cleanup_failed=false
        predicate_status_was_recorded=false
        predicate_timed_out=false
        predicate_termination_status=0
        predicate_wait_status=0
        predicate_output_file=$(mktemp "${wait_output_root}/qvi-wait.XXXXXX")
        predicate_status_file=$(mktemp "${wait_output_root}/qvi-wait-status.XXXXXX")
        (
            local completed_predicate_status=0
            "${predicate_name}" "$@" ||
                completed_predicate_status=$?
            printf '%s\n' "${completed_predicate_status}" \
                > "${predicate_status_file}"
            exit "${completed_predicate_status}"
        ) > "${predicate_output_file}" 2>&1 &
        predicate_process_id=$!

        while [[ "${predicate_finished}" == false &&
                 "${predicate_timed_out}" == false ]]; do
            predicate_status_was_recorded=false
            [[ -s "${predicate_status_file}" ]] &&
                predicate_status_was_recorded=true
            if [[ "${predicate_status_was_recorded}" == true ]]; then
                predicate_finished=true
            else
                current_time=$(date +%s)
                [[ "${current_time}" -gt "${deadline}" ]] &&
                    predicate_timed_out=true
                if [[ "${predicate_timed_out}" == false ]]; then
                    sleep 0.1
                fi
            fi
        done

        if [[ "${predicate_timed_out}" == true ]]; then
            kill "${predicate_process_id}" 2>/dev/null ||
                predicate_termination_status=$?
            wait "${predicate_process_id}" 2>/dev/null ||
                predicate_wait_status=$?
            [[ "${predicate_termination_status}" -ne 0 &&
               "${predicate_wait_status}" -eq 127 ]] &&
                predicate_cleanup_failed=true
            predicate_status=124
        else
            wait "${predicate_process_id}" || predicate_status=$?
        fi
        predicate_output=$(<"${predicate_output_file}")
        rm -f "${predicate_output_file}" "${predicate_status_file}"
        if [[ "${predicate_cleanup_failed}" == true &&
              -z "${predicate_output}" ]]; then
            predicate_output="predicate process could not be reaped at its deadline"
        fi
        if [[ -n "${predicate_output}" ]]; then
            last_predicate_output=${predicate_output}
        fi
        [[ "${predicate_status}" -eq 0 ]] && predicate_succeeded=true
        if [[ "${predicate_succeeded}" == true ]]; then
            [[ -n "${predicate_output}" ]] && printf '%s\n' "${predicate_output}"
            return 0
        fi

        current_time=$(date +%s)
        [[ "${predicate_timed_out}" == true ||
           "${current_time}" -gt "${deadline}" ]] &&
            timeout_has_elapsed=true
        if [[ "${timeout_has_elapsed}" == true ]]; then
            break
        fi
        sleep 1
    done

    printf 'Timed out after %ss waiting for %s. Last observation: %s\n' \
        "${timeout_seconds}" "${description}" \
        "${last_predicate_output:-<none>}" >&2
    return 1
}

http_request() {
    curl \
        --connect-timeout "${HTTP_CONNECT_TIMEOUT:-5}" \
        --max-time "${HTTP_REQUEST_TIMEOUT:-15}" \
        "$@"
}

compose_container_has_project_label() {
    local container_id=$1
    local actual_project=""

    actual_project=$(docker inspect \
        --format '{{ index .Config.Labels "com.docker.compose.project" }}' \
        "${container_id}" 2>/dev/null) || return 1
    [[ "${actual_project}" == "${COMPOSE_PROJECT_NAME}" ]]
}

compose_container_has_stopped() {
    local container_id=$1
    local running_state=""
    local container_has_stopped=false

    running_state=$(docker inspect --format '{{.State.Running}}' "${container_id}" 2>/dev/null) ||
        return 1
    [[ "${running_state}" == false ]] && container_has_stopped=true
    if [[ "${container_has_stopped}" == false ]]; then
        printf 'container %s running=%s\n' "${container_id}" "${running_state}"
        return 1
    fi
}

record_detached_job() {
    local logical_name=$1
    local container_id=$2
    local exit_status=$3

    append_proof_record "$(jq -cn \
        --arg name "${logical_name}" \
        --arg containerId "${container_id}" \
        --argjson exitStatus "${exit_status}" \
        '{type:"kli-job", name:$name, containerId:$containerId, exitStatus:$exitStatus}')"
}

run_detached_compose_job() {
    local service_name=$1
    local logical_name=$2
    shift 2

    local safe_name
    local container_name
    local container_id=""
    local run_status=0
    local job_started=false
    local job_name_is_available=false
    local job_name_is_safe=false
    local project_label_matches=false
    local unexpected_container_was_removed=false

    safe_name=$(printf '%s' "${logical_name}" | tr -cd '[:alnum:]_.-')
    [[ -n "${safe_name}" && "${safe_name}" == "${logical_name}" ]] &&
        job_name_is_safe=true
    if [[ "${job_name_is_safe}" == false ]]; then
        printf 'Detached job name is not path-safe: %s\n' "${logical_name}" >&2
        return 1
    fi

    [[ ! -e "${WORKFLOW_JOB_DIR}/${logical_name}.id" ]] &&
        job_name_is_available=true
    if [[ "${job_name_is_available}" == false ]]; then
        printf 'Detached job name is already active: %s\n' "${logical_name}" >&2
        return 1
    fi

    WORKFLOW_JOB_SEQUENCE=$((WORKFLOW_JOB_SEQUENCE + 1))
    container_name="${COMPOSE_PROJECT_NAME}-${safe_name}-${WORKFLOW_JOB_SEQUENCE}"
    container_id=$(workflow_compose run \
        --detach \
        --no-deps \
        --name "${container_name}" \
        "${service_name}" "$@") || run_status=$?
    [[ "${run_status}" -eq 0 && -n "${container_id}" ]] && job_started=true
    if [[ "${job_started}" == false ]]; then
        printf 'Unable to start detached %s job %s\n' "${service_name}" "${logical_name}" >&2
        return 1
    fi

    compose_container_has_project_label "${container_id}" && project_label_matches=true
    if [[ "${project_label_matches}" == false ]]; then
        printf 'Container %s is not owned by Compose project %s\n' \
            "${container_id}" "${COMPOSE_PROJECT_NAME}" >&2
        docker rm --force "${container_id}" >/dev/null 2>&1 &&
            unexpected_container_was_removed=true
        if [[ "${unexpected_container_was_removed}" == false ]]; then
            printf 'Unable to remove unexpected detached container %s\n' \
                "${container_id}" >&2
        fi
        return 1
    fi

    printf '%s\n' "${container_id}" > "${WORKFLOW_JOB_DIR}/${logical_name}.id"
}

wait_for_compose_job() {
    local logical_name=$1
    local job_file="${WORKFLOW_JOB_DIR}/${logical_name}.id"
    local script_file="${WORKFLOW_JOB_DIR}/${logical_name}.script"
    local container_id=""
    local invocation_path=""
    local exit_status=""
    local container_was_removed=false
    local job_record_was_written=false
    local logs_were_captured=false
    local project_label_matches=false
    local script_file_exists=false
    local wait_succeeded=false
    local job_succeeded=false

    local job_file_exists=false
    [[ -f "${job_file}" ]] && job_file_exists=true
    if [[ "${job_file_exists}" == false ]]; then
        printf 'No detached job is registered as %s\n' "${logical_name}" >&2
        return 1
    fi
    container_id=$(<"${job_file}")

    compose_container_has_project_label "${container_id}" &&
        project_label_matches=true
    if [[ "${project_label_matches}" == false ]]; then
        printf 'Detached job %s no longer belongs to Compose project %s\n' \
            "${logical_name}" "${COMPOSE_PROJECT_NAME}" >&2
        return 1
    fi

    wait_until \
        "detached KLI job ${logical_name}" \
        "${WORKFLOW_TIMEOUT_SECONDS}" \
        compose_container_has_stopped \
        "${container_id}" && wait_succeeded=true
    docker logs "${container_id}" 2>&1 |
        redact_stream |
        tee "${WORKFLOW_LOG_DIR}/${logical_name}.log" &&
        logs_were_captured=true

    if [[ "${wait_succeeded}" == true ]]; then
        exit_status=$(docker inspect --format '{{.State.ExitCode}}' "${container_id}") ||
            exit_status=125
    else
        exit_status=124
    fi

    [[ "${wait_succeeded}" == true &&
       "${logs_were_captured}" == true &&
       "${exit_status}" -eq 0 ]] &&
        job_succeeded=true

    record_detached_job "${logical_name}" "${container_id}" "${exit_status}" &&
        job_record_was_written=true
    docker rm --force "${container_id}" >/dev/null 2>&1 &&
        container_was_removed=true
    rm -f "${job_file}"
    [[ -f "${script_file}" ]] && script_file_exists=true
    if [[ "${script_file_exists}" == true ]]; then
        invocation_path=$(<"${script_file}")
        rm -f "${invocation_path}" "${script_file}"
    fi

    if [[ "${job_record_was_written}" == false ]]; then
        printf 'Unable to record detached KLI job %s\n' "${logical_name}" >&2
        job_succeeded=false
    fi
    if [[ "${container_was_removed}" == false ]]; then
        printf 'Unable to remove detached KLI job container %s\n' \
            "${container_id}" >&2
        job_succeeded=false
    fi
    if [[ "${job_succeeded}" == false ]]; then
        printf 'Detached KLI job %s failed with status %s\n' \
            "${logical_name}" "${exit_status}" >&2
        return 1
    fi
}

wait_for_compose_jobs() {
    local logical_name
    local all_jobs_succeeded=true

    for logical_name in "$@"; do
        wait_for_compose_job "${logical_name}" || all_jobs_succeeded=false
    done
    [[ "${all_jobs_succeeded}" == true ]]
}
