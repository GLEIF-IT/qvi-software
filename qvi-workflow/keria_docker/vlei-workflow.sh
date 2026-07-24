#!/usr/bin/env bash
# vlei-workflow.sh - KERIA Docker workflow with multisig GEDA, QVI, and LE
#
# Runs the entire QVI issuance workflow end to end
# Starts from multisig GLEIF External Delegated AID (GEDA) creation all the way to
# OOR and ECR credential issuance and finally to the creation of the Person AID for OOR and ECR
# credential usage.
#
# Note:
# 1) This script uses Docker containers for the KERIpy keystores via the KLI, KERIA, witnesses,
#    the vLEI-server for vLEI schemas, Sally for the vLEI Reporting API, the webhook Sally hits,
#    and local NodeJS scripts for the SignifyTS creation of both QVI QAR AIDs and the Person AID.
# 2) This script starts up and tears down the necessary Docker Compose environment.
# 3) This script uses the kli and kli2 commands as defined in ./kli-commands.sh to perform the QVI
#    workflow steps.
# 4) Each invocation owns a private, mode-0700 runtime and a unique Compose project.

set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORKFLOW_REPOSITORY_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)
DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-keria_signify_qvi.yaml"

# shellcheck source=./color-printing.sh
source "${SCRIPT_DIR}/color-printing.sh"
# shellcheck source=./lib/workflow-runtime.sh
source "${SCRIPT_DIR}/lib/workflow-runtime.sh"

# Used by resolve-env.ts. This driver deliberately supports only its local
# Compose topology.
ENVIRONMENT=docker-tsx
QVI_SIGNIFY_DIR=/vlei-workflow/src
QVI_DATA_DIR=/vlei-workflow/qvi_data
PARTICIPANT_CONFIG_CONTAINER=/run/qvi/participants.json

WORKFLOW_TIMEOUT_SECONDS=120
export WORKFLOW_TIMEOUT_SECONDS
HTTP_CONNECT_TIMEOUT=5
HTTP_REQUEST_TIMEOUT=15
KEEP_RUNTIME=false
PAUSE_ENABLED=false
WORKFLOW_MODE=default
HELP_REQUESTED=false
START_TIME=0

ALT_SALLY_ALIAS="alternate"
ALT_SALLY_OOBI="http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2"

function pause() {
    if [[ $PAUSE_ENABLED == true ]]; then
        read -r -p "$*"
    else
        print_dark_gray "Skipping pause ${*}"
    fi
}

fail_workflow() {
    print_red "$*"
    exit 1
}

utc_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

run_signify_json() {
    local result_json=""
    local command_status=0
    local command_failed=false
    local result_is_valid=false

    result_json=$(sig_tsx "$@") || command_status=$?
    [[ "${command_status}" -ne 0 ]] && command_failed=true
    if [[ "${command_failed}" == true ]]; then
        return "${command_status}"
    fi

    printf '%s\n' "${result_json}" |
        jq -e -s 'length == 1 and .[0].ok == true' >/dev/null 2>&1 &&
        result_is_valid=true
    if [[ "${result_is_valid}" == false ]]; then
        print_red "Signify runner did not emit exactly one successful JSON result"
        return 1
    fi

    printf '%s\n' "${result_json}" | jq -c '.'
}

run_sally_evidence() {
    local evidence_output=""
    local evidence_status=0
    local evidence_command_failed=false
    local evidence_is_valid=false

    evidence_output=$(workflow_compose exec -T hook \
        python3 /app/evidence.py "$@" 2>&1) || evidence_status=$?
    [[ "${evidence_status}" -ne 0 ]] && evidence_command_failed=true
    if [[ "${evidence_command_failed}" == true ]]; then
        printf '%s\n' "${evidence_output}"
        return "${evidence_status}"
    fi

    printf '%s\n' "${evidence_output}" |
        jq -e '.ok == true and (.evidence | type == "object")' \
        >/dev/null 2>&1 &&
        evidence_is_valid=true
    if [[ "${evidence_is_valid}" == false ]]; then
        printf 'Sally evidence validator returned an invalid result: %s\n' \
            "${evidence_output}"
        return 1
    fi

    printf '%s\n' "${evidence_output}" | jq -c '.'
}

record_sally_evidence() {
    local evidence_result=$1
    local story_label=$2
    local proof_record

    proof_record=$(printf '%s\n' "${evidence_result}" |
        jq -c \
            --arg story "${story_label}" \
            '.evidence + {type:"sally-evidence", story:$story}')
    append_proof_record "${proof_record}"
}

sally_active_evidence_is_ready() {
    local submitted_after=$1
    local credential_said=$2
    local schema=$3
    local holder=$4
    local issuer=$5

    run_sally_evidence active \
        --callbacks /proof/sally-callbacks.jsonl \
        --after "${submitted_after}" \
        --said "${credential_said}" \
        --schema "${schema}" \
        --holder "${holder}" \
        --issuer "${issuer}"
}

wait_for_active_sally_evidence() {
    local story_label=$1
    local submitted_after=$2
    local credential_said=$3
    local schema=$4
    local holder=$5
    local issuer=$6
    local evidence_result=""
    local evidence_wait_failed=false

    evidence_result=$(wait_until \
        "Sally callback for ${story_label} credential ${credential_said}" \
        "${WORKFLOW_TIMEOUT_SECONDS}" \
        sally_active_evidence_is_ready \
        "${submitted_after}" \
        "${credential_said}" \
        "${schema}" \
        "${holder}" \
        "${issuer}") || evidence_wait_failed=true
    if [[ "${evidence_wait_failed}" == true ]]; then
        fail_workflow "Sally did not prove the ${story_label} presentation"
    fi

    record_sally_evidence "${evidence_result}" "${story_label}"
}

capture_direct_sally_logs() {
    local submitted_after=$1
    local raw_log_file="${WORKFLOW_LOG_DIR}/direct-sally.raw.log"
    local redacted_log_file="${DIRECT_SALLY_LOG_FILE}.tmp"
    local log_capture_status=0
    local log_capture_failed=false
    local log_redaction_succeeded=false

    workflow_compose logs \
        --no-color \
        --timestamps \
        --since "${submitted_after}" \
        direct-sally > "${raw_log_file}" 2>&1 ||
        log_capture_status=$?
    [[ "${log_capture_status}" -ne 0 ]] && log_capture_failed=true
    if [[ "${log_capture_failed}" == true ]]; then
        rm -f "${raw_log_file}" "${redacted_log_file}"
        return "${log_capture_status}"
    fi

    redact_stream < "${raw_log_file}" > "${redacted_log_file}" &&
        log_redaction_succeeded=true
    rm -f "${raw_log_file}"
    if [[ "${log_redaction_succeeded}" == false ]]; then
        rm -f "${redacted_log_file}"
        return 1
    fi

    chmod 600 "${redacted_log_file}"
    mv "${redacted_log_file}" "${DIRECT_SALLY_LOG_FILE}"
}

sally_revoked_oor_evidence_is_ready() {
    local submitted_after=$1
    local credential_said=$2
    local issuer=$3
    local revocation_timestamp=$4
    local logs_were_captured=false

    capture_direct_sally_logs "${submitted_after}" &&
        logs_were_captured=true
    if [[ "${logs_were_captured}" == false ]]; then
        printf 'Unable to capture direct Sally logs\n'
        return 1
    fi

    run_sally_evidence revoked-oor \
        --callbacks /proof/sally-callbacks.jsonl \
        --logs /proof/direct-sally.log \
        --after "${submitted_after}" \
        --said "${credential_said}" \
        --schema "${OOR_SCHEMA}" \
        --issuer "${issuer}" \
        --revoked-at "${revocation_timestamp}"
}

no_ecr_callback_window_is_complete() {
    local submitted_after=$1
    local credential_said=$2
    local quiet_deadline=$3
    local evidence_result=""
    local evidence_is_clean=false
    local quiet_window_elapsed=false

    evidence_result=$(run_sally_evidence no-callback \
        --callbacks /proof/sally-callbacks.jsonl \
        --after "${submitted_after}" \
        --schema "${ECR_SCHEMA}" \
        --said "${credential_said}") &&
        evidence_is_clean=true
    if [[ "${evidence_is_clean}" == false ]]; then
        printf '%s\n' "${evidence_result}"
        return 1
    fi

    [[ $(date +%s) -ge "${quiet_deadline}" ]] &&
        quiet_window_elapsed=true
    if [[ "${quiet_window_elapsed}" == false ]]; then
        printf 'No ECR callback observed; quiet window is still open\n'
        return 1
    fi

    printf '%s\n' "${evidence_result}"
}

prove_no_ecr_callback() {
    local submitted_after=$1
    local credential_said=$2
    local quiet_seconds=10
    local quiet_deadline=$(( $(date +%s) + quiet_seconds ))
    local evidence_result=""
    local evidence_wait_failed=false

    evidence_result=$(wait_until \
        "a ${quiet_seconds}s window with no ECR callback" \
        "$(( quiet_seconds + 2 ))" \
        no_ecr_callback_window_is_complete \
        "${submitted_after}" \
        "${credential_said}" \
        "${quiet_deadline}") || evidence_wait_failed=true
    if [[ "${evidence_wait_failed}" == true ]]; then
        fail_workflow "An ECR callback was emitted or the quiet-window proof failed"
    fi

    record_sally_evidence "${evidence_result}" "ECR-not-presented"
}

require_system_commands() {
    local required_command
    local command_is_available=false

    for required_command in docker jq curl shasum awk sed wc; do
        command_is_available=false
        command -v "${required_command}" >/dev/null 2>&1 && command_is_available=true
        if [[ "${command_is_available}" == false ]]; then
            print_red "${required_command} is not installed. Please install it."
            return 1
        fi
    done
}

create_docker_containers() {
  local image_build_succeeded=false

  print_green "-------------------Building workflow runner and proof recorder-------------------"
  workflow_compose build signify hook && image_build_succeeded=true
  if [[ "${image_build_succeeded}" == false ]]; then
      fail_workflow "Unable to build the workflow images"
  fi
}

record_dependency_proof() {
  local keria_container_id=""
  local keria_image_id=""
  local keria_repo_digest=""
  local keria_version=""
  local signify_version=""
  local dependency_probe_failed=false
  local versions_are_expected=false

  keria_container_id=$(workflow_compose ps -q keria1) ||
      dependency_probe_failed=true
  if [[ "${dependency_probe_failed}" == false ]]; then
      keria_image_id=$(docker inspect \
          --format '{{.Image}}' "${keria_container_id}") ||
          dependency_probe_failed=true
  fi
  if [[ "${dependency_probe_failed}" == false ]]; then
      keria_repo_digest=$(docker image inspect \
          weboftrust/keria:0.4.0 \
          --format '{{range .RepoDigests}}{{println .}}{{end}}' |
          awk '/^weboftrust\/keria@sha256:/ {print; exit}') ||
          dependency_probe_failed=true
  fi
  if [[ "${dependency_probe_failed}" == false ]]; then
      keria_version=$(workflow_compose exec -T keria1 \
          python3 -c 'import keria; print(keria.__version__)') ||
          dependency_probe_failed=true
  fi
  if [[ "${dependency_probe_failed}" == false ]]; then
      signify_version=$(run_secure_compose_command \
          signify \
          node \
          --input-type=module \
          -e \
          'import {readFileSync} from "node:fs"; console.log(JSON.parse(readFileSync("./node_modules/signify-ts/package.json","utf8")).version)') ||
          dependency_probe_failed=true
  fi
  if [[ "${dependency_probe_failed}" == true ]]; then
      fail_workflow "Unable to record the resolved KERIA and SignifyTS dependencies"
  fi

  [[ "${keria_version}" == "0.4.0" &&
     "${signify_version}" == "0.4.0" &&
     "${keria_repo_digest}" == weboftrust/keria@sha256:* ]] &&
      versions_are_expected=true
  if [[ "${versions_are_expected}" == false ]]; then
      fail_workflow \
          "Dependency mismatch: KERIA=${keria_version}, SignifyTS=${signify_version}, digest=${keria_repo_digest}"
  fi

  append_proof_record "$(jq -cn \
      --arg image "weboftrust/keria:0.4.0" \
      --arg version "${keria_version}" \
      --arg imageId "${keria_image_id}" \
      --arg digest "${keria_repo_digest}" \
      '{type:"dependency",component:"KERIA",image:$image,version:$version,imageId:$imageId,digest:$digest}')"
  append_proof_record "$(jq -cn \
      --arg version "${signify_version}" \
      '{type:"dependency",component:"SignifyTS",version:$version}')"
}

# QVI Config
#### Witness Hosts ####
# Wan 5642
WIT_HOST_GAR=http://gar-witnesses:5642
WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
# Wil 5643
WIT_HOST_QAR=http://qar-witnesses:5643
WIL_PRE=BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM
# Container configuration (name of the config dir in docker containers kli*)
CONT_CONFIG_DIR=/config

#### Identifier Information ####
# GEDA AIDs - GLEIF External Delegated AID
GAR1=accolon
GAR1_PRE=
GAR2=bedivere
GAR2_PRE=
export GEDA_NAME=dagonet
export GEDA_PRE=

# Legal Entity AIDs
LAR1=elaine
LAR1_PRE=
LAR2=finn
LAR2_PRE=
LE_NAME=gareth
LE_PRE=

#### KERIA and Signify Identifiers ####
# QAR AIDs - filled in later after KERIA setup
QAR1=galahad
QAR1_PRE=
QAR1_AGENT_EID=
QAR2=lancelot
QAR2_PRE=
QAR2_AGENT_EID=
QAR3=tristan
QAR3_PRE=
QAR3_AGENT_EID=
QVI_NAME=percival
QVI_PRE=

# Person AID
PERSON=mordred
PERSON_PRE=
OOR_CRED_SAID=
ECR_CRED_SAID=
LE_CRED_SAID=
LAST_REVOCATION_TIMESTAMP=
OOR_REVOCATION_TIMESTAMP=
ECR_CALLBACK_BOUNDARY=

#### Credential data ####
LE_LEI=254900OPPU84GM83MG36 # GLEIF Americas
PERSON_NAME="Mordred Delacqs"
PERSON_ECR="Consultant"
PERSON_OOR="Advisor"

# Sally - vLEI Reporting API. Exported so the verifier container can deliver
# callbacks to the proof hook.
export WEBHOOK_HOST=http://hook:9923

# Direct mode Sally
export DIRECT_SALLY_HOST=http://direct-sally:9823
export DIRECT_SALLY_KS_NAME=direct-sally
export DIRECT_SALLY_ALIAS=direct-sally
export DIRECT_SALLY_PASSCODE=""
export DIRECT_SALLY_SALT=""
export DIRECT_SALLY_PRE=""

# Registries
GEDA_REGISTRY=vLEI-external
LE_REGISTRY=vLEI-internal
QVI_REGISTRY=vLEI-qvi

# Credential Schemas
QVI_SCHEMA=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
LE_SCHEMA=ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY
ECR_AUTH_SCHEMA=EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g
OOR_AUTH_SCHEMA=EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E
ECR_SCHEMA=EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw
OOR_SCHEMA=EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy

# Write wrong GEDA PRE, will be reset later
export GEDA_PRE=DUMMY_VALUE_INVALID_________________________

write_private_runtime_config() {
  local compose_environment_file="${COMPOSE_ENV_FILE}.tmp"
  local participant_configuration_file="${PARTICIPANT_CONFIG_FILE}.tmp"
  local qar1_salt="${QAR1_SALT:-}"
  local qar2_salt="${QAR2_SALT:-}"
  local qar3_salt="${QAR3_SALT:-}"
  local person_salt="${PERSON_SALT:-}"

  print_bg_blue "[ADMIN] Writing protected runtime configuration"

  {
    printf 'WORKFLOW_CONFIG_DIR=%s\n' "${WORKFLOW_CONFIG_DIR}"
    printf 'WORKFLOW_PROOF_DIR=%s\n' "${WORKFLOW_PROOF_DIR}"
    printf 'WORKFLOW_SECRET_DIR=%s\n' "${WORKFLOW_SECRET_DIR}"
    printf 'KEYSTORE_DIR=%s\n' "${KEYSTORE_DIR}"
    printf 'KLI_DATA_DIR=%s\n' "${KLI_DATA_DIR}"
    printf 'LOCAL_QVI_DATA_DIR=%s\n' "${LOCAL_QVI_DATA_DIR}"
    printf 'WORKFLOW_UID=%s\n' "${WORKFLOW_UID}"
    printf 'WORKFLOW_GID=%s\n' "${WORKFLOW_GID}"
    printf 'WORKFLOW_TIMEOUT_SECONDS=%s\n' "${WORKFLOW_TIMEOUT_SECONDS}"
    printf 'DIRECT_SALLY_KS_NAME=%s\n' "${DIRECT_SALLY_KS_NAME}"
    printf 'DIRECT_SALLY_ALIAS=%s\n' "${DIRECT_SALLY_ALIAS}"
    printf 'DIRECT_SALLY_PRE=%s\n' "${DIRECT_SALLY_PRE}"
    printf 'DIRECT_SALLY_SALT=%s\n' "${DIRECT_SALLY_SALT}"
    printf 'DIRECT_SALLY_PASSCODE=%s\n' "${DIRECT_SALLY_PASSCODE}"
    printf 'WEBHOOK_HOST=%s\n' "${WEBHOOK_HOST}"
    printf 'GEDA_PRE=%s\n' "${GEDA_PRE}"
  } > "${compose_environment_file}"

  {
    printf '{\n'
    printf '  "environment": "docker-tsx",\n'
    printf '  "participants": {\n'
    printf '    "qar1": {"position":"qar1","name":"%s","salt":"%s","keriaHost":1},\n' "${QAR1}" "${qar1_salt}"
    printf '    "qar2": {"position":"qar2","name":"%s","salt":"%s","keriaHost":2},\n' "${QAR2}" "${qar2_salt}"
    printf '    "qar3": {"position":"qar3","name":"%s","salt":"%s","keriaHost":3},\n' "${QAR3}" "${qar3_salt}"
    printf '    "person": {"position":"person","name":"%s","salt":"%s","keriaHost":1}\n' "${PERSON}" "${person_salt}"
    printf '  }\n'
    printf '}\n'
  } > "${participant_configuration_file}"

  chmod 600 "${compose_environment_file}" "${participant_configuration_file}"
  mv "${compose_environment_file}" "${COMPOSE_ENV_FILE}"
  mv "${participant_configuration_file}" "${PARTICIPANT_CONFIG_FILE}"
}

prepare_compose_lifecycle() {
  write_private_runtime_config
  WORKFLOW_COMPOSE_RESOURCES_MAY_EXIST=true
}

function start_docker_containers() {
  local foundation_start_failed=false
  local sally_start_failed=false

  workflow_compose up \
      --detach \
      --wait \
      --wait-timeout "${WORKFLOW_TIMEOUT_SECONDS}" \
      vlei-server \
      hook \
      gar-witnesses \
      qar-witnesses \
      person-witnesses \
      keria1 \
      keria2 \
      keria3 ||
      foundation_start_failed=true
  if [[ "${foundation_start_failed}" == true ]]; then
      fail_workflow "Docker foundation services failed to start properly"
  fi

  # Sally initializes its Habery and incepts its identifier as part of server
  # start. This keeps bootstrap ownership inside the verifier implementation.
  workflow_compose up \
      --detach \
      --wait \
      --wait-timeout "${WORKFLOW_TIMEOUT_SECONDS}" \
      direct-sally ||
      sally_start_failed=true
  if [[ "${sally_start_failed}" == true ]]; then
      fail_workflow "Sally services failed to start properly"
  fi
}

################################################
# QVI Workflow with KERIpy, KERIA, and SignifyTS
################################################
#### Prepare Salts and Passcodes ####
function generate_salts_and_passcodes(){
  # salts and passcodes need to be new and dynamic on each run so that when presenting credentials to
  # other sally instances, not this one, that duplicity is not created by virtue of using the same
  # identifier salt, passcode, and inception configuration.

  print_green "Generating protected participant salts and passcodes"
  export GAR1_SALT
  export GAR2_SALT
  export LAR1_SALT
  export LAR2_SALT
  export QAR1_SALT
  export QAR2_SALT
  export QAR3_SALT
  export PERSON_SALT
  export GAR1_PASSCODE
  export GAR2_PASSCODE
  export LAR1_PASSCODE
  export LAR2_PASSCODE
  export PERSON_PASSCODE
  export DIRECT_SALLY_SALT
  export DIRECT_SALLY_PASSCODE

  GAR1_SALT=$(kli salt | tr -d " \t\n\r")
  GAR2_SALT=$(kli salt | tr -d " \t\n\r")
  LAR1_SALT=$(kli salt | tr -d " \t\n\r")
  LAR2_SALT=$(kli salt | tr -d " \t\n\r")
  QAR1_SALT=$(kli salt | tr -d " \t\n\r")
  QAR2_SALT=$(kli salt | tr -d " \t\n\r")
  QAR3_SALT=$(kli salt | tr -d " \t\n\r")
  PERSON_SALT=$(kli salt | tr -d " \t\n\r")
  DIRECT_SALLY_SALT=$(kli salt | tr -d " \t\n\r")

  GAR1_PASSCODE=$(kli passcode generate | tr -d " \t\n\r")
  GAR2_PASSCODE=$(kli passcode generate | tr -d " \t\n\r")
  LAR1_PASSCODE=$(kli passcode generate | tr -d " \t\n\r")
  LAR2_PASSCODE=$(kli passcode generate | tr -d " \t\n\r")
  PERSON_PASSCODE=$(kli passcode generate | tr -d " \t\n\r")
  DIRECT_SALLY_PASSCODE=$(kli passcode generate | tr -d " \t\n\r")

  register_proof_secret_values \
    "${GAR1_SALT}" \
    "${GAR2_SALT}" \
    "${LAR1_SALT}" \
    "${LAR2_SALT}" \
    "${QAR1_SALT}" \
    "${QAR2_SALT}" \
    "${QAR3_SALT}" \
    "${PERSON_SALT}" \
    "${GAR1_PASSCODE}" \
    "${GAR2_PASSCODE}" \
    "${LAR1_PASSCODE}" \
    "${LAR2_PASSCODE}" \
    "${PERSON_PASSCODE}" \
    "${DIRECT_SALLY_SALT}" \
    "${DIRECT_SALLY_PASSCODE}"
}

sally_oobi_prefix_is_ready() {
  local service_name=$1
  local local_oobi_url=$2
  local response_headers=""
  local request_status=0
  local sally_prefix=""
  local prefix_has_expected_length=false
  local prefix_has_cesr_characters=false

  response_headers=$(workflow_compose exec -T \
      "${service_name}" \
      curl \
      --fail \
      --silent \
      --show-error \
      --connect-timeout 5 \
      --max-time 10 \
      --dump-header - \
      --output /dev/null \
      "${local_oobi_url}") ||
      request_status=$?
  if [[ "${request_status}" -ne 0 ]]; then
      printf '%s /oobi request exited %s\n' \
          "${service_name}" "${request_status}"
      return "${request_status}"
  fi

  sally_prefix=$(printf '%s\n' "${response_headers}" |
      awk -F ': *' '
          tolower($1) == "keri-aid" {
              gsub("\r", "", $2)
              print $2
              exit
          }
      ')
  [[ "${#sally_prefix}" -eq 44 ]] &&
      prefix_has_expected_length=true
  case "${sally_prefix}" in
      ""|*[!A-Za-z0-9_-]*) ;;
      *) prefix_has_cesr_characters=true ;;
  esac

  if [[ "${prefix_has_expected_length}" == false ||
        "${prefix_has_cesr_characters}" == false ]]; then
      printf '%s /oobi omitted a valid KERI-AID header\n' \
          "${service_name}"
      return 1
  fi

  printf '%s\n' "${sally_prefix}"
}

observe_sally_prefix() {
  local service_name=$1
  local local_oobi_url=$2
  local alias=$3
  local info_file=$4
  local observed_prefix=""
  local observation_failed=false
  local temporary_info_file="${info_file}.tmp"

  observed_prefix=$(wait_until \
      "${service_name} self-bootstrapped OOBI" \
      "${WORKFLOW_TIMEOUT_SECONDS}" \
      sally_oobi_prefix_is_ready \
      "${service_name}" \
      "${local_oobi_url}") ||
      observation_failed=true
  if [[ "${observation_failed}" == true ]]; then
      return 1
  fi

  jq -n \
      --arg alias "${alias}" \
      --arg prefix "${observed_prefix}" \
      '{alias: $alias, prefix: $prefix}' \
      > "${temporary_info_file}"
  chmod 600 "${temporary_info_file}"
  mv "${temporary_info_file}" "${info_file}"
  printf '%s\n' "${observed_prefix}"
}

load_sally_prefixes() {
  local direct_info="${WORKFLOW_SECRET_DIR}/direct-sally.json"
  local direct_observation_failed=false

  DIRECT_SALLY_PRE=$(observe_sally_prefix \
      direct-sally \
      http://127.0.0.1:9823/oobi \
      "${DIRECT_SALLY_ALIAS}" \
      "${direct_info}") ||
      direct_observation_failed=true
  if [[ "${direct_observation_failed}" == true ]]; then
      fail_workflow "Unable to observe direct Sally's self-bootstrapped AID"
  fi

  export DIRECT_SALLY_PRE
}

function setup_keria_identifiers() {
  local setup_failed=false
  local qvi_setup_data=""

  print_yellow "Creating QVI and Person Identifiers from SignifyTS + KERIA"
  run_signify_json \
      "${QVI_SIGNIFY_DIR}/qars/qars-and-person-setup.ts" \
      --config "${PARTICIPANT_CONFIG_CONTAINER}" \
      --data-dir "${QVI_DATA_DIR}" >/dev/null || setup_failed=true
  if [[ "${setup_failed}" == true ]]; then
      fail_workflow "Unable to create the QAR and Person identifiers"
  fi

  print_green "QVI and Person Identifiers from SignifyTS + KERIA are "
  # Extract prefixes from the SignifyTS output because they are dynamically generated and unique each run.
  # They are needed for doing OOBI resolutions to connect SignifyTS AIDs to KERIpy AIDs.
  qvi_setup_data=$(<"${LOCAL_QVI_DATA_DIR}/qars-and-person-info.json")
  QAR1_PRE=$(printf '%s\n' "${qvi_setup_data}" | jq -er ".QAR1.aid")
  QAR2_PRE=$(printf '%s\n' "${qvi_setup_data}" | jq -er ".QAR2.aid")
  QAR3_PRE=$(printf '%s\n' "${qvi_setup_data}" | jq -er ".QAR3.aid")
  PERSON_PRE=$(printf '%s\n' "${qvi_setup_data}" | jq -er ".PERSON.aid")
  QAR1_OOBI=$(printf '%s\n' "${qvi_setup_data}" | jq -er ".QAR1.agentOobi")
  QAR2_OOBI=$(printf '%s\n' "${qvi_setup_data}" | jq -er ".QAR2.agentOobi")
  QAR3_OOBI=$(printf '%s\n' "${qvi_setup_data}" | jq -er ".QAR3.agentOobi")
  PERSON_OOBI=$(printf '%s\n' "${qvi_setup_data}" | jq -er ".PERSON.agentOobi")
  QAR1_AGENT_EID=$(printf '%s\n' "${QAR1_OOBI}" | awk -F/ '{print $NF}')
  QAR2_AGENT_EID=$(printf '%s\n' "${QAR2_OOBI}" | awk -F/ '{print $NF}')
  QAR3_AGENT_EID=$(printf '%s\n' "${QAR3_OOBI}" | awk -F/ '{print $NF}')

  # Show dyncamic, extracted Signify identifiers and OOBIs
  print_green     "QAR1   Prefix: $QAR1_PRE"
  print_dark_gray "QAR1     OOBI: $QAR1_OOBI"
  print_green     "QAR2   Prefix: $QAR2_PRE"
  print_dark_gray "QAR2     OOBI: $QAR2_OOBI"
  print_green     "QAR3   Prefix: $QAR3_PRE"
  print_dark_gray "QAR3     OOBI: $QAR3_OOBI"
  print_green     "Person Prefix: $PERSON_PRE"
  print_dark_gray "Person   OOBI: $PERSON_OOBI"
}

# initializes a keystore and creates a single sig AID
function create_aid() {
    NAME=${1:-}
    SALT=${2:-}
    PASSCODE=${3:-}
    CONFIG_DIR=${4:-}
    CONFIG_FILE=${5:-}
    ICP_FILE=${6:-}
    KLI_CMD=${7:-}

    echo
    print_dark_gray "Creating Habery for ${NAME} with config file ${CONFIG_FILE}"
    ${KLI_CMD:-kli} init \
        --name "${NAME}" \
        --salt "${SALT}" \
        --passcode "${PASSCODE}" \
        --config-dir "${CONFIG_DIR}" \
        --config-file "${CONFIG_FILE}"

    print_dark_gray "Creating AID ${NAME} with config file ${ICP_FILE}"
    ${KLI_CMD:-kli} incept \
        --name "${NAME}" \
        --alias "${NAME}" \
        --passcode "${PASSCODE}" \
        --file "${ICP_FILE}"
    PREFIX=$(${KLI_CMD:-kli} status  --name "${NAME}"  --alias "${NAME}"  --passcode "${PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )
    print_dark_gray "Created AID: ${NAME}"
    print_green $'\tPrefix:'" ${PREFIX}"
}

# Create single Sig AIDs for GARs and LARs
function create_aids() {
    print_green "------------------------------Creating identifiers (AIDs)------------------------------"
    create_aid "${GAR1}" "${GAR1_SALT}" "${GAR1_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-gars.json" "/config/incept-cfg-gars.json"
    create_aid "${GAR2}" "${GAR2_SALT}" "${GAR2_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-gars.json" "/config/incept-cfg-gars.json"
    create_aid "${LAR1}" "${LAR1_SALT}" "${LAR1_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-qars.json" "/config/incept-cfg-qars.json"
    create_aid "${LAR2}" "${LAR2_SALT}" "${LAR2_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-qars.json" "/config/incept-cfg-qars.json"
}

function read_prefixes() {
  GAR1_PRE=$(kli status --name "${GAR1}" --alias "${GAR1}" \
      --passcode "${GAR1_PASSCODE}" |
      awk '/Identifier:/ {print $2}' |
      tr -d " \t\n\r")
  GAR2_PRE=$(kli status --name "${GAR2}" --alias "${GAR2}" \
      --passcode "${GAR2_PASSCODE}" |
      awk '/Identifier:/ {print $2}' |
      tr -d " \t\n\r")
  LAR1_PRE=$(kli status --name "${LAR1}" --alias "${LAR1}" \
      --passcode "${LAR1_PASSCODE}" |
      awk '/Identifier:/ {print $2}' |
      tr -d " \t\n\r")
  LAR2_PRE=$(kli status --name "${LAR2}" --alias "${LAR2}" \
      --passcode "${LAR2_PASSCODE}" |
      awk '/Identifier:/ {print $2}' |
      tr -d " \t\n\r")
  export GAR1_PRE GAR2_PRE LAR1_PRE LAR2_PRE

  print_green "------------------------------Reading identifier prefixes using the KLI------------------------------"
  print_lcyan "GAR1 Prefix: ${GAR1_PRE}"
  print_lcyan "GAR2 Prefix: ${GAR2_PRE}"
  print_lcyan "LAR1 Prefix: ${LAR1_PRE}"
  print_lcyan "LAR2 Prefix: ${LAR2_PRE}"
}

# OOBI resolutions between single sig AIDs
function resolve_oobis() {
    local resolution_failed=false

    DIRECT_SALLY_OOBI="${DIRECT_SALLY_HOST}/oobi"
    print_green "DIRECT SALLY OOBI: ${DIRECT_SALLY_OOBI}"

    GAR1_OOBI="${WIT_HOST_GAR}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    GAR2_OOBI="${WIT_HOST_GAR}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    LAR1_OOBI="${WIT_HOST_QAR}/oobi/${LAR1_PRE}/witness/${WIL_PRE}"
    LAR2_OOBI="${WIT_HOST_QAR}/oobi/${LAR2_PRE}/witness/${WIL_PRE}"
    OOBIS_FOR_KERIA="gar1|$GAR1_OOBI,gar2|$GAR2_OOBI,lar1|$LAR1_OOBI,lar2|$LAR2_OOBI,direct-sally|$DIRECT_SALLY_OOBI"

    run_signify_json \
        "${QVI_SIGNIFY_DIR}/qars/resolve-oobi-gars-lars-sally.ts" \
        --config "${PARTICIPANT_CONFIG_CONTAINER}" \
        --oobis "${OOBIS_FOR_KERIA}" >/dev/null ||
        resolution_failed=true
    if [[ "${resolution_failed}" == true ]]; then
        fail_workflow "KERIA participants could not resolve the workflow OOBIs"
    fi

    echo
    print_green "------------------------------Connecting Keystores with OOBI Resolutions------------------------------"
    print_yellow "Resolving OOBIs for GAR 1"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${GAR2}"   --passcode "${GAR1_PASSCODE}" --oobi "${GAR2_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${LAR1}"   --passcode "${GAR1_PASSCODE}" --oobi "${LAR1_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${LAR2}"   --passcode "${GAR1_PASSCODE}" --oobi "${LAR2_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR1}"   --passcode "${GAR1_PASSCODE}" --oobi "${QAR1_OOBI}" 
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR2}"   --passcode "${GAR1_PASSCODE}" --oobi "${QAR2_OOBI}" 
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR3}"   --passcode "${GAR1_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${PERSON}" --passcode "${GAR1_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${DIRECT_SALLY_ALIAS}"   --passcode "${GAR1_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for GAR 2"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${GAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${GAR1_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${LAR1_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${LAR2_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR1_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR3}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${PERSON}" --passcode "${GAR2_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${DIRECT_SALLY_ALIAS}"   --passcode "${GAR2_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for LAR 1"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${LAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${LAR2_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${GAR1_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${GAR2_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR1_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR3}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${PERSON}" --passcode "${LAR1_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${DIRECT_SALLY_ALIAS}"   --passcode "${LAR1_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for LAR 2"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${LAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${LAR1_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${GAR1_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${GAR2_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR1_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR3}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${PERSON}" --passcode "${LAR2_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${DIRECT_SALLY_ALIAS}"   --passcode "${LAR2_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"
    
    echo
}

CHALLENGE_WORD_FILE=""
CHALLENGE_WORD_CONTAINER_FILE=""
CHALLENGE_DIGEST=""
CHALLENGE_WORD_SEQUENCE=0
KERIA_CHALLENGE_EXN_SAID=""

function generate_challenge_words() {
    local challenge_generation_failed=false
    local challenge_words=""
    local challenge_word_count=""
    local challenge_word_file_exists=false
    local challenge_word_count_is_valid=false

    clear_challenge_words
    CHALLENGE_WORD_SEQUENCE=$((CHALLENGE_WORD_SEQUENCE + 1))
    CHALLENGE_WORD_FILE="${WORKFLOW_SECRET_DIR}/challenge-${CHALLENGE_WORD_SEQUENCE}.words"
    CHALLENGE_WORD_CONTAINER_FILE="/run/qvi/challenge-${CHALLENGE_WORD_SEQUENCE}.words"
    generate_kli_challenge_words_file "${CHALLENGE_WORD_CONTAINER_FILE}" ||
        challenge_generation_failed=true
    if [[ "${challenge_generation_failed}" == true ]]; then
        fail_workflow "Failed to generate a 128-bit challenge"
    fi

    [[ -f "${CHALLENGE_WORD_FILE}" ]] && challenge_word_file_exists=true
    if [[ "${challenge_word_file_exists}" == false ]]; then
        fail_workflow "Challenge generation completed without a protected words file"
    fi

    challenge_word_count=$(wc -w < "${CHALLENGE_WORD_FILE}" | tr -d '[:space:]')
    [[ "${challenge_word_count}" -eq 12 ]] && challenge_word_count_is_valid=true
    if [[ "${challenge_word_count_is_valid}" == false ]]; then
        fail_workflow "Expected a 12-word, 128-bit challenge"
    fi

    chmod 600 "${CHALLENGE_WORD_FILE}"
    challenge_words=$(<"${CHALLENGE_WORD_FILE}")
    register_proof_secret_values "${challenge_words}"
    CHALLENGE_DIGEST=$(shasum -a 256 "${CHALLENGE_WORD_FILE}" | awk '{print $1}')
}

function clear_challenge_words() {
    local challenge_file_is_present=false
    [[ -n "${CHALLENGE_WORD_FILE}" && -f "${CHALLENGE_WORD_FILE}" ]] &&
        challenge_file_is_present=true
    if [[ "${challenge_file_is_present}" == true ]]; then
        rm -f "${CHALLENGE_WORD_FILE}"
    fi
    CHALLENGE_WORD_FILE=""
    CHALLENGE_WORD_CONTAINER_FILE=""
    CHALLENGE_DIGEST=""
}

function verify_kli_contact_binding() {
    local verifier_name=$1
    local verifier_passcode=$2
    local responder_name=$3
    local expected_responder_prefix=$4
    local contacts_json=""
    local contact_query_failed=false
    local observed_responder_prefix=""
    local responder_prefix_matches=false

    contacts_json=$(kli contacts list \
        --name "${verifier_name}" \
        --passcode "${verifier_passcode}") || contact_query_failed=true
    if [[ "${contact_query_failed}" == true ]]; then
        fail_workflow "Unable to inspect ${verifier_name}'s contacts before challenge verification"
    fi

    observed_responder_prefix=$(printf '%s\n' "${contacts_json}" |
        jq -rs \
            --arg alias "${responder_name}" \
            '[.. | objects | select(.alias? == $alias) | (.id? // .prefix?)] |
             map(select(type == "string" and length > 0)) |
             unique |
             if length == 1 then .[0] else empty end')
    [[ "${observed_responder_prefix}" == "${expected_responder_prefix}" ]] &&
        responder_prefix_matches=true
    if [[ "${responder_prefix_matches}" == false ]]; then
        fail_workflow "Contact ${responder_name} did not resolve to its expected prefix for ${verifier_name}"
    fi
}

function verify_kli_challenge() {
    local verifier_name=$1
    local verifier_passcode=$2
    local responder_name=$3
    local expected_responder_prefix=$4
    local output=""
    local verification_failed=false
    local success_message_found=false

    verify_kli_contact_binding \
        "${verifier_name}" \
        "${verifier_passcode}" \
        "${responder_name}" \
        "${expected_responder_prefix}"

    output=$(kli_challenge_verify_from_file "${CHALLENGE_WORD_CONTAINER_FILE}" \
        --name "${verifier_name}" \
        --alias "${verifier_name}" \
        --passcode "${verifier_passcode}" \
        --signer "${responder_name}" 2>&1) || verification_failed=true
    if [[ "${verification_failed}" == true ]]; then
        fail_workflow "KLI challenge verification failed for ${verifier_name} and ${responder_name}"
    fi

    [[ "${output}" == *"successfully responded to challenge words"* ]] &&
        success_message_found=true
    if [[ "${success_message_found}" == false ]]; then
        fail_workflow "KLI did not confirm a challenge response from ${responder_name} to ${verifier_name}"
    fi

    print_green "[challenge] ${verifier_name} verified ${responder_name}"
}

function keria_challenge_action() {
    local participant=$1
    local action=$2
    local peer_prefix=$3
    local result_json=""
    local challenge_action_failed=false
    local result_matches_request=false
    local expected_status=""

    result_json=$(run_signify_json "${QVI_SIGNIFY_DIR}/keria-challenge.ts" \
        --config /run/qvi/participants.json \
        --participant "${participant}" \
        --action "${action}" \
        --peer-prefix "${peer_prefix}" \
        --words-file "${CHALLENGE_WORD_CONTAINER_FILE}") ||
        challenge_action_failed=true
    if [[ "${challenge_action_failed}" == true ]]; then
        fail_workflow "KERIA challenge ${action} failed for ${participant} and ${peer_prefix}"
    fi

    expected_status=verified
    [[ "${action}" == respond ]] && expected_status=responded
    jq -e \
        --arg status "${expected_status}" \
        --arg participant "${participant}" \
        --arg peerPrefix "${peer_prefix}" \
        --arg challengeDigest "${CHALLENGE_DIGEST}" \
        '
          .status == $status and
          .participant == $participant and
          .peerPrefix == $peerPrefix and
          .challengeDigest == $challengeDigest and
          (.responseExnSaid | type == "string" and length > 0)
        ' <<< "${result_json}" >/dev/null && result_matches_request=true
    if [[ "${result_matches_request}" == false ]]; then
        fail_workflow "KERIA challenge ${action} result did not match the requested exchange"
    fi

    KERIA_CHALLENGE_EXN_SAID=$(printf '%s\n' "${result_json}" |
        jq -r '.responseExnSaid // .exnSaid // empty')
}

function record_challenge_receipt() {
    local relationship=$1
    local direction=$2
    local challenger_prefix=$3
    local responder_prefix=$4
    local verifier_type=$5
    local response_exn_said=$6
    local verified_at

    verified_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    append_proof_record "$(jq -cn \
        --arg relationship "${relationship}" \
        --arg direction "${direction}" \
        --arg challengerPrefix "${challenger_prefix}" \
        --arg responderPrefix "${responder_prefix}" \
        --arg verifierType "${verifier_type}" \
        --arg challengeDigest "${CHALLENGE_DIGEST}" \
        --arg verifiedAt "${verified_at}" \
        --arg responseExnSaid "${response_exn_said}" \
        '{
            type: "challenge",
            relationship: $relationship,
            direction: $direction,
            challengerPrefix: $challengerPrefix,
            responderPrefix: $responderPrefix,
            verifierType: $verifierType,
            challengeDigest: $challengeDigest,
            verifiedAt: $verifiedAt
        } + if $responseExnSaid == "" then {} else {responseExnSaid: $responseExnSaid} end')"
}

function complete_challenge_direction() {
    local relationship=$1
    local challenger_type=$2
    local challenger_id=$3
    local challenger_name=$4
    local challenger_passcode=$5
    local challenger_prefix=$6
    local responder_type=$7
    local responder_id=$8
    local responder_name=$9
    shift 9
    local responder_passcode=$1
    local responder_prefix=$2
    local response_failed=false
    local response_exn_said=""
    local challenger_uses_kli=false
    local responder_uses_kli=false

    generate_challenge_words
    KERIA_CHALLENGE_EXN_SAID=""

    [[ "${challenger_type}" == kli ]] && challenger_uses_kli=true
    [[ "${responder_type}" == kli ]] && responder_uses_kli=true
    if [[ "${responder_uses_kli}" == true ]]; then
        kli_challenge_respond_from_file "${CHALLENGE_WORD_CONTAINER_FILE}" \
            --name "${responder_name}" \
            --alias "${responder_name}" \
            --passcode "${responder_passcode}" \
            --recipient "${challenger_name}" >/dev/null ||
            response_failed=true
    else
        keria_challenge_action "${responder_id}" respond "${challenger_prefix}"
        response_exn_said="${KERIA_CHALLENGE_EXN_SAID}"
    fi
    if [[ "${response_failed}" == true ]]; then
        fail_workflow "Challenge response failed from ${responder_id} to ${challenger_id}"
    fi

    if [[ "${challenger_uses_kli}" == true ]]; then
        verify_kli_challenge \
            "${challenger_name}" \
            "${challenger_passcode}" \
            "${responder_name}" \
            "${responder_prefix}"
    else
        keria_challenge_action "${challenger_id}" verify "${responder_prefix}"
        [[ -n "${KERIA_CHALLENGE_EXN_SAID}" ]] &&
            response_exn_said="${KERIA_CHALLENGE_EXN_SAID}"
    fi

    record_challenge_receipt \
        "${relationship}" \
        "${challenger_id}->${responder_id}" \
        "${challenger_prefix}" \
        "${responder_prefix}" \
        "${challenger_type}" \
        "${response_exn_said}"
    clear_challenge_words
}

function challenge_relationship() {
    local relationship=$1
    local left_type=$2
    local left_id=$3
    local left_name=$4
    local left_passcode=$5
    local left_prefix=$6
    local right_type=$7
    local right_id=$8
    local right_name=$9
    shift 9
    local right_passcode=$1
    local right_prefix=$2

    complete_challenge_direction \
        "${relationship}" \
        "${left_type}" "${left_id}" "${left_name}" "${left_passcode}" "${left_prefix}" \
        "${right_type}" "${right_id}" "${right_name}" "${right_passcode}" "${right_prefix}"
    complete_challenge_direction \
        "${relationship}" \
        "${right_type}" "${right_id}" "${right_name}" "${right_passcode}" "${right_prefix}" \
        "${left_type}" "${left_id}" "${left_name}" "${left_passcode}" "${left_prefix}"
}

function validate_challenge_receipts() {
    local expected_receipt_keys=$1
    local receipt_set_matches=false

    jq -es \
        --argjson expected "${expected_receipt_keys}" \
        '
        [.[] | select(.type == "challenge")] as $receipts |
        ($receipts | length == 16) and
        ([$receipts[] | "\(.relationship)|\(.direction)"] |
            sort | unique) == ($expected | sort) and
        all($receipts[];
            (.challengerPrefix | type == "string" and length > 0) and
            (.responderPrefix | type == "string" and length > 0) and
            (.verifierType == "kli" or .verifierType == "keria") and
            (.challengeDigest | test("^[0-9a-f]{64}$")) and
            (.verifiedAt | type == "string" and length > 0))
        ' "${PROOF_MANIFEST}" >/dev/null &&
        receipt_set_matches=true
    if [[ "${receipt_set_matches}" == false ]]; then
        fail_workflow "Challenge proof did not contain the exact 16 complete relationship directions"
    fi
}

load_challenge_participant() {
    local participant_id=$1

    case "${participant_id}" in
        gar1)
            CHALLENGE_PARTICIPANT_TYPE=kli
            CHALLENGE_PARTICIPANT_NAME="${GAR1}"
            CHALLENGE_PARTICIPANT_PASSCODE="${GAR1_PASSCODE}"
            CHALLENGE_PARTICIPANT_PREFIX="${GAR1_PRE}"
            ;;
        gar2)
            CHALLENGE_PARTICIPANT_TYPE=kli
            CHALLENGE_PARTICIPANT_NAME="${GAR2}"
            CHALLENGE_PARTICIPANT_PASSCODE="${GAR2_PASSCODE}"
            CHALLENGE_PARTICIPANT_PREFIX="${GAR2_PRE}"
            ;;
        lar1)
            CHALLENGE_PARTICIPANT_TYPE=kli
            CHALLENGE_PARTICIPANT_NAME="${LAR1}"
            CHALLENGE_PARTICIPANT_PASSCODE="${LAR1_PASSCODE}"
            CHALLENGE_PARTICIPANT_PREFIX="${LAR1_PRE}"
            ;;
        lar2)
            CHALLENGE_PARTICIPANT_TYPE=kli
            CHALLENGE_PARTICIPANT_NAME="${LAR2}"
            CHALLENGE_PARTICIPANT_PASSCODE="${LAR2_PASSCODE}"
            CHALLENGE_PARTICIPANT_PREFIX="${LAR2_PRE}"
            ;;
        qar1)
            CHALLENGE_PARTICIPANT_TYPE=keria
            CHALLENGE_PARTICIPANT_NAME="${QAR1}"
            CHALLENGE_PARTICIPANT_PASSCODE=""
            CHALLENGE_PARTICIPANT_PREFIX="${QAR1_PRE}"
            ;;
        qar2)
            CHALLENGE_PARTICIPANT_TYPE=keria
            CHALLENGE_PARTICIPANT_NAME="${QAR2}"
            CHALLENGE_PARTICIPANT_PASSCODE=""
            CHALLENGE_PARTICIPANT_PREFIX="${QAR2_PRE}"
            ;;
        qar3)
            CHALLENGE_PARTICIPANT_TYPE=keria
            CHALLENGE_PARTICIPANT_NAME="${QAR3}"
            CHALLENGE_PARTICIPANT_PASSCODE=""
            CHALLENGE_PARTICIPANT_PREFIX="${QAR3_PRE}"
            ;;
        person)
            CHALLENGE_PARTICIPANT_TYPE=keria
            CHALLENGE_PARTICIPANT_NAME="${PERSON}"
            CHALLENGE_PARTICIPANT_PASSCODE=""
            CHALLENGE_PARTICIPANT_PREFIX="${PERSON_PRE}"
            ;;
        *)
            fail_workflow "Unknown challenge participant ${participant_id}"
            ;;
    esac
}

function challenge_response() {
  local relationships=(
      "GAR1-GAR2|gar1|gar2"
      "LAR1-LAR2|lar1|lar2"
      "QAR1-QAR2|qar1|qar2"
      "QAR1-QAR3|qar1|qar3"
      "QAR2-QAR3|qar2|qar3"
      "GAR1-QAR1|gar1|qar1"
      "QAR1-LAR1|qar1|lar1"
      "QAR1-Person|qar1|person"
  )
  local relationship_record
  local relationship
  local left_id
  local right_id
  local left_type
  local left_name
  local left_passcode
  local left_prefix
  local right_type
  local right_name
  local right_passcode
  local right_prefix
  local expected_receipt_lines=""
  local expected_receipt_keys=""

  print_green "------------------------------Authenticating Keystore control with Challenge Responses------------------------------"

  for relationship_record in "${relationships[@]}"; do
      IFS='|' read -r relationship left_id right_id <<< "${relationship_record}"

      load_challenge_participant "${left_id}"
      left_type="${CHALLENGE_PARTICIPANT_TYPE}"
      left_name="${CHALLENGE_PARTICIPANT_NAME}"
      left_passcode="${CHALLENGE_PARTICIPANT_PASSCODE}"
      left_prefix="${CHALLENGE_PARTICIPANT_PREFIX}"

      load_challenge_participant "${right_id}"
      right_type="${CHALLENGE_PARTICIPANT_TYPE}"
      right_name="${CHALLENGE_PARTICIPANT_NAME}"
      right_passcode="${CHALLENGE_PARTICIPANT_PASSCODE}"
      right_prefix="${CHALLENGE_PARTICIPANT_PREFIX}"

      challenge_relationship "${relationship}" \
          "${left_type}" "${left_id}" "${left_name}" "${left_passcode}" "${left_prefix}" \
          "${right_type}" "${right_id}" "${right_name}" "${right_passcode}" "${right_prefix}"
      expected_receipt_lines="${expected_receipt_lines}${relationship}|${left_id}->${right_id}"$'\n'
      expected_receipt_lines="${expected_receipt_lines}${relationship}|${right_id}->${left_id}"$'\n'
  done

  expected_receipt_keys=$(printf '%s' "${expected_receipt_lines}" |
      jq -Rsc 'split("\n") | map(select(length > 0))')
  validate_challenge_receipts "${expected_receipt_keys}"
  print_green "[challenge] Completed 16 directed responses across 8 trust relationships"
}

################# Create Multisigs and perform delegation ################
# Create Multisig AID for GLEIF External Delegated AID (GEDA)
function create_multisig_icp_config() {
    PRE1=$1
    PRE2=$2
    local wit_pre=$3
    cat "${WORKFLOW_CONFIG_DIR}/template-multi-sig-incept-config.jq" | \
        jq ".aids = [\"$PRE1\",\"$PRE2\"]" | \
        jq ".wits = [\"$wit_pre\"]" > "${WORKFLOW_CONFIG_DIR}/multi-sig-incept-config.json"

    print_lcyan "Multisig inception config JSON:"
    print_lcyan "$(cat "${WORKFLOW_CONFIG_DIR}/multi-sig-incept-config.json")"
}

function create_geda_multisig() {
    echo
    print_yellow "[External] Multisig Inception for GEDA"

    create_multisig_icp_config "${GAR1_PRE}" "${GAR2_PRE}" "${WAN_PRE}"

    # The following multisig commands run in parallel in Docker
    print_yellow "[External] Multisig Inception from ${GAR1}: ${GAR1_PRE}"
    klid gar1 multisig incept --name "${GAR1}" --alias "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" \
        --group "${GEDA_NAME}" \
        --file /config/multi-sig-incept-config.json

    echo

    klid gar2 multisig join --name "${GAR2}" \
        --passcode "${GAR2_PASSCODE}" \
        --group "${GEDA_NAME}" \
        --auto

    echo
    print_yellow "[External] Multisig Inception { ${GAR1}, ${GAR2} } - wait for signatures"
    echo
    print_dark_gray "Waiting on Compose-scoped GAR jobs"
    wait_kli_jobs gar1 gar2

    exists=$(kli list --name "${GAR1}" --passcode "${GAR1_PASSCODE}")
    local geda_was_created=false
    [[ "${exists}" == *"${GEDA_NAME}"* ]] && geda_was_created=true
    if [[ "${geda_was_created}" == false ]]; then
        print_red "[External] GEDA Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name "${GAR1}" --alias "${GEDA_NAME}" --passcode "${GAR1_PASSCODE}" | awk '/Identifier:/ {print $2}')
    GEDA_PRE=$(printf '%s\n' "${ms_prefix}" | tr -d '[:space:]')
    export GEDA_PRE
    print_green "[External] GEDA Multisig AID ${GEDA_NAME} with prefix: ${GEDA_PRE}"
}

function recreate_sally_containers() {
  local original_prefix="${DIRECT_SALLY_PRE}"
  local restarted_prefix=""
  local restart_failed=false
  local observation_failed=false
  local direct_info="${WORKFLOW_SECRET_DIR}/direct-sally.json"
  local prefix_was_preserved=false

  # Recreate Sally with the GEDA prefix that is now known. Sally must reopen
  # the existing Habery rather than silently incepting a new verifier.
  print_yellow "Recreating Sally container with new GEDA prefix ${GEDA_PRE}"
  write_private_runtime_config
  workflow_compose up \
      --detach \
      --force-recreate \
      --wait \
      --wait-timeout "${WORKFLOW_TIMEOUT_SECONDS}" \
      direct-sally ||
      restart_failed=true
  if [[ "${restart_failed}" == true ]]; then
      fail_workflow "Sally failed to restart with the GEDA authorization prefix"
  fi

  restarted_prefix=$(observe_sally_prefix \
      direct-sally \
      http://127.0.0.1:9823/oobi \
      "${DIRECT_SALLY_ALIAS}" \
      "${direct_info}") ||
      observation_failed=true
  if [[ "${observation_failed}" == true ]]; then
      fail_workflow "Unable to observe Sally after its GEDA-authorized restart"
  fi

  [[ "${restarted_prefix}" == "${original_prefix}" ]] &&
      prefix_was_preserved=true
  if [[ "${prefix_was_preserved}" == false ]]; then
      fail_workflow \
          "Sally changed AID during restart: expected ${original_prefix}, observed ${restarted_prefix}"
  fi

  DIRECT_SALLY_PRE=${restarted_prefix}
  export DIRECT_SALLY_PRE
}

function qars_resolve_geda_oobi() {
    local geda_oobi_is_missing=false
    local geda_resolution_failed=false
    local refresh_failed=false

    GEDA_OOBI=$(kli oobi generate --name "${GAR1}" --passcode "${GAR1_PASSCODE}" --alias "${GEDA_NAME}" --role witness)
    [[ -z "${GEDA_OOBI}" ]] && geda_oobi_is_missing=true
    if [[ "${geda_oobi_is_missing}" == true ]]; then
        print_red "Failed to generate GEDA OOBI"
        exit 1
    fi
    print_yellow "GEDA OOBI: ${GEDA_OOBI}"
    run_signify_json \
        "${QVI_SIGNIFY_DIR}/qars/qvi-resolve-oobi.ts" \
        --config "${PARTICIPANT_CONFIG_CONTAINER}" \
        --alias "${GEDA_NAME}" \
        --oobi "${GEDA_OOBI}" >/dev/null ||
        geda_resolution_failed=true
    if [[ "${geda_resolution_failed}" == true ]]; then
        fail_workflow "QARs could not resolve the GEDA OOBI"
    fi

    run_signify_json \
        "${QVI_SIGNIFY_DIR}/qars/qars-refresh-geda-multisig-state.ts" \
        --config "${PARTICIPANT_CONFIG_CONTAINER}" \
        --geda-prefix "${GEDA_PRE}" >/dev/null ||
        refresh_failed=true
    if [[ "${refresh_failed}" == true ]]; then
        fail_workflow "QARs could not refresh the GEDA multisig state"
    fi
}

qvi_inception_submission_is_exact() {
    local submission=$1
    local group_prefix=$2
    local qar1_prefix=$3
    local qar2_prefix=$4
    local qar3_prefix=$5

    printf '%s\n' "${submission}" |
        jq -e \
            --arg prefix "${group_prefix}" \
            --arg qar1 "${qar1_prefix}" \
            --arg qar2 "${qar2_prefix}" \
            --arg qar3 "${qar3_prefix}" \
            '
              . as $inception |
              .status == "inception-submitted" and
              .msPrefix == $prefix and
              (.operationNames | length == 3) and
              all(
                .operationNames[];
                . == ("group." + $prefix)
              ) and
              (.coordinationReceipts | length == 6) and
              all(
                .coordinationReceipts[];
                (.exnSaid | type == "string" and length > 0) and
                (.innerExchangeSaid | type == "string" and length > 0)
              ) and
              ([.coordinationReceipts[].innerExchangeSaid] |
                unique == [$prefix]) and
              ([.coordinationReceipts[] |
                  "\(.sender)|\(.recipient)"] |
                  unique | length == 6) and
              all(
                [$qar1, $qar2, $qar3][];
                . as $sender |
                ([$inception.coordinationReceipts[] |
                    select(.sender == $sender) |
                    .recipient] |
                    sort) ==
                    ([$qar1, $qar2, $qar3] |
                     map(select(. != $sender)) |
                     sort)
              )
            ' >/dev/null
}

qvi_endrole_operation_names_are_exact() {
    local artifact_path=$1
    local group_prefix=$2
    local qar1_agent_eid=$3
    local qar2_agent_eid=$4
    local qar3_agent_eid=$5

    jq -e \
        --arg prefix "${group_prefix}" \
        --arg eid1 "${qar1_agent_eid}" \
        --arg eid2 "${qar2_agent_eid}" \
        --arg eid3 "${qar3_agent_eid}" \
        '
          [
            ("endrole." + $prefix + ".agent." + $eid1),
            ("endrole." + $prefix + ".agent." + $eid2),
            ("endrole." + $prefix + ".agent." + $eid3)
          ] as $logicalOperations |
          (.operationNames | length == 9) and
          (.operationNames | sort) ==
            (($logicalOperations + $logicalOperations + $logicalOperations) |
              sort)
        ' \
        "${artifact_path}" >/dev/null
}

qvi_registry_operation_names_are_exact() {
    local registry_result=$1
    local registry_prefix=$2

    printf '%s\n' "${registry_result}" |
        jq -e \
            --arg expectedName "registry.${registry_prefix}" \
            '
              (.operationNames | length == 3) and
              all(.operationNames[]; . == $expectedName)
            ' >/dev/null
}

# QAR: Create delegated multisig QVI AID with GEDA as delegator
function create_qvi_multisig() {
    local delegator_prefix=""
    local delegated_multisig_info=""
    local creation_result=""
    local creation_failed=false
    local creation_result_is_exact=false
    local completion_result=""
    local completion_failed=false
    local completion_result_is_exact=false

    print_yellow "Creating QVI multisig AID with GEDA as delegator"

    delegator_prefix=$(kli status \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" |
        awk '/Identifier:/ {print $2}' |
        tr -d " \t\n\r")
    print_yellow "Delegator Prefix: ${delegator_prefix}"
    creation_result=$(run_signify_json \
      "${QVI_SIGNIFY_DIR}/qars/qars-create-qvi-multisig.ts" \
      --config "${PARTICIPANT_CONFIG_CONTAINER}" \
      --group-name "${QVI_NAME}" \
      --data-dir "${QVI_DATA_DIR}" \
      --delegator-prefix "${delegator_prefix}") ||
      creation_failed=true
    if [[ "${creation_failed}" == true ]]; then
        fail_workflow "QVI delegated inception could not be submitted"
    fi

    delegated_multisig_info=$(<"${LOCAL_QVI_DATA_DIR}/qvi-multisig-info.json")
    print_yellow "Delegated Multisig Info:"
    QVI_PRE=$(printf '%s\n' "${delegated_multisig_info}" | jq -er .msPrefix)
    qvi_inception_submission_is_exact \
        "${creation_result}" \
        "${QVI_PRE}" \
        "${QAR1_PRE}" \
        "${QAR2_PRE}" \
        "${QAR3_PRE}" &&
        creation_result_is_exact=true
    if [[ "${creation_result_is_exact}" == false ]]; then
        fail_workflow "QVI inception did not prove exact per-recipient coordination"
    fi
    append_proof_record "$(printf '%s\n' "${creation_result}" |
        jq -c '. + {type:"qvi-operation",operation:"delegated-inception"}')"
    echo
    print_lcyan "QVI Multisig Prefix: ${QVI_PRE}"
    echo

    print_lcyan "[External] GEDA members approve delegated inception with 'kli delegate confirm'"
    echo

    print_yellow "GAR1 confirm delegated inception"
    klid gar1 delegate confirm --name "${GAR1}" --alias "${GEDA_NAME}" --passcode "${GAR1_PASSCODE}" --interact --auto

    print_yellow "GAR2 confirm delegated inception"
    klid gar2 delegate confirm --name "${GAR2}" --alias "${GEDA_NAME}" --passcode "${GAR2_PASSCODE}" --interact --auto


    print_yellow "[GEDA] Waiting on delegated inception completion"
 
    print_dark_gray "waiting on Docker containers gar1, gar2"
    wait_kli_jobs gar1 gar2

    completion_result=$(run_signify_json \
        "${QVI_SIGNIFY_DIR}/qars/qars-complete-multisig-incept.ts" \
        --config "${PARTICIPANT_CONFIG_CONTAINER}" \
        --geda-prefix "${GEDA_PRE}" \
        --operation-artifact \
          "/vlei-workflow/qvi_data/qvi-multisig-info.json") ||
        completion_failed=true
    if [[ "${completion_failed}" == true ]]; then
        fail_workflow "QVI delegated inception did not converge after GEDA approval"
    fi

    MULTISIG_INFO=$(<"${LOCAL_QVI_DATA_DIR}/qvi-multisig-info.json")
    QVI_PRE=$(printf '%s\n' "${MULTISIG_INFO}" | jq -er .msPrefix)
    printf '%s\n' "${completion_result}" |
        jq -e \
            --arg qvi "${QVI_PRE}" \
            --argjson expectedNames \
              "$(printf '%s\n' "${MULTISIG_INFO}" |
                  jq -c '.operationNames')" \
            '
              .status == "completed" and
              (.operationEvidence | length == 3) and
              ([.operationEvidence[].name] | sort) ==
                ($expectedNames | sort) and
              all(
                .operationEvidence[];
                .done == true and
                .error == null and
                .result.kind == "event" and
                .result.said == $qvi and
                .result.prefix == $qvi and
                .result.sequence == "0"
              )
            ' >/dev/null &&
        completion_result_is_exact=true
    if [[ "${completion_result_is_exact}" == false ]]; then
        fail_workflow "QVI delegated inception completion did not retain three terminal operation results"
    fi
    append_proof_record "$(printf '%s\n' "${completion_result}" |
        jq -c \
            '{type:"qvi-operation",operation:"delegated-inception-completion"} + .')"
    print_green "[QVI] Multisig AID ${QVI_NAME} with prefix: ${QVI_PRE}"
}

# QVI: Authorize all agent endpoint roles and derive one multisig OOBI.
QVI_OOBI=""
function authorize_qvi_multisig_agent_endpoint_role(){
    local oobi_artifact="${LOCAL_QVI_DATA_DIR}/qvi-oobi.json"
    local oobi_artifact_is_valid=false
    local authorization_result=""
    local authorization_failed=false
    local authorization_result_is_exact=false
    local endrole_operation_names_are_exact=false

    print_yellow "Authorizing QVI multisig agent endpoint role"
    authorization_result=$(run_signify_json \
      "${QVI_SIGNIFY_DIR}/qars/qars-authorize-endroles-get-qvi-oobi.ts" \
      --config /run/qvi/participants.json \
      --group-name "${QVI_NAME}" \
      --data-dir "${QVI_DATA_DIR}") || authorization_failed=true
    if [[ "${authorization_failed}" == true ]]; then
        fail_workflow "QVI agent endpoint-role authorization failed"
    fi

    jq -e \
      --arg qviPrefix "${QVI_PRE}" \
      --arg delegator "${GEDA_PRE}" \
      --arg qar1 "${QAR1_PRE}" \
      --arg qar2 "${QAR2_PRE}" \
      --arg qar3 "${QAR3_PRE}" \
      --arg eid1 "${QAR1_AGENT_EID}" \
      --arg eid2 "${QAR2_AGENT_EID}" \
      --arg eid3 "${QAR3_AGENT_EID}" \
      '
        . as $root |
        .qviPrefix == $qviPrefix and
        (
          .multisigOobi |
          capture(
            "^https?://[^/]+(?<path>/[^?#]*)(?:[?#].*)?$"
          ).path
        ) == "/oobi/\($qviPrefix)" and
        (.agentEndpoints | length == 3) and
        ([.agentEndpoints[].eid] | unique | length == 3) and
        ([.agentEndpoints[].url] | unique | length == 3) and
        ([.agentEndpoints[].eid] | sort) ==
          ([$eid1, $eid2, $eid3] | sort) and
        all(
          .agentEndpoints[];
          (.url | test("^https?://"))
        ) and
        .groupState.prefix == $qviPrefix and
        .groupState.delegator == $delegator and
        .groupState.sequence == "0" and
        .groupState.signingThreshold == ["1/3", "1/3", "1/3"] and
        .groupState.nextThreshold == ["1/3", "1/3", "1/3"] and
        (.groupState.establishmentDigest | type == "string" and length > 0) and
        (.groupState.signingMembers | sort) == ([$qar1, $qar2, $qar3] | sort) and
        (.groupState.rotationMembers | sort) == ([$qar1, $qar2, $qar3] | sort) and
        (.groupObservations | length == 3) and
        ([.groupObservations[].observerAid] | sort) ==
          ([$qar1, $qar2, $qar3] | sort) and
        all(.groupObservations[]; .snapshot == $root.groupState) and
        (.coordinationReceipts | length == 18) and
        all(.coordinationReceipts[];
            (.exnSaid | type == "string" and length > 0) and
            (.innerExchangeSaid | type == "string" and length > 0)) and
        ([.coordinationReceipts[].innerExchangeSaid] |
          unique | length == 3) and
        all(
          [$qar1, $qar2, $qar3][];
          . as $sender |
          all(
            [$qar1, $qar2, $qar3][] |
              select(. != $sender);
            . as $recipient |
            ([ $root.coordinationReceipts[] |
                select(
                  .sender == $sender and
                  .recipient == $recipient
                ) ] |
                length) == 3
          )
        )
      ' "${oobi_artifact}" >/dev/null && oobi_artifact_is_valid=true
    if [[ "${oobi_artifact_is_valid}" == false ]]; then
        fail_workflow \
            "QVI agent OOBI artifact did not prove the expected endpoints, group state, and coordination"
    fi

    qvi_endrole_operation_names_are_exact \
        "${oobi_artifact}" \
        "${QVI_PRE}" \
        "${QAR1_AGENT_EID}" \
        "${QAR2_AGENT_EID}" \
        "${QAR3_AGENT_EID}" &&
        endrole_operation_names_are_exact=true
    if [[ "${endrole_operation_names_are_exact}" == false ]]; then
        fail_workflow \
            "QVI endpoint-role artifact did not record three member observations of each logical end-role operation"
    fi

    printf '%s\n' "${authorization_result}" |
        jq -e \
            --argjson expectedNames \
              "$(jq -c '.operationNames' "${oobi_artifact}")" \
            --argjson expectedSaids \
              "$(jq -c \
                  '[.coordinationReceipts[].innerExchangeSaid] |
                    unique' \
                  "${oobi_artifact}")" \
            '
              . as $root |
              (.operationEvidence | length == 9) and
              ([.operationEvidence[].name] | sort) ==
                ($expectedNames | sort) and
              ($expectedSaids | length == 3) and
              ([.operationEvidence[].result.said] | unique | sort) ==
                ($expectedSaids | sort) and
              all(
                $expectedSaids[];
                . as $said |
                ([$root.operationEvidence[] |
                    select(.result.said == $said)] |
                    length) == 3
              ) and
              all(
                .operationEvidence[];
                .done == true and
                .error == null and
                .result.kind == "event" and
                (.result.said |
                  type == "string" and length > 0) and
                .result.route == "/end/role/add"
              )
            ' >/dev/null &&
        authorization_result_is_exact=true
    if [[ "${authorization_result_is_exact}" == false ]]; then
        fail_workflow "QVI endpoint-role authorization did not retain nine terminal operation results"
    fi

    QVI_OOBI=$(jq -er '.multisigOobi' "${oobi_artifact}")

    append_proof_record "$(jq -c '{type: "qvi-state"} + .' "${oobi_artifact}")"
    append_proof_record "$(printf '%s\n' "${authorization_result}" |
        jq -c '{type:"qvi-operation",operation:"authorize-agent-endroles"} + .')"
    print_green "Collected one canonical multisig OOBI and common QVI group state"
}

# Create Legal Entity Multisig
function create_le_multisig() {
    echo
    print_yellow "[LE] Multisig Inception for LE"

    create_multisig_icp_config "${LAR1_PRE}" "${LAR2_PRE}" "${WIL_PRE}"

    # Follow commands run in parallel
    print_yellow "[LE] Multisig Inception from ${LAR1}: ${LAR1_PRE}"
    klid lar1 multisig incept --name "${LAR1}" --alias "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --group "${LE_NAME}" \
        --file /config/multi-sig-incept-config.json

    echo

    klid lar2 multisig join --name "${LAR2}" \
        --passcode "${LAR2_PASSCODE}" \
        --group "${LE_NAME}" \
        --auto

    echo
    print_yellow "[LE] Multisig Inception { ${LAR1}, ${LAR2} } - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers lar1 and lar2"
    wait_kli_jobs lar1 lar2

    exists=$(kli list --name "${LAR1}" --passcode "${LAR1_PASSCODE}")
    local le_was_created=false
    [[ "${exists}" == *"${LE_NAME}"* ]] && le_was_created=true
    if [[ "${le_was_created}" == false ]]; then
        print_red "[LE] LE Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name "${LAR1}" --alias "${LE_NAME}" --passcode "${LAR1_PASSCODE}" | awk '/Identifier:/ {print $2}')
    LE_PRE=$(printf '%s\n' "${ms_prefix}" | tr -d '[:space:]')
    export LE_PRE
    print_green "[LE] LE Multisig AID ${LE_NAME} with prefix: ${LE_PRE}"
}

# QAR: Resolve GEDA and LE multisig OOBIs
function qars_resolve_le_oobi() {
    local le_oobi_is_missing=false
    local le_resolution_failed=false

    LE_OOBI=$(kli oobi generate --name "${LAR1}" --passcode "${LAR1_PASSCODE}" --alias "${LE_NAME}" --role witness)
    [[ -z "${LE_OOBI}" ]] && le_oobi_is_missing=true
    if [[ "${le_oobi_is_missing}" == true ]]; then
        print_red "Failed to generate LE OOBI"
        exit 1
    fi
    echo "LE OOBI: ${LE_OOBI}"
    run_signify_json \
        "${QVI_SIGNIFY_DIR}/qars/qvi-resolve-oobi.ts" \
        --config "${PARTICIPANT_CONFIG_CONTAINER}" \
        --alias "${LE_NAME}" \
        --oobi "${LE_OOBI}" >/dev/null ||
        le_resolution_failed=true
    if [[ "${le_resolution_failed}" == true ]]; then
        fail_workflow "QARs could not resolve the LE OOBI"
    fi
}

# GEDA and LE: Resolve QVI OOBI
function resolve_qvi_oobi() {
    echo
    print_yellow "Resolving the canonical QVI multisig OOBI for GEDA and LE"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QVI_NAME}" --passcode "${GAR1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QVI_NAME}" --passcode "${GAR2_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QVI_NAME}" --passcode "${LAR1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QVI_NAME}" --passcode "${LAR2_PASSCODE}" --oobi "${QVI_OOBI}"

    print_yellow "Resolving the canonical QVI multisig OOBI for Person"
    sig_tsx "${QVI_SIGNIFY_DIR}/person-resolve-qvi-oobi.ts" \
      --config /run/qvi/participants.json \
      --group-name "${QVI_NAME}" \
      --oobi-file "${QVI_DATA_DIR}/qvi-oobi.json"
    echo
}

############################ QVI Credential ##################################
# GEDA: Create GEDA credential registry
function create_geda_reg() {
    echo
    print_yellow "Creating GEDA registry"
    NONCE=$(kli nonce)

    klid gar1 vc registry incept \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --usage "QVI Credential Registry for GEDA" \
        --nonce "${NONCE}" \
        --registry-name "${GEDA_REGISTRY}"

    klid gar2 vc registry incept \
        --name "${GAR2}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR2_PASSCODE}" \
        --usage "QVI Credential Registry for GEDA" \
        --nonce "${NONCE}" \
        --registry-name "${GEDA_REGISTRY}"

    wait_kli_jobs gar1 gar2

    echo
    print_green "QVI Credential Registry created for GEDA"
    echo
}

# GEDA: Create QVI credential
function prepare_qvi_cred_data() {
    print_bg_blue "[External] Preparing QVI credential data"
    jq -n --arg lei "${LE_LEI}" '{LEI: $lei}' \
        > "${KLI_DATA_DIR}/temp-data/qvi-cred-data.json"

    print_lcyan "QVI Credential Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/qvi-cred-data.json")"
}

function create_qvi_credential() {
    echo
    print_green "[External] GEDA creating QVI credential"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    
    klid gar1 vc create \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/acdc-info/temp-data/qvi-cred-data.json \
        --rules @/acdc-info/rules/rules.json \
        --time "${KLI_TIME}"

    klid gar2 vc create \
        --name "${GAR2}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR2_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/acdc-info/temp-data/qvi-cred-data.json \
        --rules @/acdc-info/rules/rules.json \
        --time "${KLI_TIME}"

    echo
    print_yellow "[External] GEDA creating QVI credential - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers gar1 and gar2"
    wait_kli_jobs gar1 gar2

    echo
    print_lcyan "[External] QVI Credential created for GEDA"
    echo
}

# GEDA: IPEX Grant QVI credential to QVI
function grant_qvi_credential() {
    SAID=$(kli vc list \
        --name "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d '[:space:]')

    echo
    print_yellow $'[External] IPEX GRANTing QVI credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    klid gar1 ipex grant \
        --name "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}"

    klid gar2 ipex grant \
        --name "${GAR2}" \
        --passcode "${GAR2_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}"

    echo
    print_yellow "[External] Waiting for IPEX messages to be witnessed"
    echo 
    print_dark_gray "waiting on Docker containers gar1 and gar2"
    wait_kli_jobs gar1 gar2


    echo
    print_green "[External] QVI Credential issued to QVI"
    echo
}

admit_qvi_received_credential() {
    local story_label=$1
    local issuer_prefix=$2
    local schema=$3
    local credential_said=$4
    local admission_result=""
    local admission_failed=false
    local admission_is_exact=false

    admission_result=$(run_signify_json \
        "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi.ts" \
        --config "${PARTICIPANT_CONFIG_CONTAINER}" \
        --group-name "${QVI_NAME}" \
        --issuer-prefix "${issuer_prefix}" \
        --credential-said "${credential_said}") ||
        admission_failed=true
    if [[ "${admission_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to admit ${story_label} credential ${credential_said}"
    fi

    printf '%s\n' "${admission_result}" |
        jq -e \
            --arg said "${credential_said}" \
            --arg issuer "${issuer_prefix}" \
            --arg schema "${schema}" \
            --arg issuee "${QVI_PRE}" \
            '
              .status == "admitted" and
              .credentialSaid == $said and
              (.observations | length == 3) and
              ([.observations[].said] | unique == [$said]) and
              ([.observations[].issuer] | unique == [$issuer]) and
              ([.observations[].schema] | unique == [$schema]) and
              ([.observations[].issuee] | unique == [$issuee]) and
              ([.observations[].statusSequence] | unique == ["0"]) and
              ([.observations[].currentTelDigest] | unique | length == 1)
            ' >/dev/null &&
        admission_is_exact=true
    if [[ "${admission_is_exact}" == false ]]; then
        fail_workflow "[QVI] ${story_label} admission did not converge on all three QARs"
    fi

    append_proof_record "$(printf '%s\n' "${admission_result}" |
        jq -c \
            --arg story "${story_label}-admitted" \
            '. + {type:"credential",event:"admission",story:$story}')"
}

# QVI: Admit QVI credential from GEDA
function admit_qvi_credential() {
    QVI_CRED_SAID=$(kli vc list \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d " \t\n\r")
    echo
    print_yellow "[QVI] Admitting QVI Credential ${QVI_CRED_SAID} from GEDA"
    admit_qvi_received_credential \
        "QVI" \
        "${GEDA_PRE}" \
        "${QVI_SCHEMA}" \
        "${QVI_CRED_SAID}"

    echo
    print_green "[QVI] Admitted QVI credential"
    echo
}

function present_qvi_cred_to_sally_signify() {
  local presentation_result=""
  local presentation_failed=false
  local presentation_boundary
  local credential_said_is_valid=false

  QVI_CRED_SAID=$(kli vc list \
      --name "${GAR1}" \
      --alias "${GEDA_NAME}" \
      --passcode "${GAR1_PASSCODE}" \
      --issued \
      --said \
      --schema "${QVI_SCHEMA}" | tr -d '[:space:]')
  [[ -n "${QVI_CRED_SAID}" ]] && credential_said_is_valid=true
  if [[ "${credential_said_is_valid}" == false ]]; then
      fail_workflow "[QVI] Unable to identify the active QVI credential"
  fi

  presentation_boundary=$(utc_now)
  print_yellow "[QVI] Presenting QVI Credential ${QVI_CRED_SAID} to Sally"
  presentation_result=$(run_signify_json \
    "${QVI_SIGNIFY_DIR}/qars/qars-present-credential.ts" \
    --config /run/qvi/participants.json \
    --group-name "${QVI_NAME}" \
    --credential-said "${QVI_CRED_SAID}" \
    --expected-issuer "${GEDA_PRE}" \
    --expected-schema "${QVI_SCHEMA}" \
    --expected-issuee "${QVI_PRE}" \
    --recipient-prefix "${DIRECT_SALLY_PRE}" \
    --expected-status active) || presentation_failed=true
  if [[ "${presentation_failed}" == true ]]; then
      fail_workflow "[QVI] Failed to transmit the active QVI credential to Sally"
  fi

  append_proof_record "$(printf '%s\n' "${presentation_result}" |
      jq -c '. + {type:"credential",event:"presentation",story:"QVI-active"}')"
  wait_for_active_sally_evidence \
      "QVI-active" \
      "${presentation_boundary}" \
      "${QVI_CRED_SAID}" \
      "${QVI_SCHEMA}" \
      "${QVI_PRE}" \
      "${GEDA_PRE}"
  print_green "[QVI] Sally reported the exact active QVI Credential"
}

############################ LE Credential ##################################
# QVI: Prepare, create, and Issue LE credential to GEDA
# Create QVI credential registry
function create_qvi_reg() {
    local registry_result=""
    local registry_failed=false
    local registry_result_is_exact=false
    local registry_operation_names_are_exact=false

    registry_result=$(run_signify_json \
      "${QVI_SIGNIFY_DIR}/qars/qars-registry-create.ts" \
      --config "${PARTICIPANT_CONFIG_CONTAINER}" \
      --group-name "${QVI_NAME}" \
      --registry-name "${QVI_REGISTRY}" \
      --data-dir "${QVI_DATA_DIR}") ||
      registry_failed=true
    if [[ "${registry_failed}" == true ]]; then
        fail_workflow "[QVI] Credential registry creation failed"
    fi

    QVI_REG_REGK=$(jq -er .registryRegk \
        "${LOCAL_QVI_DATA_DIR}/qvi-registry-info.json")
    qvi_registry_operation_names_are_exact \
        "${registry_result}" \
        "${QVI_REG_REGK}" &&
        registry_operation_names_are_exact=true
    if [[ "${registry_operation_names_are_exact}" == false ]]; then
        fail_workflow \
            "[QVI] Registry result did not record the same logical operation in all three agent stores"
    fi

    printf '%s\n' "${registry_result}" |
        jq -e \
            --arg registry "${QVI_REG_REGK}" \
            --arg qar1 "${QAR1_PRE}" \
            --arg qar2 "${QAR2_PRE}" \
            --arg qar3 "${QAR3_PRE}" \
            '
              . as $registryResult |
              .status == "created" and
              .registryRegk == $registry and
              (.operationEvidence | length == 3) and
              ([.operationEvidence[].name] | sort) ==
                (.operationNames | sort) and
              all(
                .operationEvidence[];
                .done == true and
                .error == null and
                .result.kind == "registry-anchor" and
                .result.said == $registry and
                .result.prefix == $registry and
                .result.sequence == "0"
              ) and
              (.coordinationReceipts | length == 6) and
              all(
                .coordinationReceipts[];
                (.exnSaid | type == "string" and length > 0) and
                (.innerExchangeSaid | type == "string" and length > 0)
              ) and
              ([.coordinationReceipts[].innerExchangeSaid] |
                unique == [$registry]) and
              ([.coordinationReceipts[] |
                  "\(.sender)|\(.recipient)"] |
                  unique | length == 6) and
              all(
                [$qar1, $qar2, $qar3][];
                . as $sender |
                ([$registryResult.coordinationReceipts[] |
                    select(.sender == $sender) |
                    .recipient] |
                    sort) ==
                    ([$qar1, $qar2, $qar3] |
                     map(select(. != $sender)) |
                     sort)
              )
            ' \
            >/dev/null &&
        registry_result_is_exact=true
    if [[ "${registry_result_is_exact}" == false ]]; then
        fail_workflow "[QVI] Registry result did not match its persisted artifact"
    fi

    append_proof_record "$(printf '%s\n' "${registry_result}" |
        jq -c '. + {type:"credential",event:"registry"}')"
    print_green "[QVI] Credential Registry created for QVI with regk: ${QVI_REG_REGK}"
}

# QVI: Prepare QVI edge data
function prepare_qvi_edge() {
    QVI_CRED_SAID=$(kli vc list \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d '[:space:]')
    print_bg_blue "[QVI] Preparing QVI edge with QVI Credential SAID: ${QVI_CRED_SAID}"
    jq -n \
        --arg credentialSaid "${QVI_CRED_SAID}" \
        --arg schema "${QVI_SCHEMA}" \
        '{d: "", qvi: {n: $credentialSaid, s: $schema}}' \
        > "${KLI_DATA_DIR}/temp-data/qvi-edge.json"
    kli saidify --file /acdc-info/temp-data/qvi-edge.json
    print_lcyan "Legal Entity edge Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/qvi-edge.json" | jq )"
}

# QVI: Prepare LE credential data
function prepare_le_cred_data() {
    print_yellow "[QVI] Preparing LE credential data"
    jq -n --arg lei "${LE_LEI}" '{LEI: $lei}' \
        > "${KLI_DATA_DIR}/temp-data/legal-entity-data.json"
}

# QVI: Create LE credential
record_qvi_issuance_result() {
    local story_label=$1
    local issuance_result=$2
    local expected_schema=$3
    local expected_issuee=$4
    local issuance_is_exact=false

    printf '%s\n' "${issuance_result}" |
        jq -e \
            --arg issuer "${QVI_PRE}" \
            --arg schema "${expected_schema}" \
            --arg issuee "${expected_issuee}" \
            --arg qar1 "${QAR1_PRE}" \
            --arg qar2 "${QAR2_PRE}" \
            --arg qar3 "${QAR3_PRE}" \
            '
              def exact_fanout($receipts; $expected_inner):
                ($receipts | length == 6) and
                all(
                  $receipts[];
                  (.exnSaid | type == "string" and length > 0) and
                  (.innerExchangeSaid | type == "string" and length > 0)
                ) and
                ([$receipts[] |
                    "\(.sender)|\(.recipient)"] |
                    unique | length == 6) and
                all(
                  [$qar1, $qar2, $qar3][];
                  . as $sender |
                  ([$receipts[] |
                      select(.sender == $sender) |
                      .recipient] |
                      sort) ==
                      ([$qar1, $qar2, $qar3] |
                       map(select(. != $sender)) |
                       sort)
                ) and
                (
                  if $expected_inner == null then
                    ([$receipts[].innerExchangeSaid] |
                      unique | length == 1)
                  else
                    all(
                      $receipts[];
                      .innerExchangeSaid == $expected_inner
                    )
                  end
                );
              . as $issuance |
              $issuance.status == "converged" and
              ($issuance.observations | length == 3) and
              ([$issuance.observations[].observerAid] | sort) ==
                ([$qar1, $qar2, $qar3] | sort) and
              all(
                $issuance.observations[];
                (.said | type == "string" and length > 0) and
                (.registry | type == "string" and length > 0) and
                (.currentTelDigest | type == "string" and length > 0)
              ) and
              ([$issuance.observations[].said] | unique | length == 1) and
              ([$issuance.observations[].issuer] | unique == [$issuer]) and
              ([$issuance.observations[].schema] | unique == [$schema]) and
              ([$issuance.observations[].issuee] | unique == [$issuee]) and
              ([$issuance.observations[].registry] | unique | length == 1) and
              ([$issuance.observations[].statusSequence] | unique == ["0"]) and
              all(
                $issuance.observations[];
                .priorTelDigest == null
              ) and
              ([$issuance.observations[].currentTelDigest] | unique | length == 1) and
              ($issuance.operationEvidence | length == 3) and
              all(
                $issuance.operationEvidence[];
                .done == true and
                .error == null and
                .name == ("credential." + .result.said) and
                .result.kind == "credential" and
                .result.said == $issuance.observations[0].said and
                .result.prefix == $issuer and
                .result.schema == $schema
              ) and
              exact_fanout(
                $issuance.issuanceReceipts;
                $issuance.observations[0].currentTelDigest
              ) and
              exact_fanout($issuance.coordinationReceipts; null)
            ' \
            >/dev/null &&
        issuance_is_exact=true
    if [[ "${issuance_is_exact}" == false ]]; then
        fail_workflow "[QVI] ${story_label} issuance did not prove exact three-QAR credential and fan-out convergence"
    fi

    append_proof_record "$(printf '%s\n' "${issuance_result}" |
        jq -c \
            --arg story "${story_label}-issued" \
            '. + {type:"credential",event:"issuance",story:$story}')"
}

function create_and_grant_le_credential() {
    local issuance_result=""
    local issuance_failed=false

    echo
    print_green "[QVI] creating LE credential"

    print_lcyan "[QVI] Legal Entity edge Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/qvi-edge.json" | jq )"

    print_lcyan "[QVI] Legal Entity Credential Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/legal-entity-data.json")"

    issuance_result=$(run_signify_json \
      "${QVI_SIGNIFY_DIR}/qars/qars-le-credential-create.ts" \
      --config "${PARTICIPANT_CONFIG_CONTAINER}" \
      --group-name "${QVI_NAME}" \
      --data-dir "/acdc-info" \
      --issuee-prefix "${LE_PRE}" \
      --artifact-dir "${QVI_DATA_DIR}") ||
      issuance_failed=true
    if [[ "${issuance_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to create and grant the LE credential"
    fi
    record_qvi_issuance_result \
        "LE" \
        "${issuance_result}" \
        "${LE_SCHEMA}" \
        "${LE_PRE}"

    echo
    print_lcyan "[QVI] LE Credential created"
    echo
}

# LE: Admit LE credential from QVI
function admit_le_credential() {
    print_dark_gray "Listing IPEX Grants for LAR 1"
    SAID=$(kli ipex list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | uniq | tr -d '[:space:]') # there are three grant messages, one from each QAR, yet all share the same SAID, so uniq condenses them to one

    print_dark_gray "Listing IPEX Grants for LAR 2"
    # prime the mailbox to properly receive the messages.
    kli ipex list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | uniq

    echo
    print_yellow "[LE] Admitting LE Credential ${SAID} to ${LE_NAME} as ${LAR1}"

    KLI_TIME=$(kli time)
    klid lar1 ipex admit \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --time "${KLI_TIME}"

    print_green "[LE] Admitting LE Credential ${SAID} to ${LE_NAME} as ${LAR2}"
    klid lar2 ipex join \
        --name "${LAR2}" \
        --passcode "${LAR2_PASSCODE}" \
        --auto

    wait_kli_jobs lar1 lar2

    echo
    print_green "[LE] Admitted LE credential"
    echo
}

function present_le_cred_to_sally() {
  local presentation_result=""
  local presentation_failed=false
  local presentation_boundary

  load_qvi_leaf_credential_said \
      "${LOCAL_QVI_DATA_DIR}/le-cred-info.json" \
      "leCredSAID" \
      "LE"
  LE_CRED_SAID="${LOADED_CREDENTIAL_SAID}"
  presentation_boundary=$(utc_now)

  print_yellow "[QVI] Presenting LE Credential ${LE_CRED_SAID} to Sally"
  presentation_result=$(run_signify_json \
    "${QVI_SIGNIFY_DIR}/qars/qars-present-credential.ts" \
    --config /run/qvi/participants.json \
    --group-name "${QVI_NAME}" \
    --credential-said "${LE_CRED_SAID}" \
    --expected-issuer "${QVI_PRE}" \
    --expected-schema "${LE_SCHEMA}" \
    --expected-issuee "${LE_PRE}" \
    --recipient-prefix "${DIRECT_SALLY_PRE}" \
    --expected-status active) || presentation_failed=true
  if [[ "${presentation_failed}" == true ]]; then
      fail_workflow "[QVI] Failed to transmit the active LE credential to Sally"
  fi

  append_proof_record "$(printf '%s\n' "${presentation_result}" |
      jq -c '. + {type:"credential",event:"presentation",story:"LE-active"}')"
  wait_for_active_sally_evidence \
      "LE-active" \
      "${presentation_boundary}" \
      "${LE_CRED_SAID}" \
      "${LE_SCHEMA}" \
      "${LE_PRE}" \
      "${QVI_PRE}"
  print_green "[QVI] Sally reported the exact active LE Credential"
}

# LE: Create LE credential registry
function create_le_reg() {
    echo
    print_yellow "[LE] Creating LE registry"
    NONCE=$(kli nonce)

    klid lar1 vc registry incept \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --usage "Legal Entity Credential Registry for LE" \
        --nonce "${NONCE}" \
        --registry-name "${LE_REGISTRY}"

    klid lar2 vc registry incept \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --usage "Legal Entity Credential Registry for LE" \
        --nonce "${NONCE}" \
        --registry-name "${LE_REGISTRY}"

    wait_kli_jobs lar1 lar2

    echo
    print_green "[LE] Legal Entity Credential Registry created for LE"
    echo
}

########################## OOR Auth ####################################
# Prepare LE edge for OOR Auth credential, also used for ECR Auth credential.
function prepare_le_edge() {
    LE_SAID=$(kli vc list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --said \
        --schema "${LE_SCHEMA}" | tr -d '[:space:]')
    print_bg_blue "[LE] Preparing LE edge with LE Credential SAID: ${LE_SAID}"
    jq -n \
        --arg credentialSaid "${LE_SAID}" \
        --arg schema "${LE_SCHEMA}" \
        '{d: "", le: {n: $credentialSaid, s: $schema}}' \
        > "${KLI_DATA_DIR}/temp-data/legal-entity-edge.json"
    kli saidify --file /acdc-info/temp-data/legal-entity-edge.json
}

# Prepare OOR Auth credential data
function prepare_oor_auth_data() {
    jq -n \
        --arg aid "${PERSON_PRE}" \
        --arg lei "${LE_LEI}" \
        --arg personLegalName "${PERSON_NAME}" \
        --arg officialRole "${PERSON_OOR}" \
        '{
            AID: $aid,
            LEI: $lei,
            personLegalName: $personLegalName,
            officialRole: $officialRole
        }' > "${KLI_DATA_DIR}/temp-data/oor-auth-data.json"
}

# LE: Create OOR Auth credential
function create_oor_auth_credential() {
    print_lcyan "[LE] OOR Auth data JSON"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/oor-auth-data.json")"

    echo

    KLI_TIME=$(kli time | tr -d '[:space:]')
    print_green "[LE] LE creating OOR Auth credential at time ${KLI_TIME}"

    klid lar1 vc create \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${OOR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/acdc-info/temp-data/oor-auth-data.json \
        --edges @/acdc-info/temp-data/legal-entity-edge.json \
        --rules @/acdc-info/rules/rules.json \
        --time "${KLI_TIME}"

    klid lar2 vc create \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${OOR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/acdc-info/temp-data/oor-auth-data.json \
        --edges @/acdc-info/temp-data/legal-entity-edge.json \
        --rules @/acdc-info/rules/rules.json \
        --time "${KLI_TIME}"

    wait_kli_jobs lar1 lar2

    echo
    print_lcyan "[LE] LE created OOR Auth credential"
    echo
}

# LE: Grant OOR Auth credential to QVI
function grant_oor_auth_credential() {
    SAID=$(kli vc list \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --issued \
        --said \
        --schema ${OOR_AUTH_SCHEMA} | \
        tail -1 | tr -d '[:space:]') # get the last credential, the OOR Auth credential

    echo
    print_yellow $'[LE] IPEX GRANTing OOR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"

    KLI_TIME=$(kli time | tr -d '[:space:]') # Use consistent time so SAID of grant is same
    klid lar1 ipex grant \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}"

    klid lar2 ipex grant \
        --name "${LAR2}" \
        --passcode "${LAR2_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}"

    wait_kli_jobs lar1 lar2

    echo
    echo
    print_green "[LE] Granted OOR Auth credential to QVI"
    echo
}

# QVI: Admit OOR Auth credential
function admit_oor_auth_credential() {
    OOR_AUTH_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --issued \
        --said \
        --schema ${OOR_AUTH_SCHEMA} | tr -d '[:space:]')
    echo
    print_yellow "[QVI] Admitting OOR Auth Credential ${OOR_AUTH_SAID} from LE"
    admit_qvi_received_credential \
        "OOR-Auth" \
        "${LE_PRE}" \
        "${OOR_AUTH_SCHEMA}" \
        "${OOR_AUTH_SAID}"

    echo
    print_green "[QVI] Admitted OOR Auth Credential"
    echo
}

########################### OOR Credential ##############################
# 24. QVI: Issue, grant OOR to Person and Person admits OOR
# Prepare OOR Auth edge data
function prepare_oor_auth_edge() {
    OOR_AUTH_SAID=$(kli vc list \
        --name ${LAR1} \
        --alias ${LE_NAME} \
        --passcode "${LAR1_PASSCODE}" \
        --issued \
        --said \
        --schema ${OOR_AUTH_SCHEMA} | tr -d '[:space:]')
    print_bg_blue "[QVI] Preparing [OOR Auth] edge with [OOR Auth] Credential SAID: ${OOR_AUTH_SAID}"
    jq -n \
        --arg credentialSaid "${OOR_AUTH_SAID}" \
        --arg schema "${OOR_AUTH_SCHEMA}" \
        '{d: "", auth: {n: $credentialSaid, s: $schema, o: "I2I"}}' \
        > "${KLI_DATA_DIR}/temp-data/oor-auth-edge.json"
    kli saidify --file /acdc-info/temp-data/oor-auth-edge.json
}

# Prepare OOR credential data
function prepare_oor_cred_data() {
    print_bg_blue "[QVI] Preparing OOR credential data"
    jq -n \
        --arg lei "${LE_LEI}" \
        --arg personLegalName "${PERSON_NAME}" \
        --arg officialRole "${PERSON_OOR}" \
        '{
            LEI: $lei,
            personLegalName: $personLegalName,
            officialRole: $officialRole
        }' > "${KLI_DATA_DIR}/temp-data/oor-data.json"
}

# Create OOR credential in QVI, issued to the Person
function create_and_grant_oor_credential() {
    local credential_creation_failed=false
    local issuance_result=""

    print_lcyan "[QVI] OOR Auth edge Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/oor-auth-edge.json" | jq )"

    print_lcyan "[QVI] OOR Credential Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/oor-data.json")"

    echo
    print_green "[QVI] creating and granting OOR credential"

    issuance_result=$(run_signify_json \
      "${QVI_SIGNIFY_DIR}/qars/qars-oor-credential-create.ts" \
      --config "${PARTICIPANT_CONFIG_CONTAINER}" \
      --group-name "${QVI_NAME}" \
      --data-dir "/acdc-info" \
      --issuee-prefix "${PERSON_PRE}" \
      --artifact-dir "${QVI_DATA_DIR}") ||
      credential_creation_failed=true
    if [[ "${credential_creation_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to create and grant the OOR credential"
    fi
    record_qvi_issuance_result \
        "OOR" \
        "${issuance_result}" \
        "${OOR_SCHEMA}" \
        "${PERSON_PRE}"

    echo
    print_lcyan "[QVI] OOR credential created"
    echo
}

admit_person_leaf_credential() {
    local story_label=$1
    local schema=$2
    local credential_said=$3
    local admission_result=""
    local admission_failed=false
    local admission_is_exact=false

    admission_result=$(run_signify_json \
        "${QVI_SIGNIFY_DIR}/person/person-admit-credential.ts" \
        --config "${PARTICIPANT_CONFIG_CONTAINER}" \
        --issuer-prefix "${QVI_PRE}" \
        --credential-said "${credential_said}") ||
        admission_failed=true
    if [[ "${admission_failed}" == true ]]; then
        fail_workflow "[PERSON] Failed to admit ${story_label} credential ${credential_said}"
    fi

    printf '%s\n' "${admission_result}" |
        jq -e \
            --arg said "${credential_said}" \
            --arg issuer "${QVI_PRE}" \
            --arg schema "${schema}" \
            --arg issuee "${PERSON_PRE}" \
            '
              .status == "admitted" and
              .credential.said == $said and
              .credential.issuer == $issuer and
              .credential.schema == $schema and
              .credential.issuee == $issuee and
              .credential.statusSequence == "0"
            ' >/dev/null &&
        admission_is_exact=true
    if [[ "${admission_is_exact}" == false ]]; then
        fail_workflow "[PERSON] ${story_label} admission result did not match the issued leaf credential"
    fi

    append_proof_record "$(printf '%s\n' "${admission_result}" |
        jq -c \
            --arg story "${story_label}-person-admitted" \
            '. + {type:"credential",event:"admission",story:$story}')"
}

# Person: Admit OOR credential from QVI
function admit_oor_credential() {
    local qars_oor_said=""

    load_qvi_leaf_credential_said \
        "${LOCAL_QVI_DATA_DIR}/oor-cred-info.json" \
        "oorCredSAID" \
        "OOR"
    qars_oor_said="${LOADED_CREDENTIAL_SAID}"
    print_lcyan "OOR Credential SAID: ${qars_oor_said}"

    print_yellow "[PERSON] Admitting OOR credential ${qars_oor_said} to ${PERSON}"
    admit_person_leaf_credential \
        "OOR" \
        "${OOR_SCHEMA}" \
        "${qars_oor_said}"

    echo
    print_green "OOR Credential admitted"
    echo
}

# PERSON: Present OOR credential to Sally (vLEI Reporting API)
function person_present_oor_cred_to_sally() {
    local credential_transmission_failed=false
    local presentation_result=""
    local presentation_boundary

    load_qvi_leaf_credential_said \
        "${LOCAL_QVI_DATA_DIR}/oor-cred-info.json" \
        "oorCredSAID" \
        "OOR"
    OOR_CRED_SAID="${LOADED_CREDENTIAL_SAID}"
    presentation_boundary=$(utc_now)

    print_yellow "[PERSON] Presenting active OOR Credential ${OOR_CRED_SAID} to Sally"
    presentation_result=$(run_signify_json \
      "${QVI_SIGNIFY_DIR}/person/person-grant-credential.ts" \
      --config /run/qvi/participants.json \
      --credential-said "${OOR_CRED_SAID}" \
      --expected-issuer "${QVI_PRE}" \
      --expected-schema "${OOR_SCHEMA}" \
      --expected-issuee "${PERSON_PRE}" \
      --recipient-prefix "${DIRECT_SALLY_PRE}") ||
        credential_transmission_failed=true
    if [[ "${credential_transmission_failed}" == true ]]; then
        fail_workflow "[PERSON] Failed to transmit the active OOR credential to Sally"
    fi

    append_proof_record "$(printf '%s\n' "${presentation_result}" |
        jq -c '. + {type:"credential",event:"presentation",story:"OOR-active"}')"
    wait_for_active_sally_evidence \
        "OOR-active" \
        "${presentation_boundary}" \
        "${OOR_CRED_SAID}" \
        "${OOR_SCHEMA}" \
        "${PERSON_PRE}" \
        "${QVI_PRE}"
    print_green "[PERSON] Sally reported the exact active OOR Credential"
}

function load_qvi_leaf_credential_said() {
    local artifact=$1
    local key=$2
    local label=$3
    local artifact_is_missing=false
    local said_load_failed=false

    [[ -f "${artifact}" ]] || artifact_is_missing=true
    if [[ "${artifact_is_missing}" == true ]]; then
        fail_workflow "[QVI] Missing ${label} credential artifact ${artifact}"
    fi

    LOADED_CREDENTIAL_SAID=$(jq -er \
        --arg key "${key}" \
        '.[$key] | select(type == "string" and length > 0)' \
        "${artifact}") || said_load_failed=true
    if [[ "${said_load_failed}" == true ]]; then
        fail_workflow "[QVI] ${artifact} does not contain a valid ${key}"
    fi
}

function qvi_revocation_result_is_exact() {
    local revocation_result=$1
    local credential_said=$2
    local qvi_prefix=$3
    local qar1_prefix=$4
    local qar2_prefix=$5
    local qar3_prefix=$6
    local expected_schema=$7
    local expected_issuee=$8

    printf '%s\n' "${revocation_result}" |
        jq -e \
            --arg said "${credential_said}" \
            --arg prefix "${qvi_prefix}" \
            --arg qar1 "${qar1_prefix}" \
            --arg qar2 "${qar2_prefix}" \
            --arg qar3 "${qar3_prefix}" \
            --arg schema "${expected_schema}" \
            --arg issuee "${expected_issuee}" \
            '
              def exact_observations($observations; $sequence):
                ($observations | length == 3) and
                ([$observations[].observerAid] | sort) ==
                  ([$qar1, $qar2, $qar3] | sort) and
                ([$observations[].said] | unique == [$said]) and
                ([$observations[].issuer] | unique == [$prefix]) and
                ([$observations[].schema] | unique == [$schema]) and
                ([$observations[].issuee] | unique == [$issuee]) and
                ([$observations[].registry] | unique | length == 1) and
                ([$observations[].statusSequence] |
                  unique == [$sequence]) and
                ([$observations[].currentTelDigest] |
                  unique | length == 1) and
                all(
                  $observations[];
                  (.registry | type == "string" and length > 0) and
                  (.currentTelDigest | type == "string" and length > 0)
                );
              def exact_fanout($receipts; $inner_said):
                ($receipts | length == 6) and
                all(
                  $receipts[];
                  (.exnSaid | type == "string" and length > 0) and
                  .innerExchangeSaid == $inner_said
                ) and
                ([$receipts[] |
                    "\(.sender)|\(.recipient)"] |
                    unique | length == 6) and
                all(
                  [$qar1, $qar2, $qar3][];
                  . as $sender |
                  ([$receipts[] |
                      select(.sender == $sender) |
                      .recipient] |
                      sort) ==
                    ([$qar1, $qar2, $qar3] |
                      map(select(. != $sender)) |
                      sort)
                );
              . as $revocation |
              .credentialSaid == $said and
              .qviPrefix == $prefix and
              (.revocationTimestamp |
                type == "string" and length > 0) and
              (.revocationTelDigest |
                type == "string" and length > 0) and
              if .status == "revoked" then
                ([.before[].currentTelDigest] | unique) as $issuedDigests |
                (
                  exact_observations(.before; "0") and
                  all(.before[]; .priorTelDigest == null) and
                  exact_observations(.after; "1") and
                  all(
                    .after[];
                    .priorTelDigest == $issuedDigests[0]
                  ) and
                  ([.after[].currentTelDigest] |
                    unique == [$revocation.revocationTelDigest]) and
                  (.operationNames | length == 3) and
                  (.operationEvidence | length == 3) and
                  ([.operationEvidence[].name] | sort) ==
                    (.operationNames | sort) and
                  ([.operationEvidence[].result.said] |
                    unique | length == 1) and
                  ([.operationEvidence[].result.sequence] |
                    unique | length == 1) and
                  all(
                    .operationEvidence[];
                    .done == true and
                    .error == null and
                    .result.kind == "event" and
                    .name == ("group." + .result.said) and
                    (.result.said |
                      type == "string" and length > 0) and
                    .result.prefix == $prefix and
                    (.result.sequence |
                      type == "string" and length > 0)
                  ) and
                  exact_fanout(
                    .coordinationReceipts;
                    $revocation.revocationTelDigest
                  )
                )
              elif .status == "already-revoked" then
                exact_observations(.before; "1") and
                exact_observations(.after; "1") and
                .after == .before and
                ([.after[].currentTelDigest] |
                  unique == [$revocation.revocationTelDigest]) and
                (.operationNames | length == 0) and
                (.operationEvidence | length == 0) and
                (.coordinationReceipts | length == 0)
              else
                false
              end
            ' \
            >/dev/null
}

function revoke_qvi_leaf_credential() {
    local label=$1
    local credential_said=$2
    local expected_schema=$3
    local revocation_failed=false
    local revocation_result=""
    local revocation_result_is_valid=false

    print_yellow "[QVI] Revoking ${label} credential ${credential_said}"
    revocation_result=$(run_signify_json \
        "${QVI_SIGNIFY_DIR}/qars/qars-revoke-credential.ts" \
        --config /run/qvi/participants.json \
        --group-name "${QVI_NAME}" \
        --credential-said "${credential_said}" \
        --expected-schema "${expected_schema}" \
        --expected-issuee "${PERSON_PRE}") || revocation_failed=true
    if [[ "${revocation_failed}" == true ]]; then
        fail_workflow "[QVI] ${label} credential revocation failed"
    fi

    qvi_revocation_result_is_exact \
        "${revocation_result}" \
        "${credential_said}" \
        "${QVI_PRE}" \
        "${QAR1_PRE}" \
        "${QAR2_PRE}" \
        "${QAR3_PRE}" \
        "${expected_schema}" \
        "${PERSON_PRE}" &&
        revocation_result_is_valid=true
    if [[ "${revocation_result_is_valid}" == false ]]; then
        fail_workflow "[QVI] ${label} revocation result did not prove three-QAR TEL convergence"
    fi

    LAST_REVOCATION_TIMESTAMP=$(printf '%s\n' "${revocation_result}" |
        jq -er '.revocationTimestamp')
    append_proof_record "$(printf '%s\n' "${revocation_result}" |
        jq -c \
            --arg story "${label}-revoked" \
            '. + {type:"credential",event:"revocation",story:$story}')"
    print_green "[QVI] ${label} credential revocation converged on all three QARs"
}

function revoke_oor_credential() {
    load_qvi_leaf_credential_said \
        "${LOCAL_QVI_DATA_DIR}/oor-cred-info.json" \
        "oorCredSAID" \
        "OOR"
    OOR_CRED_SAID="${LOADED_CREDENTIAL_SAID}"
    revoke_qvi_leaf_credential "OOR" "${OOR_CRED_SAID}" "${OOR_SCHEMA}"
    OOR_REVOCATION_TIMESTAMP="${LAST_REVOCATION_TIMESTAMP}"
}

function revoke_ecr_credential() {
    load_qvi_leaf_credential_said \
        "${LOCAL_QVI_DATA_DIR}/ecr-cred-info.json" \
        "ecrCredSAID" \
        "ECR"
    ECR_CRED_SAID="${LOADED_CREDENTIAL_SAID}"
    revoke_qvi_leaf_credential "ECR" "${ECR_CRED_SAID}" "${ECR_SCHEMA}"
}

function present_revoked_oor_to_sally() {
    local credential_said_is_missing=false
    [[ -z "${OOR_CRED_SAID}" ]] && credential_said_is_missing=true
    if [[ "${credential_said_is_missing}" == true ]]; then
        fail_workflow "[QVI] Cannot present a revoked OOR without its credential SAID"
    fi

    local revocation_timestamp_is_missing=false
    local credential_transmission_failed=false
    local presentation_result=""
    local presentation_boundary
    local evidence_result=""
    local evidence_wait_failed=false

    [[ -z "${OOR_REVOCATION_TIMESTAMP:-}" ]] &&
        revocation_timestamp_is_missing=true
    if [[ "${revocation_timestamp_is_missing}" == true ]]; then
        fail_workflow "[QVI] Cannot prove a revoked OOR without its TEL timestamp"
    fi

    presentation_boundary=$(utc_now)
    print_yellow "[QVI] Presenting revoked OOR credential ${OOR_CRED_SAID} to Sally"
    presentation_result=$(run_signify_json \
        "${QVI_SIGNIFY_DIR}/qars/qars-present-credential.ts" \
        --config /run/qvi/participants.json \
        --group-name "${QVI_NAME}" \
        --credential-said "${OOR_CRED_SAID}" \
        --expected-issuer "${QVI_PRE}" \
        --expected-schema "${OOR_SCHEMA}" \
        --expected-issuee "${PERSON_PRE}" \
        --recipient-prefix "${DIRECT_SALLY_PRE}" \
        --expected-status revoked) || credential_transmission_failed=true
    if [[ "${credential_transmission_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to transmit revoked OOR credential ${OOR_CRED_SAID}"
    fi

    append_proof_record "$(printf '%s\n' "${presentation_result}" |
        jq -c '. + {type:"credential",event:"presentation",story:"OOR-revoked"}')"
    evidence_result=$(wait_until \
        "Sally rejection and revocation callback for OOR ${OOR_CRED_SAID}" \
        "${WORKFLOW_TIMEOUT_SECONDS}" \
        sally_revoked_oor_evidence_is_ready \
        "${presentation_boundary}" \
        "${OOR_CRED_SAID}" \
        "${QVI_PRE}" \
        "${OOR_REVOCATION_TIMESTAMP}") || evidence_wait_failed=true
    if [[ "${evidence_wait_failed}" == true ]]; then
        fail_workflow "[QVI] Sally did not prove revoked-OOR rejection and reporting for ${OOR_CRED_SAID}"
    fi

    record_sally_evidence "${evidence_result}" "OOR-revoked"
    print_green "[QVI] Sally rejected revoked OOR ${OOR_CRED_SAID} and emitted the exact revocation callback"
}

############################ ECR Auth ##################################
# LE: Prepare, create, and Issue ECR Auth & OOR Auth credential to QVI
# Prepare ECR Auth credential data
function prepare_ecr_auth_data() {
    jq -n \
        --arg aid "${PERSON_PRE}" \
        --arg lei "${LE_LEI}" \
        --arg personLegalName "${PERSON_NAME}" \
        --arg engagementContextRole "${PERSON_ECR}" \
        '{
            AID: $aid,
            LEI: $lei,
            personLegalName: $personLegalName,
            engagementContextRole: $engagementContextRole
        }' > "${KLI_DATA_DIR}/temp-data/ecr-auth-data.json"
}

# Create ECR Auth credential
function create_ecr_auth_credential() {
    echo
    print_green "[LE] LE creating ECR Auth credential"

    print_lcyan "[LE] Legal Entity edge JSON"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/legal-entity-edge.json" | jq)"

    print_lcyan "[LE] ECR Auth data JSON"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/ecr-auth-data.json")"

    KLI_TIME=$(kli time | tr -d '[:space:]')

    klid lar1 vc create \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/acdc-info/temp-data/ecr-auth-data.json \
        --edges @/acdc-info/temp-data/legal-entity-edge.json \
        --rules @/acdc-info/rules/ecr-auth-rules.json \
        --time "${KLI_TIME}"

    klid lar2 vc create \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/acdc-info/temp-data/ecr-auth-data.json \
        --edges @/acdc-info/temp-data/legal-entity-edge.json \
        --rules @/acdc-info/rules/ecr-auth-rules.json \
        --time "${KLI_TIME}"

    wait_kli_jobs lar1 lar2

    echo
    echo
    print_lcyan "[LE] LE created ECR Auth credential"
    echo
}

# Grant ECR Auth credential to QVI
function grant_ecr_auth_credential() {
    SAID=$(kli vc list \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --issued \
        --said \
        --schema ${ECR_AUTH_SCHEMA} | tr -d '[:space:]')

    echo
    print_yellow $'[LE] IPEX GRANTing ECR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI '"${QVI_PRE}"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    klid lar1 ipex grant \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}"

    klid lar2 ipex grant \
        --name "${LAR2}" \
        --passcode "${LAR2_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}"

    wait_kli_jobs lar1 lar2

    echo
    echo
    print_green "[LE] ECR Auth Credential granted to QVI"
    echo
}

# Admit ECR Auth credential from LE
function admit_ecr_auth_credential() {
    ECR_AUTH_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --issued \
        --said \
        --schema ${ECR_AUTH_SCHEMA} | tr -d '[:space:]')
    echo
    print_yellow "[QVI] Admitting ECR Auth Credential ${ECR_AUTH_SAID} from LE"
    admit_qvi_received_credential \
        "ECR-Auth" \
        "${LE_PRE}" \
        "${ECR_AUTH_SCHEMA}" \
        "${ECR_AUTH_SAID}"

    echo
    print_green "[QVI] Admitted ECR Auth Credential"
    echo
}

############################ ECR ##################################
# 23 Create and Issue ECR credential to Person
# Prepare ECR Auth edge data
function prepare_ecr_auth_edge() {
    ECR_AUTH_SAID=$(kli vc list \
        --name ${LAR1} \
        --alias ${LE_NAME} \
        --passcode "${LAR1_PASSCODE}" \
        --issued \
        --said \
        --schema ${ECR_AUTH_SCHEMA} | tr -d '[:space:]')
    print_bg_blue "[QVI] Preparing [ECR Auth] edge with [ECR Auth] Credential SAID: ${ECR_AUTH_SAID}"
    jq -n \
        --arg credentialSaid "${ECR_AUTH_SAID}" \
        --arg schema "${ECR_AUTH_SCHEMA}" \
        '{d: "", auth: {n: $credentialSaid, s: $schema, o: "I2I"}}' \
        > "${KLI_DATA_DIR}/temp-data/ecr-auth-edge.json"
    kli saidify --file /acdc-info/temp-data/ecr-auth-edge.json
}

# Prepare ECR credential data
function prepare_ecr_cred_data() {
    print_bg_blue "[QVI] Preparing ECR credential data"
    jq -n \
        --arg lei "${LE_LEI}" \
        --arg personLegalName "${PERSON_NAME}" \
        --arg engagementContextRole "${PERSON_ECR}" \
        '{
            LEI: $lei,
            personLegalName: $personLegalName,
            engagementContextRole: $engagementContextRole
        }' > "${KLI_DATA_DIR}/temp-data/ecr-data.json"
}

# QVI Grant ECR credential to PERSON
function create_and_grant_ecr_credential() {
    local credential_creation_failed=false
    local issuance_result=""

    print_lcyan "[QVI] ECR Auth edge Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/ecr-auth-edge.json" | jq )"

    print_lcyan "[QVI] ECR Credential Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/ecr-data.json")"

    pause "Press [enter] to create and grant the ECR credential"
    print_green "[QVI] creating and granting ECR credential"

    issuance_result=$(run_signify_json \
      "${QVI_SIGNIFY_DIR}/qars/qars-ecr-credential-create.ts" \
      --config "${PARTICIPANT_CONFIG_CONTAINER}" \
      --group-name "${QVI_NAME}" \
      --data-dir "/acdc-info" \
      --issuee-prefix "${PERSON_PRE}" \
      --artifact-dir "${QVI_DATA_DIR}") ||
      credential_creation_failed=true
    if [[ "${credential_creation_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to create and grant the ECR credential"
    fi
    record_qvi_issuance_result \
        "ECR" \
        "${issuance_result}" \
        "${ECR_SCHEMA}" \
        "${PERSON_PRE}"

    echo
    print_lcyan "[QVI] ECR credential created and granted"
    echo
}

# Person: Admit ECR credential from QVI
function admit_ecr_credential() {
    local ecr_said=""

    load_qvi_leaf_credential_said \
        "${LOCAL_QVI_DATA_DIR}/ecr-cred-info.json" \
        "ecrCredSAID" \
        "ECR"
    ecr_said="${LOADED_CREDENTIAL_SAID}"
    print_yellow "[PERSON] Admitting ECR credential ${ecr_said} to ${PERSON}"
    admit_person_leaf_credential \
        "ECR" \
        "${ECR_SCHEMA}" \
        "${ecr_said}"

    echo
    print_green "ECR Credential admitted"
    echo
}

############################ Staging Sally Presentation ##################################
# Present LE credential to GLEIF Staging Sally
function present_le_gleif_staging() {
  SALLY_WIT_OOBI="http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2"
  OOBI_ALIAS="sally-staging-wit-oc-au"
  kli oobi resolve --name "${LAR1}" --passcode "${LAR1_PASSCODE}" --oobi-alias "${OOBI_ALIAS}" --oobi "${SALLY_WIT_OOBI}"
  kli oobi resolve --name "${LAR2}" --passcode "${LAR2_PASSCODE}" --oobi-alias "${OOBI_ALIAS}" --oobi "${SALLY_WIT_OOBI}"
  LE_SAID=$(kli vc list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" --alias "${LE_NAME}" --said --schema "${LE_SCHEMA}" | tr -d '[:space:]')

  print_yellow "[LE] Granting LE credential to GLEIF Staging Sally  at ${SALLY_WIT_OOBI}"
  klid lar1 ipex grant --name "${LAR1}" --alias "${LE_NAME}" --passcode "${LAR1_PASSCODE}" --said "${LE_SAID}" \
        --recipient "${OOBI_ALIAS}"

  klid lar2 ipex join --name "${LAR2}" --passcode "${LAR2_PASSCODE}" --auto

  print_dark_gray "[LE] Waiting for GLEIF Staging Sally to receive the LE Credential"
  wait_kli_jobs lar1 lar2
}

function present_le_gleif_production() {
  SALLY_WIT_OOBI="http://5.161.69.25:5623/oobi/EMRlhEQK44_V5804rsRvQ99Gtf7uDpYQqZuvrw0LhV3S/witness/BNfDO63ZpGc3xiFb0-jIOUnbr_bA-ixMva5cZb3s4BHB"
  OOBI_ALIAS="sally-production-wit-na-us"
  kli oobi resolve --name "${LAR1}" --passcode "${LAR1_PASSCODE}" --oobi-alias "${OOBI_ALIAS}" --oobi "${SALLY_WIT_OOBI}"
  kli oobi resolve --name "${LAR2}" --passcode "${LAR2_PASSCODE}" --oobi-alias "${OOBI_ALIAS}" --oobi "${SALLY_WIT_OOBI}"
  LE_SAID=$(kli vc list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" --alias "${LE_NAME}" --said --schema "${LE_SCHEMA}" | tr -d '[:space:]')

  print_yellow "[LE] Granting LE credential to GLEIF Production Sally  at ${SALLY_WIT_OOBI}"
  klid lar1 ipex grant --name "${LAR1}" --alias "${LE_NAME}" --passcode "${LAR1_PASSCODE}" --said "${LE_SAID}" \
        --recipient "${OOBI_ALIAS}"

  klid lar2 ipex join --name "${LAR2}" --passcode "${LAR2_PASSCODE}" --auto

  print_dark_gray "[LE] Waiting for GLEIF Staging Sally to receive the LE Credential"
  wait_kli_jobs lar1 lar2
}

function present_le_to_alternate() {
  local alt_alias=$1
  local alt_oobi=$2
  kli oobi resolve --name "${LAR1}" --passcode "${LAR1_PASSCODE}" --oobi-alias "${alt_alias}" --oobi "${alt_oobi}"
  kli oobi resolve --name "${LAR2}" --passcode "${LAR2_PASSCODE}" --oobi-alias "${alt_alias}" --oobi "${alt_oobi}"
  LE_SAID=$(kli vc list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" --alias "${LE_NAME}" --said --schema "${LE_SCHEMA}" | tr -d '[:space:]')

  print_yellow "[LE] Granting LE credential to alternate Sally at ${alt_oobi}"
  klid lar1 ipex grant --name "${LAR1}" --alias "${LE_NAME}" --passcode "${LAR1_PASSCODE}" --said "${LE_SAID}" \
        --recipient "${alt_alias}"

  klid lar2 ipex join --name "${LAR2}" --passcode "${LAR2_PASSCODE}" --auto

  print_dark_gray "[LE] Waiting for Alternate Sally to receive the LE Credential"
  wait_kli_jobs lar1 lar2
}
# Prepare ECR Auth edge data

############################ Workflow functions ##################################
function end_workflow() {
  return 0
}

# main setup function
function setup() {
  # Salt generation is the first Compose-backed action. Persist a complete,
  # protected environment and arm scoped cleanup before that boundary so an
  # interruption always has enough information to tear down the exact project.
  prepare_compose_lifecycle
  generate_salts_and_passcodes
  write_private_runtime_config
  create_docker_containers
  start_docker_containers
  record_dependency_proof
  load_sally_prefixes
  write_private_runtime_config
#  pause "press enter to set up keria identifiers"
  setup_keria_identifiers
  create_aids
  read_prefixes

  resolve_oobis
  challenge_response
}

# Sets up GEDA, GEDA registry, delegation to the QVI, and QVI OOBI resolution for GARs and LARs
function geda_delegation_to_qvi() {
  create_geda_multisig
  create_geda_reg
  recreate_sally_containers
  qars_resolve_geda_oobi
  create_qvi_multisig
  authorize_qvi_multisig_agent_endpoint_role
  resolve_qvi_oobi
}

# Creates the QVI credential, grants it from the GEDA to the QVI, and presents it to sally
function qvi_credential() {
  prepare_qvi_cred_data
  create_qvi_credential
  grant_qvi_credential
  admit_qvi_credential
  pause "Press [ENTER] to present QVI credential to Sally"
  present_qvi_cred_to_sally_signify
}

# Creates the LE multisig, resolves the LE OOBI, creates the QVI registry, and prepares and grants the LE credential
function le_creation_and_granting() {
  create_le_multisig
  qars_resolve_le_oobi
  create_qvi_reg
  prepare_qvi_edge
  prepare_le_cred_data
  create_and_grant_le_credential
  admit_le_credential
  create_le_reg
  prepare_le_edge
}

# Presents the LE credential to the local Sally deployment
function le_sally_presentation() {
  present_le_cred_to_sally
}

# Creates the OOR Auth credential and grants it to the QVI
function oor_auth_cred() {
  prepare_oor_auth_data
  create_oor_auth_credential
  grant_oor_auth_credential
  admit_oor_auth_credential
  prepare_oor_auth_edge
}

# Creates the OOR credential, grants it to the Person, and presents it to Sally from the person
function oor_cred(){
  prepare_oor_cred_data
  create_and_grant_oor_credential
  admit_oor_credential
}

# Workflow function for the OOR Auth and OOR credentials
function oor_auth_and_oor_cred() {
  oor_auth_cred
  oor_cred
}

# Creates the ECR Auth credential and grants it to the QVI
function ecr_auth_cred() {
  prepare_ecr_auth_data
  create_ecr_auth_credential
  grant_ecr_auth_credential
  admit_ecr_auth_credential
  prepare_ecr_auth_edge
}

# Creates the ECR credential, grants it to the Person, and admits it
function ecr_cred() {
  prepare_ecr_cred_data
  create_and_grant_ecr_credential
  admit_ecr_credential
}

# Workflow function for the ECR Auth and ECR credentials
function ecr_auth_and_ecr_cred() {
  ecr_auth_cred
  ecr_cred
}

# Main workflow driving the end to end QVI credentialing and reporting process
function main_flow() {
  print_lcyan "--------------------------------------------------------------------------------"
  print_lcyan "                       Running Main workflow (env: ${ENVIRONMENT})"
  print_lcyan "--------------------------------------------------------------------------------"
  setup
  geda_delegation_to_qvi
  qvi_credential

  le_creation_and_granting
  pause "Press [ENTER] to present LE credential to Sally"
  le_sally_presentation

  oor_auth_and_oor_cred
  pause "Press [ENTER] to present OOR to Sally"
  person_present_oor_cred_to_sally

  revoke_oor_credential
  present_revoked_oor_to_sally

  ECR_CALLBACK_BOUNDARY=$(utc_now)
  ecr_auth_and_ecr_cred
  revoke_ecr_credential
  prove_no_ecr_callback "${ECR_CALLBACK_BOUNDARY}" "${ECR_CRED_SAID}"

  pause "Press [enter] to end workflow"
  end_workflow
}

# Runs the workflow and presents the LE credential to GLEIF Staging Sally
function present_to_staging() {
  print_green "--------------------------------------------------------------------------------"
  print_green "Running workflow and presenting LE credential to GLEIF Staging Sally"
  print_green "Using the following URL for Sally's mailbox:"
  print_green "http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2"
  print_green "--------------------------------------------------------------------------------"
  setup
  geda_delegation_to_qvi
  qvi_credential
  le_creation_and_granting
  present_le_gleif_staging
  end_workflow
}

# Runs the workflow and presents the LE credential to GLEIF Production Sally
function present_to_production() {
  print_green "--------------------------------------------------------------------------------"
  print_green "Running workflow and presenting LE credential to GLEIF Production Sally"
  print_green "Using the following URL for Sally's mailbox:"
  print_green "http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2"
  print_green "--------------------------------------------------------------------------------"
  setup
  geda_delegation_to_qvi
  qvi_credential
  le_creation_and_granting
  present_le_gleif_production
  end_workflow
}

# Runs the workflow and presents the LE credential to an alternate Sally
function present_to_alternate_sally() {
  print_green "--------------------------------------------------------------------------------"
  print_green "Running workflow and presenting LE credential to alternate Sally: ${ALT_SALLY_ALIAS}"
  print_green "Using the following URL for Sally's mailbox:"
  print_green "${ALT_SALLY_OOBI}"
  print_green "--------------------------------------------------------------------------------"
  setup
  geda_delegation_to_qvi
  qvi_credential
  le_creation_and_granting
  present_le_to_alternate "${ALT_SALLY_ALIAS}" "${ALT_SALLY_OOBI}"
  end_workflow
}

usage() {
    printf 'Usage: %s [options]\n' "${0##*/}"
    printf '%s\n' \
        "Options:" \
        "  -t, --alternate       Present the LE credential to an alternate Sally" \
        "  -s, --staging         Present the LE credential to GLEIF Staging Sally" \
        "  -p, --production      Present the LE credential to GLEIF Production Sally" \
        "  -a, --alias ALIAS     Alias for --alternate (default: alternate)" \
        "  -o, --oobi OOBI       OOBI URL for --alternate" \
        "      --timeout SECONDS Timeout for each bounded operation (default: 120)" \
        "      --keep-runtime    Preserve the private runtime and Compose stack" \
        "      --pause           Pause at story checkpoints" \
        "  -h, --help            Display this help message"
}

select_workflow_mode() {
    local requested_mode=$1
    local mode_is_unset=false
    local mode_matches=false

    [[ "${WORKFLOW_MODE}" == default ]] && mode_is_unset=true
    [[ "${WORKFLOW_MODE}" == "${requested_mode}" ]] && mode_matches=true
    if [[ "${mode_is_unset}" == false && "${mode_matches}" == false ]]; then
        print_red "Only one of --alternate, --staging, and --production may be selected"
        return 1
    fi
    WORKFLOW_MODE="${requested_mode}"
}

parse_arguments() {
    local alternate_mode_is_selected=false
    local option_has_value=false
    local timeout_is_valid=false
    local alternate_option_was_customized=false
    local mode_selection_succeeded=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --pause)
                PAUSE_ENABLED=true
                shift
                ;;
            --keep-runtime)
                KEEP_RUNTIME=true
                shift
                ;;
            --timeout)
                option_has_value=false
                [[ $# -ge 2 && -n "${2:-}" ]] && option_has_value=true
                if [[ "${option_has_value}" == false ]]; then
                    print_red "Error: --timeout requires a value"
                    return 2
                fi
                timeout_is_valid=false
                [[ "$2" =~ ^[1-9][0-9]*$ ]] && timeout_is_valid=true
                if [[ "${timeout_is_valid}" == false ]]; then
                    print_red "Error: --timeout must be a positive integer"
                    return 2
                fi
                WORKFLOW_TIMEOUT_SECONDS=$2
                export WORKFLOW_TIMEOUT_SECONDS
                shift 2
                ;;
            -a|--alias)
                option_has_value=false
                [[ $# -ge 2 && -n "${2:-}" ]] && option_has_value=true
                if [[ "${option_has_value}" == false ]]; then
                    print_red "Error: --alias requires a value"
                    return 2
                fi
                ALT_SALLY_ALIAS=$2
                alternate_option_was_customized=true
                shift 2
                ;;
            -o|--oobi)
                option_has_value=false
                [[ $# -ge 2 && -n "${2:-}" ]] && option_has_value=true
                if [[ "${option_has_value}" == false ]]; then
                    print_red "Error: --oobi requires a value"
                    return 2
                fi
                ALT_SALLY_OOBI=$2
                alternate_option_was_customized=true
                shift 2
                ;;
            -t|--alternate)
                mode_selection_succeeded=false
                select_workflow_mode alternate && mode_selection_succeeded=true
                if [[ "${mode_selection_succeeded}" == false ]]; then
                    return 2
                fi
                shift
                ;;
            -s|--staging)
                mode_selection_succeeded=false
                select_workflow_mode staging && mode_selection_succeeded=true
                if [[ "${mode_selection_succeeded}" == false ]]; then
                    return 2
                fi
                shift
                ;;
            -p|--production)
                mode_selection_succeeded=false
                select_workflow_mode production && mode_selection_succeeded=true
                if [[ "${mode_selection_succeeded}" == false ]]; then
                    return 2
                fi
                shift
                ;;
            -h|--help)
                HELP_REQUESTED=true
                shift
                ;;
            *)
                print_red "Unknown option: $1"
                return 2
                ;;
        esac
    done

    [[ "${WORKFLOW_MODE}" == alternate ]] && alternate_mode_is_selected=true
    if [[ "${alternate_option_was_customized}" == true &&
          "${alternate_mode_is_selected}" == false ]]; then
        print_red "--alias and --oobi require --alternate"
        return 2
    fi
}

main() {
    local argument_parse_succeeded=false
    local proof_contains_secret=false
    local proof_redaction_succeeded=false
    local workflow_duration

    parse_arguments "$@" && argument_parse_succeeded=true
    if [[ "${argument_parse_succeeded}" == false ]]; then
        usage >&2
        return 2
    fi
    if [[ "${HELP_REQUESTED}" == true ]]; then
        usage
        return 0
    fi

    require_system_commands
    install_workflow_traps
    create_workflow_runtime
    # shellcheck source=./kli-commands.sh
    source "${SCRIPT_DIR}/kli-commands.sh"
    START_TIME=$(date +%s)
    append_proof_record "$(jq -cn \
        --arg project "${COMPOSE_PROJECT_NAME}" \
        --arg startedAt "$(utc_now)" \
        --argjson timeoutSeconds "${WORKFLOW_TIMEOUT_SECONDS}" \
        '{type:"runtime",composeProject:$project,startedAt:$startedAt,timeoutSeconds:$timeoutSeconds}')"

    case "${WORKFLOW_MODE}" in
        alternate) present_to_alternate_sally ;;
        staging) present_to_staging ;;
        production) present_to_production ;;
        default) main_flow ;;
    esac

    workflow_duration=$(( $(date +%s) - START_TIME ))
    append_proof_record "$(jq -cn \
        --argjson durationSeconds "${workflow_duration}" \
        '{type:"workflow",status:"passed",durationSeconds:$durationSeconds}')"
    write_proof_summary passed "${workflow_duration}"
    retained_proof_contains_registered_secret &&
        proof_contains_secret=true
    if [[ "${proof_contains_secret}" == true ]]; then
        redact_retained_proof_files &&
            proof_redaction_succeeded=true
        if [[ "${proof_redaction_succeeded}" == false ]]; then
            fail_workflow "Retained proof contains a secret value and could not be sanitized"
        fi
        fail_workflow "Retained proof contained a secret value and was sanitized"
    fi
    print_lcyan "Full chain workflow completed in ${workflow_duration} seconds"
}

script_is_being_executed=false
[[ "${BASH_SOURCE[0]}" == "$0" ]] && script_is_being_executed=true
if [[ "${script_is_being_executed}" == true ]]; then
    main "$@"
fi
