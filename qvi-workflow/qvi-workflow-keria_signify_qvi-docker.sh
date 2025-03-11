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
clear_containers

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
WIT_HOST=http://witness-demo:5642
SCHEMA_SERVER=http://vlei-server:7723
# KERIA_SERVER=http://keria:3903
#TODO check if needed SALLY_SERVER=http://  

# Container configuration
CONT_CONFIG_DIR=/config
# CONT_DATA_DIR=/data
CONT_INIT_CFG=qvi-workflow-init-config-dev-docker-compose.json #witness and schemas(5) oobis
CONT_ICP_CFG=/config/single-sig-incept-config.json #Created by create_icp_config()

# GEDA AIDs - GLEIF External Delegated AID
GEDA_PT1=accolon
GEDA_PT1_PRE=ENFbr9MI0K7f4Wz34z4hbzHmCTxIPHR9Q_gWjLJiv20h
GEDA_PT1_SALT=0AA2-S2YS4KqvlSzO7faIEpH
GEDA_PT1_PASSCODE=18b2c88fd050851c45c67

GEDA_PT2=bedivere
GEDA_PT2_PRE=EJ7F9XcRW85_S-6F2HIUgXcIcywAy0Nv-GilEBSRnicR
GEDA_PT2_SALT=0ADD292rR7WEU4GPpaYK4Z6h
GEDA_PT2_PASSCODE=b26ef3dd5c85f67c51be8

# GIDA AIDs - GLEIF Internal Delegated AID
GIDA_PT1=elaine
GIDA_PT1_PRE=ELTDtBrcFsHTMpfYHIJFvuH6awXY1rKq4w6TBlGyucoF
GIDA_PT1_SALT=0AB90ainJghoJa8BzFmGiEWa
GIDA_PT1_PASSCODE=tcc6Yj4JM8MfTDs1IiidP

GIDA_PT2=finn
GIDA_PT2_PRE=EBpwQouCaOlglS6gYo0uD0zLbuAto5sUyy7AK9_O0aI1
GIDA_PT2_SALT=0AA4m2NxBxn0w5mM9oZR2kHz
GIDA_PT2_PASSCODE=2pNNtRkSx8jFd7HWlikcg

GEDA_MS=dagonet
GEDA_PRE=EMCRBKH4Kvj03xbEVzKmOIrg0sosqHUF9VG2vzT9ybzv
# GEDA_MS_SALT=0ABLokRLKfPg4n49ztPuSPG1
# GEDA_MS_PASSCODE=7e6b659da2ff7c4f40fef

GIDA_MS=gareth
GIDA_PRE=EBsmQ6zMqopxMWhfZ27qXVpRKIsRNKbTS_aXMtWt67eb
# GIDA_MS_SALT=0AAOfZHXD6eerQUNzTHUOe8S
# GIDA_MS_PASSCODE=fwULUwdzavFxpcuD9c96z

# QAR AIDs - filled in later after KERIA setup
QAR_PT1=galahad
QAR_PT1_SALT=0ACgCmChLaw_qsLycbqBoxDK

QAR_PT2=lancelot
QAR_PT2_SALT=0ACaYJJv0ERQmy7xUfKgR6a4

QAR_PT3=tristan
QAR_PT3_SALT=0AAzX0tS638c9SEf5LnxTlj4

QVI_MS=percival
# QVI_PRE=
# QVI_MS_SALT=0AA2sMML7K-XdQLrgzOfIvf3
# QVI_MS_PASSCODE=97542531221a214cc0a55

# Person AID
#PERSON_NAME="Mordred Delacqs"
PERSON=mordred
PERSON_SALT=0ABlXAYDE2TkaNDk4UXxxtaN
#PERSON_ECR="Consultant"
#PERSON_OOR="Advisor"

# Sally - vLEI Reporting API
#WEBHOOK_HOST=http://127.0.0.1:9923
SALLY_HOST=http://127.0.0.1:9723
#SALLY=sally
#SALLY_PASSCODE=VVmRdBTe5YCyLMmYRqTAi
#SALLY_SALT=0AD45YWdzWSwNREuAoitH_CC
#SALLY_PRE=ECu-Lt62sUHkdZPnhIBoSuQrJWbi4Rqf_xUBOOJqAR7K
#SALLY_PRE=EHLWiN8Q617zXqb4Se4KfEGteHbn_way2VG5mcHYh5bm # sally 0.9.4

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


# Creates inception config file
function create_icp_config() {
    jq ".wits = [\"$WAN_PRE\"]" ./config/template-single-sig-incept-config.jq > ./config/single-sig-incept-config.json
    print_lcyan "Single sig inception config JSON:"
    print_lcyan "$(cat ./config/single-sig-incept-config.json)"
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
create_aids

# 3. GAR: OOBI resolutions between single sig AIDs
function resolve_oobis() {
    exists=$(kli contacts list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GEDA_PT2}")
    if [[ "$exists" =~ "${GEDA_PT2}" ]]; then
        print_yellow "OOBIs already resolved"
        return
    fi

    GEDA1_OOBI="${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    GEDA2_OOBI="${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    GIDA1_OOBI="${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    GIDA2_OOBI="${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    # TODO sort out the sally situation    
    SALLY_OOBI="${SALLY_HOST}/oobi" # self-oobi
    # SALLY_OOBI="${SALLY_HOST}/oobi/${SALLY_PRE}/controller" # controller OOBI
    # SALLY_OOBI="${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}" # sally 0.9.4
    OOBIS_FOR_KERIA="geda1|$GEDA1_OOBI,geda2|$GEDA2_OOBI,gida1|$GIDA1_OOBI,gida2|$GIDA2_OOBI,sally|$SALLY_OOBI"

    print_red "qars-person-single-sig-oobis-setup.ts" #EG
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-person-single-sig-oobis-setup.ts" $ENVIRONMENT $SIGTS_AIDS $OOBIS_FOR_KERIA

    echo
    print_lcyan "-----Resolving OOBIs-----"
    print_yellow "Resolving OOBIs for GEDA 1"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GEDA_PT2}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${GEDA2_OOBI}" 
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GIDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${GIDA1_OOBI}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GIDA_PT2}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${GIDA2_OOBI}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QAR_PT1}"  --passcode "${GEDA_PT1_PASSCODE}" --oobi "${QAR1_OOBI}" 
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QAR_PT2}"  --passcode "${GEDA_PT1_PASSCODE}" --oobi "${QAR2_OOBI}" 
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QAR_PT3}"  --passcode "${GEDA_PT1_PASSCODE}" --oobi "${QAR3_OOBI}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${PERSON}"   --passcode "${GEDA_PT1_PASSCODE}" --oobi "${PERSON_OOBI}"

    print_yellow "Resolving OOBIs for GEDA 2"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GEDA_PT1}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${GEDA1_OOBI}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GIDA_PT1}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${GIDA1_OOBI}" 
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GIDA_PT2}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${GIDA2_OOBI}" 
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT1}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${QAR1_OOBI}" 
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT2}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${QAR2_OOBI}" 
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT3}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${QAR3_OOBI}" 
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${PERSON}"   --passcode "${GEDA_PT2_PASSCODE}" --oobi "${PERSON_OOBI}"

    print_yellow "Resolving OOBIs for GIDA 1"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${GIDA_PT2}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${GIDA2_OOBI}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${GEDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${GEDA1_OOBI}" 
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${GEDA_PT2}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${GEDA2_OOBI}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QAR_PT1}"  --passcode "${GIDA_PT1_PASSCODE}" --oobi "${QAR1_OOBI}" 
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QAR_PT2}"  --passcode "${GIDA_PT1_PASSCODE}" --oobi "${QAR2_OOBI}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QAR_PT3}"  --passcode "${GIDA_PT1_PASSCODE}" --oobi "${QAR3_OOBI}" 
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${PERSON}"   --passcode "${GIDA_PT1_PASSCODE}" --oobi "${PERSON_OOBI}"

    print_yellow "Resolving OOBIs for GIDA 2"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${GIDA_PT1}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${GIDA1_OOBI}"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${GEDA_PT1}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${GEDA1_OOBI}"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${GEDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${GEDA2_OOBI}" 
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QAR_PT1}"  --passcode "${GIDA_PT2_PASSCODE}" --oobi "${QAR1_OOBI}" 
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QAR_PT2}"  --passcode "${GIDA_PT2_PASSCODE}" --oobi "${QAR2_OOBI}" 
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QAR_PT3}"  --passcode "${GIDA_PT2_PASSCODE}" --oobi "${QAR3_OOBI}" 
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${PERSON}"   --passcode "${GIDA_PT2_PASSCODE}" --oobi "${PERSON_OOBI}"
    
    echo
}
resolve_oobis

# TODO
# challenge_response() including SignifyTS Integration

# 4. GAR: Create Multisig AID (GEDA)
function create_multisig_icp_config() {
    PRE1=$1
    PRE2=$2
    cat ./config/template-multi-sig-incept-config.jq | \
        jq ".aids = [\"$PRE1\",\"$PRE2\"]" | \
        jq ".wits = [\"$WAN_PRE\"]" > ./config/multi-sig-incept-config.json

    print_lcyan "Multisig inception config JSON:"
    print_lcyan "$(cat ./config/multi-sig-incept-config.json)"
}

function create_geda_multisig() {
    exists=$(kli list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | grep "${GEDA_MS}")
    if [[ "$exists" =~ "${GEDA_MS}" ]]; then
        print_dark_gray "[External] GEDA Multisig AID ${GEDA_MS} already exists"
        return
    fi

    echo
    print_yellow "[External] Multisig Inception for GEDA"

    create_multisig_icp_config "${GEDA_PT1_PRE}" "${GEDA_PT2_PRE}"

    # The following multisig commands run in parallel in Docker
    print_yellow "[External] Multisig Inception from ${GEDA_PT1}: ${GEDA_PT1_PRE}"
    klid geda1 multisig incept --name ${GEDA_PT1} --alias ${GEDA_PT1} \
        --passcode ${GEDA_PT1_PASSCODE} \
        --group ${GEDA_MS} \
        --file /config/multi-sig-incept-config.json

    echo

    klid geda2 multisig join --name ${GEDA_PT2} \
        --passcode ${GEDA_PT2_PASSCODE} \
        --group ${GEDA_MS} \
        --auto

    echo
    print_yellow "[External] Multisig Inception { ${GEDA_PT1}, ${GEDA_PT2} } - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers geda1 and geda2"
    docker wait geda1 geda2
    docker logs geda1 # show what happened
    docker logs geda2 # show what happened
    docker rm geda1 geda2

    exists=$(kli list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | grep "${GEDA_MS}")
    if [[ ! "$exists" =~ "${GEDA_MS}" ]]; then
        print_red "[External] GEDA Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name "${GEDA_PT1}" --alias "${GEDA_MS}" --passcode "${GEDA_PT1_PASSCODE}" | awk '/Identifier:/ {print $2}')
    print_green "[External] GEDA Multisig AID ${GEDA_MS} with prefix: ${ms_prefix}"
}
create_geda_multisig

# 45. Create Multisig GLEIF Internal Delegated AID (GIDA), acts as legal entity
function create_gida_multisig() {
    exists=$(kli list --name "${GIDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" | grep "${GIDA_MS}")
    if [[ "$exists" =~ "${GIDA_MS}" ]]; then
        print_dark_gray "[Internal] GIDA Multisig AID ${GIDA_MS} already exists"
        return
    fi

    echo
    print_yellow "[Internal] Multisig Inception for GIDA"

    create_multisig_icp_config "${GIDA_PT1_PRE}" "${GIDA_PT2_PRE}"

    # Follow commands run in parallel
    print_yellow "[Internal] Multisig Inception from ${GIDA_PT1}: ${GIDA_PT1_PRE}"
    klid gida1 multisig incept --name ${GIDA_PT1} --alias ${GIDA_PT1} \
        --passcode ${GIDA_PT1_PASSCODE} \
        --group ${GIDA_MS} \
        --file /config/multi-sig-incept-config.json 

    echo

    klid gida2 multisig join --name ${GIDA_PT2} \
        --passcode ${GIDA_PT2_PASSCODE} \
        --group ${GIDA_MS} \
        --auto

    echo
    print_yellow "[Internal] Multisig Inception { ${GIDA_PT1}, ${GIDA_PT2} } - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers gida1 and gida2"
    docker wait gida1
    docker wait gida2
    docker logs gida1 # show what happened
    docker logs gida2 # show what happened
    docker rm gida1 gida2

    exists=$(kli list --name "${GIDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" | grep "${GIDA_MS}")
    if [[ ! "$exists" =~ "${GIDA_MS}" ]]; then
        print_red "[Internal] GIDA Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name "${GIDA_PT1}" --alias "${GIDA_MS}" --passcode "${GIDA_PT1_PASSCODE}" | awk '/Identifier:/ {print $2}')
    print_green "[Internal] GIDA Multisig AID ${GIDA_MS} with prefix: ${ms_prefix}"
}
create_gida_multisig

# 9. QAR: Resolve GEDA OOBI
GEDA_OOBI=""
GIDA_OOBI=""
function resolve_geda_and_gida_oobis() {
    GEDA_OOBI=$(kli oobi generate --name ${GEDA_PT1} --passcode ${GEDA_PT1_PASSCODE} --alias ${GEDA_MS} --role witness)
    GIDA_OOBI=$(kli oobi generate --name ${GIDA_PT1} --passcode ${GIDA_PT1_PASSCODE} --alias ${GIDA_MS} --role witness)
    MULTISIG_OOBIS="gedaMS|$GEDA_OOBI,gidaMS|$GIDA_OOBI"
    echo "GEDA OOBI: ${GEDA_OOBI}"
    echo "GIDA OOBI: ${GIDA_OOBI}"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-resolve-geda-and-le-oobis.ts" $ENVIRONMENT $SIGTS_AIDS $MULTISIG_OOBIS
}
resolve_geda_and_gida_oobis

# 10. QAR: Create delegated multisig QVI AID
# 11. QVI: Create delegated AID with GEDA as delegator
# 12. GEDA: delegate to QVI
function create_qvi_multisig() {
    QVI_MULTISIG_SEQ_NO=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}"
      )
    if [[ "$QVI_MULTISIG_SEQ_NO" -gt -1 ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_MS} already exists"
        return
    fi

    print_yellow "Creating QVI multisig"
    local delegator_prefix=$(kli status --name ${GEDA_PT1} --alias ${GEDA_MS} --passcode ${GEDA_PT1_PASSCODE} | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r")
    print_yellow "Delegator Prefix: ${delegator_prefix}"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-create-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${QVI_DATA_DIR}" \
      "${SIGTS_AIDS}" \
      "${delegator_prefix}"
    local delegated_multisig_info=$(cat $QVI_DATA_DIR/qvi-multisig-info.json)
    print_yellow "Delegated Multisig Info:"
    print_lcyan $delegated_multisig_info
    MULTISIG_PREFIX=$(echo $delegated_multisig_info | jq .msPrefix | tr -d '"')
    QVI_PRE=$MULTISIG_PREFIX

    print_lcyan "[External] GEDA members approve delegated inception with 'kli delegate confirm'"
    echo

    print_yellow "GEDA1 confirm delegated inception"
    kli delegate confirm --name ${GEDA_PT1} --alias ${GEDA_MS} --passcode ${GEDA_PT1_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"
    print_yellow "GEDA2 confirm delegated inception"
    kli delegate confirm --name ${GEDA_PT2} --alias ${GEDA_MS} --passcode ${GEDA_PT2_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"

    print_yellow "[GEDA] Waiting 5s on delegated inception completion"
    wait $PID_LIST
    sleep 5

    print_lcyan "[QVI] QARs refresh GEDA multisig keystate to discover new GEDA delegation seal anchored in interaction event."
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-complete-multisig-incept.ts" $ENVIRONMENT $SIGTS_AIDS $GEDA_PRE
}
create_qvi_multisig
MULTISIG_INFO=$(cat $QVI_DATA_DIR/qvi-multisig-info.json)
QVI_PRE=$(echo $MULTISIG_INFO | jq .msPrefix | tr -d '"')
print_green "[QVI] Multisig AID ${QVI_MS} with prefix: ${QVI_PRE}"

# Script cleanup calls
clear_containers
cleanup