#!/usr/bin/env bash
# qvi-workflow-kli-docker.sh
# Runs the entire QVI issuance workflow end to end starting from multisig AID creatin including the
# GLEIF External Delegated AID (GEDA) creation all the way to OOR and ECR credential issuance to the
# Person AID for usage in the iXBRL data attestation.
#
# Note:
# 1) This script uses the kli and kli2 commands as defined in ./kli-commands.sh to perform the QVI
#    workflow steps.
# 2) $HOME/.docker-keystores should be cleared out prior to running this script.
#    By specifying a directory as the first argument to this script you can control where the keystores are located.
#

set -u # undefined variable detection

KEYSTORE_DIR=${1:-./docker-keystores}
NO_CHALLENGE=${2:-true}

if $NO_CHALLENGE; then
    print_dark_gray "skipping challenge and response"
fi

# Check system dependencies
required_sys_commands=(docker jq tsx)
for cmd in "${required_sys_commands[@]}"; do
    if ! command -v $cmd &>/dev/null; then
        print_red "$cmd is not installed. Please install it."
        exit 1
    fi
done

# Load utility functions
source ./color-printing.sh
echo
print_bg_blue "------------------------------vLEI QVI Workflow Script (KLI - Docker)------------------------------"
echo

# Load kli commands
source ./kli-commands.sh "$KEYSTORE_DIR"

# Create docker network if it does not exist
docker network inspect vlei >/dev/null 2>&1 || docker network create vlei

# starts containers and waits for them all to be healthy before running the rest of the script
DOCKER_COMPOSE_FILE=docker-compose-qvi-workflow-kli.yaml
docker compose -f $DOCKER_COMPOSE_FILE up -d --wait

trap cleanup INT
function cleanup() {
    print_red "Caught Ctrl+C, stopping containers and exiting script..."
    echo
    docker compose -f $DOCKER_COMPOSE_FILE kill
    docker compose -f $DOCKER_COMPOSE_FILE down -v
    rm -rfv "${KEYSTORE_DIR}"/*
     container_names=("gar1" "gar2" "lar1" "lar2" "qvi1" "qvi2")

     for name in "${container_names[@]}"; do
     if docker ps -a | grep -q "$name"; then
         docker kill $name || true && \
          docker rm $name || true
     fi
     done
     exit 0
}

function clear_containers() {
    container_names=("gar1" "gar2" "lar1" "lar2" "qvi1" "qvi2")

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

# GAR: Prepare environment
CONFIG_DIR=./config
WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
WIT_HOST=http://witness-demo:5642
SCHEMA_SERVER=http://vlei-server:7723

# Container configuration
CONT_CONFIG_DIR=/config
CONT_INIT_CFG=habery-config-docker.json
CONT_ICP_CFG=/config/single-sig-incept-config.json

LE_LEI=254900OPPU84GM83MG36 # GLEIF Americas

# GEDA AIDs - GLEIF External Delegated AID
GAR1=accolon
GAR1_PRE=ENFbr9MI0K7f4Wz34z4hbzHmCTxIPHR9Q_gWjLJiv20h
GAR1_SALT=0AA2-S2YS4KqvlSzO7faIEpH
GAR1_PASSCODE=18b2c88fd050851c45c67

GAR2=bedivere
GAR2_PRE=EJ7F9XcRW85_S-6F2HIUgXcIcywAy0Nv-GilEBSRnicR
GAR2_SALT=0ADD292rR7WEU4GPpaYK4Z6h
GAR2_PASSCODE=b26ef3dd5c85f67c51be8

GEDA_NAME=dagonet
GEDA_PRE=EMCRBKH4Kvj03xbEVzKmOIrg0sosqHUF9VG2vzT9ybzv

# LE AIDs - Legal Entity
LAR1=elaine
LAR1_PRE=ELTDtBrcFsHTMpfYHIJFvuH6awXY1rKq4w6TBlGyucoF
LAR1_SALT=0AB90ainJghoJa8BzFmGiEWa
LAR1_PASSCODE=tcc6Yj4JM8MfTDs1IiidP

LAR2=finn
LAR2_PRE=EBpwQouCaOlglS6gYo0uD0zLbuAto5sUyy7AK9_O0aI1
LAR2_SALT=0AA4m2NxBxn0w5mM9oZR2kHz
LAR2_PASSCODE=2pNNtRkSx8jFd7HWlikcg

LE_NAME=gareth
LE_PRE=EBsmQ6zMqopxMWhfZ27qXVpRKIsRNKbTS_aXMtWt67eb

# QAR AIDs
QAR1=galahad
QAR1_PRE=ELPwNB8R_CsMNHw_amyp-xnLvpxxTgREjEIvc7oJgqfW
QAR1_SALT=0ACgCmChLaw_qsLycbqBoxDK
QAR1_PASSCODE=e6b3402845de8185abe94

QAR2=lancelot
QAR2_PRE=ENlxz3lZXjEo73a-JBrW1eL8nxSWyLU49-VkuqQZKMtt
QAR2_SALT=0ACaYJJv0ERQmy7xUfKgR6a4
QAR2_PASSCODE=bdf1565a750ff3f76e4fc

QVI_NAME=percival
QVI_PRE=EAwP4xBP4C8KzoKCYV2e6767OTnmR5Bt8zmwhUJr9jHh

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

# Registries
GEDA_REGISTRY=vLEI-external
LE_REGISTRY=vLEI-internal
QVI_REGISTRY=vLEI-qvi

# Credential Schemas
QVI_SCHEMA=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
LE_SCHEMA=ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY
OOR_AUTH_SCHEMA=EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E
ECR_AUTH_SCHEMA=EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g
OOR_SCHEMA=EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy
ECR_SCHEMA=EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw

DOCKER_COMPOSE_FILE=docker-compose-qvi-workflow-kli.yaml
docker compose -f $DOCKER_COMPOSE_FILE up -d --wait
if [ $? -ne 0 ]; then
    print_red "Docker services failed to start properly. Exiting."
    cleanup
    exit 1
fi

# functions
function create_icp_config() {
    jq ".wits = [\"$WAN_PRE\"]" ./config/template-single-sig-incept-config.jq > ./config/single-sig-incept-config.json
    print_lcyan "Single sig inception config JSON:"
    print_lcyan "$(cat ./config/single-sig-incept-config.json)"
}

# creates a single sig AID
function create_keystore_and_aid() {
    NAME=$1
    SALT=$2
    PASSCODE=$3
    CONFIG_DIR=$4
    CONFIG_FILE=$5
    ICP_FILE=$6
    KLI_CMD=${7:-kli}

    # Check if exists
    exists=$(kli list --name "${NAME}" --passcode "${PASSCODE}")
    if [[ ! "$exists" =~ "Keystore must already exist" ]]; then
        print_dark_gray "AID ${NAME} already exists"
        return
    fi

    ${KLI_CMD} init \
        --name "${NAME}" \
        --salt "${SALT}" \
        --passcode "${PASSCODE}" \
        --config-dir "${CONFIG_DIR}" \
        --config-file "${CONFIG_FILE}"

    ${KLI_CMD} incept \
        --name "${NAME}" \
        --alias "${NAME}" \
        --passcode "${PASSCODE}" \
        --file "${ICP_FILE}"
    PREFIX=$(${KLI_CMD} status  --name "${NAME}"  --alias "${NAME}"  --passcode "${PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )
    # Need this since resolving with bootstrap config file isn't working
    print_dark_gray "Created AID: ${NAME}"
    print_green $'\tPrefix:'" ${PREFIX}"
}

# GAR: Create single Sig AIDs (2)
function create_aids() {
    print_green "-----Creating AIDs-----"
    create_icp_config    
    create_keystore_and_aid "${GAR1}"   "${GAR1_SALT}"   "${GAR1_PASSCODE}"   "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
    create_keystore_and_aid "${GAR2}"   "${GAR2_SALT}"   "${GAR2_PASSCODE}"   "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
    create_keystore_and_aid "${LAR1}"   "${LAR1_SALT}"   "${LAR1_PASSCODE}"   "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
    create_keystore_and_aid "${LAR2}"   "${LAR2_SALT}"   "${LAR2_PASSCODE}"   "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
    create_keystore_and_aid "${QAR1}"   "${QAR1_SALT}"   "${QAR1_PASSCODE}"   "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}" "kli2"
    create_keystore_and_aid "${QAR2}"   "${QAR2_SALT}"   "${QAR2_PASSCODE}"   "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}" "kli2"
    create_keystore_and_aid "${PERSON}" "${PERSON_SALT}" "${PERSON_PASSCODE}" "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}" "kli2"
    create_keystore_and_aid "${SALLY}"  "${SALLY_SALT}"  "${SALLY_PASSCODE}"  "${CONT_CONFIG_DIR}" "${CONT_INIT_CFG}" "${CONT_ICP_CFG}"
}
create_aids

# GAR: OOBI resolutions between single sig AIDs
function resolve_oobis() {
    exists=$(kli contacts list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GAR2}")
    if [[ "$exists" =~ "${GAR2}" ]]; then
        print_yellow "OOBIs already resolved"
        return
    fi

    echo
    print_lcyan "-----Resolving OOBIs-----"
    print_yellow "Resolving OOBIs for GAR1"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${GAR2}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR1}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR2}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${LAR1}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${LAR2}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${PERSON}" --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for GAR2"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${GAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${PERSON}" --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for LAR1"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${LAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${PERSON}" --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for LAR2"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${LAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${PERSON}" --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for QAR 1"
    kli2 oobi resolve --name "${QAR1}" --oobi-alias "${QAR2}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR1}" --oobi-alias "${GAR1}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR1}" --oobi-alias "${GAR2}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR1}" --oobi-alias "${LAR1}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR1}" --oobi-alias "${LAR2}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR1}" --oobi-alias "${PERSON}" --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR1}" --oobi-alias "$SALLY"    --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for QAR 2"
    kli2 oobi resolve --name "${QAR2}" --oobi-alias "${QAR1}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR2}" --oobi-alias "${GAR2}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR2}" --oobi-alias "${GAR1}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR2}" --oobi-alias "${LAR1}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR2}" --oobi-alias "${LAR2}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR2}" --oobi-alias "${PERSON}" --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${QAR2}" --oobi-alias "$SALLY"    --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"

    # print_yellow "Resolving OOBIs for Person"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${QAR1}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${QAR2}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${GAR1}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${GAR2}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${LAR1}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli2 oobi resolve --name "${PERSON}"  --oobi-alias "${LAR2}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    
    echo
}
resolve_oobis

# GAR: Challenge responses between single sig AIDs
function challenge_response() {
    chall_length=$(kli contacts list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | jq "select(.alias == \"${GAR2}\") | .challenges | length")
    if [[ "$chall_length" -gt 0 ]]; then
        print_yellow "Challenges already processed"
        return
    fi

    print_yellow "-----Challenge Responses-----"

    print_dark_gray "---Challenge responses for GEDA---"

    print_dark_gray "Challenge: GAR1 -> GAR2"
    words_gar1_to_gar2=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR2}" --alias "${GAR2}" --passcode "${GAR2_PASSCODE}" --recipient "${GAR1}" --words "${words_gar1_to_gar2}"
    kli challenge verify  --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --signer "${GAR2}"    --words "${words_gar1_to_gar2}"

    print_dark_gray "Challenge: GAR2 -> GAR1"
    words_gar2_to_gar1=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --recipient "${GAR2}" --words "${words_gar2_to_gar1}"
    kli challenge verify  --name "${GAR2}" --alias "${GAR2}" --passcode "${GAR2_PASSCODE}" --signer "${GAR1}"    --words "${words_gar2_to_gar1}"

    print_dark_gray "---Challenge responses for QAR---"

    print_dark_gray "Challenge: QAR 1 -> QAR 2"
    words_qar1_to_qar2=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --recipient "${QAR1}" --words "${words_qar1_to_qar2}"
    kli2 challenge verify  --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --signer "${QAR2}"    --words "${words_qar1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> QAR 1"
    words_qar2_to_qar1=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --recipient "${QAR2}" --words "${words_qar2_to_qar1}"
    kli2 challenge verify  --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --signer "${QAR1}"    --words "${words_qar2_to_qar1}"

    print_dark_gray "---Challenge responses between GEDA and QAR---"
    
    print_dark_gray "Challenge: GAR1 -> QAR 1"
    words_gar1_to_qar1=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --recipient "${GAR1}" --words "${words_gar1_to_qar1}"
    kli challenge verify  --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --signer "${QAR1}"    --words "${words_gar1_to_qar1}"

    print_dark_gray "Challenge: QAR 1 -> GAR1"
    words_qar1_to_gar1=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --recipient "${QAR1}" --words "${words_qar1_to_gar1}"
    kli2 challenge verify  --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --signer "${GAR1}"    --words "${words_qar1_to_gar1}"

    print_dark_gray "Challenge: GAR2 -> QAR 2"
    words_gar1_to_qar2=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --recipient "${GAR1}" --words "${words_gar1_to_qar2}"
    kli challenge verify  --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --signer "${QAR2}"    --words "${words_gar1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> GAR1"
    words_qar2_to_gar1=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --recipient "${QAR2}" --words "${words_qar2_to_gar1}"
    kli2 challenge verify  --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --signer "${GAR1}"    --words "${words_qar2_to_gar1}"

    print_dark_gray "---Challenge responses for LE---"

    print_dark_gray "Challenge: LAR1 -> LAR2"
    words_lar1_to_lar2=$(kli challenge generate --out string)
    kli challenge respond --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --recipient "${LAR1}" --words "${words_lar1_to_lar2}"
    kli challenge verify  --name "${LAR1}" --alias "${LAR1}" --passcode "${LAR1_PASSCODE}" --signer "${LAR2}"    --words "${words_lar1_to_lar2}"

    print_dark_gray "Challenge: LAR2 -> LAR1"
    words_lar2_to_lar1=$(kli challenge generate --out string)
    kli challenge respond --name "${LAR1}" --alias "${LAR1}" --passcode "${LAR1_PASSCODE}" --recipient "${LAR2}" --words "${words_lar2_to_lar1}"
    kli challenge verify  --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --signer "${LAR1}"    --words "${words_lar2_to_lar1}"

    print_dark_gray "---Challenge responses between QAR and LE---"

    print_dark_gray "Challenge: QAR 1 -> LAR1"
    words_qar1_to_lar1=$(kli challenge generate --out string)
    kli challenge respond --name "${LAR1}" --alias "${LAR1}" --passcode "${LAR1_PASSCODE}" --recipient "${QAR1}" --words "${words_qar1_to_lar1}"
    kli2 challenge verify  --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --signer "${LAR1}"    --words "${words_qar1_to_lar1}"

    print_dark_gray "Challenge: LAR1 -> QAR 1"
    words_lar1_to_qar1=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --recipient "${LAR1}" --words "${words_lar1_to_qar1}"
    kli challenge verify  --name "${LAR1}" --alias "${LAR1}" --passcode "${LAR1_PASSCODE}" --signer "${QAR1}"    --words "${words_lar1_to_qar1}"

    print_dark_gray "Challenge: QAR 2 -> LAR2"
    words_qar2_to_lar2=$(kli challenge generate --out string)
    kli challenge respond --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --recipient "${QAR2}" --words "${words_qar2_to_lar2}"
    kli2 challenge verify  --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --signer "${LAR2}"    --words "${words_qar2_to_lar2}"

    print_dark_gray "Challenge: LAR2 -> QAR 2"
    words_lar2_to_qar2=$(kli challenge generate --out string)
    kli2 challenge respond --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --recipient "${LAR2}" --words "${words_lar2_to_qar2}"
    kli challenge verify  --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --signer "${QAR2}"    --words "${words_lar2_to_qar2}" 

    print_green "-----Finished challenge and response-----"
}
if [[ $NO_CHALLENGE ]]; then
    print_yellow "Skipping challenge and response"
else
    challenge_response
fi

# GAR: Create Multisig AID (GEDA)
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
    exists=$(kli list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | grep "${GEDA_NAME}")
    if [[ "$exists" =~ "${GEDA_NAME}" ]]; then
        print_dark_gray "[External] GEDA Multisig AID ${GEDA_NAME} already exists"
        return
    fi

    echo
    print_yellow "[External] Multisig Inception for GEDA"

    create_multisig_icp_config "${GAR1_PRE}" "${GAR2_PRE}"

    # The following multisig commands run in parallel in Docker
    print_yellow "[External] Multisig Inception from ${GAR1}: ${GAR1_PRE}"
    klid gar1 multisig incept --name ${GAR1} --alias ${GAR1} \
        --passcode ${GAR1_PASSCODE} \
        --group ${GEDA_NAME} \
        --file /config/multi-sig-incept-config.json

    echo

    klid gar2 multisig join --name ${GAR2} \
        --passcode ${GAR2_PASSCODE} \
        --group ${GEDA_NAME} \
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
    print_green "[External] GEDA Multisig AID ${GEDA_NAME} with prefix: ${ms_prefix}"
}
create_geda_multisig

# Create Multisig Legal Entity
function create_le_multisig() {
    exists=$(kli list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" | grep "${LE_NAME}")
    if [[ "$exists" =~ "${LE_NAME}" ]]; then
        print_dark_gray "[LE] LE Multisig AID ${LE_NAME} already exists"
        return
    fi

    echo
    print_yellow "[LE] Multisig Inception for LE"

    create_multisig_icp_config "${LAR1_PRE}" "${LAR2_PRE}"

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
    print_green "[LE] LE Multisig AID ${LE_NAME} with prefix: ${ms_prefix}"
}
create_le_multisig

# QAR: Resolve GEDA OOBI
function resolve_geda_oobis() {
    exists=$(kli2 contacts list --name "${QAR1}" --passcode "${QAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GEDA_NAME}")
    if [[ "$exists" =~ "${GEDA_NAME}" ]]; then
        print_yellow "GEDA OOBIs already resolved"
        return
    fi

    GEDA_OOBI=$(kli oobi generate --name "${GAR1}" --passcode "${GAR1_PASSCODE}" --alias ${GEDA_NAME} --role witness)
    echo "GEDA OOBI: ${GEDA_OOBI}"
    kli2 oobi resolve --name "${QAR1}" --oobi-alias "${GEDA_NAME}" --passcode "${QAR1_PASSCODE}" --oobi "${GEDA_OOBI}"
    kli2 oobi resolve --name "${QAR2}" --oobi-alias "${GEDA_NAME}" --passcode "${QAR2_PASSCODE}" --oobi "${GEDA_OOBI}"
}
resolve_geda_oobis

# QAR: Create delegated multisig QVI AID
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
    exists=$(kli2 list --name "${QAR1}" --passcode "${QAR1_PASSCODE}" | grep "${QVI_NAME}")
    if [[ "$exists" =~ "${QVI_NAME}" ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_NAME} already exists"
        return
    fi

    echo
    print_yellow "[QVI] delegated multisig inception from ${GEDA_NAME} | ${GEDA_PRE}"

    create_delegated_multisig_icp_config "${GEDA_PRE}" "${QAR1_PRE}" "${QAR2_PRE}" "${WAN_PRE}"

    # Follow commands run in parallel
    echo
    print_yellow "[QVI] delegated multisig inception started by ${QAR1}: ${QAR1_PRE}"

    kli2d qvi1 multisig incept --name "${QAR1}" --alias "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --group "${QVI_NAME}" \
        --file /config/multi-sig-delegated-incept-config.json

    echo

    kli2d qvi2 multisig incept --name "${QAR2}" --alias "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --group "${QVI_NAME}" \
        --file /config/multi-sig-delegated-incept-config.json

    # kli2d qvi2 multisig join --name ${QAR2} \
    #     --passcode ${QAR2_PASSCODE} \
    #     --group ${QVI_NAME} \
    #     --auto

    echo
    print_yellow "[QVI] delegated multisig Inception { ${QAR1}, ${QAR2} } - wait for signatures"
    echo

    print_lcyan "[External] GEDA members approve delegated inception with 'kli delegate confirm'"
    echo

    klid gar1 delegate confirm --name "${GAR1}" --alias "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" --interact --auto
    klid gar2 delegate confirm --name "${GAR2}" --alias "${GAR2}" \
        --passcode "${GAR2_PASSCODE}" --interact --auto

    print_dark_gray "waiting on Docker containers qvi1, qvi2, gar1, gar2"
    docker wait qvi1 qvi2 gar1 gar2
    docker logs qvi1 # show what happened
    docker logs qvi2 # show what happened
    docker logs gar1
    docker logs gar2
    docker rm qvi1 qvi2 gar1 gar2

    echo
    print_lcyan "[QVI] Show multisig status for ${QAR1}"
    kli2 status --name "${QAR1}" --alias "${QVI_NAME}" --passcode "${QAR1_PASSCODE}"
    echo

    exists=$(kli2 list --name "${QAR1}" --passcode "${QAR1_PASSCODE}" | grep "${QVI_NAME}")
    if [[ ! "$exists" =~ "${QVI_NAME}" ]]; then
        print_red "[QVI] Multisig inception failed"
        kill -SIGINT $$ # exit script and trigger TRAP above
    fi

    ms_prefix=$(kli2 status --name "${QAR1}" --alias "${QVI_NAME}" --passcode "${QAR1_PASSCODE}" | awk '/Identifier:/ {print $2}')
    print_green "[QVI] Multisig AID ${QVI_NAME} with prefix: ${ms_prefix}"
}
create_qvi_multisig

# QVI: (skip) Perform endpoint role authorizations
# QVI: Generate OOBI for QVI to send to GEDA
QVI_OOBI=$(kli2 oobi generate --name "${QAR1}" --passcode "${QAR1_PASSCODE}" --alias "${QVI_NAME}" --role witness)

# GEDA and LE: Resolve QVI OOBI
function resolve_qvi_oobi() {
    exists=$(kli contacts list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${QVI_NAME}")
    if [[ "$exists" =~ "${QVI_NAME}" ]]; then
        print_yellow "QVI OOBIs already resolved"
        return
    fi

    echo
    echo "QVI OOBI: ${QVI_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QVI_NAME}" --passcode "${GAR1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QVI_NAME}" --passcode "${GAR2_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QVI_NAME}" --passcode "${LAR1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QVI_NAME}" --passcode "${LAR2_PASSCODE}" --oobi "${QVI_OOBI}"
    # kli oobi resolve --name "${PERSON}"   --oobi-alias "${QVI_NAME}" --passcode "${PERSON_PASSCODE}"   --oobi "${QVI_OOBI}"
    echo
}
resolve_qvi_oobi
        
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
    NONCE=$(kli nonce | tr -d '[:space:]')
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
    
    echo
    print_yellow "[External] GEDA registry inception - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers gar1 and gar2"
    docker wait gar1 gar2
    docker logs gar1
    docker logs gar2
    docker rm gar1 gar2

    echo
    print_green "QVI Credential Registry created for GEDA"
    echo
}
create_geda_reg

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
prepare_qvi_cred_data

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
        print_dark_gray "[External] GEDA QVI credential already created"
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
        --data @/data/temp-data/qvi-cred-data.json \
        --rules @/data/rules/rules.json \
        --time "${KLI_TIME}"

    klid gar2 vc create \
        --name "${GAR2}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR2_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/temp-data/qvi-cred-data.json \
        --rules @/data/rules/rules.json \
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
create_qvi_credential

# GEDA: IPEX Grant QVI credential to QVI
function grant_qvi_credential() {
    QVI_GRANT_SAID=$(kli2 ipex list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --poll \
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

    echo
    print_yellow "[External] Waiting for IPEX messages to be witnessed"
    echo 
    print_dark_gray "waiting on Docker containers gar1 and gar2"
    docker wait gar1 gar2
    docker logs gar1
    docker logs gar2
    docker rm gar1 gar2

    echo
    print_green "[QVI] Polling for QVI Credential in ${QAR1}..."
    kli2 ipex list \
            --name "${QAR1}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR1_PASSCODE}" \
            --poll \
            --said | tr -d '[:space:]'
    QVI_GRANT_SAID=$?
    if [ -z "${QVI_GRANT_SAID}" ]; then
        print_red "[QVI] QVI Credential not granted - exiting"
        exit 1
    fi

    print_green "[QVI] Polling for QVI Credential in ${QAR2}..."
    kli2 ipex list \
            --name "${QAR2}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR2_PASSCODE}" \
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

# QVI: Admit QVI credential from GEDA
function admit_qvi_credential() {
    VC_SAID=$(kli2 vc list \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --said \
        --schema "${QVI_SCHEMA}")
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] QVI Credential already admitted"
        return
    fi
    SAID=$(kli2 ipex list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --poll \
        --said | tr -d '[:space:]')

    echo
    print_yellow "[QVI] ${QVI_NAME} admitting QVI Credential ${SAID} from GEDA ${GEDA_NAME}"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    kli2d qvi1 ipex admit \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" 
    
    kli2d qvi2 ipex admit \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --time "${KLI_TIME}"

    echo
    print_yellow "[QVI] Admitting QVI credential - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers gar1 and gar2"
    docker wait qvi1 qvi2
    docker logs qvi1
    docker logs qvi2
    docker rm qvi1 qvi2


    VC_SAID=$(kli2 vc list \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
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

# Create QVI credential registry
function create_qvi_reg() {
    # Check if QVI credential registry already exists
    REGISTRY=$(kli2 vc registry list \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" | awk '{print $1}')
    if [ ! -z "${REGISTRY}" ]; then
        print_dark_gray "[QVI] QVI registry already created"
        return
    fi

    echo
    print_yellow "[QVI] Creating QVI registry"
    NONCE=$(kli nonce | tr -d '[:space:]')
    kli2d qvi1 vc registry incept \
        --name ${QAR1} \
        --alias ${QVI_NAME} \
        --passcode ${QAR1_PASSCODE} \
        --usage "Credential Registry for QVI" \
        --nonce ${NONCE} \
        --registry-name ${QVI_REGISTRY} 

    kli2d qvi2 vc registry incept \
        --name ${QAR2} \
        --alias ${QVI_NAME} \
        --passcode ${QAR2_PASSCODE} \
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

# QVI OOBIs with LE
function resolve_gida_and_qvi_oobis() {
    exists=$(kli2 contacts list --name "${QAR1}" --passcode "${QAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${LE_NAME}")
    if [[ "$exists" =~ "${LE_NAME}" ]]; then
        print_yellow "LE OOBIs already resolved for QARs"
        return
    fi

    echo
    LE_OOBI=$(kli oobi generate --name ${LAR1} --passcode ${LAR1_PASSCODE} --alias ${LE_NAME} --role witness)
    echo "LE OOBI: ${LE_OOBI}"
    kli2 oobi resolve --name "${QAR1}" --oobi-alias "${LE_NAME}" --passcode "${QAR1_PASSCODE}" --oobi "${LE_OOBI}"
    kli2 oobi resolve --name "${QAR2}" --oobi-alias "${LE_NAME}" --passcode "${QAR2_PASSCODE}" --oobi "${LE_OOBI}"
    
    echo    
}
resolve_gida_and_qvi_oobis

# QVI: Prepare, create, and Issue LE credential to GEDA
# Prepare LE edge data
function prepare_qvi_edge() {
    QVI_SAID=$(kli2 vc list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
    echo "$QVI_EDGE_JSON" > ./acdc-info/temp-data/qvi-edge.json

    kli saidify --file /data/temp-data/qvi-edge.json
    
    print_lcyan "Legal Entity edge Data"
    print_lcyan "$(cat ./acdc-info/temp-data/qvi-edge.json | jq )"
}
prepare_qvi_edge

# LE: Create LE credential registry
function create_gida_reg() {
    # Check if LE credential registry already exists
    REGISTRY=$(kli vc registry list \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" | awk '{print $1}')
    if [ ! -z "${REGISTRY}" ]; then
        print_dark_gray "[LE] LE registry already created"
        return
    fi

    echo
    print_yellow "[LE] Creating LE registry"
    NONCE=$(kli nonce | tr -d '[:space:]')
    
    klid lar1 vc registry incept \
        --name ${LAR1} \
        --alias ${LE_NAME} \
        --passcode ${LAR1_PASSCODE} \
        --usage "Legal Entity Credential Registry for LE" \
        --nonce ${NONCE} \
        --registry-name ${LE_REGISTRY} 

    klid lar2 vc registry incept \
        --name ${LAR2} \
        --alias ${LE_NAME} \
        --passcode ${LAR2_PASSCODE} \
        --usage "Legal Entity Credential Registry for LE" \
        --nonce ${NONCE} \
        --registry-name ${LE_REGISTRY} 

    echo
    print_yellow "[LE] LE creating LE registry - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers lar1 and lar2"
    docker wait lar1 lar2
    docker logs lar1
    docker logs lar2
    docker rm lar1 lar2

    echo
    print_green "[LE] Legal Entity Credential Registry created for LE"
    echo
}
create_gida_reg

# Prepare LE credential data
function prepare_le_cred_data() {
    print_yellow "[QVI] Preparing LE credential data"
    read -r -d '' LE_CRED_DATA << EOM
{
    "LEI": "${LE_LEI}"
}
EOM

    echo "$LE_CRED_DATA" > ./acdc-info/temp-data/legal-entity-data.json

    print_lcyan "[QVI] Legal Entity Credential Data"
    print_lcyan "$(cat ./acdc-info/temp-data/legal-entity-data.json)"
}
prepare_le_cred_data

# Create LE credential in QVI
function create_le_credential() {
    # Check if LE credential already exists
    SAID=$(kli2 vc list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${LE_SCHEMA}" \
        --recipient "${LE_PRE}" \
        --data @/data/temp-data/legal-entity-data.json \
        --edges @/data/temp-data/qvi-edge.json \
        --rules @/data/rules/rules.json \
        --time "${KLI_TIME}" 

    kli2d qvi2 vc create \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${LE_SCHEMA}" \
        --recipient "${LE_PRE}" \
        --data @/data/temp-data/legal-entity-data.json \
        --edges @/data/temp-data/qvi-edge.json \
        --rules @/data/rules/rules.json \
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
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --type "grant" \
        --passcode "${LAR1_PASSCODE}" \
        --poll \
        --said | tr -d '[:space:]')
    if [ ! -z "${LE_GRANT_SAID}" ]; then
        print_dark_gray "[LE] LE credential already granted"
        return
    fi
    SAID=$(kli2 vc list \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --issued \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')

    echo
    print_yellow $'[QVI] IPEX GRANTing LE credential with\n\tSAID'" ${SAID}"$'\n\tto LE'" ${LE_PRE}"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    kli2d qvi1 ipex grant \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --recipient "${LE_PRE}" \
        --time "${KLI_TIME}"

    kli2d qvi2 ipex grant \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --recipient "${LE_PRE}" \
        --time "${KLI_TIME}"

    echo
    print_yellow "[QVI] granting LE credential to LE - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers qvi1 and qvi2"
    docker wait qvi1 qvi2
    docker logs qvi1    
    docker logs qvi2
    docker rm qvi1 qvi2

    echo
    print_green "[LE] Polling for LE Credential in ${LAR1}..."
    kli ipex list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | tr -d '[:space:]'
    LE_GRANT_SAID=$?
    if [ -z "${LE_GRANT_SAID}" ]; then
        print_red "LE Credential not granted"
        exit 1
    else 
        print_green "[LE] ${QVI_NAME} granted LE Credential to LE ${LAR1} SAID ${LE_GRANT_SAID}"
    fi

    print_green "[LE] Polling for LE Credential in ${LAR2}..."
    kli ipex list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | tr -d '[:space:]'
    LE_GRANT_SAID=$?
    if [ -z "${LE_GRANT_SAID}" ]; then 
        print_red "LE Credential not granted"
        exit 1
    else 
        print_green "[LE] ${QVI_NAME} granted LE Credential to LE ${LAR2} SAID ${LE_GRANT_SAID}"
    fi

    echo
    print_green "[QVI] LE Credential granted to LE"
    echo
}
grant_le_credential

# GEDA: Admit LE credential from QVI
function admit_le_credential() {
    VC_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[LE] LE Credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | tr -d '[:space:]')

    echo
    print_yellow "[LE] Admitting LE Credential ${SAID} to ${LE_NAME} as ${LAR1}"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    klid lar1 ipex admit \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" 

    print_green "[LE] Admitting LE Credential ${SAID} to ${LE_NAME} as ${LAR2}"
    klid lar2 ipex admit \
        --name "${LAR2}" \
        --passcode "${LAR2_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" 

    echo
    print_yellow "[LE] Admitting LE credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers lar1 and lar2"
    docker wait lar1 lar2
    docker logs lar1
    docker logs lar2
    docker rm lar1 lar2

    VC_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')

    if [ -z "${VC_SAID}" ]; then
        print_red "[LE] LE Credential not admitted"
        exit 1
    fi

    echo
    print_green "[LE] Admitted LE credential"
    echo
}
admit_le_credential

# GEDA: Prepare, create, and Issue ECR Auth & OOR Auth credential to QVI
# prepare LE edge to ECR auth cred
function prepare_le_edge() {
    LE_SAID=$(kli vc list \
        --name ${LAR1} \
        --alias ${LE_NAME} \
        --passcode "${LAR1_PASSCODE}" \
        --said \
        --schema ${LE_SCHEMA} | tr -d '[:space:]')
    print_bg_blue "[LE] Preparing ECR Auth cred with LE Credential SAID: ${LE_SAID}"
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
    kli saidify --file /data/temp-data/legal-entity-edge.json
    
    print_lcyan "[LE] Legal Entity edge JSON"
    print_lcyan "$(cat ./acdc-info/temp-data/legal-entity-edge.json | jq)"
}
prepare_le_edge

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
    print_lcyan "[LE] ECR Auth data JSON"
    print_lcyan "$(cat ./acdc-info/temp-data/ecr-auth-data.json)"
}
prepare_ecr_auth_data

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

    KLI_TIME=$(kli time | tr -d '[:space:]')
    
    klid lar1 vc create \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/temp-data/ecr-auth-data.json \
        --edges @/data/temp-data/legal-entity-edge.json \
        --rules @/data/rules/ecr-auth-rules.json \
        --time "${KLI_TIME}" 

    klid lar2 vc create \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/temp-data/ecr-auth-data.json \
        --edges @/data/temp-data/legal-entity-edge.json \
        --rules @/data/rules/ecr-auth-rules.json \
        --time "${KLI_TIME}" 

    echo 
    print_yellow "[LE] LE creating ECR Auth credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers lar1 and lar2"
    docker wait lar1 lar2
    docker logs lar1
    docker logs lar2
    docker rm lar1 lar2

    SAID=$(kli vc list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${ECR_AUTH_SCHEMA}" | tr -d '[:space:]')

    if [ -z "${SAID}" ]; then
        print_red "[LE] ECR Auth Credential not created"
        exit 1
    fi

    echo
    print_lcyan "[LE] LE created ECR Auth credential"
    echo
}
create_ecr_auth_credential

# Grant ECR Auth credential to QVI
function grant_ecr_auth_credential() {
    # This relies on there being only one grant in the list for the GEDA
    GRANT_COUNT=$(kli2 ipex list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --type "grant" \
        --passcode "${QAR1_PASSCODE}" \
        --poll \
        --said | wc -l | tr -d ' ') # get the last grant
    if [ "${GRANT_COUNT}" -ge 2 ]; then
        print_dark_gray "[QVI] ECR Auth credential grant already received"
        return
    fi
    SAID=$(kli vc list \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --issued \
        --said \
        --schema "${ECR_AUTH_SCHEMA}" | tr -d '[:space:]')

    echo
    print_yellow $'[LE] IPEX GRANTing ECR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI '"${QVI_PRE}"

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

    echo
    print_yellow "[LE] Granting ECR Auth credential to QVI - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers lar1 and lar2"
    docker wait lar1 lar2
    docker logs lar1
    docker logs lar2
    docker rm lar1 lar2

    echo
    print_green "[QVI] Polling for ECR Auth Credential in ${QAR1}..."
    kli2 ipex list \
            --name "${QAR1}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR1_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    print_green "[QVI] Polling for ECR Auth Credential in ${QAR2}..."
    kli2 ipex list \
            --name "${QAR2}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR2_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    echo
    print_green "[LE] ECR Auth Credential granted to QVI"
    echo
}
grant_ecr_auth_credential

# Admit ECR Auth credential from LE
function admit_ecr_auth_credential() {
    VC_SAID=$(kli2 vc list \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --said \
        --schema "${ECR_AUTH_SCHEMA}" | tr -d '[:space:]')
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] ECR Auth Credential already admitted"
        return
    fi
    SAID=$(kli2 ipex list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | \
        tail -1 | tr -d '[:space:]') # get the last grant, which should be the ECR Auth credential

    echo
    print_yellow "[QVI] Admitting ECR Auth Credential ${SAID} from LE"

    KLI_TIME=$(kli time | tr -d '[:space:]') # Use consistent time so SAID of grant is same
    kli2d qvi1 ipex admit \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" 

    print_green "[QVI] Admitting ECR Auth Credential as ${QVI_NAME} from LE"
    kli2d qvi2 ipex admit \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --alias "${QVI_NAME}" \
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
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
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
    print_lcyan "[LE] OOR Auth data JSON"
    print_lcyan "$(cat ./acdc-info/temp-data/oor-auth-data.json)"
}
prepare_oor_auth_data

# Create OOR Auth credential
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

    echo
    print_green "[LE] LE creating OOR Auth credential"

    KLI_TIME=$(kli time | tr -d '[:space:]')
    klid lar1 vc create \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${OOR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/temp-data/oor-auth-data.json \
        --edges @/data/temp-data/legal-entity-edge.json \
        --rules @/data/rules/rules.json \
        --time "${KLI_TIME}" 

    klid lar2 vc create \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${OOR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/temp-data/oor-auth-data.json \
        --edges @/data/temp-data/legal-entity-edge.json \
        --rules @/data/rules/rules.json \
        --time "${KLI_TIME}" 

    echo 
    print_yellow "[LE] LE creating OOR Auth credential - wait for signatures"
    echo 
    print_dark_gray "waiting on Docker containers lar1 and lar2"
    docker wait lar1 lar2
    docker logs lar1
    docker logs lar2
    docker rm lar1 lar2

    SAID=$(kli vc list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${OOR_AUTH_SCHEMA}" | tr -d '[:space:]')
    if [ -z "${SAID}" ]; then
        print_red "[LE] OOR Auth Credential not created"
        exit 1
    fi

    echo
    print_lcyan "[LE] LE created OOR Auth credential"
    echo
}
create_oor_auth_credential

# Grant OOR Auth credential to QVI
function grant_oor_auth_credential() {
    # This relies on the last grant being the OOR Auth credential
    GRANT_COUNT=$(kli2 ipex list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --type "grant" \
        --passcode "${QAR1_PASSCODE}" \
        --poll \
        --said | wc -l | tr -d ' ') # get grant count, remove whitespace
    if [ "${GRANT_COUNT}" -ge 3 ]; then
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

    echo
    print_yellow "[LE] Granting OOR Auth credential to QVI - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers lar1 and lar2"
    docker wait lar1 lar2
    docker logs lar1
    docker logs lar2
    docker rm lar1 lar2


    echo
    print_green "[QVI] Polling for OOR Auth Credential in ${QAR1}..."
    kli2 ipex list \
            --name "${QAR1}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR1_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    print_green "[QVI] Polling for OOR Auth Credential in ${QAR2}..."
    kli2 ipex list \
            --name "${QAR2}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR2_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    echo
    print_green "[LE] Granted OOR Auth credential to QVI"
    echo
}
grant_oor_auth_credential

# QVI: Admit OOR Auth credential
function admit_oor_auth_credential() {
    VC_SAID=$(kli2 vc list \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --said \
        --schema ${OOR_AUTH_SCHEMA} | tr -d '[:space:]')
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] OOR Auth Credential already admitted"
        return
    fi
    SAID=$(kli2 ipex list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | \
        tail -1 | tr -d '[:space:]') # get the last grant, which should be the ECR Auth credential

    echo
    print_yellow "[QVI] Admitting OOR Auth Credential ${SAID} from LE"

    KLI_TIME=$(kli time | tr -d '[:space:]') # Use consistent time so SAID of grant is same
    kli2d qvi1 ipex admit \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --time "${KLI_TIME}"

    print_green "[QVI] Admitting OOR Auth Credential as ${QVI_NAME} from LE"
    kli2d qvi2 ipex admit \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --alias "${QVI_NAME}" \
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
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
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

# QVI: Create and Issue ECR credential to Person
# Prepare ECR Auth edge data
function prepare_ecr_auth_edge() {
    ECR_AUTH_SAID=$(kli2 vc list \
        --name ${QAR1} \
        --alias ${QVI_NAME} \
        --passcode "${QAR1_PASSCODE}" \
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

    kli saidify --file /data/temp-data/ecr-auth-edge.json
    
    print_lcyan "[QVI] ECR Auth edge Data"
    print_lcyan "$(cat ./acdc-info/temp-data/ecr-auth-edge.json | jq )"
}
prepare_ecr_auth_edge

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

    print_lcyan "[QVI] ECR Credential Data"
    print_lcyan "$(cat ./acdc-info/temp-data/ecr-data.json)"
}
prepare_ecr_cred_data

# Create ECR credential in QVI, issued to the Person
function create_ecr_credential() {
    # Check if ECR credential already exists
    SAID=$(kli2 vc list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --private-credential-nonce "${CRED_NONCE}" \
        --private-subject-nonce "${SUBJ_NONCE}" \
        --private \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${ECR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @/data/temp-data/ecr-data.json \
        --edges @/data/temp-data/ecr-auth-edge.json \
        --rules @/data/rules/ecr-rules.json \
        --time "${KLI_TIME}"

    kli2d qvi2 vc create \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --private \
        --private-credential-nonce "${CRED_NONCE}" \
        --private-subject-nonce "${SUBJ_NONCE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${ECR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @/data/temp-data/ecr-data.json \
        --edges @/data/temp-data/ecr-auth-edge.json \
        --rules @/data/rules/ecr-rules.json \
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
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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

# QVI Grant ECR credential to PERSON
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
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --issued \
        --said \
        --schema ${ECR_SCHEMA} | tr -d '[:space:]')

    echo
    print_yellow $'[QVI] IPEX GRANTing ECR credential with\n\tSAID'" ${SAID}"$'\n\tto'" ${PERSON} ${PERSON_PRE}"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    kli2d qvi1 ipex grant \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" \
        --time "${KLI_TIME}"

    kli2d qvi2 ipex grant \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --alias "${QVI_NAME}" \
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

#  Person: Admit ECR credential from QVI
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

# QVI: Issue, grant OOR to Person and Person admits OOR
# Prepare OOR Auth edge data
function prepare_oor_auth_edge() {
    OOR_AUTH_SAID=$(kli2 vc list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
    echo "$OOR_AUTH_EDGE_JSON" > ./acdc-info/temp-data/oor-auth-edge.json

    kli saidify --file /data/temp-data/oor-auth-edge.json
    
    print_lcyan "[QVI] OOR Auth edge Data"
    print_lcyan "$(cat ./acdc-info/temp-data/oor-auth-edge.json | jq )"
}
prepare_oor_auth_edge      

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

    print_lcyan "[QVI] OOR Credential Data"
    print_lcyan "$(cat ./acdc-info/temp-data/oor-data.json)"
}
prepare_oor_cred_data

# Create OOR credential in QVI, issued to the Person
function create_oor_credential() {
    # Check if OOR credential already exists
    SAID=$(kli2 vc list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${OOR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @/data/temp-data/oor-data.json \
        --edges @/data/temp-data/oor-auth-edge.json \
        --rules @/data/rules/oor-rules.json \
        --time "${KLI_TIME}" 

    kli2d qvi2 vc create \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${OOR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @/data/temp-data/oor-data.json \
        --edges @/data/temp-data/oor-auth-edge.json \
        --rules @/data/rules/oor-rules.json \
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


# QVI Grant OOR credential to PERSON
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
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --issued \
        --said \
        --schema ${OOR_SCHEMA} | tr -d '[:space:]')

    echo
    print_yellow $'[QVI] IPEX GRANTing OOR credential with\n\tSAID'" ${SAID}"$'\n\tto'" ${PERSON} ${PERSON_PRE}"
    KLI_TIME=$(kli time | tr -d '[:space:]')
    kli2d qvi1 ipex grant \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" \
        --time "${KLI_TIME}"

    kli2d qvi2 ipex grant \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --alias "${QVI_NAME}" \
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

# Person: Admit OOR credential from QVI
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

# QVI: Present issued ECR Auth and OOR Auth to Sally (vLEI Reporting API)
function present_le_cred_to_sally() {
    print_yellow "[QVI] Presenting LE Credential to Sally"
    LE_SAID=$(kli vc list --name ${LAR1} \
        --alias ${LE_NAME} \
        --passcode "${LAR1_PASSCODE}" \
        --said --schema ${LE_SCHEMA})

    PID_LIST=""
    klid qar1 ipex grant \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --said "${LE_SAID}" \
        --recipient "${SALLY}"

    kli ipex join \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --auto

    echo
    print_yellow "[QVI] Presenting LE Credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker containers qar1 and qar2"
    docker wait qar1 qar2
    docker logs qar1
    docker logs qar2
    docker rm qar1 qar2

    sleep 30
    print_green "[QVI] LE Credential presented to Sally"
}
present_le_cred_to_sally

cleanup
print_lcyan "Full chain workflow completed"

# TODO:
# QVI: Revoke ECR Auth and OOR Auth credentials
# QVI: Present revoked credentials to Sally
