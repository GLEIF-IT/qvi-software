#!/usr/bin/env bash
# vlei-workflow.sh - KERIA Docker with single sig GEDA, QVI, and LE
# Runs the entire QVI issuance workflow end to end

set -u  # undefined variable detection
START_TIME=$(date +%s)

# Load utility functions
source color-printing.sh

# NOTE: (used by resolve-env.ts)
ENVIRONMENT=single-sig-docker # means separate witnesses for GARs, QARs + LARs, Person, and Sally
KEYSTORE_DIR=./docker-keystores

# Load kli commands
source ./kli-commands.sh "${KEYSTORE_DIR}" "${ENVIRONMENT}"

ALT_SALLY_ALIAS="alternate"
ALT_SALLY_OOBI="http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2"

PAUSE_ENABLED=false
function pause() {
    if [[ $PAUSE_ENABLED == true ]]; then
        read -p "$*"
    else
        print_dark_gray "Skipping pause ${*}"
    fi
}

# Check system dependencies
required_sys_commands=(docker jq tsx)
for cmd in "${required_sys_commands[@]}"; do
    if ! command -v $cmd &>/dev/null; then
        print_red "$cmd is not installed. Please install it."
        exit 1
    fi
done

# Cleanup functions
trap cleanup INT
trap cleanup ERR
function cleanup() {
    echo
    docker compose -f $DOCKER_COMPOSE_FILE kill
    docker compose -f $DOCKER_COMPOSE_FILE down -v
    rm -rfv "${KEYSTORE_DIR:?}"/*
    END_TIME=$(date +%s)
    SCRIPT_TIME=$(($END_TIME - $START_TIME))
    print_lcyan "Script took ${SCRIPT_TIME} seconds to run"
    print_lcyan "Single Sig KERIA Docker vLEI workflow completed"
    exit 0
}

function clear_containers() {
    container_names=("gar" "lar" "qar" "person" "sally" "direct-sally")

    for name in "${container_names[@]}"; do
    if docker ps -a | grep -q "$name"; then
        docker kill $name || true && docker rm $name || true
    fi
    done
}

DOCKER_COMPOSE_FILE=docker-compose.yaml

function create_docker_network() {
  print_yellow "KEYSTORE_DIR: ${KEYSTORE_DIR}"
  print_yellow "Using environment $ENVIRONMENT"
  # Create docker network if it does not exist
  docker network inspect vlei >/dev/null 2>&1 || docker network create vlei
}

function create_docker_containers() {
  print_green "-------------------Building gleif/vlei-workflow-signify container---------------"
  # Build gleif/vlei-workflow-signify container
  make build-signify
}

# QVI Config
QVI_SIGNIFY_DIR=/vlei-workflow/src
QVI_DATA_DIR=/vlei-workflow/qvi_data
LOCAL_QVI_DATA_DIR=$(dirname "$0")/qvi_data

SCHEMA_SERVER=http://vlei-server:7723

#### Witness Hosts ####
# Wan 5642
WIT_HOST_GAR=http://gar-witnesses:5642
WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
# Wil 5643
WIT_HOST_QAR=http://qar-witnesses:5643
WIL_PRE=BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM
# Wes 5644
WIT_HOST_PERSON=http://person-witnesses:5644
WES_PRE=BIKKuvBwpmDVA4Ds-EpL5bt9OqPzWPja2LigFYZN2YfX
# Wit 5645
WIT_HOST_SALLY=http://sally-witnesses:5645
WIT_PRE=BM35JN8XeJSEfpxopjn5jr7tAHCE5749f0OobhMLCorE

# Container configuration (name of the config dir in docker containers kli*)
CONT_CONFIG_DIR=/config

#### Identifier Information ####
# GEDA AIDs - GLEIF External Delegated AID
GAR=accolon
export GAR_PRE=temp_geda_pre

# Legal Entity AIDs
LAR=elaine
export LAR_PRE=temp_lar_pre

#### KERIA and Signify Identifiers ####
QAR=galahad
export QAR_PRE=temp_qar_pre
export QVI_NAME=qvi

# Person AID
PERSON=mordred
export PERSON_PRE=temp_person_pre

#### Credential data ####
LE_LEI=254900OPPU84GM83MG36 # GLEIF Americas
PERSON_NAME="Mordred Delacqs"
PERSON_ECR="Consultant"
PERSON_OOR="Advisor"

# Sally - vLEI Reporting API
WEBHOOK_HOST_LOCAL=http://127.0.0.1:9923
# exporting so available for child docker compose processes
export WEBHOOK_HOST=http://hook:9923
export SALLY_HOST=http://sally:9723
export SALLY=sally
export SALLY_ALIAS=sallyIndirect
export SALLY_PASSCODE=VVmRdBTe5YCyLMmYRqTAi
export SALLY_SALT=0AD45YWdzWSwNREuAoitH_CC
export SALLY_PRE=EA69Z5sR2kr-05QmZ7v3VuMq8MdhVupve3caHXbhom0D # Different here because Sally uses witness Wit instead of Wan

# Direct mode Sally
export DIRECT_SALLY_HOST=http://direct-sally:9823
export DIRECT_SALLY=direct-sally
export DIRECT_SALLY_ALIAS=directSally
export DIRECT_SALLY_PASSCODE=4TBjjhmKu9oeDp49J7Xdy
export DIRECT_SALLY_SALT=0ABVqAtad0CBkhDhCEPd514T
export DIRECT_SALLY_PRE=ECLwKe5b33BaV20x7HZWYi_KUXgY91S41fRL2uCaf4WQ # Different here because of direct mode sally with no witnesses and a new passcode and salt

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

#### Write keria-signify-docker.env file with updated values ####
function write_docker_env(){
  print_bg_blue "[ADMIN] Writing prefixes, salts, passcodes, and schemas to keria-signfiy-docker.env"
  read -r -d '' DOCKER_ENV << EOM
#### Identifier Information ####
# GLEIF Authorized Representatives (GAR) AIDs
GAR=$GAR
GAR_SALT=$GAR_SALT
GAR_PASSCODE=$GAR_PASSCODE

# Legal Entity AIDs
LAR=$LAR
LAR_SALT=$LAR_SALT
LAR_PASSCODE=$LAR_PASSCODE

# Sally AID
SALLY_ALIAS=$SALLY_ALIAS
SALLY_PRE=$SALLY_PRE

# Direct Sally AID
DIRECT_SALLY_ALIAS=$DIRECT_SALLY_ALIAS
DIRECT_SALLY_PRE=$DIRECT_SALLY_PRE

# Credential Schemas
QVI_REGISTRY=vLEI-qvi
QVI_SCHEMA=$QVI_SCHEMA
LE_SCHEMA=$LE_SCHEMA
ECR_AUTH_SCHEMA=$ECR_AUTH_SCHEMA
OOR_AUTH_SCHEMA=$OOR_AUTH_SCHEMA
ECR_SCHEMA=$ECR_SCHEMA
OOR_SCHEMA=$OOR_SCHEMA
EOM

  print_dark_gray "Writing keystore and identifier information to docker.env"
  print_lcyan "${DOCKER_ENV}"
  echo "${DOCKER_ENV}" > ./keria-signify-docker.env
}

function start_docker_containers() {
  # Containers
  docker compose -f $DOCKER_COMPOSE_FILE up --wait
  if [ $? -ne 0 ]; then
      print_red "Docker services failed to start properly. Exiting."
      cleanup
      exit 1
  fi
}

################################################
# QVI Workflow with KERIpy, KERIA, and SignifyTS
################################################
#### Prepare Salts and Passcodes ####
export SIGTS_AIDS=""
function generate_salts_and_passcodes(){
  # salts and passcodes need to be new and dynamic on each run so that when presenting credentials to
  # other sally instances, not this one, that duplicity is not created by virtue of using the same
  # identifier salt, passcode, and inception configuration.

  # Does not include Sally because it is okay if sally stays the same.

  print_green "Generating salts"
  # Export these variables so they are available in the child docker compose processes
  export GAR_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "GAR_SALT: ${GAR_SALT}"
  export LAR_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "LAR_SALT: ${LAR_SALT}"
  export QAR_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "QAR_SALT: ${QAR_SALT}"
  export QVI_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "QVI_SALT: ${QVI_SALT}"
  export PERSON_SALT=$(kli salt | tr -d " \t\n\r" ) && print_lcyan "PERSON_SALT: ${PERSON_SALT}"

  export GAR_PASSCODE=$(kli passcode generate | tr -d " \t\n\r" )   && print_lcyan "GAR_PASSCODE: ${GAR_PASSCODE}"
  export LAR_PASSCODE=$(kli passcode generate | tr -d " \t\n\r" )   && print_lcyan "LAR_PASSCODE: ${LAR_PASSCODE}"
  export PERSON_PASSCODE=$(kli passcode generate | tr -d " \t\n\r" ) && print_lcyan "PERSON_PASSCODE: ${PERSON_PASSCODE}"

  # Does not include Sally because it is okay if sally stays the same.

  # KERIA SignifyTS QVI cryptographic names and seeds to feed into SignifyTS as a bespoke, delimited data format
  SIGTS_AIDS="qar|$QAR|$QAR_SALT,person|$PERSON|$PERSON_SALT,qvi|$QVI_NAME|$QVI_SALT"
}

function setup_keria_identifiers() {
  print_yellow "Creating QVI and Person Identifiers from SignifyTS + KERIA"

  sig_tsx "${QVI_SIGNIFY_DIR}/single-sig/qar-and-person-setup.ts" "${ENVIRONMENT}" "${QVI_DATA_DIR}" "${SIGTS_AIDS}"

  print_green "QVI and Person Identifiers from SignifyTS + KERIA are "
  # Extract prefixes from the SignifyTS output because they are dynamically generated and unique each run.
  # They are needed for doing OOBI resolutions to connect SignifyTS AIDs to KERIpy AIDs.
  qvi_setup_data=$(cat "${LOCAL_QVI_DATA_DIR}"/qar-and-person-info.json)
  QAR_PRE=$(echo    $qvi_setup_data | jq -r ".QAR.aid"           | tr -d '"')
  PERSON_PRE=$(echo  $qvi_setup_data | jq -r ".PERSON.aid"       | tr -d '"')
  QAR_OOBI=$(echo   $qvi_setup_data | jq -r ".QAR.agentOobi"     | tr -d '"')
  PERSON_OOBI=$(echo $qvi_setup_data | jq -r ".PERSON.agentOobi" | tr -d '"')

  # Show dyncamic, extracted Signify identifiers and OOBIs
  print_green     "QAR   Prefix: $QAR_PRE"
  print_dark_gray "QAR     OOBI: $QAR_OOBI"
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

    # Check if exists
    exists=$(${KLI_CMD:-kli} list --name "${NAME}" --passcode "${PASSCODE}")
    if [[ ! "$exists" =~ "Keystore must already exist" ]]; then
        print_dark_gray "AID ${NAME} already exists"
        return
    fi

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
    create_aid "${GAR}" "${GAR_SALT}" "${GAR_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-gars.json" "/config/incept-cfg-gars.json"
    create_aid "${LAR}" "${LAR_SALT}" "${LAR_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-qars.json" "/config/incept-cfg-qars.json"
}

function read_prefixes() {
  export GAR_PRE=$(kli status  --name "${GAR}"  --alias "${GAR}"  --passcode "${GAR_PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )
  export LAR_PRE=$(kli status  --name "${LAR}"  --alias "${LAR}"  --passcode "${LAR_PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )

  print_green "------------------------------Reading identifier prefixes using the KLI------------------------------"
  print_lcyan "GAR Prefix: ${GAR_PRE}"
  print_lcyan "LAR Prefix: ${LAR_PRE}"
}

# OOBI resolutions between single sig AIDs
function resolve_oobis() {
    exists=$(kli contacts list --name "${GAR}" --passcode "${GAR_PASSCODE}" | jq .alias | tr -d '"' | grep "${LAR}")
    if [[ "$exists" =~ "${LAR}" ]]; then
        print_yellow "OOBIs already resolved"
        return
    fi

    export SALLY_OOBI="${WIT_HOST_SALLY}/oobi/${SALLY_PRE}/witness/${WIT_PRE}" # indirect-mode sally
    export DIRECT_SALLY_OOBI="${DIRECT_SALLY_HOST}/oobi"
    export GAR_OOBI="${WIT_HOST_GAR}/oobi/${GAR_PRE}/witness/${WAN_PRE}"
    export LAR_OOBI="${WIT_HOST_QAR}/oobi/${LAR_PRE}/witness/${WIL_PRE}"
    export OOBIS_FOR_KERIA="gar|$GAR_OOBI,lar|$LAR_OOBI,directSally|$DIRECT_SALLY_OOBI"

    print_green "DIRECT SALLY OOBI: ${DIRECT_SALLY_OOBI}"

    sig_tsx "${QVI_SIGNIFY_DIR}/single-sig/resolve-oobis-lar-gar-sally.ts" $ENVIRONMENT "${SIGTS_AIDS}" "${OOBIS_FOR_KERIA}"

    echo
    print_green "------------------------------Connecting Keystores with OOBI Resolutions------------------------------"
    print_yellow "Resolving OOBIs for GAR"
    kli oobi resolve --name "${GAR}" --oobi-alias "${GAR}"    --passcode "${GAR_PASSCODE}" --oobi "${GAR_OOBI}"
    kli oobi resolve --name "${GAR}" --oobi-alias "${LAR}"    --passcode "${GAR_PASSCODE}" --oobi "${LAR_OOBI}"
    kli oobi resolve --name "${GAR}" --oobi-alias "${QAR}"    --passcode "${GAR_PASSCODE}" --oobi "${QAR_OOBI}"
    kli oobi resolve --name "${GAR}" --oobi-alias "${PERSON}" --passcode "${GAR_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${GAR}" --oobi-alias "${SALLY_ALIAS}"        --passcode "${GAR_PASSCODE}" --oobi "${SALLY_OOBI}"
    kli oobi resolve --name "${GAR}" --oobi-alias "${DIRECT_SALLY_ALIAS}" --passcode "${GAR_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for LAR 1"
    kli oobi resolve --name "${LAR}" --oobi-alias "${GAR}"    --passcode "${LAR_PASSCODE}" --oobi "${GAR_OOBI}"
    kli oobi resolve --name "${LAR}" --oobi-alias "${QAR}"    --passcode "${LAR_PASSCODE}" --oobi "${QAR_OOBI}"
    kli oobi resolve --name "${LAR}" --oobi-alias "${PERSON}" --passcode "${LAR_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${LAR}" --oobi-alias "${SALLY_ALIAS}"        --passcode "${LAR_PASSCODE}" --oobi "${SALLY_OOBI}"
    kli oobi resolve --name "${LAR}" --oobi-alias "${DIRECT_SALLY_ALIAS}" --passcode "${LAR_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    echo
}

function create_gar_reg() {
  # Check if GEDA credential registry already exists
  REGISTRY=$(kli vc registry list \
      --name "${GAR}" \
      --passcode "${GAR_PASSCODE}" | awk '{print $1}')
  if [ ! -z "${REGISTRY}" ]; then
      print_dark_gray "GEDA registry already created"
      return
  fi

  echo
  print_yellow "Creating GEDA registry"

  klid gar vc registry incept \
      --name ${GAR} \
      --alias ${GAR} \
      --passcode ${GAR_PASSCODE} \
      --usage "QVI Credential Registry for GEDA" \
      --registry-name ${GEDA_REGISTRY}

  docker wait gar
  docker rm gar

  echo
  print_green "QVI Credential Registry created for GEDA"
  echo
}

function recreate_sally_containers() {
  # Recreate sally container with new GEDA prefix
  export GEDA_PRE=${GAR_PRE}
  print_yellow "Recreating Sally container with new GEDA prefix ${GEDA_PRE}"
  docker compose -f $DOCKER_COMPOSE_FILE up -d sally direct-sally --wait
}

function create_qvi_delegate() {
    print_yellow "Creating QVI multisig AID with GEDA as delegator"

    local delegator_prefix="${GAR_PRE}"
    print_yellow "Delegator Prefix: ${delegator_prefix}"
    sig_tsx "${QVI_SIGNIFY_DIR}/single-sig/create-qvi-delegate.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${OOBIS_FOR_KERIA}" \
      "${delegator_prefix}" \
      "${QVI_DATA_DIR}"
    local delegated_qvi_info
    delegated_qvi_info=$(cat "${LOCAL_QVI_DATA_DIR}"/qvi-delegate-info.json)
    print_yellow "Delegated QVI Info:"
    print_lcyan "${delegated_qvi_info}"

    export QVI_PRE
    export QVI_PRE=$(echo "${delegated_qvi_info}" | jq .qviPre | tr -d '"')
    icpOpName=$(echo "${delegated_qvi_info}" | jq .icpOpName | tr -d '"')
    echo
    print_lcyan "QVI Prefix: ${QVI_PRE}"
    echo

    print_lcyan "[External] GEDA member approves delegated inception with 'kli delegate confirm'"
    echo

    print_yellow "GAR confirm delegated inception"
    kli delegate confirm --name "${GAR}" --alias "${GAR}" --passcode "${GAR_PASSCODE}" --interact --auto

    print_yellow "[GEDA] Waiting 5s on delegated inception completion"

    sig_tsx "${QVI_SIGNIFY_DIR}/single-sig/delegation-completion-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${delegator_prefix}" \
      "${icpOpName}" \
      "${QVI_DATA_DIR}"

    print_green "[QVI] AID ${QVI_NAME} with prefix: ${QVI_PRE}"
}

export QVI_OOBI=""
function resolve_qvi_oobi() {
    export QVI_OOBI=$(cat "${LOCAL_QVI_DATA_DIR}/qvi-agent-oobi.json" | jq .qviAgentOobi | tr -d '"')
    print_green "QVI Agent OOBI: ${QVI_OOBI}"
    kli oobi resolve --name "${GAR}" --oobi-alias "${QVI_NAME}" --passcode "${GAR_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${LAR}" --oobi-alias "${QVI_NAME}" --passcode "${LAR_PASSCODE}" --oobi "${QVI_OOBI}"

    print_yellow "Resolving QVI OOBI for Person"
    sig_tsx "${QVI_SIGNIFY_DIR}/single-sig/resolve-qvi-oobi-person.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${QVI_OOBI}"
    echo
}

function qvi_resolve_schema_oobis() {
    print_yellow "Resolving credential schema OOBIs for QVI"
    sig_tsx "${QVI_SIGNIFY_DIR}/single-sig/resolve-schema-oobis-qvi.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${OOBIS_FOR_KERIA}"
    echo
}

function prepare_qvi_cred_data() {
    print_bg_blue "[External] Preparing QVI credential data"
    read -r -d '' QVI_CRED_DATA << EOM
{
    "LEI": "${LE_LEI}"
}
EOM

    echo "$QVI_CRED_DATA" > ./acdc-info/temp-data/qvi-cred-data.json

    print_lcyan "QVI Credential Data"
    print_lcyan "$(cat ./acdc-info/temp-data/qvi-cred-data.json)"
}

function create_qvi_credential() {
    # Check if QVI credential already exists
    SAID=$(kli vc list \
        --name "${GAR}" \
        --alias "${GAR}" \
        --passcode "${GAR_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}")
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[External] QVI credential already created ${SAID} done."
        return
    fi

    echo
    print_green "[External] creating QVI credential"

    kli vc create \
        --name "${GAR}" \
        --alias "${GAR}" \
        --passcode "${GAR_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/acdc-info/temp-data/qvi-cred-data.json \
        --rules @/acdc-info/rules/rules.json

    echo
    print_lcyan "[External] QVI Credential created"
    echo
}

function grant_qvi_credential() {
    QVI_GRANT_SAID=$(kli ipex list \
        --name "${GAR}" \
        --alias "${GAR}" \
        --passcode "${GAR_PASSCODE}" \
        --sent \
        --said)
    if [ ! -z "${QVI_GRANT_SAID}" ]; then
        print_dark_gray "[External] GEDA QVI credential already granted"
        return
    fi
    SAID=$(kli vc list \
        --name "${GAR}" \
        --passcode "${GAR_PASSCODE}" \
        --alias "${GAR}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d '[:space:]')

    echo
    print_yellow $'[External] IPEX GRANTing QVI credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"
    kli ipex grant \
        --name "${GAR}" \
        --passcode "${GAR_PASSCODE}" \
        --alias "${GAR}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}"

    echo
    print_green "[External] QVI Credential issued to QVI"
    echo
}

function admit_qvi_credential() {
    QVI_CRED_SAID=$(kli vc list \
        --name "${GAR}" \
        --alias "${GAR}" \
        --passcode "${GAR_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d " \t\n\r")
    received=$(sig_tsx "${QVI_SIGNIFY_DIR}/single-sig/qvi-check-received-credential.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${QVI_CRED_SAID}"
    )
    if [[ "$received" == "true" ]]; then
        print_dark_gray "[QVI] QVI Credential ${QVI_CRED_SAID} already admitted"
        return
    fi

    echo
    print_yellow "[QVI] Admitting QVI Credential ${QVI_CRED_SAID} from GEDA"

    sig_tsx "${QVI_SIGNIFY_DIR}/single-sig/qvi-admit-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${GAR_PRE}" \
      "${QVI_CRED_SAID}"

    echo
    print_green "[QVI] Admitted QVI credential"
    echo
}

function present_qvi_cred_to_sally_kli() {
  print_yellow "Presenting QVI credential to Sally using KLI"
  SAID=$(kli vc list \
        --name "${GAR}" \
        --passcode "${GAR_PASSCODE}" \
        --alias "${GAR}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d '[:space:]')

    echo
    print_yellow $'[External] IPEX GRANTing QVI credential with\n\tSAID'" ${SAID}"$'\n\tto Sally'" ${SALLY_PRE}"
    kli ipex grant \
        --name "${GAR}" \
        --passcode "${GAR_PASSCODE}" \
        --alias "${GAR}" \
        --said "${SAID}" \
        --recipient "${SALLY_PRE}"

    echo
    print_green "[External] QVI Credential presented to Sally Indirect"
    echo
}

function present_qvi_cred_to_sally_signify() {
  print_yellow "Presenting QVI credential to Sally using SignifyTS"
  print_yellow "[QVI] Presenting QVI Credential to Sally"

#  print_dark_gray "arguments sent to script:"
#  print_lcyan "Environment: ${ENVIRONMENT}"
#  print_lcyan "SIGTS_AIDS: ${SIGTS_AIDS}"
#  print_lcyan "QVI_SCHEMA: ${QVI_SCHEMA}"
#  print_lcyan "GAR_PRE: ${GAR_PRE}"
#  print_lcyan "QVI_PRE: ${QVI_PRE}"
#  print_lcyan "SALLY_PRE: ${SALLY_PRE}"

  sig_tsx "${QVI_SIGNIFY_DIR}/single-sig/qvi-present-credential.ts" \
    "${ENVIRONMENT}" \
    "${SIGTS_AIDS}" \
    "${QVI_SCHEMA}" \
    "${GAR_PRE}" \
    "${QVI_PRE}"\
    "${SALLY_PRE}"

  start=$(date +%s)
  present_result=0
  print_dark_gray "[QVI] Waiting for Sally to receive the QVI Credential"
  while [ $present_result -ne 200 ]; do
    present_result=$(curl -s -o /dev/null -w "%{http_code}" "${WEBHOOK_HOST_LOCAL}/?holder=${QVI_PRE}")
    print_dark_gray "[QVI] received ${present_result} from Sally"
    sleep 1
    if (( $(date +%s)-start > 25 )); then
      print_red "[QVI] TIMEOUT - Sally did not receive the QVI Credential for ${QVI_NAME} | ${QVI_PRE}"
      break;
    fi
  done

  print_green "[QVI] QVI Credential presented to Sally"
}

############################ Workflow functions ##################################
function end_workflow() {
  # Script cleanup calls
  clear_containers
  cleanup
}

# main setup function
function setup() {
  clear_containers
  create_docker_containers
  create_docker_network
  generate_salts_and_passcodes
  write_docker_env
  start_docker_containers

  setup_keria_identifiers
  create_aids
  read_prefixes
  resolve_oobis
  # challenge_response() including SignifyTS Integration
}

# Sets up GEDA, GEDA registry, delegation to the QVI, and QVI OOBI resolution for GARs and LARs
function gar_delegation_to_qvi() {
  print_lcyan "------------------------------GEDA Delegation to QVI------------------------------"
  create_gar_reg
  recreate_sally_containers
  create_qvi_delegate
  resolve_qvi_oobi
  qvi_resolve_schema_oobis
  #qvi_rotate
}

# Creates the QVI credential, grants it from the GEDA to the QVI, and presents it to sally
function qvi_credential() {
  prepare_qvi_cred_data
  create_qvi_credential
  grant_qvi_credential
  admit_qvi_credential
#  present_qvi_cred_to_sally_kli
  pause "Press [ENTER] to present QVI to Sally"
  present_qvi_cred_to_sally_signify
  pause "Press [ENTER] to present QVI to Sally again"
  present_qvi_cred_to_sally_signify
}

# Creates the LE multisig, resolves the LE OOBI, creates the QVI registry, and prepares and grants the LE credential
#function le_creation_and_granting() {
#  create_le_multisig
#  qars_resolve_le_oobi
#  create_qvi_reg
#  prepare_qvi_edge
#  prepare_le_cred_data
#  create_and_grant_le_credential
#  admit_le_credential
#  create_le_reg
#  prepare_le_edge
#}

# Presents the LE credential to the local Sally deployment
#function le_sally_presentation() {
#  present_le_cred_to_sally
#}

# Creates the OOR Auth credential and grants it to the QVI
#function oor_auth_cred() {
#  prepare_oor_auth_data
#  create_oor_auth_credential
#  grant_oor_auth_credential
#  admit_oor_auth_credential
#  prepare_oor_auth_edge
#}

# Creates the OOR credential, grants it to the Person, and presents it to Sally from the person
#function oor_cred(){
#  prepare_oor_cred_data
#  create_and_grant_oor_credential
#  admit_oor_credential
#}

# Workflow function for the OOR Auth and OOR credentials
#function oor_auth_and_oor_cred() {
#  oor_auth_cred
#  oor_cred
#}

# Creates the ECR Auth credential and grants it to the QVI
#function ecr_auth_cred() {
#  prepare_ecr_auth_data
#  create_ecr_auth_credential
#  grant_ecr_auth_credential
#  admit_ecr_auth_credential
#  prepare_ecr_auth_edge
#}

# Creates the ECR credential, grants it to the Person, and presents it to Sally from the person
#function ecr_cred() {
#  prepare_ecr_cred_data
#  create_and_grant_ecr_credential
#  admit_ecr_credential
#}

# Workflow function for the ECR Auth and ECR credentials
#function ecr_auth_and_ecr_cred() {
#  ecr_auth_cred
#  ecr_cred
#}

# Main workflow driving the end to end QVI credentialing and reporting process
function main_flow() {
  print_lcyan "--------------------------------------------------------------------------------"
  print_lcyan "                       Running Main workflow (env: ${ENVIRONMENT})"
  print_lcyan "--------------------------------------------------------------------------------"
  setup
  gar_delegation_to_qvi
  qvi_credential
#
#  le_creation_and_granting
#  le_sally_presentation
#
#  oor_auth_and_oor_cred
#  person_present_oor_cred_to_sally
#  person_present_oor_cred_to_sally # second presentation for now since there is a bug where the first presentation does not succeed
#
#  ecr_auth_and_ecr_cred
#  pause "Press [ENTER] to present ECR to Sally"
#  present_ecr_cred_to_sally
#  pause "Press [ENTER] to present ECR to Sally again"
#  present_ecr_cred_to_sally

  # TODO Revoke OOR
  # TODO Present revoked OOR to Sally
  # TODO Revoke ECR
  # TODO Present revoked ECR to Sally
  pause "Press [enter] to end workflow"
  end_workflow
}

function debug_workflow() {
  # Use this function as a work in progress for debugging or otherwise playing with the script.
  # It's okay to commit non-working code in this function as it exists just as a tool.
  # Run this with `./vlei-workflow.sh -d`
  print_lcyan "--------DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-------"
  print_lcyan "Running DEBUG workflow "
  print_lcyan "--------DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-------"

  setup
  gar_delegation_to_qvi
  qvi_credential
  pause "press enter to end the workflow"
  end_workflow
}

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -k, --keystore-dir DIR  Specify keystore directory directory (default: ./docker-keystores)"
    echo "  -a, --alias ALIAS       OOBI alias for target Sally deployment (default: alternate)"
    echo "  -o, --oobi OOBI         OOBI URL for target Sally deployment (default: staging OC AU Sally OOBI- http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2)"
    echo "  -e, --environment ENV   Specify an environment (default: docker-tsx)"
    echo "  -t, --alternate         Run and present LE credential to alternate Sally"
    echo "  -s, --staging           Run and present LE credential to GLEIF Staging Sally"
    echo "  -p, --production        Run and present LE credential to GLEIF Production Sally"
    echo "  -d, --debug             Run the Debug workflow"
    echo "  -c, --clear             Clear all containers, keystores, and networks"
    echo "  -h, --help              Display this help message"
    echo "  --pause                 Enable pausing between steps"
    exit 1
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --pause)
            PAUSE_ENABLED=true
            shift
            ;;
        -e|--environment)
            if [[ -z $2 ]]; then
                print_red "Error: Environment not specified"
                end_workflow
            fi
            ENVIRONMENT="$2"
            print_yellow "Using environment: ${ENVIRONMENT}"
            source ./kli-commands.sh "${KEYSTORE_DIR}" "${ENVIRONMENT}"
            shift 2
            ;;
        -k|--keystore-dir)
            if [[ -z $2 ]]; then
                KEYSTORE_DIR="./docker-keystores"
                print_red "Error: Keystore directory not specified"
                end_workflow
            fi
            KEYSTORE_DIR="$2"
            print_yellow "Using keystore directory: ${KEYSTORE_DIR}"
            source ./kli-commands.sh "${KEYSTORE_DIR}" "${ENVIRONMENT}"
            shift 2
            ;;
        -a|--alias)
            if [[ -z $2 ]]; then
               print_red "Error: OOBI Alias not specified yet argument used."
               end_workflow
            fi
            ALT_SALLY_ALIAS="$2"
            shift 2
            ;;
        -o|--oobi)
            if [[ -z $2 ]]; then
                print_red "Error: OOBI URL not specified yet argument used."
                end_workflow
            fi
            ALT_SALLY_OOBI="$2"
            shift 2
            ;;
        -t|--alternate)
            present_to_alternate_sally "${ALT_SALLY_ALIAS}" "${ALT_SALLY_OOBI}"
            ;;
        -s|--staging)
            present_to_staging
            ;;
        -p|--production)
            present_to_production
            ;;
        -d|--debug)
            debug_workflow
            ;;
        -c|--clear)
            end_workflow
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

main_flow
