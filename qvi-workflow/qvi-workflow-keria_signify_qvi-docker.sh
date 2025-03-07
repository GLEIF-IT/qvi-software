#!/usr/bin/env bash

#########################################
# Work In Progress - DO NOT USE
#########################################

# Runs the entire QVI issuance workflow end to end starting from multisig AID creatin including the
# GLEIF External Delegated AID (GEDA) creation all the way to OOR and ECR credential issuance to the
# Person AID for usage in the iXBRL data attestation.
#
# Note:
# 1) This script uses a dockerized containers for KERIA, witnesses, and the vLEI-server for vLEI schemas,
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


# First, check system dependencies
# NOTE: added tsx to the list of required commands
required_sys_commands=(docker jq tsx)
for cmd in "${required_sys_commands[@]}"; do
    if ! command -v $cmd &>/dev/null; then 
        print_red "$cmd is not installed. Please install it."
        exit 1
    fi
done

# TODO refactor
# Cleanup functions
trap cleanup INT
function cleanup() {
    echo
    docker compose -f $DOCKER_COMPOSE_FILE kill
    docker compose -f $DOCKER_COMPOSE_FILE down -v
    exit 0
}

# TODO check later if qvi1 and qvi2 are needed here
function clear_containers() {
    container_names=("geda1" "geda2" "gida1" "gida2" "qvi1" "qvi2")

    for name in "${container_names[@]}"; do
    if docker ps -a | grep -q "$name"; then
        docker kill $name || true && docker rm $name || true
    fi
    done
}

# TODO remove this line. it's here for convinience 
rm -rf "$HOME/.qvi_workflow_docker"


# Load utility functions
source ./script-utils.sh

# Load kli commands
source ./kli-commands.sh ${1:-}

# Create docker network if it does not exist
docker network inspect vlei >/dev/null 2>&1 || docker network create vlei


####################################################
# TODO Configuration variables
# - Complete and create as needed 

# NOTE: (used by resolve-envs.ts)
# Since the ts scripts run on the host use 'ENVIRONMENT=local'
ENVIRONMENT=docker

# Process outline:
# 1. GAR: Prepare environment

# QVI Config
# KEYSTORE_DIR=${1:-$HOME/.qvi_workflow_docker} # Not needed?
QVI_SIGNIFY_DIR=$(dirname "$0")/signify_qvi
QVI_DATA_DIR="${QVI_SIGNIFY_DIR}/qvi_data"

WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
# WIT_HOST=http://witness-demo:5642
SCHEMA_SERVER=http://vlei-server:7723
# KERIA_SERVER=http://keria:3903
#TODO check if needed SALLY_SERVER=http://  

# Container configuration
CONT_CONFIG_DIR=/config
# CONT_DATA_DIR=/data
CONT_INIT_CFG=qvi-workflow-init-config-dev-docker-compose.json #witness and schemas(5) oobis
CONT_ICP_CFG=/config/single-sig-incept-config.json #Created by create_icp_config()

# GEDA AIDs - GLEIF External Delegated AID
GEDA_PT1=geda_pt1 #accolon
# GEDA_PT1_PRE=ENFbr9MI0K7f4Wz34z4hbzHmCTxIPHR9Q_gWjLJiv20h
GEDA_PT1_SALT=0AA2-S2YS4KqvlSzO7faIEpH
GEDA_PT1_PASSCODE=18b2c88fd050851c45c67

GEDA_PT2=geda_pt2 #bedivere
# GEDA_PT2_PRE=EJ7F9XcRW85_S-6F2HIUgXcIcywAy0Nv-GilEBSRnicR
GEDA_PT2_SALT=0ADD292rR7WEU4GPpaYK4Z6h
GEDA_PT2_PASSCODE=b26ef3dd5c85f67c51be8

# GIDA AIDs - GLEIF Internal Delegated AID
GIDA_PT1=gida_pt1 #elaine
# GIDA_PT1_PRE=ELTDtBrcFsHTMpfYHIJFvuH6awXY1rKq4w6TBlGyucoF
GIDA_PT1_SALT=0AB90ainJghoJa8BzFmGiEWa
GIDA_PT1_PASSCODE=tcc6Yj4JM8MfTDs1IiidP

GIDA_PT2=gida_pt2 #finn
# GIDA_PT2_PRE=EBpwQouCaOlglS6gYo0uD0zLbuAto5sUyy7AK9_O0aI1
GIDA_PT2_SALT=0AA4m2NxBxn0w5mM9oZR2kHz
GIDA_PT2_PASSCODE=2pNNtRkSx8jFd7HWlikcg

# QAR AIDs - filled in later after KERIA setup
QAR_PT1=qar_pt1 #galahad
QAR_PT1_SALT=0ACgCmChLaw_qsLycbqBoxDK

QAR_PT2=qar_pt2 #lancelot
QAR_PT2_SALT=0ACaYJJv0ERQmy7xUfKgR6a4

QAR_PT3=qar_pt3 #tristan
QAR_PT3_SALT=0AAzX0tS638c9SEf5LnxTlj4

# Person AID
#PERSON_NAME="Mordred Delacqs"
PERSON=person #mordred
PERSON_SALT=0ABlXAYDE2TkaNDk4UXxxtaN
#PERSON_ECR="Consultant"
#PERSON_OOR="Advisor"

# Credentials
#GEDA_REGISTRY=vLEI-external
#GIDA_REGISTRY=vLEI-internal
#QVI_REGISTRY=vLEI-qvi
#QVI_SCHEMA=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
LE_SCHEMA=ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY
#ECR_AUTH_SCHEMA=EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g
#OOR_AUTH_SCHEMA=EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E
ECR_SCHEMA=EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw
#OOR_SCHEMA=EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy

###################################################

# TODO docker-compose-keria_signify_qvi.yaml needs to be reviewed and updated 
# - it is a copy of docker-compose-qvi-workflow.yaml
# - It may be needed to add Sally service TBD
# Starts containers and waits for them all to be healthy before running the rest of the script
DOCKER_COMPOSE_FILE=docker-compose-keria_signify_qvi.yaml
docker compose -f $DOCKER_COMPOSE_FILE up -d --wait


###############################################
# Workflow 
###############################################

# Creates inception config file
function create_icp_config() {
    jq ".wits = [\"$WAN_PRE\"]" ./config/template-single-sig-incept-config.jq > ./config/single-sig-incept-config.json
    print_lcyan "Single sig inception config JSON:"
    print_lcyan "$(cat ./config/single-sig-incept-config.json)"
}

# creates a single sig AID
function create_aid() {
    NAME=${1:-}
    SALT=${2:-}
    PASSCODE=${3:-}
    CONFIG_DIR=${4:-}
    CONFIG_FILE=${5:-}
    ICP_FILE=${6:-}
    KLI_CMD=${7:-}

    # TODO Check if makes sense to replace kli with KLI_CMD?
    # Check if exists
    exists=$(kli list --name "${NAME}" --passcode "${PASSCODE}")
    if [[ ! "$exists" =~ "Keystore must already exist" ]]; then
        print_dark_gray "AID ${NAME} already exists"
        return
    fi

    ${KLI_CMD:-kli} init \
        --name "${NAME}" \
        --salt "${SALT}" \
        --passcode "${PASSCODE}" \
        --config-dir "${CONFIG_DIR}" \
        --config-file "${CONFIG_FILE}" >/dev/null 2>&1

    ${KLI_CMD:-kli} incept \
        --name "${NAME}" \
        --alias "${NAME}" \
        --passcode "${PASSCODE}" \
        --file "${ICP_FILE}" >/dev/null 2>&1
    PREFIX=$(${KLI_CMD:-kli} status  --name "${NAME}"  --alias "${NAME}"  --passcode "${PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )
    # Need this since resolving with bootstrap config file isn't working
    print_dark_gray "Created AID: ${NAME}"
    print_green $'\tPrefix:'" ${PREFIX}"
    resolve_credential_oobis "${NAME}" "${PASSCODE}" "${KLI_CMD}" 
}

function resolve_credential_oobis() {
    # Need this function because for some reason resolving more than 8 OOBIs with the bootstrap config file doesn't work
    NAME=$1
    PASSCODE=$2
    KLI_CMD=$3

    print_dark_gray $'\t'"Resolving credential OOBIs for ${NAME}"
    # LE
    ${KLI_CMD:-kli} oobi resolve \
        --name "${NAME}" \
        --passcode "${PASSCODE}" \
        --oobi "${SCHEMA_SERVER}/oobi/${LE_SCHEMA}" >/dev/null 2>&1
    # LE ECR
    ${KLI_CMD:-kli} oobi resolve \
        --name "${NAME}" \
        --passcode "${PASSCODE}" \
        --oobi "${SCHEMA_SERVER}/oobi/${ECR_SCHEMA}" >/dev/null 2>&1
}

# 2. GAR: Create single Sig AIDs (2)
function create_aids() {
    print_green "-----Creating AIDs-----"
    create_icp_config    
    create_aid "${GEDA_PT1}" "${GEDA_PT1_SALT}" "${GEDA_PT1_PASSCODE}" "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
    create_aid "${GEDA_PT2}" "${GEDA_PT2_SALT}" "${GEDA_PT2_PASSCODE}" "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
    create_aid "${GIDA_PT1}" "${GIDA_PT1_SALT}" "${GIDA_PT1_PASSCODE}" "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
    create_aid "${GIDA_PT2}" "${GIDA_PT2_SALT}" "${GIDA_PT2_PASSCODE}" "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
    # TODO I believe this won't be needed since this part is going to be done with SignifyTS
    #create_aid "${QAR_PT1}"  "${QAR_PT1_SALT}"  "${QAR_PT1_PASSCODE}"  "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}" "kli2"
    #create_aid "${QAR_PT2}"  "${QAR_PT2_SALT}"  "${QAR_PT2_PASSCODE}"  "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}" "kli2"
    #create_aid "${PERSON}"   "${PERSON_SALT}"   "${PERSON_PASSCODE}"   "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}" "kli2"
    # TODO I believe this won't be needed 
    #create_aid "${SALLY}"    "${SALLY_SALT}"    "${SALLY_PASSCODE}"    "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
}
#create_aids


# KERIA SignifyTS QVI salts
SIGTS_AIDS="qar1|$QAR_PT1|$QAR_PT1_SALT,qar2|$QAR_PT2|$QAR_PT2_SALT,qar3|$QAR_PT3|$QAR_PT3_SALT,person|$PERSON|$PERSON_SALT"

print_yellow "Creating QVI and Person Identifiers from SignifyTS + KERIA"


tsx "${QVI_SIGNIFY_DIR}/qars/qars-and-person-setup.ts" $ENVIRONMENT $QVI_DATA_DIR $SIGTS_AIDS
print_green "QVI and Person Identifiers from SignifyTS + KERIA are "
qvi_setup_data=$(cat "${QVI_DATA_DIR}"/qars-and-person-info.json)
echo $qvi_setup_data | jq
QAR_PT1_PRE=$(echo $qvi_setup_data | jq -r ".QAR1.aid" | tr -d '"')
QAR_PT2_PRE=$(echo $qvi_setup_data | jq -r ".QAR2.aid" | tr -d '"')
QAR_PT3_PRE=$(echo $qvi_setup_data | jq -r ".QAR3.aid" | tr -d '"')
PERSON_PRE=$(echo $qvi_setup_data | jq -r ".PERSON.aid" | tr -d '"')
QAR1_OOBI=$(echo $qvi_setup_data | jq -r ".QAR1.agentOobi" | tr -d '"')
QAR2_OOBI=$(echo $qvi_setup_data | jq -r ".QAR2.agentOobi" | tr -d '"')
QAR3_OOBI=$(echo $qvi_setup_data | jq -r ".QAR3.agentOobi" | tr -d '"')
PERSON_OOBI=$(echo $qvi_setup_data | jq -r ".PERSON.agentOobi" | tr -d '"')


# Script cleanup calls
clear_containers
cleanup