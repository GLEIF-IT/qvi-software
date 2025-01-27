#!/usr/bin/env bash
# qvi-workflow-kli-docker.sh
# Runs the entire QVI issuance workflow end to end starting from multisig AID creatin including the
# GLEIF External Delegated AID (GEDA) creation all the way to OOR and ECR credential issuance to the
# Person AID for usage in the iXBRL data attestation.
#
# Note:
# 1) This script uses the kli and kli2 commands as defined in ./kli-commands.sh to perform the QVI
#    workflow steps.
# 2) $HOME/.qvi_workflow_docker should be cleared out prior to running this script.
#    By specifying a directory as the first argument to this script you can control where the keystores are located.
#


# Load utility functions
source ./script-utils.sh
echo
print_bg_blue "------------------------------vLEI QVI Workflow Script (KLI - Docker)------------------------------"
echo

# Load kli commands
source ./kli-commands.sh $1

# Create docker network if it does not exist
docker network inspect vlei >/dev/null 2>&1 || docker network create vlei

# starts containers and waits for them all to be healthy before running the rest of the script
DOCKER_COMPOSE_FILE=docker-compose-qvi-workflow-kli.yaml
docker compose -f $DOCKER_COMPOSE_FILE up -d --wait

trap cleanup INT
function cleanup() {
    echo
    docker compose -f $DOCKER_COMPOSE_FILE kill
    docker compose -f $DOCKER_COMPOSE_FILE down -v
    # print_red "Caught Ctrl+C, stopping containers and exiting script..."
    # container_names=("geda1" "geda2" "gida1" "gida2" "qvi1" "qvi2")

    # for name in "${container_names[@]}"; do
    # if docker ps -a | grep -q "$name"; then
    #     docker kill $name || true && docker rm $name || true
    # fi
    # done
    exit 0
}

function clear_containers() {
    container_names=("geda1" "geda2" "gida1" "gida2" "qvi1" "qvi2")

    for name in "${container_names[@]}"; do
    if docker ps -a | grep -q "$name"; then
        docker kill $name || true && docker rm $name || true
    fi
    done
}
clear_containers

required_commands=(docker kli klid kli2 kli2d jq)
for cmd in "${required_commands[@]}"; do
    if ! command -v $cmd &>/dev/null; then 
        print_red "$cmd is not installed. Please install it."
        exit 1
    fi
done


# Process outline:
# 1. GAR: Prepare environment
KEYSTORE_DIR=${1:-$HOME/.qvi_workflow_docker}
CONFIG_DIR=./config
DATA_DIR=./data
WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
WIT_HOST=http://witness-demo:5642
SCHEMA_SERVER=http://vlei-server:7723

# Container configuration
CONT_CONFIG_DIR=/config
CONT_DATA_DIR=/data
CONT_INIT_CFG=qvi-workflow-init-config-dev-docker-compose.json
CONT_ICP_CFG=/config/single-sig-incept-config.json


GEDA_LEI=254900OPPU84GM83MG36 # GLEIF Americas

# GEDA AIDs - GLEIF External Delegated AID
GEDA_PT1=accolon
GEDA_PT1_PRE=ENFbr9MI0K7f4Wz34z4hbzHmCTxIPHR9Q_gWjLJiv20h
GEDA_PT1_SALT=0AA2-S2YS4KqvlSzO7faIEpH
GEDA_PT1_PASSCODE=18b2c88fd050851c45c67

GEDA_PT2=bedivere
GEDA_PT2_PRE=EJ7F9XcRW85_S-6F2HIUgXcIcywAy0Nv-GilEBSRnicR
GEDA_PT2_SALT=0ADD292rR7WEU4GPpaYK4Z6h
GEDA_PT2_PASSCODE=b26ef3dd5c85f67c51be8

GEDA_MS=dagonet
GEDA_PRE=EMCRBKH4Kvj03xbEVzKmOIrg0sosqHUF9VG2vzT9ybzv
GEDA_MS_SALT=0ABLokRLKfPg4n49ztPuSPG1
GEDA_MS_PASSCODE=7e6b659da2ff7c4f40fef


# GIDA AIDs - GLEIF Internal Delegated AID
GIDA_PT1=elaine
GIDA_PT1_PRE=ELTDtBrcFsHTMpfYHIJFvuH6awXY1rKq4w6TBlGyucoF
GIDA_PT1_SALT=0AB90ainJghoJa8BzFmGiEWa
GIDA_PT1_PASSCODE=tcc6Yj4JM8MfTDs1IiidP

GIDA_PT2=finn
GIDA_PT2_PRE=EBpwQouCaOlglS6gYo0uD0zLbuAto5sUyy7AK9_O0aI1
GIDA_PT2_SALT=0AA4m2NxBxn0w5mM9oZR2kHz
GIDA_PT2_PASSCODE=2pNNtRkSx8jFd7HWlikcg

GIDA_MS=gareth
GIDA_PRE=EBsmQ6zMqopxMWhfZ27qXVpRKIsRNKbTS_aXMtWt67eb
GIDA_MS_SALT=0AAOfZHXD6eerQUNzTHUOe8S
GIDA_MS_PASSCODE=fwULUwdzavFxpcuD9c96z


# QAR AIDs
QAR_PT1=galahad
QAR_PT1_PRE=ELPwNB8R_CsMNHw_amyp-xnLvpxxTgREjEIvc7oJgqfW
QAR_PT1_SALT=0ACgCmChLaw_qsLycbqBoxDK
QAR_PT1_PASSCODE=e6b3402845de8185abe94

QAR_PT2=lancelot
QAR_PT2_PRE=ENlxz3lZXjEo73a-JBrW1eL8nxSWyLU49-VkuqQZKMtt
QAR_PT2_SALT=0ACaYJJv0ERQmy7xUfKgR6a4
QAR_PT2_PASSCODE=bdf1565a750ff3f76e4fc

QVI_MS=percival
QVI_PRE=EAwP4xBP4C8KzoKCYV2e6767OTnmR5Bt8zmwhUJr9jHh
QVI_MS_SALT=0AA2sMML7K-XdQLrgzOfIvf3
QVI_MS_PASSCODE=97542531221a214cc0a55


# Person AID
PERSON_NAME="Mordred Delacqs"
PERSON=mordred
PERSON_PRE=EIV2RRWifgojIlyX1CyEIJEppNzNKTidpOI7jYnpycne
PERSON_SALT=0ABlXAYDE2TkaNDk4UXxxtaN
PERSON_PASSCODE=c4479ae785625c8e50a7e
PERSON_ECR="Consultant"
PERSON_OOR="Advisor"


# Sally - vLEI Reporting API
SALLY=sally
SALLY_PASSCODE=VVmRdBTe5YCyLMmYRqTAi
SALLY_SALT=0AD45YWdzWSwNREuAoitH_CC
SALLY_PRE=EHLWiN8Q617zXqb4Se4KfEGteHbn_way2VG5mcHYh5bm

# Credentials
GEDA_REGISTRY=vLEI-external
GIDA_REGISTRY=vLEI-internal
QVI_REGISTRY=vLEI-qvi
QVI_SCHEMA=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
LE_SCHEMA=ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY
ECR_AUTH_SCHEMA=EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g
OOR_AUTH_SCHEMA=EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E
ECR_SCHEMA=EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw
OOR_SCHEMA=EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy

# functions
function create_icp_config() {
    jq ".wits = [\"$WAN_PRE\"]" ./config/template-single-sig-incept-config.jq > ./config/single-sig-incept-config.json
    print_lcyan "Single sig inception config JSON:"
    print_lcyan "$(cat ./config/single-sig-incept-config.json)"
}

# creates a single sig AID
function create_aid() {
    NAME=$1
    SALT=$2
    PASSCODE=$3
    CONFIG_DIR=$4
    CONFIG_FILE=$5
    ICP_FILE=$6
    KLI_CMD=$7

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
    create_aid "${QAR_PT1}"  "${QAR_PT1_SALT}"  "${QAR_PT1_PASSCODE}"  "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}" "kli2"
    create_aid "${QAR_PT2}"  "${QAR_PT2_SALT}"  "${QAR_PT2_PASSCODE}"  "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}" "kli2"
    create_aid "${PERSON}"   "${PERSON_SALT}"   "${PERSON_PASSCODE}"   "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}" "kli2"
    create_aid "${SALLY}"    "${SALLY_SALT}"    "${SALLY_PASSCODE}"    "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
}
create_aids

# 3. GAR: OOBI resolutions between single sig AIDs
function resolve_oobis() {
    exists=$(kli contacts list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GEDA_PT2}")
    if [[ "$exists" =~ "${GEDA_PT2}" ]]; then
        print_yellow "OOBIs already resolved"
        return
    fi

    echo
    print_lcyan "-----Resolving OOBIs-----"
    print_yellow "Resolving OOBIs for GEDA 1"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GEDA_PT2}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QAR_PT1}"  --passcode "${GEDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QAR_PT2}"  --passcode "${GEDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GIDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GIDA_PT2}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${PERSON}"   --passcode "${GEDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for GEDA 2"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GEDA_PT1}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT2}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT1}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GIDA_PT1}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GIDA_PT2}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${PERSON}"   --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for GIDA 1"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${GIDA_PT2}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${GEDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${GEDA_PT2}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QAR_PT1}"  --passcode "${GIDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QAR_PT2}"  --passcode "${GIDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${PERSON}"   --passcode "${GIDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for GIDA 2"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${GIDA_PT1}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${GEDA_PT1}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${GEDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QAR_PT1}"  --passcode "${GIDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QAR_PT2}"  --passcode "${GIDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${PERSON}"   --passcode "${GIDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for QAR 1"
    kli2 oobi resolve --name "${QAR_PT1}" --oobi-alias "${QAR_PT2}"   --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${QAR_PT2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT1}" --oobi-alias "${GEDA_PT1}"  --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT1}" --oobi-alias "${GEDA_PT2}"  --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT1}" --oobi-alias "${GIDA_PT1}"  --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT1}" --oobi-alias "${GIDA_PT2}"  --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT1}" --oobi-alias "${PERSON}"    --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT1}" --oobi-alias "$SALLY"       --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for QAR 2"
    kli2 oobi resolve --name "${QAR_PT2}" --oobi-alias "${QAR_PT1}"   --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${QAR_PT1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT2}" --oobi-alias "${GEDA_PT2}"  --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT2}" --oobi-alias "${GEDA_PT1}"  --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT2}" --oobi-alias "${GIDA_PT1}"  --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT2}" --oobi-alias "${GIDA_PT2}"  --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT2}" --oobi-alias "${PERSON}"    --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR_PT2}" --oobi-alias "$SALLY"       --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"

    # print_yellow "Resolving OOBIs for Person"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${QAR_PT1}"   --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${QAR_PT1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${QAR_PT2}"   --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${QAR_PT2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${GEDA_PT1}"  --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${GEDA_PT2}"  --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${GIDA_PT1}"  --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${GIDA_PT2}"  --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    
    echo
}
resolve_oobis

# 3.5 GAR: Challenge responses between single sig AIDs
function challenge_response() {
    chall_length=$(kli contacts list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | jq "select(.alias == \"${GEDA_PT2}\") | .challenges | length")
    if [[ "$chall_length" > 0 ]]; then
        print_yellow "Challenges already processed"
        return
    fi

    print_yellow "-----Challenge Responses-----"

    print_dark_gray "---Challenge responses for GEDA---"

    print_dark_gray "Challenge: GEDA 1 -> GEDA 2"
    words_geda1_to_geda2=$(kli challenge generate --out string)
    kli challenge respond --name "${GEDA_PT2}" --alias "${GEDA_PT2}" --passcode "${GEDA_PT2_PASSCODE}" --recipient "${GEDA_PT1}" --words "${words_geda1_to_geda2}"
    kli challenge verify  --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --signer "${GEDA_PT2}"    --words "${words_geda1_to_geda2}"

    print_dark_gray "Challenge: GEDA 2 -> GEDA 1"
    words_geda2_to_geda1=$(kli challenge generate --out string)
    kli challenge respond --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --recipient "${GEDA_PT2}" --words "${words_geda2_to_geda1}"
    kli challenge verify  --name "${GEDA_PT2}" --alias "${GEDA_PT2}" --passcode "${GEDA_PT2_PASSCODE}" --signer "${GEDA_PT1}"    --words "${words_geda2_to_geda1}"

    print_dark_gray "---Challenge responses for QAR---"

    print_dark_gray "Challenge: QAR 1 -> QAR 2"
    words_qar1_to_qar2=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --recipient "${QAR_PT1}" --words "${words_qar1_to_qar2}"
    kli2 challenge verify  --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --signer "${QAR_PT2}"    --words "${words_qar1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> QAR 1"
    words_qar2_to_qar1=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --recipient "${QAR_PT2}" --words "${words_qar2_to_qar1}"
    kli2 challenge verify  --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --signer "${QAR_PT1}"    --words "${words_qar2_to_qar1}"

    print_dark_gray "---Challenge responses between GEDA and QAR---"
    
    print_dark_gray "Challenge: GEDA 1 -> QAR 1"
    words_geda1_to_qar1=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --recipient "${GEDA_PT1}" --words "${words_geda1_to_qar1}"
    kli challenge verify  --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --signer "${QAR_PT1}"    --words "${words_geda1_to_qar1}"

    print_dark_gray "Challenge: QAR 1 -> GEDA 1"
    words_qar1_to_geda1=$(kli challenge generate --out string)
    kli challenge respond --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --recipient "${QAR_PT1}" --words "${words_qar1_to_geda1}"
    kli2 challenge verify  --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --signer "${GEDA_PT1}"    --words "${words_qar1_to_geda1}"

    print_dark_gray "Challenge: GEDA 2 -> QAR 2"
    words_geda1_to_qar2=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --recipient "${GEDA_PT1}" --words "${words_geda1_to_qar2}"
    kli challenge verify  --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --signer "${QAR_PT2}"    --words "${words_geda1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> GEDA 1"
    words_qar2_to_geda1=$(kli challenge generate --out string)
    kli challenge respond --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --recipient "${QAR_PT2}" --words "${words_qar2_to_geda1}"
    kli2 challenge verify  --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --signer "${GEDA_PT1}"    --words "${words_qar2_to_geda1}"

    print_dark_gray "---Challenge responses for GIDA (LE)---"

    print_dark_gray "Challenge: GIDA 1 -> GIDA 2"
    words_gida1_to_gida2=$(kli challenge generate --out string)
    kli challenge respond --name "${GIDA_PT2}" --alias "${GIDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --recipient "${GIDA_PT1}" --words "${words_gida1_to_gida2}"
    kli challenge verify  --name "${GIDA_PT1}" --alias "${GIDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" --signer "${GIDA_PT2}"    --words "${words_gida1_to_gida2}"

    print_dark_gray "Challenge: GIDA 2 -> GIDA 1"
    words_gida2_to_gida1=$(kli challenge generate --out string)
    kli challenge respond --name "${GIDA_PT1}" --alias "${GIDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" --recipient "${GIDA_PT2}" --words "${words_gida2_to_gida1}"
    kli challenge verify  --name "${GIDA_PT2}" --alias "${GIDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --signer "${GIDA_PT1}"    --words "${words_gida2_to_gida1}"

    print_dark_gray "---Challenge responses between QAR and GIDA (LE)---"

    print_dark_gray "Challenge: QAR 1 -> GIDA 1"
    words_qar1_to_gida1=$(kli challenge generate --out string)
    kli challenge respond --name "${GIDA_PT1}" --alias "${GIDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" --recipient "${QAR_PT1}" --words "${words_qar1_to_gida1}"
    kli2 challenge verify  --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --signer "${GIDA_PT1}"    --words "${words_qar1_to_gida1}"

    print_dark_gray "Challenge: GIDA 1 -> QAR 1"
    words_gida1_to_qar1=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --recipient "${GIDA_PT1}" --words "${words_gida1_to_qar1}"
    kli challenge verify  --name "${GIDA_PT1}" --alias "${GIDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" --signer "${QAR_PT1}"    --words "${words_gida1_to_qar1}"

    print_dark_gray "Challenge: QAR 2 -> GIDA 2"
    words_qar2_to_gida2=$(kli challenge generate --out string)
    kli challenge respond --name "${GIDA_PT2}" --alias "${GIDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --recipient "${QAR_PT2}" --words "${words_qar2_to_gida2}"
    kli2 challenge verify  --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --signer "${GIDA_PT2}"    --words "${words_qar2_to_gida2}"

    print_dark_gray "Challenge: GIDA 2 -> QAR 2"
    words_gida2_to_qar2=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --recipient "${GIDA_PT2}" --words "${words_gida2_to_qar2}"
    kli challenge verify  --name "${GIDA_PT2}" --alias "${GIDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --signer "${QAR_PT2}"    --words "${words_gida2_to_qar2}" 

    print_green "-----Finished challenge and response-----"
}
#challenge_response

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

# 5. GAR: Generate OOBI for GEDA to send to QVI
# done in step 9 below in the function

# 6. QAR: Create identifiers (2)
# created in step 2

# 7. QAR: OOBI and Challenge QAR single sig AIDs
# completed in step 3.5

# 8. QAR: OOBI and Challenge GAR single sig AIDs
# completed in step 3.5

# 9. QAR: Resolve GEDA OOBI
function resolve_geda_oobis() {
    exists=$(kli2 contacts list --name "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GEDA_MS}")
    if [[ "$exists" =~ "${GEDA_MS}" ]]; then
        print_yellow "GEDA OOBIs already resolved"
        return
    fi

    GEDA_OOBI=$(kli oobi generate --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --alias ${GEDA_MS} --role witness)
    echo "GEDA OOBI: ${GEDA_OOBI}"
    kli2 oobi resolve --name "${QAR_PT1}" --oobi-alias "${GEDA_MS}" --passcode "${QAR_PT1_PASSCODE}" --oobi "${GEDA_OOBI}"
    kli2 oobi resolve --name "${QAR_PT2}" --oobi-alias "${GEDA_MS}" --passcode "${QAR_PT2_PASSCODE}" --oobi "${GEDA_OOBI}"
}
resolve_geda_oobis

# 10. QAR: Create delegated multisig QVI AID
# 11. QVI: Create delegated AID with GEDA as delegator
# 12. GEDA: delegate to QVI

function create_delegated_multisig_icp_config() {
    DELPRE=$1
    PRE1=$2
    PRE2=$3
    WITPRE=$4
    cat ./config/template-multi-sig-delegated-incept-config.jq | \
        jq ".delpre = \"$DELPRE\"" | \
        jq ".aids = [\"$PRE1\",\"$PRE2\"]" | \
        jq ".wits = [\"$WITPRE\"]" > ./config/multi-sig-delegated-incept-config.json

    print_lcyan "Delegated multisig inception config JSON:"
    print_lcyan "$(cat ./config/multi-sig-delegated-incept-config.json)"
}

function create_qvi_multisig() {
    exists=$(kli2 list --name "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" | grep "${QVI_MS}")
    if [[ "$exists" =~ "${QVI_MS}" ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_MS} already exists"
        return
    fi

    echo
    print_yellow "[QVI] delegated multisig inception from ${GEDA_MS} | ${GEDA_PRE}"

    create_delegated_multisig_icp_config "${GEDA_PRE}" "${QAR_PT1_PRE}" "${QAR_PT2_PRE}" "${WAN_PRE}"

    # Follow commands run in parallel
    echo
    print_yellow "[QVI] delegated multisig inception started by ${QAR_PT1}: ${QAR_PT1_PRE}"

    kli2d qvi1 multisig incept --name "${QAR_PT1}" --alias "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --group "${QVI_MS}" \
        --file /config/multi-sig-delegated-incept-config.json

    echo

    kli2d qvi2 multisig incept --name "${QAR_PT2}" --alias "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --group "${QVI_MS}" \
        --file /config/multi-sig-delegated-incept-config.json

    # kli2d qvi2 multisig join --name ${QAR_PT2} \
    #     --passcode ${QAR_PT2_PASSCODE} \
    #     --group ${QVI_MS} \
    #     --auto

    echo
    print_yellow "[QVI] delegated multisig Inception { ${QAR_PT1}, ${QAR_PT2} } - wait for signatures"
    echo

    print_lcyan "[External] GEDA members approve delegated inception with 'kli delegate confirm'"
    echo

    klid geda1 delegate confirm --name "${GEDA_PT1}" --alias "${GEDA_PT1}" \
        --passcode "${GEDA_PT1_PASSCODE}" --interact --auto
    klid geda2 delegate confirm --name "${GEDA_PT2}" --alias "${GEDA_PT2}" \
        --passcode "${GEDA_PT2_PASSCODE}" --interact --auto

    print_dark_gray "waiting on Docker containers qvi1, qvi2, geda1, geda2"
    docker wait qvi1 qvi2 geda1 geda2
    docker logs qvi1 # show what happened
    docker logs qvi2 # show what happened
    docker logs geda1
    docker logs geda2
    docker rm qvi1 qvi2 geda1 geda2

    echo
    print_lcyan "[QVI] Show multisig status for ${QAR_PT1}"
    kli2 status --name "${QAR_PT1}" --alias "${QVI_MS}" --passcode "${QAR_PT1_PASSCODE}"
    echo

    exists=$(kli2 list --name "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" | grep "${QVI_MS}")
    if [[ ! "$exists" =~ "${QVI_MS}" ]]; then
        print_red "[QVI] Multisig inception failed"
        kill -SIGINT $$ # exit script and trigger TRAP above
    fi

    ms_prefix=$(kli2 status --name "${QAR_PT1}" --alias "${QVI_MS}" --passcode "${QAR_PT1_PASSCODE}" | awk '/Identifier:/ {print $2}')
    print_green "[QVI] Multisig AID ${QVI_MS} with prefix: ${ms_prefix}"
}
create_qvi_multisig

# 13. QVI: (skip) Perform endpoint role authorizations

# 14. QVI: Generate OOBI for QVI to send to GEDA
QVI_OOBI=$(kli2 oobi generate --name "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --alias "${QVI_MS}" --role witness)

# 15. GEDA and GIDA: Resolve QVI OOBI
function resolve_qvi_oobi() {
    exists=$(kli contacts list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | jq .alias | tr -d '"' | grep "${QVI_MS}")
    if [[ "$exists" =~ "${QVI_MS}" ]]; then
        print_yellow "QVI OOBIs already resolved"
        return
    fi

    echo
    echo "QVI OOBI: ${QVI_OOBI}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QVI_MS}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QVI_MS}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QVI_MS}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QVI_MS}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${QVI_OOBI}"
    # kli oobi resolve --name "${PERSON}"   --oobi-alias "${QVI_MS}" --passcode "${PERSON_PASSCODE}"   --oobi "${QVI_OOBI}"
    echo
}
resolve_qvi_oobi

        
# 15.5 GEDA: Create GEDA credential registry
function create_geda_reg() {
    # Check if GEDA credential registry already exists
    REGISTRY=$(kli vc registry list \
        --name "${GEDA_PT1}" \
        --passcode "${GEDA_PT1_PASSCODE}" | awk '{print $1}')
    if [ ! -z "${REGISTRY}" ]; then
        print_dark_gray "GEDA registry already created"
        return
    fi

    echo
    print_yellow "Creating GEDA registry"
    NONCE=$(kli nonce | tr -d '[:space:]')
    klid geda1 vc registry incept \
        --name "${GEDA_PT1}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT1_PASSCODE}" \
        --usage "QVI Credential Registry for GEDA" \
        --nonce "${NONCE}" \
        --registry-name "${GEDA_REGISTRY}" 

    klid geda2 vc registry incept \
        --name "${GEDA_PT2}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT2_PASSCODE}" \
        --usage "QVI Credential Registry for GEDA" \
        --nonce "${NONCE}" \
        --registry-name "${GEDA_REGISTRY}"
    
    echo
    print_yellow "[External] GEDA registry inception - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers geda1 and geda2"
    docker wait geda1 geda2
    docker logs geda1
    docker logs geda2
    docker rm geda1 geda2

    echo
    print_green "QVI Credential Registry created for GEDA"
    echo
}
create_geda_reg

# 16. GEDA: Create QVI credential
function prepare_qvi_cred_data() {
    print_bg_blue "[External] Preparing QVI credential data"
    read -r -d '' QVI_CRED_DATA << EOM
{
    "LEI": "${GEDA_LEI}"
}
EOM

    echo "$QVI_CRED_DATA" > ./data/qvi-cred-data.json

    print_lcyan "QVI Credential Data"
    print_lcyan "$(cat ./data/qvi-cred-data.json)"
}
prepare_qvi_cred_data

function create_qvi_credential() {
    # Check if QVI credential already exists
    SAID=$(kli vc list \
        --name "${GEDA_PT1}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}")
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[External] GEDA QVI credential already created"
        return
    fi

    echo
    print_green "[External] GEDA creating QVI credential"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    
    klid geda1 vc create \
        --name "${GEDA_PT1}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT1_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/qvi-cred-data.json \
        --rules @/data/rules.json \
        --time "${KLI_TIME}"

    klid geda2 vc create \
        --name "${GEDA_PT2}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT2_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/qvi-cred-data.json \
        --rules @/data/rules.json \
        --time "${KLI_TIME}"

    echo
    print_yellow "[External] GEDA creating QVI credential - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers geda1 and geda2"
    docker wait geda1 geda2
    docker logs geda1
    docker logs geda2
    docker rm geda1 geda2

    echo
    print_lcyan "[External] QVI Credential created for GEDA"
    echo
}
create_qvi_credential

# 17. GEDA: IPEX Grant QVI credential to QVI
function grant_qvi_credential() {
    QVI_GRANT_SAID=$(kli2 ipex list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --poll \
        --said)
    if [ ! -z "${QVI_GRANT_SAID}" ]; then
        print_dark_gray "[External] GEDA QVI credential already granted"
        return
    fi
    SAID=$(kli vc list \
        --name "${GEDA_PT1}" \
        --passcode "${GEDA_PT1_PASSCODE}" \
        --alias "${GEDA_MS}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d '[:space:]')

    echo
    print_yellow $'[External] IPEX GRANTing QVI credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    klid geda1 ipex grant \
        --name "${GEDA_PT1}" \
        --passcode "${GEDA_PT1_PASSCODE}" \
        --alias "${GEDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}"

    klid geda2 ipex grant \
        --name "${GEDA_PT2}" \
        --passcode "${GEDA_PT2_PASSCODE}" \
        --alias "${GEDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}"

    echo
    print_yellow "[External] Waiting for IPEX messages to be witnessed"
    echo 
    print_dark_gray "waiting on Docker containers geda1 and geda2"
    docker wait geda1 geda2
    docker logs geda1
    docker logs geda2
    docker rm geda1 geda2

    echo
    print_green "[QVI] Polling for QVI Credential in ${QAR_PT1}..."
    kli2 ipex list \
            --name "${QAR_PT1}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT1_PASSCODE}" \
            --poll \
            --said | tr -d '[:space:]'
    QVI_GRANT_SAID=$?
    if [ -z "${QVI_GRANT_SAID}" ]; then
        print_red "[QVI] QVI Credential not granted - exiting"
        exit 1
    fi

    print_green "[QVI] Polling for QVI Credential in ${QAR_PT2}..."
    kli2 ipex list \
            --name "${QAR_PT2}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT2_PASSCODE}" \
            --poll \
            --said | tr -d '[:space:]'
    QVI_GRANT_SAID=$?
    if [ -z "${QVI_GRANT_SAID}" ]; then 
        print_red "[QVI] QVI Credential not granted - exiting"
        exit 1
    fi

    echo
    print_green "[External] QVI Credential issued to QVI"
    echo
}
grant_qvi_credential

# 18. QVI: Admit QVI credential from GEDA
function admit_qvi_credential() {
    VC_SAID=$(kli2 vc list \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --said \
        --schema "${QVI_SCHEMA}")
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] QVI Credential already admitted"
        return
    fi
    SAID=$(kli2 ipex list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --poll \
        --said | tr -d '[:space:]')

    echo
    print_yellow "[QVI] ${QVI_MS} admitting QVI Credential ${SAID} from GEDA ${GEDA_MS}"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    kli2d qvi1 ipex admit \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" 
    
    kli2d qvi2 ipex admit \
        --name "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --time "${KLI_TIME}"

    echo
    print_yellow "[QVI] Admitting QVI credential - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers geda1 and geda2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2
    docker rm qvi1 qvi2


    VC_SAID=$(kli2 vc list \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --said \
        --schema "${QVI_SCHEMA}")
    if [ -z "${VC_SAID}" ]; then
        print_red "[QVI] QVI Credential not admitted"
        exit 1
    fi

    echo
    print_green "[QVI] Admitted QVI credential"
    echo
}
admit_qvi_credential

# 18.5 Create QVI credential registry
function create_qvi_reg() {
    # Check if QVI credential registry already exists
    REGISTRY=$(kli2 vc registry list \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" | awk '{print $1}')
    if [ ! -z "${REGISTRY}" ]; then
        print_dark_gray "[QVI] QVI registry already created"
        return
    fi

    echo
    print_yellow "[QVI] Creating QVI registry"
    NONCE=$(kli nonce | tr -d '[:space:]')
    kli2d qvi1 vc registry incept \
        --name ${QAR_PT1} \
        --alias ${QVI_MS} \
        --passcode ${QAR_PT1_PASSCODE} \
        --usage "Credential Registry for QVI" \
        --nonce ${NONCE} \
        --registry-name ${QVI_REGISTRY} 

    kli2d qvi2 vc registry incept \
        --name ${QAR_PT2} \
        --alias ${QVI_MS} \
        --passcode ${QAR_PT2_PASSCODE} \
        --usage "Credential Registry for QVI" \
        --nonce ${NONCE} \
        --registry-name ${QVI_REGISTRY} 

    echo
    print_yellow "[QVI] Creating QVI registry - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2
    docker rm qvi1 qvi2

    echo
    print_green "[QVI] Credential Registry created for QVI"
    echo
}
create_qvi_reg

# 18.6 QVI OOBIs with GIDA
function resolve_gida_and_qvi_oobis() {
    exists=$(kli2 contacts list --name "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GIDA_MS}")
    if [[ "$exists" =~ "${GIDA_MS}" ]]; then
        print_yellow "GIDA OOBIs already resolved for QARs"
        return
    fi

    echo
    GIDA_OOBI=$(kli oobi generate --name ${GIDA_PT1} --passcode ${GIDA_PT1_PASSCODE} --alias ${GIDA_MS} --role witness)
    echo "GIDA OOBI: ${GIDA_OOBI}"
    kli2 oobi resolve --name "${QAR_PT1}" --oobi-alias "${GIDA_MS}" --passcode "${QAR_PT1_PASSCODE}" --oobi "${GIDA_OOBI}"
    kli2 oobi resolve --name "${QAR_PT2}" --oobi-alias "${GIDA_MS}" --passcode "${QAR_PT2_PASSCODE}" --oobi "${GIDA_OOBI}"
    
    echo    
}
resolve_gida_and_qvi_oobis

# 19. QVI: Prepare, create, and Issue LE credential to GEDA



# 19.1 Prepare LE edge data
function prepare_qvi_edge() {
    QVI_SAID=$(kli2 vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d '[:space:]')
    print_bg_blue "[QVI] Preparing QVI edge with QVI Credential SAID: ${QVI_SAID}"
    read -r -d '' QVI_EDGE_JSON << EOM
{
    "d": "", 
    "qvi": {
        "n": "${QVI_SAID}", 
        "s": "${QVI_SCHEMA}"
    }
}
EOM
    echo "$QVI_EDGE_JSON" > ./data/qvi-edge.json

    kli saidify --file /data/qvi-edge.json
    
    print_lcyan "Legal Entity edge Data"
    print_lcyan "$(cat ./data/qvi-edge.json | jq )"
}
prepare_qvi_edge    



# 19.1.5 GIDA: Create GIDA credential registry
function create_gida_reg() {
    # Check if GIDA credential registry already exists
    REGISTRY=$(kli vc registry list \
        --name "${GIDA_PT1}" \
        --passcode "${GIDA_PT1_PASSCODE}" | awk '{print $1}')
    if [ ! -z "${REGISTRY}" ]; then
        print_dark_gray "[Internal] GIDA registry already created"
        return
    fi

    echo
    print_yellow "[Internal] Creating GIDA registry"
    NONCE=$(kli nonce | tr -d '[:space:]')
    
    klid gida1 vc registry incept \
        --name ${GIDA_PT1} \
        --alias ${GIDA_MS} \
        --passcode ${GIDA_PT1_PASSCODE} \
        --usage "Legal Entity Credential Registry for GIDA (LE)" \
        --nonce ${NONCE} \
        --registry-name ${GIDA_REGISTRY} 

    klid gida2 vc registry incept \
        --name ${GIDA_PT2} \
        --alias ${GIDA_MS} \
        --passcode ${GIDA_PT2_PASSCODE} \
        --usage "Legal Entity Credential Registry for GIDA (LE)" \
        --nonce ${NONCE} \
        --registry-name ${GIDA_REGISTRY} 

    echo
    print_yellow "[Internal] GIDA creating GIDA registry - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers gida1 and gida2"
    docker wait gida1 gida2
    docker logs gida1
    docker logs gida2
    docker rm gida1 gida2

    echo
    print_green "[Internal] Legal Entity Credential Registry created for GIDA"
    echo
}
create_gida_reg

# 19.2 Prepare LE credential data
function prepare_le_cred_data() {
    print_yellow "[QVI] Preparing LE credential data"
    read -r -d '' LE_CRED_DATA << EOM
{
    "LEI": "${GEDA_LEI}"
}
EOM

    echo "$LE_CRED_DATA" > ./data/legal-entity-data.json

    print_lcyan "[QVI] Legal Entity Credential Data"
    print_lcyan "$(cat ./data/legal-entity-data.json)"
}
prepare_le_cred_data

# 19.3 Create LE credential in QVI
function create_le_credential() {
    # Check if LE credential already exists
    SAID=$(kli2 vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[QVI] LE credential already created"
        return
    fi

    echo
    print_green "[QVI] creating LE credential"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    
    kli2d qvi1 vc create \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${LE_SCHEMA}" \
        --recipient "${GIDA_PRE}" \
        --data @/data/legal-entity-data.json \
        --edges @/data/qvi-edge.json \
        --rules @/data/rules.json \
        --time "${KLI_TIME}" 

    kli2d qvi2 vc create \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${LE_SCHEMA}" \
        --recipient "${GIDA_PRE}" \
        --data @/data/legal-entity-data.json \
        --edges @/data/qvi-edge.json \
        --rules @/data/rules.json \
        --time "${KLI_TIME}" 

    echo
    print_yellow "[QVI] creating LE credential - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2    
    docker rm qvi1 qvi2

    SAID=$(kli2 vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')

    if [ -z "${SAID}" ]; then
        print_red "[QVI] LE Credential not created"
        exit 1
    fi

    echo
    print_lcyan "[QVI] LE Credential created"
    echo
}
create_le_credential



function grant_le_credential() {
    # This only works because there will be only one grant in the list for the GEDA
    LE_GRANT_SAID=$(kli ipex list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --type "grant" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --poll \
        --said | tr -d '[:space:]')
    if [ ! -z "${LE_GRANT_SAID}" ]; then
        print_dark_gray "[GIDA] LE credential already granted"
        return
    fi
    SAID=$(kli2 vc list \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --issued \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')

    echo
    print_yellow $'[QVI] IPEX GRANTing LE credential with\n\tSAID'" ${SAID}"$'\n\tto GIDA'" ${GIDA_PRE}"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    kli2d qvi1 ipex grant \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --recipient "${GIDA_PRE}" \
        --time "${KLI_TIME}"

    kli2d qvi2 ipex grant \
        --name "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --recipient "${GIDA_PRE}" \
        --time "${KLI_TIME}"

    echo
    print_yellow "[QVI] granting LE credential to GIDA - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1    
    docker logs qvi2
    docker rm qvi1 qvi2

    echo
    print_green "[Internal] Polling for LE Credential in ${GIDA_PT1}..."
    kli ipex list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | tr -d '[:space:]'
    LE_GRANT_SAID=$?
    if [ -z "${LE_GRANT_SAID}" ]; then
        print_red "LE Credential not granted"
        exit 1
    else 
        print_green "[Internal] ${QVI_MS} granted LE Credential to GIDA ${GIDA_PT1} SAID ${LE_GRANT_SAID}"
    fi

    print_green "[Internal] Polling for LE Credential in ${GIDA_PT2}..."
    kli ipex list \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | tr -d '[:space:]'
    LE_GRANT_SAID=$?
    if [ -z "${LE_GRANT_SAID}" ]; then 
        print_red "LE Credential not granted"
        exit 1
    else 
        print_green "[Internal] ${QVI_MS} granted LE Credential to GIDA ${GIDA_PT2} SAID ${LE_GRANT_SAID}"
    fi

    echo
    print_green "[QVI] LE Credential granted to GIDA"
    echo
}
grant_le_credential

# 20. GEDA: Admit LE credential from QVI
function admit_le_credential() {
    VC_SAID=$(kli vc list \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[Internal] LE Credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | tr -d '[:space:]')

    echo
    print_yellow "[Internal] Admitting LE Credential ${SAID} to ${GIDA_MS} as ${GIDA_PT1}"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    klid gida1 ipex admit \
        --name "${GIDA_PT1}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" 

    print_green "[Internal] Admitting LE Credential ${SAID} to ${GIDA_MS} as ${GIDA_PT2}"
    klid gida2 ipex admit \
        --name "${GIDA_PT2}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" 

    echo
    print_yellow "[Internal] Admitting LE credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers gida1 and gida2"
    docker wait gida1 gida2
    docker logs gida1
    docker logs gida2
    docker rm gida1 gida2

    VC_SAID=$(kli vc list \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')

    if [ -z "${VC_SAID}" ]; then
        print_red "[Internal] LE Credential not admitted"
        exit 1
    fi

    echo
    print_green "[Internal] Admitted LE credential"
    echo
}
admit_le_credential

# 21. GEDA: Prepare, create, and Issue ECR Auth & OOR Auth credential to QVI

# 21.1 prepare LE edge to ECR auth cred
function prepare_le_edge() {
    LE_SAID=$(kli vc list \
        --name ${GIDA_PT1} \
        --alias ${GIDA_MS} \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')
    print_bg_blue "[Internal] Preparing ECR Auth cred with LE Credential SAID: ${LE_SAID}"
    read -r -d '' LE_EDGE_JSON << EOM
{
    "d": "", 
    "le": {
        "n": "${LE_SAID}", 
        "s": "${LE_SCHEMA}"
    }
}
EOM

    echo "$LE_EDGE_JSON" > ./data/legal-entity-edge.json
    kli saidify --file /data/legal-entity-edge.json
    
    print_lcyan "[Internal] Legal Entity edge JSON"
    print_lcyan "$(cat ./data/legal-entity-edge.json | jq)"
}
prepare_le_edge

# 21.2 Prepare ECR Auth credential data
function prepare_ecr_auth_data() {
    read -r -d '' ECR_AUTH_DATA_JSON << EOM
{
  "AID": "${PERSON_PRE}",
  "LEI": "${GEDA_LEI}",
  "personLegalName": "${PERSON_NAME}",
  "engagementContextRole": "${PERSON_ECR}"
}
EOM

    echo "$ECR_AUTH_DATA_JSON" > ./data/ecr-auth-data.json
    print_lcyan "[Internal] ECR Auth data JSON"
    print_lcyan "$(cat ./data/ecr-auth-data.json)"
}
prepare_ecr_auth_data

# 21.3 Create ECR Auth credential
function create_ecr_auth_credential() {
    # Check if ECR auth credential already exists
    SAID=$(kli vc list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema "${ECR_AUTH_SCHEMA}" | tr -d '[:space:]')
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[Internal] ECR Auth credential already created"
        return
    fi

    echo
    print_green "[Internal] GIDA creating ECR Auth credential"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    
    klid gida1 vc create \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --registry-name "${GIDA_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/ecr-auth-data.json \
        --edges @/data/legal-entity-edge.json \
        --rules @/data/ecr-auth-rules.json \
        --time "${KLI_TIME}" 

    klid gida2 vc create \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --registry-name "${GIDA_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/ecr-auth-data.json \
        --edges @/data/legal-entity-edge.json \
        --rules @/data/ecr-auth-rules.json \
        --time "${KLI_TIME}" 

    echo 
    print_yellow "[Internal] GIDA creating ECR Auth credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers gida1 and gida2"
    docker wait gida1 gida2
    docker logs gida1
    docker logs gida2
    docker rm gida1 gida2

    SAID=$(kli vc list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema "${ECR_AUTH_SCHEMA}" | tr -d '[:space:]')

    if [ -z "${SAID}" ]; then
        print_red "[Internal] ECR Auth Credential not created"
        exit 1
    fi

    echo
    print_lcyan "[Internal] GIDA created ECR Auth credential"
    echo
}
create_ecr_auth_credential

# 21.4 Grant ECR Auth credential to QVI
function grant_ecr_auth_credential() {
    # This relies on there being only one grant in the list for the GEDA
    GRANT_COUNT=$(kli2 ipex list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --type "grant" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --poll \
        --said | wc -l | tr -d ' ') # get the last grant
    if [ "${GRANT_COUNT}" -ge 2 ]; then
        print_dark_gray "[QVI] ECR Auth credential grant already received"
        return
    fi
    SAID=$(kli vc list \
        --name "${GIDA_PT1}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --issued \
        --said \
        --schema "${ECR_AUTH_SCHEMA}" | tr -d '[:space:]')

    echo
    print_yellow $'[Internal] IPEX GRANTing ECR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI '"${QVI_PRE}"

    KLI_TIME=$(kli time | tr -d '[:space:]') # Use consistent time so SAID of grant is same
    klid gida1 ipex grant \
        --name "${GIDA_PT1}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" 

    klid gida2 ipex grant \
        --name "${GIDA_PT2}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" 

    echo
    print_yellow "[Internal] Granting ECR Auth credential to QVI - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers gida1 and gida2"
    docker wait gida1 gida2
    docker logs gida1
    docker logs gida2
    docker rm gida1 gida2

    echo
    print_green "[QVI] Polling for ECR Auth Credential in ${QAR_PT1}..."
    kli2 ipex list \
            --name "${QAR_PT1}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT1_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    print_green "[QVI] Polling for ECR Auth Credential in ${QAR_PT2}..."
    kli2 ipex list \
            --name "${QAR_PT2}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT2_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    echo
    print_green "[Internal] ECR Auth Credential granted to QVI"
    echo
}
grant_ecr_auth_credential

# 21.5 (part of 22) Admit ECR Auth credential from GIDA
function admit_ecr_auth_credential() {
    VC_SAID=$(kli2 vc list \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --said \
        --schema "${ECR_AUTH_SCHEMA}" | tr -d '[:space:]')
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] ECR Auth Credential already admitted"
        return
    fi
    SAID=$(kli2 ipex list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | \
        tail -1 | tr -d '[:space:]') # get the last grant, which should be the ECR Auth credential

    echo
    print_yellow "[QVI] Admitting ECR Auth Credential ${SAID} from GIDA LE"

    KLI_TIME=$(kli time | tr -d '[:space:]') # Use consistent time so SAID of grant is same
    kli2d qvi1 ipex admit \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" 

    print_green "[QVI] Admitting ECR Auth Credential as ${QVI_MS} from GIDA LE"
    kli2d qvi2 ipex admit \
        --name "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" 
    
    echo
    print_yellow "[QVI] Admitting ECR Auth credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2
    docker rm qvi1 qvi2

    VC_SAID=$(kli2 vc list \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --said \
        --schema "${ECR_AUTH_SCHEMA}" | tr -d '[:space:]')
    if [ -z "${VC_SAID}" ]; then
        print_red "[QVI] ECR Auth Credential not admitted"
        exit 1
    fi

    echo
    print_green "[QVI] Admitted ECR Auth Credential"
    echo
}
admit_ecr_auth_credential

# 21.6 Prepare OOR Auth credential data
function prepare_oor_auth_data() {
    read -r -d '' OOR_AUTH_DATA_JSON << EOM
{
  "AID": "${PERSON_PRE}",
  "LEI": "${GEDA_LEI}",
  "personLegalName": "${PERSON_NAME}",
  "officialRole": "${PERSON_OOR}"
}
EOM

    echo "$OOR_AUTH_DATA_JSON" > ./data/oor-auth-data.json
    print_lcyan "[Internal] OOR Auth data JSON"
    print_lcyan "$(cat ./data/oor-auth-data.json)"
}
prepare_oor_auth_data

# 21.7 Create OOR Auth credential
function create_oor_auth_credential() {
    # Check if OOR auth credential already exists
    SAID=$(kli vc list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema "${OOR_AUTH_SCHEMA}" | tr -d '[:space:]')
    if [ ! -z "${SAID}" ]; then
        print_yellow "[QVI] OOR Auth credential already created"
        return
    fi

    echo
    print_green "[Internal] GIDA creating OOR Auth credential"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    klid gida1 vc create \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --registry-name "${GIDA_REGISTRY}" \
        --schema "${OOR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/oor-auth-data.json \
        --edges @/data/legal-entity-edge.json \
        --rules @/data/rules.json \
        --time "${KLI_TIME}" 

    klid gida2 vc create \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --registry-name "${GIDA_REGISTRY}" \
        --schema "${OOR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/oor-auth-data.json \
        --edges @/data/legal-entity-edge.json \
        --rules @/data/rules.json \
        --time "${KLI_TIME}" 

    echo 
    print_yellow "[Internal] GIDA creating OOR Auth credential - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers gida1 and gida2"
    docker wait gida1 gida2
    docker logs gida1
    docker logs gida2
    docker rm gida1 gida2

    SAID=$(kli vc list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema "${OOR_AUTH_SCHEMA}" | tr -d '[:space:]')
    if [ -z "${SAID}" ]; then
        print_red "[Internal] OOR Auth Credential not created"
        exit 1
    fi

    echo
    print_lcyan "[Internal] GIDA created OOR Auth credential"
    echo
}
create_oor_auth_credential



# 21.8 Grant OOR Auth credential to QVI
function grant_oor_auth_credential() {
    # This relies on the last grant being the OOR Auth credential
    GRANT_COUNT=$(kli2 ipex list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --type "grant" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --poll \
        --said | wc -l | tr -d ' ') # get grant count, remove whitespace
    if [ "${GRANT_COUNT}" -ge 3 ]; then
        print_dark_gray "[QVI] OOR Auth credential already granted"
        return
    fi
    SAID=$(kli vc list \
        --name "${GIDA_PT1}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --issued \
        --said \
        --schema ${OOR_AUTH_SCHEMA} | \
        tail -1 | tr -d '[:space:]') # get the last credential, the OOR Auth credential

    echo
    print_yellow $'[Internal] IPEX GRANTing OOR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"

    KLI_TIME=$(kli time | tr -d '[:space:]') # Use consistent time so SAID of grant is same
    klid gida1 ipex grant \
        --name "${GIDA_PT1}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" 

    klid gida2 ipex grant \
        --name "${GIDA_PT2}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" 

    echo
    print_yellow "[Internal] Granting OOR Auth credential to QVI - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers gida1 and gida2"
    docker wait gida1 gida2
    docker logs gida1
    docker logs gida2
    docker rm gida1 gida2


    echo
    print_green "[QVI] Polling for OOR Auth Credential in ${QAR_PT1}..."
    kli2 ipex list \
            --name "${QAR_PT1}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT1_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    print_green "[QVI] Polling for OOR Auth Credential in ${QAR_PT2}..."
    kli2 ipex list \
            --name "${QAR_PT2}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT2_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    echo
    print_green "[Internal] Granted OOR Auth credential to QVI"
    echo
}
grant_oor_auth_credential



# 22. QVI: Admit OOR Auth credential
function admit_oor_auth_credential() {
    VC_SAID=$(kli2 vc list \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --said \
        --schema ${OOR_AUTH_SCHEMA} | tr -d '[:space:]')
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] OOR Auth Credential already admitted"
        return
    fi
    SAID=$(kli2 ipex list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | \
        tail -1 | tr -d '[:space:]') # get the last grant, which should be the ECR Auth credential

    echo
    print_yellow "[QVI] Admitting OOR Auth Credential ${SAID} from GIDA LE"

    KLI_TIME=$(kli time | tr -d '[:space:]') # Use consistent time so SAID of grant is same
    kli2d qvi1 ipex admit \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --time "${KLI_TIME}"

    print_green "[QVI] Admitting OOR Auth Credential as ${QVI_MS} from GIDA LE"
    kli2d qvi2 ipex admit \
        --name "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --time "${KLI_TIME}"

    echo
    print_yellow "[QVI] Admitting OOR Auth credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2
    docker rm qvi1 qvi2

    VC_SAID=$(kli2 vc list \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --said \
        --schema ${OOR_AUTH_SCHEMA} | tr -d '[:space:]')
    if [ -z "${VC_SAID}" ]; then
        print_red "[QVI] OOR Auth Credential not admitted"
        exit 1
    fi

    echo
    print_green "[QVI] OOR Auth Credential admitted"
    echo
}
admit_oor_auth_credential




# 23. QVI: Create and Issue ECR credential to Person
# 23.1 Prepare ECR Auth edge data
function prepare_ecr_auth_edge() {
    ECR_AUTH_SAID=$(kli2 vc list \
        --name ${QAR_PT1} \
        --alias ${QVI_MS} \
        --passcode "${QAR_PT1_PASSCODE}" \
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
    echo "$ECR_AUTH_EDGE_JSON" > ./data/ecr-auth-edge.json

    kli saidify --file /data/ecr-auth-edge.json
    
    print_lcyan "[QVI] ECR Auth edge Data"
    print_lcyan "$(cat ./data/ecr-auth-edge.json | jq )"
}
prepare_ecr_auth_edge      



# 23.2 Prepare ECR credential data
function prepare_ecr_cred_data() {
    print_bg_blue "[QVI] Preparing ECR credential data"
    read -r -d '' ECR_CRED_DATA << EOM
{
  "LEI": "${GEDA_LEI}",
  "personLegalName": "${PERSON_NAME}",
  "engagementContextRole": "${PERSON_ECR}"
}
EOM

    echo "${ECR_CRED_DATA}" > ./data/ecr-data.json

    print_lcyan "[QVI] ECR Credential Data"
    print_lcyan "$(cat ./data/ecr-data.json)"
}
prepare_ecr_cred_data



# 23.3 Create ECR credential in QVI, issued to the Person
function create_ecr_credential() {
    # Check if ECR credential already exists
    SAID=$(kli2 vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema ${ECR_SCHEMA} | tr -d '[:space:]')
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[QVI] ECR credential already created"
        return
    fi

    echo
    print_green "[QVI] creating ECR credential"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    CRED_NONCE=$(kli nonce | tr -d '[:space:]')
    SUBJ_NONCE=$(kli nonce | tr -d '[:space:]')
    kli2d qvi1 vc create \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --private-credential-nonce "${CRED_NONCE}" \
        --private-subject-nonce "${SUBJ_NONCE}" \
        --private \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${ECR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @/data/ecr-data.json \
        --edges @/data/ecr-auth-edge.json \
        --rules @/data/ecr-rules.json \
        --time "${KLI_TIME}"

    kli2d qvi2 vc create \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --private \
        --private-credential-nonce "${CRED_NONCE}" \
        --private-subject-nonce "${SUBJ_NONCE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${ECR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @/data/ecr-data.json \
        --edges @/data/ecr-auth-edge.json \
        --rules @/data/ecr-rules.json \
        --time "${KLI_TIME}" 

    echo
    print_yellow "[QVI] creating ECR credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2
    docker rm qvi1 qvi2

    SAID=$(kli2 vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema ${ECR_SCHEMA} | tr -d '[:space:]')
    if [ -z "${SAID}" ]; then
        print_red "[QVI] ECR Credential not created"
        exit 1
    fi

    echo
    print_lcyan "[QVI] ECR credential created"
    echo
}
create_ecr_credential

# 23.4 QVI Grant ECR credential to PERSON
function grant_ecr_credential() {
    # This only works the last grant is the ECR credential
    ECR_GRANT_SAID=$(kli ipex list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --type "grant" \
        --passcode "${PERSON_PASSCODE}" \
        --poll \
        --said | \
        tail -1 | tr -d '[:space:]') # get the last grant
    if [ ! -z "${ECR_GRANT_SAID}" ]; then
        print_yellow "[QVI] ECR credential already granted"
        return
    fi
    SAID=$(kli vc list \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --issued \
        --said \
        --schema ${ECR_SCHEMA} | tr -d '[:space:]')

    echo
    print_yellow $'[QVI] IPEX GRANTing ECR credential with\n\tSAID'" ${SAID}"$'\n\tto'" ${PERSON} ${PERSON_PRE}"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    kli2d qvi1 ipex grant \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" \
        --time "${KLI_TIME}"

    kli2d qvi2 ipex grant \
        --name "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" \
        --time "${KLI_TIME}"

    echo 
    print_yellow "[QVI] Granting ECR credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2
    docker rm qvi1 qvi2
    
    echo
    print_green "[PERSON] Polling for ECR Credential in ${PERSON}..."
    kli ipex list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --type "grant" \
        --poll \
        --said

    echo
    print_green "ECR Credential granted to ${PERSON}"
    echo
}
grant_ecr_credential

# 23.5. Person: Admit ECR credential from QVI
function admit_ecr_credential() {
    VC_SAID=$(kli vc list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --said \
        --schema ${ECR_SCHEMA} | tr -d '[:space:]')
    if [ ! -z "${VC_SAID}" ]; then
        print_yellow "[PERSON] ECR credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | tr -d '[:space:]')

    echo
    print_yellow "[PERSON] Admitting ECR credential ${SAID} to ${PERSON}"

    kli2d person ipex admit \
        --name "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --alias "${PERSON}" \
        --said "${SAID}" 

    echo
    print_yellow "[PERSON] Admitting ECR credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers person"
    docker wait person
    docker logs person
    docker rm person

    VC_SAID=$(kli2 vc list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --said \
        --schema ${ECR_SCHEMA} | tr -d '[:space:]')
    if [ -z "${VC_SAID}" ]; then
        print_red "[PERSON] ECR Credential not admitted"
        exit 1
    else 
        print_green "[PERSON] ECR Credential admitted"
    fi
}
admit_ecr_credential

# 24. QVI: Issue, grant OOR to Person and Person admits OOR
# 24.1 Prepare OOR Auth edge data
function prepare_oor_auth_edge() {
    OOR_AUTH_SAID=$(kli2 vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --said \
        --schema "${OOR_AUTH_SCHEMA}" | tr -d '[:space:]')
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
    echo "$OOR_AUTH_EDGE_JSON" > ./data/oor-auth-edge.json

    kli saidify --file /data/oor-auth-edge.json
    
    print_lcyan "[QVI] OOR Auth edge Data"
    print_lcyan "$(cat ./data/oor-auth-edge.json | jq )"
}
prepare_oor_auth_edge      

# 24.2 Prepare OOR credential data
function prepare_oor_cred_data() {
    print_bg_blue "[QVI] Preparing OOR credential data"
    read -r -d '' OOR_CRED_DATA << EOM
{
  "LEI": "${GEDA_LEI}",
  "personLegalName": "${PERSON_NAME}",
  "officialRole": "${PERSON_OOR}"
}
EOM

    echo "${OOR_CRED_DATA}" > ./data/oor-data.json

    print_lcyan "[QVI] OOR Credential Data"
    print_lcyan "$(cat ./data/oor-data.json)"
}
prepare_oor_cred_data

# 24.3 Create OOR credential in QVI, issued to the Person
function create_oor_credential() {
    # Check if OOR credential already exists
    SAID=$(kli2 vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema ${OOR_SCHEMA} | tr -d '[:space:]')
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[QVI] OOR credential already created"
        return
    fi

    echo
    print_green "[QVI] creating OOR credential"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    PID_LIST=""
    kli2d qvi1 vc create \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${OOR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @/data/oor-data.json \
        --edges @/data/oor-auth-edge.json \
        --rules @/data/oor-rules.json \
        --time "${KLI_TIME}" 

    kli2d qvi2 vc create \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${OOR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @/data/oor-data.json \
        --edges @/data/oor-auth-edge.json \
        --rules @/data/oor-rules.json \
        --time "${KLI_TIME}" 

    echo 
    print_yellow "[QVI] creating OOR credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2
    docker rm qvi1 qvi2    

    echo
    print_lcyan "[QVI] OOR credential created"
    echo
}
create_oor_credential


# 24.4 QVI Grant OOR credential to PERSON
function grant_oor_credential() {
    # This only works the last grant is the OOR credential
    GRANT_COUNT=$(kli2 ipex list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --type "grant" \
        --passcode "${PERSON_PASSCODE}" \
        --poll \
        --said | wc -l | tr -d ' ') # get the last grant
    if [ "${GRANT_COUNT}" -ge 2 ]; then
        print_yellow "[QVI] OOR credential already granted"
        return
    fi
    SAID=$(kli2 vc list \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --issued \
        --said \
        --schema ${OOR_SCHEMA} | tr -d '[:space:]')

    echo
    print_yellow $'[QVI] IPEX GRANTing OOR credential with\n\tSAID'" ${SAID}"$'\n\tto'" ${PERSON} ${PERSON_PRE}"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    kli2d qvi1 ipex grant \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" \
        --time "${KLI_TIME}"

    kli2d qvi2 ipex grant \
        --name "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" \
        --time "${KLI_TIME}"

    echo
    print_yellow "[QVI] Granting OOR credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2
    docker rm qvi1 qvi2

    echo
    print_green "[PERSON] Polling for OOR Credential in ${PERSON}..."
    kli2 ipex list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --type "grant" \
        --poll \
        --said

    echo
    print_green "OOR Credential granted to ${PERSON}"
    echo
}
grant_oor_credential

# 24.5. Person: Admit OOR credential from QVI
function admit_oor_credential() {
    VC_SAID=$(kli2 vc list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --said \
        --schema ${OOR_SCHEMA} | tr -d '[:space:]')
    if [ ! -z "${VC_SAID}" ]; then
        print_yellow "[PERSON] OOR credential already admitted"
        return
    fi
    SAID=$(kli2 ipex list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | tail -1 | tr -d '[:space:]') # get the last grant, which should be the OOR credential

    echo
    print_yellow "[PERSON] Admitting OOR credential ${SAID} to ${PERSON}"

    kli2d person ipex admit \
        --name ${PERSON} \
        --passcode ${PERSON_PASSCODE} \
        --alias ${PERSON} \
        --said ${SAID}  

    echo 
    print_yellow "[PERSON] Admitting OOR credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers person"
    docker wait person
    docker logs person
    docker rm person

    VC_SAID=$(kli2 vc list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --said \
        --schema ${OOR_SCHEMA} | tr -d '[:space:]')
    if [ -z "${VC_SAID}" ]; then
        print_red "[PERSON] OOR Credential not admitted"
        exit 1
    else 
        print_green "[PERSON] OOR Credential admitted"
    fi
}
admit_oor_credential

# 25. QVI: Present issued ECR Auth and OOR Auth to Sally (vLEI Reporting API)
print_red "Sally and Webhook not yet functional in Docker, exiting..."
cleanup
exit 0

SALLY_PID=""
WEBHOOK_PID=""
function sally_setup() {
    # Supposedly not needed
    # kli oobi resolve --name $SALLY \
    #     --alias $SALLY \
    #     --oobi-alias ${QVI_MS} \
    #     --oobi ${QVI_OOBI}
    print_yellow "[GLEIF] setting up sally"
    print_yellow "[GLEIF] setting up webhook"
    sally hook demo & # For the webhook Sally will call upon credential presentation
    WEBHOOK_PID=$!

    print_yellow "[GLEIF] starting sally"
    sally server start \
        --name $SALLY \
        --alias $SALLY \
        --passcode $SALLY_PASSCODE \
        --web-hook http://webhook:9923 \
        --auth ${GEDA_PRE} & # who will be presenting the credential
    SALLY_PID=$!

    sleep 5
}
sally_setup

function present_le_cred_to_sally() {
    print_yellow "[QVI] Presenting LE Credential to Sally"
    LE_SAID=$(kli vc list --name ${GIDA_PT1} \
        --alias ${GIDA_MS} \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --said --schema ${LE_SCHEMA})

    PID_LIST=""
    kli ipex grant \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --said "${LE_SAID}" \
        --recipient "${SALLY}" &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --auto &
    pid=$!
    PID_LIST+=" $pid"
    wait $PID_LIST

    sleep 30
    print_green "[QVI] LE Credential presented to Sally"
}
present_le_cred_to_sally

# send sigterm to sally PID
function sally_teardown() {
    kill -SIGTERM $SALLY_PID
    kill -SIGTERM $WEBHOOK_PID
}
sally_teardown

# 26. QVI: Revoke ECR Auth and OOR Auth credentials

# 27. QVI: Present revoked credentials to Sally


print_lcyan "Full chain workflow completed"