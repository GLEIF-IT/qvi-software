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
# 3) This script uses the KLI commands defined in ./kli-commands.sh to perform the QVI
#    workflow steps.
# 4) This is a one-run-at-a-time developer demonstration. Generated data lives
#    in ./runtime and the next invocation replaces it.

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-keria_signify_qvi.yaml"
WORKFLOW_ENV_FILE="${SCRIPT_DIR}/keria-signify-docker.env"

if [[ ! -f "${WORKFLOW_ENV_FILE}" ]]; then
    printf 'Workflow environment file does not exist: %s\n' \
        "${WORKFLOW_ENV_FILE}" >&2
    exit 2
fi

set -a
# shellcheck source=./keria-signify-docker.env
source "${WORKFLOW_ENV_FILE}"
set +a

# shellcheck source=./color-printing.sh
source "${SCRIPT_DIR}/color-printing.sh"
# shellcheck source=./lib/workflow-runtime.sh
source "${SCRIPT_DIR}/lib/workflow-runtime.sh"

QVI_SIGNIFY_DIR=/vlei-workflow/src
QVI_DATA_DIR=/vlei-workflow/qvi_data
QVI_PARTICIPANT_CONFIG=/vlei-workflow/participants.json

: "${WORKFLOW_TIMEOUT_SECONDS:=120}"
export WORKFLOW_TIMEOUT_SECONDS
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
    local normalized_result=""
    local command_status=0
    local command_failed=false
    local normalization_failed=false

    result_json=$(sig_tsx "$@") || command_status=$?
    [[ "${command_status}" -ne 0 ]] && command_failed=true
    if [[ "${command_failed}" == true ]]; then
        return "${command_status}"
    fi

    normalized_result=$(printf '%s\n' "${result_json}" |
        jq -c '.') || normalization_failed=true
    if [[ "${normalization_failed}" == true ]]; then
        print_red "Signify runner did not emit valid JSON"
        return 1
    fi

    printf '%s\n' "${normalized_result}"
}

run_qvi_json() {
    local phase=$1
    shift
    run_signify_json \
        "${QVI_SIGNIFY_DIR}/qvi.ts" \
        "${phase}" \
        --config "${QVI_PARTICIPANT_CONFIG}" \
        "$@"
}

assert_qvi_group_state() {
    local expected_sequence=$1
    local signing_roles=""
    local rotation_roles=""
    local assertion_failed=false

    case "${expected_sequence}" in
        0|1)
            signing_roles=qar1,qar2,qar3
            rotation_roles=qar1,qar2,qar3
            ;;
        2)
            signing_roles=qar1,qar2,qar3
            rotation_roles=qar1,qar2,qar4
            ;;
        3)
            signing_roles=qar1,qar2,qar4
            rotation_roles=qar1,qar2,qar4
            ;;
        *) return 1 ;;
    esac
    run_qvi_json \
        ms-assert-group \
        --group-prefix "${QVI_PRE}" \
        --delegator-prefix "${GEDA_PRE}" \
        --sequence "${expected_sequence}" \
        --signing-roles "${signing_roles}" \
        --rotation-roles "${rotation_roles}" >/dev/null ||
        assertion_failed=true
    if [[ "${assertion_failed}" == true ]]; then
        fail_workflow \
            "[QVI] Group state did not converge at sequence ${expected_sequence}"
    fi
}

assert_qvi_credential_state() {
    local credential_said=$1
    local issuer_prefix=$2
    local schema=$3
    local issuee_prefix=$4
    local status_sequence=$5
    local assertion_failed=false

    run_qvi_json \
        ms-assert-credential \
        --actor qvi \
        --credential-said "${credential_said}" \
        --issuer-prefix "${issuer_prefix}" \
        --schema "${schema}" \
        --issuee-prefix "${issuee_prefix}" \
        --status-sequence "${status_sequence}" >/dev/null ||
        assertion_failed=true
    if [[ "${assertion_failed}" == true ]]; then
        fail_workflow \
            "[QVI] Credential ${credential_said} did not converge at TEL sequence ${status_sequence}"
    fi
}

assert_person_credential_state() {
    local credential_said=$1
    local issuer_prefix=$2
    local schema=$3
    local issuee_prefix=$4
    local status_sequence=$5
    local assertion_failed=false

    run_qvi_json \
        ms-assert-credential \
        --actor person \
        --credential-said "${credential_said}" \
        --issuer-prefix "${issuer_prefix}" \
        --schema "${schema}" \
        --issuee-prefix "${issuee_prefix}" \
        --status-sequence "${status_sequence}" >/dev/null ||
        assertion_failed=true
    if [[ "${assertion_failed}" == true ]]; then
        fail_workflow \
            "[PERSON] Credential ${credential_said} does not match the story"
    fi
}

callback_was_recorded() {
    local action=$1
    local credential_said=$2
    local action_fragment="\"action\":\"${action}\""
    local credential_fragment="\"credential\":\"${credential_said}\""
    local matching_line=""

    [[ -f "${SALLY_CALLBACK_FILE}" ]] || return 1
    matching_line=$(grep -F "${action_fragment}" "${SALLY_CALLBACK_FILE}" |
        grep -F "${credential_fragment}" |
        tail -n 1) || return 1
    printf '%s\n' "${matching_line}"
}

wait_for_sally_callback() {
    local story_label=$1
    local action=$2
    local credential_said=$3
    local callback_result=""
    local callback_wait_failed=false

    # callback_was_recorded performs one local JSONL lookup per poll. Its
    # matching callback line becomes poll_until's successful result.
    callback_result=$(poll_until \
        "Sally ${action} callback for ${story_label} credential ${credential_said}" \
        "${WORKFLOW_TIMEOUT_SECONDS}" \
        callback_was_recorded \
        "${action}" \
        "${credential_said}") || callback_wait_failed=true
    if [[ "${callback_wait_failed}" == true ]]; then
        fail_workflow "Sally did not report the ${story_label} credential ${credential_said}"
    fi

    print_green "[Sally] ${story_label} callback received for ${credential_said}"
}

revoked_oor_was_rejected_and_reported() {
    local submitted_after=$1
    local credential_said=$2
    local sally_logs=""
    local rejection_message="revoked credential ${credential_said} being presented"
    local callback_found=false
    local rejection_found=false

    callback_was_recorded rev "${credential_said}" >/dev/null &&
        callback_found=true
    sally_logs=$(workflow_compose logs \
        --no-color \
        --timestamps \
        --since "${submitted_after}" \
        direct-sally 2>&1) || return 1
    [[ "${sally_logs}" == *"${rejection_message}"* ]] &&
        rejection_found=true

    if [[ "${callback_found}" == true &&
          "${rejection_found}" == true ]]; then
        printf 'Sally rejected and reported revoked OOR %s\n' \
            "${credential_said}"
        return 0
    fi

    printf 'callback=%s rejection=%s\n' \
        "${callback_found}" "${rejection_found}"
    return 1
}

require_system_commands() {
    local required_command
    local command_is_available=false

    for required_command in docker jq curl awk sed wc; do
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

  print_green "-------------------Building workflow runner and callback recorder-------------------"
  workflow_compose build signify callback-recorder &&
      image_build_succeeded=true
  if [[ "${image_build_succeeded}" == false ]]; then
      fail_workflow "Unable to build the workflow images"
  fi
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
GAR1_PRE=
GAR2_PRE=
export GEDA_NAME

# Legal Entity AIDs
LAR1_PRE=
LAR2_PRE=
LE_PRE=

#### KERIA and Signify Identifiers ####
# QAR AIDs - filled in later after KERIA setup
QAR1_PRE=
QAR1_AGENT_EID=
QAR2_PRE=
QAR2_AGENT_EID=
QAR3_PRE=
QAR3_AGENT_EID=
QAR4_PRE=
QAR4_AGENT_EID=
QVI_PRE=

# Person AID
PERSON_PRE=
OOR_CRED_SAID=
ECR_CRED_SAID=
LE_CRED_SAID=
LAST_ISSUED_CREDENTIAL_SAID=
LAST_REVOCATION_TIMESTAMP=
LAST_REVOCATION_TEL_DIGEST=

#### Credential data ####
LE_LEI=254900OPPU84GM83MG36 # GLEIF Americas
PERSON_NAME="Mordred Delacqs"
PERSON_ECR="Consultant"
PERSON_OOR="Advisor"

# Sally values and public demo salts/passcodes come from the workflow env file.
export WEBHOOK_HOST
export DIRECT_SALLY_HOST DIRECT_SALLY_KS_NAME DIRECT_SALLY_ALIAS
export DIRECT_SALLY_PASSCODE DIRECT_SALLY_SALT
export DIRECT_SALLY_PRE=""

function start_foundation_services() {
  local foundation_start_failed=false

  workflow_compose up \
      --detach \
      --wait \
      --wait-timeout "${WORKFLOW_TIMEOUT_SECONDS}" \
      vlei-server \
      callback-recorder \
      gar-witnesses \
      qar-witnesses \
      person-witnesses \
      keria1 \
      keria2 \
      keria3 \
      keria4 ||
      foundation_start_failed=true
  if [[ "${foundation_start_failed}" == true ]]; then
      fail_workflow "Docker foundation services failed to start properly"
  fi

}

# Verify the package versions exposed by every participating runtime before
# any KERI state is created.
function preflight_versions() {
  local python_check='from importlib.metadata import version; import sys; actual=version(sys.argv[1]); expected=sys.argv[2]; print(f"{sys.argv[1]}={actual}"); raise SystemExit(0 if actual == expected else 1)'
  local kli_version=""

  run_qvi_json preflight >/dev/null || return 1
  workflow_compose exec -T keria1 \
      python -c "${python_check}" keria 0.4.0 || return 1
  workflow_compose exec -T keria1 \
      python -c "${python_check}" keri 1.2.12 || return 1
  # gleif/keri:1.2.9 is the image release; its installed KERIpy package is
  # 1.3.1. Keep both expectations visible instead of conflating the versions.
  workflow_compose exec -T gar-witnesses \
      python -c "${python_check}" keri 1.3.1 || return 1
  workflow_compose exec -T qar-witnesses \
      python -c "${python_check}" keri 1.3.1 || return 1
  workflow_compose exec -T person-witnesses \
      python -c "${python_check}" keri 1.3.1 || return 1
  kli_version=$(kli version) || return 1
  [[ "${kli_version}" == *"1.1.32"* ]] || return 1
}

function start_sally() {
  local sally_start_failed=false

  if [[ -z "${GEDA_PRE:-}" ]]; then
      fail_workflow "Cannot start Sally before the GEDA prefix exists"
  fi

  workflow_compose up \
      --detach \
      --wait \
      --wait-timeout "${WORKFLOW_TIMEOUT_SECONDS}" \
      direct-sally ||
      sally_start_failed=true
  if [[ "${sally_start_failed}" == true ]]; then
      fail_workflow "Sally services failed to start properly"
  fi
  load_sally_prefixes || return 1
}

################################################
# QVI Workflow with KERIpy, KERIA, and SignifyTS
################################################

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
  local observed_prefix=""
  local observation_failed=false

  # sally_oobi_prefix_is_ready performs one bounded HTTP request per poll.
  observed_prefix=$(poll_until \
      "${service_name} self-bootstrapped OOBI" \
      "${WORKFLOW_TIMEOUT_SECONDS}" \
      sally_oobi_prefix_is_ready \
      "${service_name}" \
      "${local_oobi_url}") ||
      observation_failed=true
  if [[ "${observation_failed}" == true ]]; then
      return 1
  fi

  printf '%s\n' "${observed_prefix}"
}

load_sally_prefixes() {
  local direct_observation_failed=false

  DIRECT_SALLY_PRE=$(observe_sally_prefix \
      direct-sally \
      http://127.0.0.1:9823/oobi) ||
      direct_observation_failed=true
  if [[ "${direct_observation_failed}" == true ]]; then
      fail_workflow "Unable to observe direct Sally's self-bootstrapped AID"
  fi

  export DIRECT_SALLY_PRE
}

function setup_keria_identifiers() {
  local setup_failed=false
  local qvi_setup_data=""
  local setup_fields=""

  print_yellow "Creating QVI and Person Identifiers from SignifyTS + KERIA"
  qvi_setup_data=$(run_qvi_json ms-setup) || setup_failed=true
  if [[ "${setup_failed}" == true ]]; then
      fail_workflow "Unable to create the QAR and Person identifiers"
  fi

  print_green "QVI and Person Identifiers from SignifyTS + KERIA are "
  # Extract prefixes from the SignifyTS output because they are dynamically generated and unique each run.
  # They are needed for doing OOBI resolutions to connect SignifyTS AIDs to KERIpy AIDs.
  setup_fields=$(printf '%s\n' "${qvi_setup_data}" |
      jq -r '
        .participants |
        [
          .QAR1.aid,
          .QAR1.agentOobi,
          .QAR1.agentEid,
          .QAR2.aid,
          .QAR2.agentOobi,
          .QAR2.agentEid,
          .QAR3.aid,
          .QAR3.agentOobi,
          .QAR3.agentEid,
          .QAR4.aid,
          .QAR4.agentOobi,
          .QAR4.agentEid,
          .PERSON.aid,
          .PERSON.agentOobi
        ] |
        @tsv
      ')
  IFS=$'\t' read -r \
      QAR1_PRE QAR1_OOBI QAR1_AGENT_EID \
      QAR2_PRE QAR2_OOBI QAR2_AGENT_EID \
      QAR3_PRE QAR3_OOBI QAR3_AGENT_EID \
      QAR4_PRE QAR4_OOBI QAR4_AGENT_EID \
      PERSON_PRE PERSON_OOBI <<< "${setup_fields}"

  # Show dyncamic, extracted Signify identifiers and OOBIs
  print_green     "QAR1   Prefix: $QAR1_PRE"
  print_dark_gray "QAR1     OOBI: $QAR1_OOBI"
  print_green     "QAR2   Prefix: $QAR2_PRE"
  print_dark_gray "QAR2     OOBI: $QAR2_OOBI"
  print_green     "QAR3   Prefix: $QAR3_PRE"
  print_dark_gray "QAR3     OOBI: $QAR3_OOBI"
  print_green     "QAR4   Prefix: $QAR4_PRE"
  print_dark_gray "QAR4     OOBI: $QAR4_OOBI"
  print_green     "Person Prefix: $PERSON_PRE"
  print_dark_gray "Person   OOBI: $PERSON_OOBI"
}

function resolve_gar_oobis() {
    GAR1_OOBI="${WIT_HOST_GAR}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    GAR2_OOBI="${WIT_HOST_GAR}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"

    kli oobi resolve \
        --name "${GAR1}" \
        --oobi-alias "${GAR2}" \
        --passcode "${GAR1_PASSCODE}" \
        --oobi "${GAR2_OOBI}" || return 1
    kli oobi resolve \
        --name "${GAR2}" \
        --oobi-alias "${GAR1}" \
        --passcode "${GAR2_PASSCODE}" \
        --oobi "${GAR1_OOBI}" || return 1
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

    run_qvi_json \
        ms-resolve-external \
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
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR4}"   --passcode "${GAR1_PASSCODE}" --oobi "${QAR4_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${PERSON}" --passcode "${GAR1_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${DIRECT_SALLY_ALIAS}"   --passcode "${GAR1_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for GAR 2"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${GAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${GAR1_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${LAR1_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${LAR2_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR1_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR3}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR4}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR4_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${PERSON}" --passcode "${GAR2_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${DIRECT_SALLY_ALIAS}"   --passcode "${GAR2_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for LAR 1"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${LAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${LAR2_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${GAR1_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${GAR2_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR1_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR3}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR4}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR4_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${PERSON}" --passcode "${LAR1_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${DIRECT_SALLY_ALIAS}"   --passcode "${LAR1_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for LAR 2"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${LAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${LAR1_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${GAR1_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${GAR2_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR1_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR3}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR4}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR4_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${PERSON}" --passcode "${LAR2_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${DIRECT_SALLY_ALIAS}"   --passcode "${LAR2_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"
    
    echo
}

CHALLENGE_WORDS=""

function generate_challenge_words() {
    local challenge_generation_failed=false
    local challenge_word_count=""
    local challenge_word_count_is_valid=false

    CHALLENGE_WORDS=$(kli challenge generate --out string |
        tr -d '\r\n') || challenge_generation_failed=true
    if [[ "${challenge_generation_failed}" == true ]]; then
        fail_workflow "Failed to generate a 128-bit challenge"
    fi

    challenge_word_count=$(printf '%s\n' "${CHALLENGE_WORDS}" |
        wc -w |
        tr -d '[:space:]')
    [[ "${challenge_word_count}" -eq 12 ]] && challenge_word_count_is_valid=true
    if [[ "${challenge_word_count_is_valid}" == false ]]; then
        fail_workflow "Expected a 12-word, 128-bit challenge"
    fi
}

function verify_kli_challenge() {
    local verifier_name=$1
    local verifier_passcode=$2
    local responder_name=$3
    local output=""
    local verification_failed=false
    local success_message_found=false

    output=$(kli challenge verify \
        --name "${verifier_name}" \
        --alias "${verifier_name}" \
        --passcode "${verifier_passcode}" \
        --signer "${responder_name}" \
        --words "${CHALLENGE_WORDS}" 2>&1) || verification_failed=true
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
    local challenge_action_failed=false

    run_qvi_json ms-challenge \
        --participant "${participant}" \
        --action "${action}" \
        --peer-prefix "${peer_prefix}" \
        --words "${CHALLENGE_WORDS}" >/dev/null ||
        challenge_action_failed=true
    if [[ "${challenge_action_failed}" == true ]]; then
        fail_workflow "KERIA challenge ${action} failed for ${participant} and ${peer_prefix}"
    fi
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
    local challenger_uses_kli=false
    local responder_uses_kli=false

    generate_challenge_words

    [[ "${challenger_type}" == kli ]] && challenger_uses_kli=true
    [[ "${responder_type}" == kli ]] && responder_uses_kli=true
    if [[ "${responder_uses_kli}" == true ]]; then
        kli challenge respond \
            --name "${responder_name}" \
            --alias "${responder_name}" \
            --passcode "${responder_passcode}" \
            --recipient "${challenger_name}" \
            --words "${CHALLENGE_WORDS}" >/dev/null ||
            response_failed=true
    else
        keria_challenge_action "${responder_id}" respond "${challenger_prefix}"
    fi
    if [[ "${response_failed}" == true ]]; then
        fail_workflow "Challenge response failed from ${responder_id} to ${challenger_id}"
    fi

    if [[ "${challenger_uses_kli}" == true ]]; then
        verify_kli_challenge \
            "${challenger_name}" \
            "${challenger_passcode}" \
            "${responder_name}"
    else
        keria_challenge_action "${challenger_id}" verify "${responder_prefix}"
    fi

    print_green "[challenge] ${relationship}: ${challenger_id} verified ${responder_id}"
    CHALLENGE_WORDS=""
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
        qar4)
            CHALLENGE_PARTICIPANT_TYPE=keria
            CHALLENGE_PARTICIPANT_NAME="${QAR4}"
            CHALLENGE_PARTICIPANT_PASSCODE=""
            CHALLENGE_PARTICIPANT_PREFIX="${QAR4_PRE}"
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
      "QAR1-QAR2|qar1|qar2"
      "GAR1-QAR1|gar1|qar1"
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
  done

  print_green "[challenge] Completed 4 directed responses across 2 trust relationships"
}

################# Create Multisigs and perform delegation ################
# Create Multisig AID for GLEIF External Delegated AID (GEDA)
function create_multisig_icp_config() {
    PRE1=$1
    PRE2=$2
    local wit_pre=$3
    jq \
        --arg first_aid "${PRE1}" \
        --arg second_aid "${PRE2}" \
        --arg witness "${wit_pre}" \
        '.aids = [$first_aid, $second_aid] |
         .wits = [$witness]' \
        "${WORKFLOW_CONFIG_DIR}/template-multi-sig-incept-config.jq" \
        > "${WORKFLOW_CONFIG_DIR}/multi-sig-incept-config.json"

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
    print_dark_gray "Waiting on GAR jobs"
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
    run_qvi_json \
        ms-resolve-oobi \
        --alias "${GEDA_NAME}" \
        --oobi "${GEDA_OOBI}" \
        --roles qar1,qar2,qar3,qar4,person >/dev/null ||
        geda_resolution_failed=true
    if [[ "${geda_resolution_failed}" == true ]]; then
        fail_workflow "QARs could not resolve the GEDA OOBI"
    fi

    run_qvi_json \
        ms-refresh-delegator \
        --delegator-prefix "${GEDA_PRE}" \
        --roles qar1,qar2,qar3 >/dev/null ||
        refresh_failed=true
    if [[ "${refresh_failed}" == true ]]; then
        fail_workflow "QARs could not refresh the GEDA multisig state"
    fi
}

# QAR: Create delegated multisig QVI AID with GEDA as delegator
function create_qvi_multisig() {
    local delegator_prefix=""
    local creation_result=""
    local creation_failed=false
    local completion_failed=false

    print_yellow "Creating QVI multisig AID with GEDA as delegator"

    delegator_prefix=$(kli status \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" |
        awk '/Identifier:/ {print $2}' |
        tr -d " \t\n\r")
    print_yellow "Delegator Prefix: ${delegator_prefix}"
    creation_result=$(run_qvi_json \
      ms-incept-submit \
      --delegator-prefix "${delegator_prefix}" \
      --member-roles qar1,qar2,qar3 \
      --artifact "${QVI_DATA_DIR}/pending-group-event.json") ||
      creation_failed=true
    if [[ "${creation_failed}" == true ]]; then
        fail_workflow "QVI delegated inception could not be submitted"
    fi

    print_yellow "Delegated Multisig Info:"
    QVI_PRE=$(printf '%s\n' "${creation_result}" |
        jq -r '.event.groupPrefix')
    echo
    print_lcyan "QVI Multisig Prefix: ${QVI_PRE}"
    echo

    approve_qvi_delegation "${QAR1_PRE}" "${QAR2_PRE}" "${QAR3_PRE}" ||
        return 1

    run_qvi_json \
        ms-incept-complete \
        --delegator-prefix "${GEDA_PRE}" \
        --expected-sequence 0 \
        --signing-roles qar1,qar2,qar3 \
        --rotation-roles qar1,qar2,qar3 \
        --artifact "${QVI_DATA_DIR}/pending-group-event.json" >/dev/null ||
        completion_failed=true
    if [[ "${completion_failed}" == true ]]; then
        fail_workflow "QVI delegated inception did not converge after GEDA approval"
    fi
    assert_qvi_group_state 0

    print_green "[QVI] Multisig AID ${QVI_NAME} with prefix: ${QVI_PRE}"
}

approve_qvi_delegation() {
    local participant_prefix

    for participant_prefix in "$@"; do
        kli query \
            --name "${GAR1}" \
            --alias "${GEDA_NAME}" \
            --passcode "${GAR1_PASSCODE}" \
            --prefix "${participant_prefix}" >/dev/null || return 1
        kli query \
            --name "${GAR2}" \
            --alias "${GEDA_NAME}" \
            --passcode "${GAR2_PASSCODE}" \
            --prefix "${participant_prefix}" >/dev/null || return 1
    done

    klid gar1 delegate confirm \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --interact \
        --auto || return 1
    klid gar2 delegate confirm \
        --name "${GAR2}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR2_PASSCODE}" \
        --interact \
        --auto || return 1
    wait_kli_jobs gar1 gar2 || return 1
}

rotate_qvi_existing_members() {
    local expected_sequence=$1
    local signing_roles=$2
    local rotation_roles=$3
    shift 3
    local submit_result=""

    print_yellow "[QVI] Submitting rotation sequence ${expected_sequence}"
    submit_result=$(run_qvi_json \
        ms-rotate-submit \
        --signing-roles "${signing_roles}" \
        --rotation-roles "${rotation_roles}" \
        --artifact "${QVI_DATA_DIR}/pending-group-event.json") ||
        return 1
    [[ "$(printf '%s\n' "${submit_result}" | jq -r '.event.groupPrefix')" == "${QVI_PRE}" ]] ||
        return 1

    approve_qvi_delegation "$@" || return 1
    run_qvi_json \
        ms-rotate-complete \
        --delegator-prefix "${GEDA_PRE}" \
        --expected-sequence "${expected_sequence}" \
        --signing-roles "${signing_roles}" \
        --rotation-roles "${rotation_roles}" \
        --artifact "${QVI_DATA_DIR}/pending-group-event.json" >/dev/null ||
        return 1
}

rotate_qvi_with_joining_member() {
    local expected_sequence=$1
    shift
    local submit_result=""

    print_yellow "[QVI] Submitting joining-member rotation sequence ${expected_sequence}"
    submit_result=$(run_qvi_json \
        ms-join-rotation-submit \
        --existing-roles qar1,qar2 \
        --joining-role qar4 \
        --signing-roles qar1,qar2,qar4 \
        --rotation-roles qar1,qar2,qar4 \
        --artifact "${QVI_DATA_DIR}/pending-group-event.json") ||
        return 1
    [[ "$(printf '%s\n' "${submit_result}" | jq -r '.event.groupPrefix')" == "${QVI_PRE}" ]] ||
        return 1

    approve_qvi_delegation "$@" || return 1
    run_qvi_json \
        ms-rotate-complete \
        --delegator-prefix "${GEDA_PRE}" \
        --expected-sequence "${expected_sequence}" \
        --signing-roles qar1,qar2,qar4 \
        --rotation-roles qar1,qar2,qar4 \
        --artifact "${QVI_DATA_DIR}/pending-group-event.json" >/dev/null ||
        return 1
}

establish_qvi() {
    create_qvi_multisig || return 1
    rotate_qvi_existing_members 1 \
        qar1,qar2,qar3 \
        qar1,qar2,qar3 \
        "${QAR1_PRE}" "${QAR2_PRE}" "${QAR3_PRE}" || return 1
    rotate_qvi_existing_members 2 \
        qar1,qar2,qar3 \
        qar1,qar2,qar4 \
        "${QAR1_PRE}" "${QAR2_PRE}" "${QAR3_PRE}" || return 1
    rotate_qvi_with_joining_member 3 \
        "${QAR1_PRE}" "${QAR2_PRE}" "${QAR4_PRE}" || return 1
    authorize_qvi_multisig_agent_endpoint_role || return 1
    resolve_qvi_oobi || return 1
}

# QVI: Authorize all agent endpoint roles and derive one multisig OOBI.
QVI_OOBI=""
function authorize_qvi_multisig_agent_endpoint_role(){
    local authorization_result=""
    local authorization_failed=false

    print_yellow "Authorizing QVI multisig agent endpoint role"
    authorization_result=$(run_qvi_json \
      ms-authorize \
      --data-dir "${QVI_DATA_DIR}") ||
      authorization_failed=true
    if [[ "${authorization_failed}" == true ]]; then
        fail_workflow "QVI agent endpoint-role authorization failed"
    fi

    QVI_OOBI=$(printf '%s\n' "${authorization_result}" |
        jq -r '.multisigOobi')
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
    run_qvi_json \
        ms-resolve-oobi \
        --alias "${LE_NAME}" \
        --oobi "${LE_OOBI}" \
        --roles qar1,qar2,qar4 >/dev/null ||
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
    run_qvi_json \
      ms-resolve-person-oobi \
      --oobi-file "${QVI_DATA_DIR}/qvi-oobi.json" >/dev/null ||
      return 1
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
    local admission_failed=false

    run_qvi_json \
        ms-admit \
        --actor qvi \
        --issuer-prefix "${issuer_prefix}" \
        --credential-said "${credential_said}" \
        --schema "${schema}" \
        --issuee-prefix "${QVI_PRE}" \
        --status-sequence 0 >/dev/null ||
        admission_failed=true
    if [[ "${admission_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to admit ${story_label} credential ${credential_said}"
    fi
    assert_qvi_credential_state \
        "${credential_said}" \
        "${issuer_prefix}" \
        "${schema}" \
        "${QVI_PRE}" \
        0
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
  local presentation_failed=false
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

  print_yellow "[QVI] Presenting QVI Credential ${QVI_CRED_SAID} to Sally"
  run_qvi_json \
    ms-present \
    --actor qvi \
    --credential-said "${QVI_CRED_SAID}" \
    --recipient-prefix "${DIRECT_SALLY_PRE}" >/dev/null ||
    presentation_failed=true
  if [[ "${presentation_failed}" == true ]]; then
      fail_workflow "[QVI] Failed to transmit the active QVI credential to Sally"
  fi

  wait_for_sally_callback "active QVI" iss "${QVI_CRED_SAID}"
}

############################ LE Credential ##################################
# QVI: Prepare, create, and Issue LE credential to GEDA
# Create QVI credential registry
function create_qvi_reg() {
    local registry_result=""
    local registry_failed=false

    registry_result=$(run_qvi_json \
      ms-registry \
      --registry-name "${QVI_REGISTRY}") ||
      registry_failed=true
    if [[ "${registry_failed}" == true ]]; then
        fail_workflow "[QVI] Credential registry creation failed"
    fi

    QVI_REG_REGK=$(printf '%s\n' "${registry_result}" |
        jq -r '.registryRegk')

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
    print_lcyan "$(jq '.' "${KLI_DATA_DIR}/temp-data/qvi-edge.json")"
}

# QVI: Prepare LE credential data
function prepare_le_cred_data() {
    print_yellow "[QVI] Preparing LE credential data"
    jq -n --arg lei "${LE_LEI}" '{LEI: $lei}' \
        > "${KLI_DATA_DIR}/temp-data/legal-entity-data.json"
}

# QVI: Create LE credential
record_qvi_issuance_result() {
    local issuance_result=$1
    LAST_ISSUED_CREDENTIAL_SAID=$(
        printf '%s\n' "${issuance_result}" |
            jq -r '.credentialSaid'
    )
}

function create_and_grant_le_credential() {
    local issuance_result=""
    local issuance_failed=false

    echo
    print_green "[QVI] creating LE credential"

    print_lcyan "[QVI] Legal Entity edge Data"
    print_lcyan "$(jq '.' "${KLI_DATA_DIR}/temp-data/qvi-edge.json")"

    print_lcyan "[QVI] Legal Entity Credential Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/legal-entity-data.json")"

    issuance_result=$(run_qvi_json \
      ms-issue \
      --kind le \
      --data-dir "/acdc-info" \
      --issuee-prefix "${LE_PRE}") ||
      issuance_failed=true
    if [[ "${issuance_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to create and grant the LE credential"
    fi
    record_qvi_issuance_result "${issuance_result}"
    LE_CRED_SAID="${LAST_ISSUED_CREDENTIAL_SAID}"
    assert_qvi_credential_state \
        "${LE_CRED_SAID}" \
        "${QVI_PRE}" \
        "${LE_SCHEMA}" \
        "${LE_PRE}" \
        0

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
  local grant_time=""

  print_yellow "[LE] Presenting its own credential ${LE_CRED_SAID} to Sally"
  grant_time=$(kli time | tr -d '[:space:]') || return 1
  klid lar1 ipex grant \
      --name "${LAR1}" \
      --alias "${LE_NAME}" \
      --passcode "${LAR1_PASSCODE}" \
      --said "${LE_CRED_SAID}" \
      --recipient "${DIRECT_SALLY_PRE}" \
      --time "${grant_time}" || return 1
  klid lar2 ipex join \
      --name "${LAR2}" \
      --passcode "${LAR2_PASSCODE}" \
      --auto || return 1
  wait_kli_jobs lar1 lar2 || return 1

  wait_for_sally_callback "active LE" iss "${LE_CRED_SAID}"
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
    print_lcyan "$(jq '.' "${KLI_DATA_DIR}/temp-data/oor-auth-edge.json")"

    print_lcyan "[QVI] OOR Credential Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/oor-data.json")"

    echo
    print_green "[QVI] creating and granting OOR credential"

    issuance_result=$(run_qvi_json \
      ms-issue \
      --kind oor \
      --data-dir "/acdc-info" \
      --issuee-prefix "${PERSON_PRE}") ||
      credential_creation_failed=true
    if [[ "${credential_creation_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to create and grant the OOR credential"
    fi
    record_qvi_issuance_result "${issuance_result}"
    OOR_CRED_SAID="${LAST_ISSUED_CREDENTIAL_SAID}"
    assert_qvi_credential_state \
        "${OOR_CRED_SAID}" \
        "${QVI_PRE}" \
        "${OOR_SCHEMA}" \
        "${PERSON_PRE}" \
        0

    echo
    print_lcyan "[QVI] OOR credential created"
    echo
}

admit_person_leaf_credential() {
    local story_label=$1
    local schema=$2
    local credential_said=$3
    local admission_failed=false

    run_qvi_json \
        ms-admit \
        --actor person \
        --issuer-prefix "${QVI_PRE}" \
        --credential-said "${credential_said}" \
        --schema "${schema}" \
        --issuee-prefix "${PERSON_PRE}" \
        --status-sequence 0 >/dev/null ||
        admission_failed=true
    if [[ "${admission_failed}" == true ]]; then
        fail_workflow "[PERSON] Failed to admit ${story_label} credential ${credential_said}"
    fi
    assert_person_credential_state \
        "${credential_said}" \
        "${QVI_PRE}" \
        "${schema}" \
        "${PERSON_PRE}" \
        0
}

# Person: Admit OOR credential from QVI
function admit_oor_credential() {
    print_lcyan "OOR Credential SAID: ${OOR_CRED_SAID}"

    print_yellow "[PERSON] Admitting OOR credential ${OOR_CRED_SAID} to ${PERSON}"
    admit_person_leaf_credential \
        "OOR" \
        "${OOR_SCHEMA}" \
        "${OOR_CRED_SAID}"

    echo
    print_green "OOR Credential admitted"
    echo
}

# PERSON: Present OOR credential to Sally (vLEI Reporting API)
function person_present_oor_cred_to_sally() {
    local credential_transmission_failed=false

    print_yellow "[PERSON] Presenting active OOR Credential ${OOR_CRED_SAID} to Sally"
    run_qvi_json \
      ms-present \
      --actor person \
      --credential-said "${OOR_CRED_SAID}" \
      --recipient-prefix "${DIRECT_SALLY_PRE}" >/dev/null ||
        credential_transmission_failed=true
    if [[ "${credential_transmission_failed}" == true ]]; then
        fail_workflow "[PERSON] Failed to transmit the active OOR credential to Sally"
    fi

    wait_for_sally_callback "active OOR" iss "${OOR_CRED_SAID}"
}

function revoke_qvi_leaf_credential() {
    local label=$1
    local credential_said=$2
    local schema=$3
    local revocation_failed=false
    local revocation_result=""

    print_yellow "[QVI] Revoking ${label} credential ${credential_said}"
    revocation_result=$(run_qvi_json \
        ms-revoke \
        --credential-said "${credential_said}") ||
        revocation_failed=true
    if [[ "${revocation_failed}" == true ]]; then
        fail_workflow "[QVI] ${label} credential revocation failed"
    fi

    LAST_REVOCATION_TIMESTAMP=$(printf '%s\n' "${revocation_result}" |
        jq -r '.revocationTimestamp')
    LAST_REVOCATION_TEL_DIGEST=$(printf '%s\n' "${revocation_result}" |
        jq -r '.revocationTelDigest')
    assert_qvi_credential_state \
        "${credential_said}" \
        "${QVI_PRE}" \
        "${schema}" \
        "${PERSON_PRE}" \
        1
    print_green "[QVI] ${label} credential revocation converged on all three QARs"
    print_lcyan \
        "[QVI] ${label} revocation TEL: ${LAST_REVOCATION_TEL_DIGEST} at ${LAST_REVOCATION_TIMESTAMP}"
}

function revoke_oor_credential() {
    revoke_qvi_leaf_credential "OOR" "${OOR_CRED_SAID}" "${OOR_SCHEMA}"
}

function revoke_ecr_credential() {
    revoke_qvi_leaf_credential "ECR" "${ECR_CRED_SAID}" "${ECR_SCHEMA}"
}

function present_revoked_oor_to_sally() {
    local credential_said_is_missing=false
    [[ -z "${OOR_CRED_SAID}" ]] && credential_said_is_missing=true
    if [[ "${credential_said_is_missing}" == true ]]; then
        fail_workflow "[QVI] Cannot present a revoked OOR without its credential SAID"
    fi

    local credential_transmission_failed=false
    local presentation_boundary
    local evidence_wait_failed=false

    presentation_boundary=$(utc_now)
    print_yellow "[QVI] Presenting revoked OOR credential ${OOR_CRED_SAID} to Sally"
    run_qvi_json \
        ms-present \
        --actor qvi \
        --credential-said "${OOR_CRED_SAID}" \
        --recipient-prefix "${DIRECT_SALLY_PRE}" >/dev/null ||
        credential_transmission_failed=true
    if [[ "${credential_transmission_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to transmit revoked OOR credential ${OOR_CRED_SAID}"
    fi

    # revoked_oor_was_rejected_and_reported checks the callback file and one
    # current Sally log snapshot per poll. Docker CLI responsiveness remains
    # an infrastructure prerequisite rather than a poller responsibility.
    poll_until \
        "Sally rejection and revocation callback for OOR ${OOR_CRED_SAID}" \
        "${WORKFLOW_TIMEOUT_SECONDS}" \
        revoked_oor_was_rejected_and_reported \
        "${presentation_boundary}" \
        "${OOR_CRED_SAID}" >/dev/null || evidence_wait_failed=true
    if [[ "${evidence_wait_failed}" == true ]]; then
        fail_workflow "[QVI] Sally did not prove revoked-OOR rejection and reporting for ${OOR_CRED_SAID}"
    fi
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
    print_lcyan "$(jq '.' "${KLI_DATA_DIR}/temp-data/legal-entity-edge.json")"

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
    print_lcyan "$(jq '.' "${KLI_DATA_DIR}/temp-data/ecr-auth-edge.json")"

    print_lcyan "[QVI] ECR Credential Data"
    print_lcyan "$(cat "${KLI_DATA_DIR}/temp-data/ecr-data.json")"

    pause "Press [enter] to create and grant the ECR credential"
    print_green "[QVI] creating and granting ECR credential"

    issuance_result=$(run_qvi_json \
      ms-issue \
      --kind ecr \
      --data-dir "/acdc-info" \
      --issuee-prefix "${PERSON_PRE}") ||
      credential_creation_failed=true
    if [[ "${credential_creation_failed}" == true ]]; then
        fail_workflow "[QVI] Failed to create and grant the ECR credential"
    fi
    record_qvi_issuance_result "${issuance_result}"
    ECR_CRED_SAID="${LAST_ISSUED_CREDENTIAL_SAID}"
    assert_qvi_credential_state \
        "${ECR_CRED_SAID}" \
        "${QVI_PRE}" \
        "${ECR_SCHEMA}" \
        "${PERSON_PRE}" \
        0

    echo
    print_lcyan "[QVI] ECR credential created and granted"
    echo
}

# Person: Admit ECR credential from QVI
function admit_ecr_credential() {
    print_yellow "[PERSON] Admitting ECR credential ${ECR_CRED_SAID} to ${PERSON}"
    admit_person_leaf_credential \
        "ECR" \
        "${ECR_SCHEMA}" \
        "${ECR_CRED_SAID}"

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
  create_docker_containers || return 1
  start_foundation_services || return 1
  preflight_versions || return 1
  setup_keria_identifiers || return 1
  create_aids || return 1
  read_prefixes || return 1
  resolve_gar_oobis || return 1
}

# Sets up GEDA, GEDA registry, delegation to the QVI, and QVI OOBI resolution for GARs and LARs
function geda_delegation_to_qvi() {
  create_geda_multisig || return 1
  create_geda_reg || return 1
  start_sally || return 1
  resolve_oobis || return 1
  challenge_response || return 1
  qars_resolve_geda_oobi || return 1
  establish_qvi || return 1
}

# Creates the QVI credential, grants it from the GEDA to the QVI, and presents it to sally
function qvi_credential() {
  prepare_qvi_cred_data || return 1
  create_qvi_credential || return 1
  grant_qvi_credential || return 1
  admit_qvi_credential || return 1
  pause "Press [ENTER] to present QVI credential to Sally" || return 1
  present_qvi_cred_to_sally_signify || return 1
}

# Creates the LE multisig, resolves the LE OOBI, creates the QVI registry, and prepares and grants the LE credential
function le_creation_and_granting() {
  create_le_multisig || return 1
  qars_resolve_le_oobi || return 1
  create_qvi_reg || return 1
  prepare_qvi_edge || return 1
  prepare_le_cred_data || return 1
  create_and_grant_le_credential || return 1
  admit_le_credential || return 1
  create_le_reg || return 1
  prepare_le_edge || return 1
}

# Presents the LE credential to the local Sally deployment
function le_sally_presentation() {
  present_le_cred_to_sally || return 1
}

# Creates the OOR Auth credential and grants it to the QVI
function oor_auth_cred() {
  prepare_oor_auth_data || return 1
  create_oor_auth_credential || return 1
  grant_oor_auth_credential || return 1
  admit_oor_auth_credential || return 1
  prepare_oor_auth_edge || return 1
}

# Creates the OOR credential, grants it to the Person, and presents it to Sally from the person
function oor_cred(){
  prepare_oor_cred_data || return 1
  create_and_grant_oor_credential || return 1
  admit_oor_credential || return 1
}

# Workflow function for the OOR Auth and OOR credentials
function oor_auth_and_oor_cred() {
  oor_auth_cred || return 1
  oor_cred || return 1
}

# Creates the ECR Auth credential and grants it to the QVI
function ecr_auth_cred() {
  prepare_ecr_auth_data || return 1
  create_ecr_auth_credential || return 1
  grant_ecr_auth_credential || return 1
  admit_ecr_auth_credential || return 1
  prepare_ecr_auth_edge || return 1
}

# Creates the ECR credential, grants it to the Person, and admits it
function ecr_cred() {
  prepare_ecr_cred_data || return 1
  create_and_grant_ecr_credential || return 1
  admit_ecr_credential || return 1
}

# Workflow function for the ECR Auth and ECR credentials
function ecr_auth_and_ecr_cred() {
  ecr_auth_cred || return 1
  ecr_cred || return 1
}

# Main workflow driving the end to end QVI credentialing and reporting process
function main_flow() {
  print_lcyan "--------------------------------------------------------------------------------"
  print_lcyan "                       Running canonical QVI workflow"
  print_lcyan "--------------------------------------------------------------------------------"
  setup || return 1
  geda_delegation_to_qvi || return 1
  qvi_credential || return 1

  le_creation_and_granting || return 1
  pause "Press [ENTER] to present LE credential to Sally" || return 1
  le_sally_presentation || return 1

  oor_auth_and_oor_cred || return 1
  pause "Press [ENTER] to present OOR to Sally" || return 1
  person_present_oor_cred_to_sally || return 1

  revoke_oor_credential || return 1
  present_revoked_oor_to_sally || return 1

  ecr_auth_and_ecr_cred || return 1
  revoke_ecr_credential || return 1

  pause "Press [enter] to end workflow" || return 1
  end_workflow || return 1
}

# Runs the workflow and presents the LE credential to GLEIF Staging Sally
function present_to_staging() {
  print_green "--------------------------------------------------------------------------------"
  print_green "Running workflow and presenting LE credential to GLEIF Staging Sally"
  print_green "Using the following URL for Sally's mailbox:"
  print_green "http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2"
  print_green "--------------------------------------------------------------------------------"
  setup || return 1
  geda_delegation_to_qvi || return 1
  qvi_credential || return 1
  le_creation_and_granting || return 1
  present_le_gleif_staging || return 1
  end_workflow || return 1
}

# Runs the workflow and presents the LE credential to GLEIF Production Sally
function present_to_production() {
  print_green "--------------------------------------------------------------------------------"
  print_green "Running workflow and presenting LE credential to GLEIF Production Sally"
  print_green "Using the following URL for Sally's mailbox:"
  print_green "http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2"
  print_green "--------------------------------------------------------------------------------"
  setup || return 1
  geda_delegation_to_qvi || return 1
  qvi_credential || return 1
  le_creation_and_granting || return 1
  present_le_gleif_production || return 1
  end_workflow || return 1
}

# Runs the workflow and presents the LE credential to an alternate Sally
function present_to_alternate_sally() {
  print_green "--------------------------------------------------------------------------------"
  print_green "Running workflow and presenting LE credential to alternate Sally: ${ALT_SALLY_ALIAS}"
  print_green "Using the following URL for Sally's mailbox:"
  print_green "${ALT_SALLY_OOBI}"
  print_green "--------------------------------------------------------------------------------"
  setup || return 1
  geda_delegation_to_qvi || return 1
  qvi_credential || return 1
  le_creation_and_granting || return 1
  present_le_to_alternate "${ALT_SALLY_ALIAS}" "${ALT_SALLY_OOBI}" || return 1
  end_workflow || return 1
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
        "      --keep-runtime    Preserve runtime/ and the Compose stack" \
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

    case "${WORKFLOW_MODE}" in
        alternate) present_to_alternate_sally ;;
        staging) present_to_staging ;;
        production) present_to_production ;;
        default) main_flow ;;
    esac

    workflow_duration=$(( $(date +%s) - START_TIME ))
    print_lcyan "Full chain workflow completed in ${workflow_duration} seconds"
}

script_is_being_executed=false
[[ "${BASH_SOURCE[0]}" == "$0" ]] && script_is_being_executed=true
if [[ "${script_is_being_executed}" == true ]]; then
    main "$@"
fi
