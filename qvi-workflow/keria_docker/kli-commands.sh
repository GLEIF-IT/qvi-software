#!/usr/bin/env bash
##################################################################
##                                                              ##
##      Compose-scoped KLI and Signify command adapters          ##
##                                                              ##
##################################################################

# This file is source-only. vlei-workflow.sh creates the private runtime and
# initializes workflow_compose before any command below is called. Commands
# are written to mode-0600 scripts mounted in the job container so passcodes,
# salts, participant seeds, and challenge words never appear in Docker argv.

WORKFLOW_INVOCATION_SEQUENCE=0
SECURE_INVOCATION_HOST_PATH=""
SECURE_INVOCATION_CONTAINER_PATH=""

create_secure_invocation() {
    local executable=$1
    shift
    local argument

    WORKFLOW_INVOCATION_SEQUENCE=$((WORKFLOW_INVOCATION_SEQUENCE + 1))
    SECURE_INVOCATION_HOST_PATH="${WORKFLOW_SECRET_DIR}/invoke-${WORKFLOW_INVOCATION_SEQUENCE}.sh"
    SECURE_INVOCATION_CONTAINER_PATH="/run/qvi/invoke-${WORKFLOW_INVOCATION_SEQUENCE}.sh"

    {
        printf '#!/usr/bin/env bash\n'
        printf 'exec %q' "${executable}"
        for argument in "$@"; do
            printf ' %q' "${argument}"
        done
        printf '\n'
    } > "${SECURE_INVOCATION_HOST_PATH}"
    chmod 600 "${SECURE_INVOCATION_HOST_PATH}"
}

run_secure_compose_command() {
    local service_name=$1
    local executable=$2
    shift 2
    local command_status=0

    create_secure_invocation "${executable}" "$@"
    workflow_compose run --rm --no-deps -T \
        "${service_name}" "${SECURE_INVOCATION_CONTAINER_PATH}" ||
        command_status=$?
    rm -f "${SECURE_INVOCATION_HOST_PATH}"
    return "${command_status}"
}

generate_kli_challenge_words_file() {
    local container_words_file=$1
    # $1 is expanded by the nested shell inside the KLI container.
    # shellcheck disable=SC2016
    run_secure_compose_command \
        kli \
        /bin/bash \
        -c \
        'umask 077; kli challenge generate --out string | tr -d "\r\n" > "$1"' \
        qvi-challenge-generator \
        "${container_words_file}"
}

run_kli_challenge_with_words_file() {
    local action=$1
    local container_words_file=$2
    shift 2
    local argument
    local command_status=0

    WORKFLOW_INVOCATION_SEQUENCE=$((WORKFLOW_INVOCATION_SEQUENCE + 1))
    SECURE_INVOCATION_HOST_PATH="${WORKFLOW_SECRET_DIR}/invoke-${WORKFLOW_INVOCATION_SEQUENCE}.sh"
    SECURE_INVOCATION_CONTAINER_PATH="/run/qvi/invoke-${WORKFLOW_INVOCATION_SEQUENCE}.sh"
    {
        printf '#!/usr/bin/env bash\n'
        # These expressions belong to the generated script, not this shell.
        # shellcheck disable=SC2016
        printf 'challenge_words=$(<%q)\n' "${container_words_file}"
        printf 'exec kli challenge %q' "${action}"
        for argument in "$@"; do
            printf ' %q' "${argument}"
        done
        # shellcheck disable=SC2016
        printf ' --words "${challenge_words}"\n'
    } > "${SECURE_INVOCATION_HOST_PATH}"
    chmod 600 "${SECURE_INVOCATION_HOST_PATH}"

    workflow_compose run --rm --no-deps -T \
        kli "${SECURE_INVOCATION_CONTAINER_PATH}" ||
        command_status=$?
    rm -f "${SECURE_INVOCATION_HOST_PATH}"
    return "${command_status}"
}

kli_challenge_respond_from_file() {
    local container_words_file=$1
    shift
    run_kli_challenge_with_words_file respond "${container_words_file}" "$@"
}

kli_challenge_verify_from_file() {
    local container_words_file=$1
    shift
    run_kli_challenge_with_words_file verify "${container_words_file}" "$@"
}

kli() {
    run_secure_compose_command kli kli "$@"
}

klid() {
    local logical_name=$1
    shift

    create_secure_invocation kli "$@"
    run_detached_compose_job \
        kli \
        "${logical_name}" \
        "${SECURE_INVOCATION_CONTAINER_PATH}"
    printf '%s\n' "${SECURE_INVOCATION_HOST_PATH}" \
        > "${WORKFLOW_JOB_DIR}/${logical_name}.script"
}

kli2() {
    run_secure_compose_command kli2 kli "$@"
}

kli2d() {
    local logical_name=$1
    shift

    create_secure_invocation kli "$@"
    run_detached_compose_job \
        kli2 \
        "${logical_name}" \
        "${SECURE_INVOCATION_CONTAINER_PATH}"
    printf '%s\n' "${SECURE_INVOCATION_HOST_PATH}" \
        > "${WORKFLOW_JOB_DIR}/${logical_name}.script"
}

sig_tsx() {
    run_secure_compose_command signify tsx "$@"
}

wait_kli_jobs() {
    wait_for_compose_jobs "$@"
}
