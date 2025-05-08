#!/usr/bin/env bash

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
# 4) $HOME/.qvi_workflow_docker should be cleared out prior to running this script.
#    By specifying a directory as the first argument to this script you can control where the keystores are located.
# 5) make sure to perform "npm install" in this directory to be able to run the NodeJS scripts.

set -u  # undefined variable detection

# Note:
# 1) $HOME/.qvi_workflow_docker should be cleared out prior to running this script.
#    By specifying a directory as the first argument to this script you can control where the keystores are located.

# Load utility functions
source color-printing.sh

# NOTE: (used by resolve-env.ts)
ENVIRONMENT=docker-witness-split # means separate witnesses for GARs, QARs + LARs, Person, and Sally
KEYSTORE_DIR=./docker-keystores

# Load kli commands
source ./kli-commands.sh "${KEYSTORE_DIR}" "${ENVIRONMENT}"

ALT_SALLY_ALIAS="alternate"
ALT_SALLY_OOBI="http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2"


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
    rm -rfv "${KEYSTORE_DIR}"/*
    exit 0
}

function clear_containers() {
    container_names=("gar1" "gar2" "lar1" "lar2")

    for name in "${container_names[@]}"; do
    if docker ps -a | grep -q "$name"; then
        docker kill $name || true && docker rm $name || true
    fi
    done
}

DOCKER_COMPOSE_FILE=docker-compose-keria_signify_qvi.yaml

function create_docker_network() {
  print_yellow "KEYSTORE_DIR: ${KEYSTORE_DIR}"
  print_yellow "Using environment $ENVIRONMENT"
  # Create docker network if it does not exist
  docker network inspect vlei >/dev/null 2>&1 || docker network create vlei
}

function create_docker_containers() {
  print_green "-------------------Building gleif/vlei-workflow-signify container---------------"
  # Build gleif/vlei-workflow-signify container
  docker build \
		--platform=linux/amd64,linux/arm64 \
		-f signify-ts.Dockerfile \
		-t gleif/vlei-workflow-signify:1.0.0 \
		-t gleif/vlei-workflow-signify:latest .
}

# QVI Config
QVI_SIGNIFY_DIR=/vlei-workflow/signify_qvi
QVI_DATA_DIR=/vlei-workflow/qvi_data
LOCAL_QVI_DATA_DIR=$(dirname "$0")/signify_qvi/qvi_data

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
QAR2=lancelot
QAR2_PRE=
QAR3=tristan
QAR3_PRE=
QVI_NAME=percival
QVI_PRE=

# Person AID
PERSON=mordred
PERSON_PRE=

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
export SALLY_PASSCODE=VVmRdBTe5YCyLMmYRqTAi
export SALLY_SALT=0AD45YWdzWSwNREuAoitH_CC
export SALLY_PRE=EA69Z5sR2kr-05QmZ7v3VuMq8MdhVupve3caHXbhom0D # Different here because Sally uses witness Wit instead of Wan

# Direct mode Sally
export DIRECT_SALLY_HOST=http://direct-sally:9823
export DIRECT_SALLY=direct-sally
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

# Write wrong GEDA PRE, will be reset later
export GEDA_PRE=DUMMY_VALUE_INVALID_________________________

#### Write keria-signify-docker.env file with updated values ####
function write_docker_env(){
  print_bg_blue "[ADMIN] Writing prefixes, salts, passcodes, and schemas to keria-signfiy-docker.env"
  read -r -d '' DOCKER_ENV << EOM
#### Identifier Information ####
# GLEIF Authorized Representatives (GAR) AIDs
GAR1=$GAR1
GAR1_SALT=$GAR1_SALT
GAR1_PASSCODE=$GAR1_PASSCODE

GAR2=$GAR2
GAR2_SALT=$GAR2_SALT
GAR2_PASSCODE=$GAR2_PASSCODE

GEDA_NAME=$GEDA_NAME

# Legal Entity AIDs
LAR1=$LAR1
LAR1_SALT=$LAR1_SALT
LAR1_PASSCODE=$LAR1_PASSCODE

LAR2=$LAR2
LAR2_SALT=$LAR2_SALT
LAR2_PASSCODE=$LAR2_PASSCODE

LE_NAME=gareth

# Sally AID
SALLY=$SALLY
SALLY_PRE=$SALLY_PRE
SALLY_SALT=$SALLY_SALT
SALLY_PASSCODE=$SALLY_PASSCODE

# Direct Sally AID
DIRECT_SALLY=$DIRECT_SALLY
DIRECT_SALLY_PRE=$DIRECT_SALLY_PRE
DIRECT_SALLY_SALT=$DIRECT_SALLY_SALT
DIRECT_SALLY_PASSCODE=$DIRECT_SALLY_PASSCODE

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
  docker compose -f $DOCKER_COMPOSE_FILE up -d --wait
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
SIGTS_AIDS=""
function generate_salts_and_passcodes(){
  # salts and passcodes need to be new and dynamic on each run so that when presenting credentials to
  # other sally instances, not this one, that duplicity is not created by virtue of using the same
  # identifier salt, passcode, and inception configuration.

  # Does not include Sally because it is okay if sally stays the same.

  print_green "Generating salts for GARs and LARs"
  # Export these variables so they are available in the child docker compose processes
  export GAR1_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "GAR1_SALT: ${GAR1_SALT}"
  export GAR2_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "GAR2_SALT: ${GAR2_SALT}"
  export LAR1_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "LAR1_SALT: ${LAR1_SALT}"
  export LAR2_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "LAR2_SALT: ${LAR2_SALT}"
  export QAR1_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "QAR1_SALT: ${QAR1_SALT}"
  export QAR2_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "QAR2_SALT: ${QAR2_SALT}"
  export QAR3_SALT=$(kli salt | tr -d " \t\n\r" )   && print_lcyan "QAR3_SALT: ${QAR3_SALT}"
  export PERSON_SALT=$(kli salt | tr -d " \t\n\r" ) && print_lcyan "PERSON_SALT: ${PERSON_SALT}"

  export GAR1_PASSCODE=$(kli passcode generate | tr -d " \t\n\r" )   && print_lcyan "GAR1_PASSCODE: ${GAR1_PASSCODE}"
  export GAR2_PASSCODE=$(kli passcode generate | tr -d " \t\n\r" )   && print_lcyan "GAR2_PASSCODE: ${GAR2_PASSCODE}"
  export LAR1_PASSCODE=$(kli passcode generate | tr -d " \t\n\r" )   && print_lcyan "LAR1_PASSCODE: ${LAR1_PASSCODE}"
  export LAR2_PASSCODE=$(kli passcode generate | tr -d " \t\n\r" )   && print_lcyan "LAR2_PASSCODE: ${LAR2_PASSCODE}"
  export PERSON_PASSCODE=$(kli passcode generate | tr -d " \t\n\r" ) && print_lcyan "PERSON_PASSCODE: ${PERSON_PASSCODE}"

  # Does not include Sally because it is okay if sally stays the same.

  # KERIA SignifyTS QVI cryptographic names and seeds to feed into SignifyTS as a bespoke, delimited data format
  SIGTS_AIDS="qar1|$QAR1|$QAR1_SALT,qar2|$QAR2|$QAR2_SALT,qar3|$QAR3|$QAR3_SALT,person|$PERSON|$PERSON_SALT"
}

function setup_keria_identifiers() {
  print_yellow "Creating QVI and Person Identifiers from SignifyTS + KERIA"

  sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-and-person-setup.ts" "${ENVIRONMENT}" "${QVI_DATA_DIR}" "${SIGTS_AIDS}"

  print_green "QVI and Person Identifiers from SignifyTS + KERIA are "
  # Extract prefixes from the SignifyTS output because they are dynamically generated and unique each run.
  # They are needed for doing OOBI resolutions to connect SignifyTS AIDs to KERIpy AIDs.
  qvi_setup_data=$(cat "${LOCAL_QVI_DATA_DIR}"/qars-and-person-info.json)
  QAR1_PRE=$(echo    $qvi_setup_data | jq -r ".QAR1.aid"         | tr -d '"')
  QAR2_PRE=$(echo    $qvi_setup_data | jq -r ".QAR2.aid"         | tr -d '"')
  QAR3_PRE=$(echo    $qvi_setup_data | jq -r ".QAR3.aid"         | tr -d '"')
  PERSON_PRE=$(echo  $qvi_setup_data | jq -r ".PERSON.aid"       | tr -d '"')
  QAR1_OOBI=$(echo   $qvi_setup_data | jq -r ".QAR1.agentOobi"   | tr -d '"')
  QAR2_OOBI=$(echo   $qvi_setup_data | jq -r ".QAR2.agentOobi"   | tr -d '"')
  QAR3_OOBI=$(echo   $qvi_setup_data | jq -r ".QAR3.agentOobi"   | tr -d '"')
  PERSON_OOBI=$(echo $qvi_setup_data | jq -r ".PERSON.agentOobi" | tr -d '"')

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
    create_aid "${GAR1}" "${GAR1_SALT}" "${GAR1_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-gars.json" "/config/incept-cfg-gars.json"
    create_aid "${GAR2}" "${GAR2_SALT}" "${GAR2_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-gars.json" "/config/incept-cfg-gars.json"
    create_aid "${LAR1}" "${LAR1_SALT}" "${LAR1_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-qars.json" "/config/incept-cfg-qars.json"
    create_aid "${LAR2}" "${LAR2_SALT}" "${LAR2_PASSCODE}" "${CONT_CONFIG_DIR}" "habery-cfg-qars.json" "/config/incept-cfg-qars.json"
}

function read_prefixes() {
  export GAR1_PRE=$(kli status  --name "${GAR1}"  --alias "${GAR1}"  --passcode "${GAR1_PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )
  export GAR2_PRE=$(kli status  --name "${GAR2}"  --alias "${GAR2}"  --passcode "${GAR2_PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )
  export LAR1_PRE=$(kli status  --name "${LAR1}"  --alias "${LAR1}"  --passcode "${LAR1_PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )
  export LAR2_PRE=$(kli status  --name "${LAR2}"  --alias "${LAR2}"  --passcode "${LAR2_PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )

  print_green "------------------------------Reading identifier prefixes using the KLI------------------------------"
  print_lcyan "GAR1 Prefix: ${GAR1_PRE}"
  print_lcyan "GAR2 Prefix: ${GAR2_PRE}"
  print_lcyan "LAR1 Prefix: ${LAR1_PRE}"
  print_lcyan "LAR2 Prefix: ${LAR2_PRE}"
}

# OOBI resolutions between single sig AIDs
function resolve_oobis() {
    exists=$(kli contacts list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GAR2}")
    if [[ "$exists" =~ "${GAR2}" ]]; then
        print_yellow "OOBIs already resolved"
        return
    fi

    # SALLY_OOBI="${SALLY_HOST}/oobi/${SALLY_PRE}/controller" # controller OOBI - for direct-mode
    SALLY_OOBI="${WIT_HOST_SALLY}/oobi/${SALLY_PRE}/witness/${WIT_PRE}" # indirect-mode sally
    DIRECT_SALLY_OOBI="${DIRECT_SALLY_HOST}/oobi"
    print_green "SALLY OOBI: ${SALLY_OOBI}"
    print_green "DIRECT SALLY OOBI: ${DIRECT_SALLY_OOBI}"

    GAR1_OOBI="${WIT_HOST_GAR}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    GAR2_OOBI="${WIT_HOST_GAR}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    LAR1_OOBI="${WIT_HOST_QAR}/oobi/${LAR1_PRE}/witness/${WIL_PRE}"
    LAR2_OOBI="${WIT_HOST_QAR}/oobi/${LAR2_PRE}/witness/${WIL_PRE}"
    OOBIS_FOR_KERIA="gar1|$GAR1_OOBI,gar2|$GAR2_OOBI,lar1|$LAR1_OOBI,lar2|$LAR2_OOBI,sally|$SALLY_OOBI,direct-sally|$DIRECT_SALLY_OOBI"

    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-person-single-sig-oobis-setup.ts" $ENVIRONMENT "${SIGTS_AIDS}" "${OOBIS_FOR_KERIA}"

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
    kli oobi resolve --name "${GAR1}" --oobi-alias "${SALLY}"  --passcode "${GAR1_PASSCODE}" --oobi "${SALLY_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${DIRECT_SALLY}" --passcode "${GAR1_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for GAR 2"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${GAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${GAR1_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${LAR1_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${LAR2_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR1_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR3}"   --passcode "${GAR2_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${PERSON}" --passcode "${GAR2_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${SALLY}"  --passcode "${GAR2_PASSCODE}" --oobi "${SALLY_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${DIRECT_SALLY}" --passcode "${GAR2_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for LAR 1"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${LAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${LAR2_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${GAR1_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${GAR2_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR1_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR3}"   --passcode "${LAR1_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${PERSON}" --passcode "${LAR1_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${SALLY}"  --passcode "${LAR1_PASSCODE}" --oobi "${SALLY_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${DIRECT_SALLY}" --passcode "${LAR1_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"

    print_yellow "Resolving OOBIs for LAR 2"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${LAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${LAR1_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${GAR1_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${GAR2_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR1_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR3}"   --passcode "${LAR2_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${PERSON}" --passcode "${LAR2_PASSCODE}" --oobi "${PERSON_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${SALLY}"  --passcode "${LAR2_PASSCODE}" --oobi "${SALLY_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${DIRECT_SALLY}" --passcode "${LAR2_PASSCODE}" --oobi "${DIRECT_SALLY_OOBI}"
    
    echo
}

# TODO write Challenge Response between GARs, LARs, QARs, and Person
function challenge_response() {
  print_green "------------------------------Authenticating Keystore control with Challenge Responses------------------------------"
}

################# Create Multisigs and perform delegation ################
# Create Multisig AID for GLEIF External Delegated AID (GEDA)
function create_multisig_icp_config() {
    PRE1=$1
    PRE2=$2
    local wit_pre=$3
    cat ./config/template-multi-sig-incept-config.jq | \
        jq ".aids = [\"$PRE1\",\"$PRE2\"]" | \
        jq ".wits = [\"$wit_pre\"]" > ./config/multi-sig-incept-config.json

    print_lcyan "Multisig inception config JSON:"
    print_lcyan "$(cat ./config/multi-sig-incept-config.json)"
}

function create_geda_multisig() {
    exists=$(kli list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | grep "${GEDA_NAME}")
    if [[ "$exists" =~ "${GEDA_NAME}" ]]; then
        print_dark_gray "[External] GEDA Multisig AID ${GEDA_NAME} already exists"
        return
    fi

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
    print_dark_gray "waiting on Docker containers gar1 and gar2"
    docker wait gar1 gar2
    docker logs gar1 # show what happened
    docker logs gar2 # show what happened
    docker rm gar1 gar2

    exists=$(kli list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | grep "${GEDA_NAME}")
    if [[ ! "$exists" =~ "${GEDA_NAME}" ]]; then
        print_red "[External] GEDA Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name "${GAR1}" --alias "${GEDA_NAME}" --passcode "${GAR1_PASSCODE}" | awk '/Identifier:/ {print $2}')
    export GEDA_PRE=$(echo "${ms_prefix}" | tr -d '[:space:]')
    print_green "[External] GEDA Multisig AID ${GEDA_NAME} with prefix: ${GEDA_PRE}"
}

function recreate_sally_containers() {
  # Recreate sally container with new GEDA prefix
  print_yellow "Recreating Sally container with new GEDA prefix ${GEDA_PRE}"
  docker compose -f $DOCKER_COMPOSE_FILE up -d sally direct-sally --wait
}

function qars_resolve_geda_oobi() {
    GEDA_OOBI=$(kli oobi generate --name "${GAR1}" --passcode "${GAR1_PASSCODE}" --alias "${GEDA_NAME}" --role witness)
    if [[ -z "${GEDA_OOBI}" ]]; then
        print_red "Failed to generate GEDA OOBI"
        exit 1
    fi
    print_yellow "GEDA OOBI: ${GEDA_OOBI}"
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qvi-resolve-oobi.ts" $ENVIRONMENT "${SIGTS_AIDS}" "${GEDA_NAME}" "${GEDA_OOBI}"
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-refresh-geda-multisig-state.ts" "${ENVIRONMENT}" "${SIGTS_AIDS}" "${GEDA_PRE}"
}

# QAR: Create delegated multisig QVI AID with GEDA as delegator
function create_qvi_multisig() {
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-qvi-multisig.ts" "${ENVIRONMENT}" "${QVI_NAME}" "${SIGTS_AIDS}" "${QVI_DATA_DIR}"
    QVI_MULTISIG_SEQ_NO=$(cat "${LOCAL_QVI_DATA_DIR}"/qvi-sequence-no.json | jq .sequenceNo | tr -d '"')
    if [[ "$QVI_MULTISIG_SEQ_NO" -gt -1 ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_NAME} already exists"
        return
    fi
    print_yellow "Creating QVI multisig AID with GEDA as delegator"

    local delegator_prefix=$(kli status --name ${GAR1} --alias ${GEDA_NAME} --passcode ${GAR1_PASSCODE} | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r")
    print_yellow "Delegator Prefix: ${delegator_prefix}"
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-create-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${QVI_DATA_DIR}" \
      "${SIGTS_AIDS}" \
      "${delegator_prefix}"
    local delegated_multisig_info=$(cat "${LOCAL_QVI_DATA_DIR}"/qvi-multisig-info.json)
    print_yellow "Delegated Multisig Info:"
    QVI_PRE=$(echo "${delegated_multisig_info}" | jq .msPrefix | tr -d '"')
    echo
    print_lcyan "QVI Multisig Prefix: ${QVI_PRE}"
    echo

    print_lcyan "[External] GEDA members approve delegated inception with 'kli delegate confirm'"
    echo

    print_yellow "GAR1 confirm delegated inception"
    klid gar1 delegate confirm --name "${GAR1}" --alias "${GEDA_NAME}" --passcode "${GAR1_PASSCODE}" --interact --auto

    print_yellow "GAR2 confirm delegated inception"
    klid gar2 delegate confirm --name "${GAR2}" --alias "${GEDA_NAME}" --passcode "${GAR2_PASSCODE}" --interact --auto


    print_yellow "[GEDA] Waiting 5s on delegated inception completion"
 
    print_dark_gray "waiting on Docker containers gar1, gar2"
    docker wait gar1 gar2
    docker logs gar1
    docker logs gar2
    docker rm gar1 gar2

    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-complete-multisig-incept.ts" "${ENVIRONMENT}" "${SIGTS_AIDS}" "${GEDA_PRE}"

    MULTISIG_INFO=$(cat "${LOCAL_QVI_DATA_DIR}"/qvi-multisig-info.json)
    QVI_PRE=$(echo "${MULTISIG_INFO}" | jq .msPrefix | tr -d '"')
    print_green "[QVI] Multisig AID ${QVI_NAME} with prefix: ${QVI_PRE}"
}

# QVI: Perform endpoint role authorizations and generate OOBI for QVI to send to GEDA and LE
QVI_OOBI=""
function authorize_qvi_multisig_agent_endpoint_role(){
    print_yellow "Authorizing QVI multisig agent endpoint role"
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-authorize-endroles-get-qvi-oobi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${QVI_DATA_DIR}" \
      "${SIGTS_AIDS}"
    QVI_OOBI=$(cat "${LOCAL_QVI_DATA_DIR}/qvi-oobi.json" | jq .oobi | tr -d '"')
    print_green "QVI Agent OOBI: ${QVI_OOBI}"
}

# QVI: Delegated multisig rotation() {
function qvi_rotate() {
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-qvi-multisig.ts" "${ENVIRONMENT}" "${QVI_NAME}" "${SIGTS_AIDS}" "${QVI_DATA_DIR}"
    QVI_MULTISIG_SEQ_NO=$(cat "${LOCAL_QVI_DATA_DIR}"/qvi-sequence-no.json | jq .sequenceNo | tr -d '"')
    if [[ "$QVI_MULTISIG_SEQ_NO" -gt 1 ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_NAME} already rotated with SN=${QVI_MULTISIG_SEQ_NO}"
        return
    fi
    print_yellow "[QVI] Rotating QVI Multisig"
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-rotate-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}"
    QVI_PREFIX=$(cat "${LOCAL_QVI_DATA_DIR}/qvi-multisig-info.json" | jq .msPrefix | tr -d '"')
    print_green "[QVI] Rotated QVI Multisig with prefix: ${QVI_PREFIX}"

    # GEDA participants Query keystate from QARs
    print_yellow "[GEDA] Query QVI multisig participants to discover new delegated rotation and complete delegation for KERIpy 1.1.x+"
    print_yellow "[GEDA] GAR1 querying QAR1, 2, and 3 multisig for new key state"
    klid gar1 query --name ${GAR1} --alias ${GAR1} --passcode ${GAR1_PASSCODE} --prefix "${QAR1_PRE}"
    docker wait gar1
    docker logs gar1
    docker rm gar1
    klid gar1 query --name ${GAR1} --alias ${GAR1} --passcode ${GAR1_PASSCODE} --prefix "${QAR2_PRE}"
    docker wait gar1
    docker logs gar1
    docker rm gar1
    klid gar1 query --name ${GAR1} --alias ${GAR1} --passcode ${GAR1_PASSCODE} --prefix "${QAR3_PRE}"
    docker wait gar1
    docker logs gar1
    docker rm gar1

    print_yellow "[GEDA] GAR2 querying QAR1, 2, and 3 multisig for new key state"
    klid gar2 query --name ${GAR2} --alias ${GAR2} --passcode ${GAR2_PASSCODE} --prefix "${QAR1_PRE}"
    docker wait gar2
    # docker logs gar2
    docker rm gar2
    klid gar2 query --name ${GAR2} --alias ${GAR2} --passcode ${GAR2_PASSCODE} --prefix "${QAR2_PRE}"
    docker wait gar2
    # docker logs gar2
    docker rm gar2
    klid gar2 query --name ${GAR2} --alias ${GAR2} --passcode ${GAR2_PASSCODE} --prefix "${QAR3_PRE}"
    docker wait gar2
    # docker logs gar2
    docker rm gar2

    print_yellow "GAR1 confirm delegated rotation"
    klid gar1 delegate confirm --name ${GAR1} --alias ${GEDA_NAME} --passcode ${GAR1_PASSCODE} --interact --auto 

    print_yellow "GAR2 confirm delegated rotation"
    klid gar2 delegate confirm --name ${GAR2} --alias ${GEDA_NAME} --passcode ${GAR2_PASSCODE} --interact --auto

    print_yellow "[GEDA] Waiting 5s on delegated rotation completion"
    print_dark_gray "waiting on Docker containers gar1, gar2"
    docker wait gar1 gar2
    docker logs gar1
    docker logs gar2
    docker rm gar1 gar2

    print_lcyan "[QVI] QARs refresh GEDA multisig keystate to discover GEDA approval of delegated rotation"
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-refresh-geda-multisig-state.ts" $ENVIRONMENT $SIGTS_AIDS $GEDA_PRE

    print_yellow "[QVI] Waiting 8s for QARs to refresh GEDA keystate and complete delegation"
    sleep 8

}

# Create Legal Entity Multisig
function create_le_multisig() {
    exists=$(kli list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" | grep "${LE_NAME}")
    if [[ "$exists" =~ "${LE_NAME}" ]]; then
        print_dark_gray "[LE] LE Multisig AID ${LE_NAME} already exists"
        return
    fi

    echo
    print_yellow "[LE] Multisig Inception for LE"

    create_multisig_icp_config "${LAR1_PRE}" "${LAR2_PRE}" "${WIL_PRE}"

    # Follow commands run in parallel
    print_yellow "[LE] Multisig Inception from ${LAR1}: ${LAR1_PRE}"
    klid lar1 multisig incept --name ${LAR1} --alias ${LAR1} \
        --passcode ${LAR1_PASSCODE} \
        --group ${LE_NAME} \
        --file /config/multi-sig-incept-config.json

    echo

    klid lar2 multisig join --name ${LAR2} \
        --passcode ${LAR2_PASSCODE} \
        --group ${LE_NAME} \
        --auto

    echo
    print_yellow "[LE] Multisig Inception { ${LAR1}, ${LAR2} } - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers lar1 and lar2"
    docker wait lar1
    docker wait lar2
    docker logs lar1 # show what happened
    docker logs lar2 # show what happened
    docker rm lar1 lar2

    exists=$(kli list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" | grep "${LE_NAME}")
    if [[ ! "$exists" =~ "${LE_NAME}" ]]; then
        print_red "[LE] LE Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name "${LAR1}" --alias "${LE_NAME}" --passcode "${LAR1_PASSCODE}" | awk '/Identifier:/ {print $2}')
    export LE_PRE=$(echo "${ms_prefix}" | tr -d '[:space:]')
    print_green "[LE] LE Multisig AID ${LE_NAME} with prefix: ${LE_PRE}"
}

# QAR: Resolve GEDA and LE multisig OOBIs
function qars_resolve_le_oobi() {
    LE_OOBI=$(kli oobi generate --name "${LAR1}" --passcode "${LAR1_PASSCODE}" --alias "${LE_NAME}" --role witness)
    if [[ -z "${LE_OOBI}" ]]; then
        print_red "Failed to generate LE OOBI"
        exit 1
    fi
    echo "LE OOBI: ${LE_OOBI}"
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qvi-resolve-oobi.ts" $ENVIRONMENT "${SIGTS_AIDS}" "${LE_NAME}" "${LE_OOBI}"
}

# GEDA and LE: Resolve QVI OOBI
function resolve_qvi_oobi() {
    exists=$(kli contacts list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${QVI_NAME}")
    if [[ "$exists" =~ "${QVI_NAME}" ]]; then
        print_yellow "QVI OOBIs already resolved"
        return
    fi

    echo
    echo "QVI OOBI: ${QVI_OOBI}"
    print_yellow "Resolving QVI OOBI for GEDA and LE"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QVI_NAME}" --passcode "${GAR1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QVI_NAME}" --passcode "${GAR2_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QVI_NAME}" --passcode "${LAR1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QVI_NAME}" --passcode "${LAR2_PASSCODE}" --oobi "${QVI_OOBI}"

    print_yellow "Resolving QVI OOBI for Person"
    sig_tsx "${QVI_SIGNIFY_DIR}/person-resolve-qvi-oobi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${QVI_OOBI}"
    echo
}

############################ QVI Credential ##################################
# GEDA: Create GEDA credential registry
function create_geda_reg() {
    # Check if GEDA credential registry already exists
    REGISTRY=$(kli vc registry list \
        --name "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" | awk '{print $1}')
    if [ ! -z "${REGISTRY}" ]; then
        print_dark_gray "GEDA registry already created"
        return
    fi

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

    docker wait gar1 gar2
    docker logs gar1
    docker logs gar2
    docker rm gar1 gar2

    echo
    print_green "QVI Credential Registry created for GEDA"
    echo
}

# GEDA: Create QVI credential
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
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}")
    if [ ! -z "${SAID}" ]; then 
        print_dark_gray "[External] GEDA QVI credential already created ${SAID} done."
        return
    fi

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
    docker wait gar1 gar2
    docker logs gar1
    docker logs gar2
    docker rm gar1 gar2

    echo
    print_lcyan "[External] QVI Credential created for GEDA"
    echo
}

# GEDA: IPEX Grant QVI credential to QVI
function grant_qvi_credential() {
    QVI_GRANT_SAID=$(kli ipex list \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --sent \
        --said)
    if [ ! -z "${QVI_GRANT_SAID}" ]; then
        print_dark_gray "[External] GEDA QVI credential already granted"
        return
    fi
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
    # klid gar2 ipex join \
    #     --name ${GAR2} \
    #     --passcode ${GAR2_PASSCODE} \
    #     --auto

    echo
    print_yellow "[External] Waiting for IPEX messages to be witnessed"
    echo 
    print_dark_gray "waiting on Docker containers gar1 and gar2"
    docker wait gar1 gar2
    docker logs gar1
    docker logs gar2
    docker rm gar1 gar2


    echo
    print_green "[External] QVI Credential issued to QVI"
    echo
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
    received=$(sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-received-credential.ts" \
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
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${GEDA_PRE}" \
      "${QVI_CRED_SAID}"

    echo
    print_green "[QVI] Admitted QVI credential"
    echo
}

function present_qvi_cred_to_sally_kli() {
    SAID=$(kli vc list \
        --name "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d '[:space:]')

    echo
    print_yellow $'[External] IPEX GRANTing QVI credential with\n\tSAID'" ${SAID}"$'\n\tto Sally'" ${SALLY_PRE}"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    klid gar1 ipex grant \
        --name "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --said "${SAID}" \
        --recipient "${SALLY_PRE}" \
        --time "${KLI_TIME}"

    klid gar2 ipex grant \
        --name "${GAR2}" \
        --passcode "${GAR2_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --said "${SAID}" \
        --recipient "${SALLY_PRE}" \
        --time "${KLI_TIME}"

    echo
    print_yellow "[External] Waiting for IPEX messages to be witnessed"
    echo
    print_dark_gray "waiting on Docker containers gar1 and gar2"
    docker wait gar1 gar2
    docker logs gar1
    docker logs gar2
    docker rm gar1 gar2

    echo
    print_green "[External] QVI Credential issued to QVI"
    echo
}

function present_qvi_cred_to_sally_signify() {
  print_yellow "[QVI] Presenting QVI Credential to Sally"

  sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-present-credential.ts" \
    "${ENVIRONMENT}" \
    "${QVI_NAME}" \
    "${SIGTS_AIDS}" \
    "${QVI_SCHEMA}" \
    "${GEDA_PRE}" \
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

############################ LE Credential ##################################
# QVI: Prepare, create, and Issue LE credential to GEDA
# Create QVI credential registry
function create_qvi_reg() {
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-registry-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${QVI_REGISTRY}" \
      "${QVI_DATA_DIR}" \
      "${SIGTS_AIDS}"
    QVI_REG_REGK=$(cat "${LOCAL_QVI_DATA_DIR}/qvi-registry-info.json" | jq .registryRegk | tr -d '"')
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
    read -r -d '' QVI_EDGE_JSON << EOM
{
    "d": "",
    "qvi": {
        "n": "${QVI_CRED_SAID}",
        "s": "${QVI_SCHEMA}"
    }
}
EOM

    echo "$QVI_EDGE_JSON" > ./acdc-info/temp-data/qvi-edge.json
    kli saidify --file /acdc-info/temp-data/qvi-edge.json
    print_lcyan "Legal Entity edge Data"
    print_lcyan "$(cat ./acdc-info/temp-data/qvi-edge.json | jq )"
}

# QVI: Prepare LE credential data
function prepare_le_cred_data() {
    print_yellow "[QVI] Preparing LE credential data"
    read -r -d '' LE_CRED_DATA << EOM
{
    "LEI": "${LE_LEI}"
}
EOM

    echo "$LE_CRED_DATA" > ./acdc-info/temp-data/legal-entity-data.json
}

# QVI: Create LE credential
function create_and_grant_le_credential() {
    # Check if LE credential already exists
    le_said=$(sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      $ENVIRONMENT \
      $QVI_NAME \
      $SIGTS_AIDS \
      $LE_PRE \
      $LE_SCHEMA
    )
    if [[ ! "$le_said" =~ "false" ]]; then
        print_dark_gray "[QVI] LE Credential already created"
        return
    fi

    echo
    print_green "[QVI] creating LE credential"

    print_lcyan "[QVI] Legal Entity edge Data"
    print_lcyan "$(cat ./acdc-info/temp-data/qvi-edge.json | jq )"

    print_lcyan "[QVI] Legal Entity Credential Data"
    print_lcyan "$(cat ./acdc-info/temp-data/legal-entity-data.json)"

    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-le-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "/acdc-info" \
      "${SIGTS_AIDS}" \
      "${LE_PRE}" \
      "${QVI_DATA_DIR}"

    echo
    print_lcyan "[QVI] LE Credential created"
    print_dark_gray "Waiting 10 seconds for LE credential to be witnessed..."
    sleep 10
    echo
}

# LE: Admit LE credential from QVI
function admit_le_credential() {
    VC_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --said \
        --schema "${LE_SCHEMA}" | tr -d '[:space:]')
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[LE] LE Credential already admitted"
        return
    fi

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

    docker wait lar1 lar2
    docker rm lar1 lar2

    print_yellow "[LE] Waiting 8s for LE IPEX messages to be witnessed"
    sleep 8

    echo
    print_green "[LE] Admitted LE credential"
    echo
}

function present_le_cred_to_sally() {
  print_yellow "[QVI] Presenting LE Credential to Sally"

  sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-present-credential.ts" \
    "${ENVIRONMENT}" \
    "${QVI_NAME}" \
    "${SIGTS_AIDS}" \
    "${LE_SCHEMA}" \
    "${QVI_PRE}" \
    "${LE_PRE}"\
    "${SALLY_PRE}"

  start=$(date +%s)
  present_result=0
  print_dark_gray "[QVI] Waiting for Sally to receive the LE Credential"
  while [ $present_result -ne 200 ]; do
    present_result=$(curl -s -o /dev/null -w "%{http_code}" "${WEBHOOK_HOST_LOCAL}/?holder=${LE_PRE}")
    print_dark_gray "[QVI] received ${present_result} from Sally"
    sleep 1
    if (( $(date +%s)-start > 25 )); then
      print_red "[QVI] TIMEOUT - Sally did not receive the LE Credential for ${LE_NAME} | ${LE_PRE}"
      break;
    fi # 25 seconds timeout
  done

  print_green "[PERSON] LE Credential presented to Sally"

}

# LE: Create LE credential registry
function create_le_reg() {
    # Check if LE credential registry already exists
    REGISTRY=$(kli vc registry list \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" | awk '{print $1}' | tr -d '[:space:]')
    if [ ! -z "${REGISTRY}" ]; then
        print_dark_gray "[LE] LE registry already created"
        return
    fi

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

    docker wait lar1 lar2
    docker rm lar1 lar2

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
    read -r -d '' LE_EDGE_JSON << EOM
{
    "d": "",
    "le": {
        "n": "${LE_SAID}",
        "s": "${LE_SCHEMA}"
    }
}
EOM

    echo "$LE_EDGE_JSON" > ./acdc-info/temp-data/legal-entity-edge.json
    kli saidify --file /acdc-info/temp-data/legal-entity-edge.json
}

# Prepare OOR Auth credential data
function prepare_oor_auth_data() {
    read -r -d '' OOR_AUTH_DATA_JSON << EOM
{
  "AID": "${PERSON_PRE}",
  "LEI": "${LE_LEI}",
  "personLegalName": "${PERSON_NAME}",
  "officialRole": "${PERSON_OOR}"
}
EOM

    echo "$OOR_AUTH_DATA_JSON" > ./acdc-info/temp-data/oor-auth-data.json
}

# LE: Create OOR Auth credential
function create_oor_auth_credential() {
    # Check if OOR auth credential already exists
    SAID=$(kli vc list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${OOR_AUTH_SCHEMA}" | tr -d '[:space:]')
    if [ ! -z "${SAID}" ]; then
        print_yellow "[QVI] OOR Auth credential already created"
        return
    fi

    print_lcyan "[LE] OOR Auth data JSON"
    print_lcyan "$(cat ./acdc-info/temp-data/oor-auth-data.json)"

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

    docker wait lar1 lar2
    docker rm lar1 lar2

    echo
    print_lcyan "[LE] LE created OOR Auth credential"
    echo
}

# LE: Grant OOR Auth credential to QVI
function grant_oor_auth_credential() {
    # This relies on the last grant being the OOR Auth credential
    GRANT_COUNT=$(kli ipex list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --type "grant" \
        --passcode "${LAR1_PASSCODE}" \
        --sent \
        --said | wc -l | tr -d '[:space:]') # get grant count, remove whitespace
    if [ "${GRANT_COUNT}" -ge 1 ]; then
        print_dark_gray "[QVI] OOR Auth credential already granted"
        return
    fi
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

    docker wait lar1 lar2
    docker rm lar1 lar2

    echo
    print_yellow "[LE] Waiting for OOR Auth IPEX grant messages to be witnessed"
    sleep 5

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
    received=$(sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-received-credential.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${OOR_AUTH_SAID}"
    )
    if [[ "$received" == "true" ]]; then
        print_dark_gray "[QVI] OOR Auth Credential already admitted"
        return
    fi

    echo
    print_yellow "[QVI] Admitting OOR Auth Credential ${OOR_AUTH_SAID} from LE"
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${LE_PRE}" \
      "${OOR_AUTH_SAID}"

    print_yellow "[QVI] Waiting for OOR Auth IPEX admit messages to be witnessed"
    sleep 8

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
    read -r -d '' OOR_AUTH_EDGE_JSON << EOM
{
    "d": "",
    "auth": {
        "n": "${OOR_AUTH_SAID}",
        "s": "${OOR_AUTH_SCHEMA}",
        "o": "I2I"
    }
}
EOM
    echo "$OOR_AUTH_EDGE_JSON" > ./acdc-info/temp-data/oor-auth-edge.json
    kli saidify --file /acdc-info/temp-data/oor-auth-edge.json
}

# Prepare OOR credential data
function prepare_oor_cred_data() {
    print_bg_blue "[QVI] Preparing OOR credential data"
    read -r -d '' OOR_CRED_DATA << EOM
{
  "LEI": "${LE_LEI}",
  "personLegalName": "${PERSON_NAME}",
  "officialRole": "${PERSON_OOR}"
}
EOM

    echo "${OOR_CRED_DATA}" > ./acdc-info/temp-data/oor-data.json
}

# Create OOR credential in QVI, issued to the Person
function create_and_grant_oor_credential() {
    # Check if OOR credential already exists
    oor_said=$(sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_NAME" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$OOR_SCHEMA"
    )
    if [[ ! "$oor_said" =~ "false" ]]; then
        print_dark_gray "[QVI] OOR Credential already created"
        return
    fi

    print_lcyan "[QVI] OOR Auth edge Data"
    print_lcyan "$(cat ./acdc-info/temp-data/oor-auth-edge.json | jq )"

    print_lcyan "[QVI] OOR Credential Data"
    print_lcyan "$(cat ./acdc-info/temp-data/oor-data.json)"

    echo
    print_green "[QVI] creating and granting OOR credential"

    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-oor-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "/acdc-info" \
      "${SIGTS_AIDS}" \
      "${PERSON_PRE}" \
      "${QVI_DATA_DIR}"

    print_yellow "[QVI] Waiting for OOR IPEX messages to be witnessed"
    sleep 5

    echo
    print_lcyan "[QVI] OOR credential created"
    echo
}

# Person: Admit OOR credential from QVI
function admit_oor_credential() {
    # check if OOR has been admitted to receiver
    oor_said=$(sig_tsx "${QVI_SIGNIFY_DIR}/person/person-check-received-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${OOR_SCHEMA}" \
      "${QVI_PRE}"
    )
    if [[ ! "$oor_said" =~ "false" ]]; then
        print_dark_gray "[PERSON] OOR Credential already admitted with SAID ${oor_said}"
        return
    fi

    # get OOR cred SAID from issuer
    oor_said=$(sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_NAME" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$OOR_SCHEMA"
    )

    echo
    print_yellow "[PERSON] Admitting OOR credential ${oor_said} to ${PERSON}"

    sig_tsx "${QVI_SIGNIFY_DIR}/person/person-admit-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${QVI_PRE}" \
      "${oor_said}"

    print_yellow "[PERSON] Waiting for OOR Cred IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "OOR Credential admitted"
    echo
}

# PERSON: Present OOR credential to Sally (vLEI Reporting API)
function present_oor_cred_to_sally() {
    print_yellow "[QVI] Presenting OOR Credential to Sally"

    sig_tsx "${QVI_SIGNIFY_DIR}/person/person-grant-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${OOR_SCHEMA}" \
      "${QVI_PRE}" \
      "${SALLY_PRE}"

    start=$(date +%s)
    present_result=0
    print_dark_gray "[PERSON] Waiting for Sally to receive the OOR Credential"
    while [ $present_result -ne 200 ]; do
      present_result=$(curl -s -o /dev/null -w "%{http_code}" "${WEBHOOK_HOST_LOCAL}/?holder=${PERSON_PRE}")
      print_dark_gray "[PERSON] received ${present_result} from Sally"
      sleep 1
      if (( $(date +%s)-start > 25 )); then
        print_red "[PERSON] TIMEOUT - Sally did not receive the OOR Credential for ${PERSON_NAME} | ${PERSON_PRE}"
        break;
      fi # 25 seconds timeout
    done

    print_green "[PERSON] OOR Credential presented to Sally"
}

############################ ECR Auth ##################################
# LE: Prepare, create, and Issue ECR Auth & OOR Auth credential to QVI
# Prepare ECR Auth credential data
function prepare_ecr_auth_data() {
    read -r -d '' ECR_AUTH_DATA_JSON << EOM
{
  "AID": "${PERSON_PRE}",
  "LEI": "${LE_LEI}",
  "personLegalName": "${PERSON_NAME}",
  "engagementContextRole": "${PERSON_ECR}"
}
EOM

    echo "$ECR_AUTH_DATA_JSON" > ./acdc-info/temp-data/ecr-auth-data.json
}

# Create ECR Auth credential
function create_ecr_auth_credential() {
    # Check if ECR auth credential already exists
    SAID=$(kli vc list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${ECR_AUTH_SCHEMA}" | tr -d '[:space:]')
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[LE] ECR Auth credential already created"
        return
    fi

    echo
    print_green "[LE] LE creating ECR Auth credential"

    print_lcyan "[LE] Legal Entity edge JSON"
    print_lcyan "$(cat ./acdc-info/temp-data/legal-entity-edge.json | jq)"

    print_lcyan "[LE] ECR Auth data JSON"
    print_lcyan "$(cat ./acdc-info/temp-data/ecr-auth-data.json)"

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

    docker wait lar1 lar2
    docker rm lar1 lar2

    echo
    print_yellow "[LE] Waiting 8s ECR Auth for IPEX messages to be witnessed"
    sleep 8

    echo
    print_lcyan "[LE] LE created ECR Auth credential"
    echo
}

# Grant ECR Auth credential to QVI
function grant_ecr_auth_credential() {
    # This relies on there being only one grant in the list for the GEDA
    GRANT_COUNT=$(kli ipex list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --type "grant" \
        --passcode "${LAR1_PASSCODE}" \
        --sent \
        --said | wc -l | tr -d ' ') # get the last grant
    if [ "${GRANT_COUNT}" -ge 2 ]; then
        print_dark_gray "[LE] ECR Auth credential grant already granted"
        return
    fi
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

    docker wait lar1 lar2
    docker rm lar1 lar2

    echo
    print_yellow "[LE] Waiting for IPEX ECR Auth grant messages to be witnessed"
    sleep 8

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
    received=$(sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-received-credential.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${ECR_AUTH_SAID}"
    )
    if [[ "$received" == "true" ]]; then
        print_dark_gray "[QVI] ECR Auth Credential already admitted"
        return
    fi

    echo
    print_yellow "[QVI] Admitting ECR Auth Credential ${ECR_AUTH_SAID} from LE"
    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${LE_PRE}" \
      "${ECR_AUTH_SAID}"

    print_yellow "[QVI] Waiting 8s for IPEX admit messages to be witnessed"
    sleep 8

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
    read -r -d '' ECR_AUTH_EDGE_JSON << EOM
{
    "d": "",
    "auth": {
        "n": "${ECR_AUTH_SAID}",
        "s": "${ECR_AUTH_SCHEMA}",
        "o": "I2I"
    }
}
EOM
    echo "$ECR_AUTH_EDGE_JSON" > ./acdc-info/temp-data/ecr-auth-edge.json
    kli saidify --file /acdc-info/temp-data/ecr-auth-edge.json
}

# Prepare ECR credential data
function prepare_ecr_cred_data() {
    print_bg_blue "[QVI] Preparing ECR credential data"
    read -r -d '' ECR_CRED_DATA << EOM
{
  "LEI": "${LE_LEI}",
  "personLegalName": "${PERSON_NAME}",
  "engagementContextRole": "${PERSON_ECR}"
}
EOM

    echo "${ECR_CRED_DATA}" > ./acdc-info/temp-data/ecr-data.json
}

# QVI Grant ECR credential to PERSON
function create_and_grant_ecr_credential() {
    # Check if ECR credential already exists
    ecr_said=$(sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_NAME" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$ECR_SCHEMA"
    )
    if [[ ! "$ecr_said" =~ "false" ]]; then
        print_dark_gray "[QVI] ECR Credential already created"
        return
    fi

    print_lcyan "[QVI] ECR Auth edge Data"
    print_lcyan "$(cat ./acdc-info/temp-data/ecr-auth-edge.json | jq )"

    print_lcyan "[QVI] ECR Credential Data"
    print_lcyan "$(cat ./acdc-info/temp-data/ecr-data.json)"

    echo
    print_green "[QVI] creating and granting ECR credential"

    sig_tsx "${QVI_SIGNIFY_DIR}/qars/qars-ecr-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "/acdc-info" \
      "${SIGTS_AIDS}" \
      "${PERSON_PRE}" \
      "${QVI_DATA_DIR}"

    print_yellow "[QVI] Waiting for ECR IPEX messages to be witnessed"
    sleep 8

    echo
    print_lcyan "[QVI] ECR credential created and granted"
    echo
}

# Person: Admit ECR credential from QVI
function admit_ecr_credential() {
    # check if ECR has been admitted to receiver
    ecr_said=$(sig_tsx "${QVI_SIGNIFY_DIR}/person/person-check-received-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${ECR_SCHEMA}" \
      "${QVI_PRE}"
    )
    if [[ ! "$ecr_said" =~ "false" ]]; then
        print_dark_gray "[PERSON] ECR Credential already admitted with SAID ${ecr_said}"
        return
    fi

    # get ECR cred SAID from issuer
    ecr_said=$(sig_tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_NAME" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$ECR_SCHEMA"
    )

    echo
    print_yellow "[PERSON] Admitting ECR credential ${ecr_said} to ${PERSON}"

    sig_tsx "${QVI_SIGNIFY_DIR}/person/person-admit-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${QVI_PRE}" \
      "${ecr_said}"

    print_yellow "[PERSON] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "ECR Credential admitted"
    echo
}

# Present ECR credential to Sally (vLEI Reporting API)
# Sally does not recognize the ECR credential and will reject it.
# This just tests out the presentation capability for testing purposes.
function present_ecr_cred_to_sally() {
    print_yellow "[QVI] Presenting ECR Credential to Sally"

    sig_tsx "${QVI_SIGNIFY_DIR}/person/person-grant-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${ECR_SCHEMA}" \
      "${QVI_PRE}" \
      "${SALLY_PRE}"

    start=$(date +%s)
    present_result=0
    print_dark_gray "[PERSON] Waiting for Sally to receive the ECR Credential"
    # This check will not return any 200 success values for the ECR as Sally does not recognize this credential.
    # It is just here for illustration and to give Sally time to receive the credential.
    while [ $present_result -ne 200 ]; do
      present_result=$(curl -s -o /dev/null -w "%{http_code}" "${WEBHOOK_HOST_LOCAL}/?holder=${PERSON_PRE}")
      print_dark_gray "[PERSON] received ${present_result} from Sally"
      sleep 1
      if (( $(date +%s)-start > 3 )); then
        print_red "[PERSON] TIMEOUT - Sally did not receive the ECR Credential for ${PERSON_NAME} | ${PERSON_PRE}"
        break;
      fi
    done

    print_green "[PERSON] ECR Credential presented to Sally"
}

# QVI: Revoke ECR Auth and OOR Auth credentials

# QVI: Present revoked credentials to Sally

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
  docker wait lar1 lar2
  docker logs lar1
  docker logs lar2
  docker rm lar1 lar2
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
  docker wait lar1 lar2
  docker logs lar1
  docker logs lar2
  docker rm lar1 lar2
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
  docker wait lar1 lar2
  docker logs lar1
  docker logs lar2
  docker rm lar1 lar2
}
# Prepare ECR Auth edge data

############################ Workflow functions ##################################
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
function geda_delegation_to_qvi() {
  create_geda_multisig
  create_geda_reg
  recreate_sally_containers
  qars_resolve_geda_oobi
  create_qvi_multisig
  authorize_qvi_multisig_agent_endpoint_role
  resolve_qvi_oobi
  #qvi_rotate
}

# Creates the QVI credential, grants it from the GEDA to the QVI, and presents it to sally
function qvi_credential() {
  prepare_qvi_cred_data
  create_qvi_credential
  grant_qvi_credential
  admit_qvi_credential
  present_qvi_cred_to_sally_kli
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
  read -p "Press [ENTER] to present LE cred to Sally from QARs"
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
  present_oor_cred_to_sally
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

# Creates the ECR credential, grants it to the Person, and presents it to Sally from the person
function ecr_cred() {
  prepare_ecr_cred_data
  create_and_grant_ecr_credential
  admit_ecr_credential
  present_ecr_cred_to_sally
}

# Workflow function for the ECR Auth and ECR credentials
function ecr_auth_and_ecr_cred() {
  ecr_auth_cred
  ecr_cred
}

# Main workflow driving the end to end QVI credentialing and reporting process
function main_flow() {
  setup
  geda_delegation_to_qvi
  qvi_credential
  le_creation_and_granting
  le_sally_presentation
  oor_auth_and_oor_cred
  ecr_auth_and_ecr_cred

  # TODO Revoke OOR
  # TODO Present revoked OOR to Sally
  # TODO Revoke ECR
  # TODO Present revoked ECR to Sally
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

function end_workflow() {
  # Script cleanup calls
  clear_containers
  cleanup
}

function debug_workflow() {
  # Use this function as a work in progress for debugging or otherwise playing with the script.
  # It's okay to commit non-working code in this function as it exists just as a tool.
  # Run this with `./vlei-workflow.sh -d`
  print_lcyan "--------DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-------"
  print_lcyan "Running DEBUG workflow "
  print_lcyan "--------DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-DEBUG-------"

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
  geda_delegation_to_qvi
  qvi_credential
  le_creation_and_granting
  read -p "Press [ENTER] to present to Sally"
  le_sally_presentation
  # challenge_response() including SignifyTS Integration

  end_workflow
}

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -k, --keystore-dir DIR  Specify keystore directory directory (default: ./docker-keystores)"
    echo "  -a, --alias ALIAS       OOBI alias for target Sally deployment (default: alternate)"
    echo "  -o, --oobi OOBI         OOBI URL for target Sally deployment (default: staging OC AU Sally OOBI- http://139.99.193.43:5623/oobi/EPZN94iifUVP-3u_6BNDOFS934c8nJDU2A5bcDF9FkzT/witness/BN6TBUuiDY_m87govmYhQ2ryYP2opJROqjDkZToxuxS2)"
    echo "  -e, --environment ENV   Specify an environment (default: docker-witness-split)"
    echo "  -t, --alternate         Run and present LE credential to alternate Sally"
    echo "  -s, --staging           Run and present LE credential to GLEIF Staging Sally"
    echo "  -p, --production        Run and present LE credential to GLEIF Production Sally"
    echo "  -d, --debug             Run the Debug workflow"
    echo "  -c, --clear             Clear all containers, keystores, and networks"
    echo "  -h, --help              Display this help message"
    exit 1
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            if [[ -z $2 ]]; then
                ENVIRONMENT="docker-witness-split"
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

print_lcyan "Full chain workflow completed"
