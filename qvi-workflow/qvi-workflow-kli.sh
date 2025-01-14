#!/usr/bin/env bash
# qvi-workflow-kli.sh
# Runs the entire QVI issuance workflow end to end starting from multisig AID creatin including the
# GLEIF External Delegated AID (GEDA) creation all the way to OOR and ECR credential issuance to the
# Person AID for usage in the iXBRL data attestation.
#
# Note:
# This is designed to work with a local installation of the necessary components.
# This script uses only KERIpy keystores for all participants.
# It does not use KERIA or SignifyTS for the QVI and Person AIDs, rather it uses KERIpy.
#
# To run this script you need to run the following command in a separate terminals:
#   > kli witness demo
# and from the vLEI repo run:
#   > vLEI-server -s ./schema/acdc -c ./samples/acdc/ -o ./samples/oobis/
# This script runs the "sally" program so it must be installed and available on the path
# in order to complete successfully. This script also runs the webhook with "sally hook demo" that
# Sally sends a webhook call to.


trap cleanup INT
function cleanup() {
    # Triggered on Control + C, cleans up resources the script uses
    echo
    print_red "Caught Ctrl+C, Exiting script..."
    exit 0
}

source ./script-utils.sh
echo
print_bg_blue "------------------------------vLEI QVI Workflow Script (KLI)------------------------------"
echo

# 1. GAR: Prepare environment
KEYSTORE_DIR=${1:-$HOME/.keri}
print_yellow "KEYSTORE_DIR: ${KEYSTORE_DIR}"

CONFIG_DIR=./config
DATA_DIR=./data
INIT_CFG=qvi-workflow-init-config-dev-local.json
WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
WIT_HOST=http://127.0.0.1:5642
SCHEMA_SERVER=http://127.0.0.1:7723


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

function test_dependencies() {
  # check that sally is installed and available on the PATH
  command -v kli >/dev/null 2>&1 || { print_red "kli is not installed or not available on the PATH. Aborting."; exit 1; }
  command -v tsx >/dev/null 2>&1 || { print_red "tsx is not installed or not available on the PATH. Aborting."; exit 1; }
  command -v jq >/dev/null 2>&1 || { print_red "jq is not installed or not available on the PATH. Aborting."; exit 1; }
  command -v sally >/dev/null 2>&1 || { print_red "sally is not installed or not available on the PATH. Aborting."; exit 1; }

  curl ${WIT_HOST}/oobi/${WAN_PRE} >/dev/null 2>&1
    status=$?
    if [ $status -ne 0 ]; then
        print_red "Witness server not running at ${WIT_HOST}"
        cleanup
    fi

    curl ${SCHEMA_SERVER}/oobi/${QVI_SCHEMA} >/dev/null 2>&1
    status=$?
    if [ $status -ne 0 ]; then
        print_red "Schema server not running at ${SCHEMA_SERVER}"
        cleanup
    fi
}
test_dependencies
# functions
temp_icp_config=""
function create_temp_icp_cfg() {
    read -r -d '' ICP_CONFIG_JSON << EOM
{
  "transferable": true,
  "wits": ["$WAN_PRE"],
  "toad": 1,
  "icount": 1,
  "ncount": 1,
  "isith": "1",
  "nsith": "1"
}
EOM
    print_lcyan "Using temporary AID config file heredoc:"
    print_lcyan "${ICP_CONFIG_JSON}"

    # create temporary file to store json
    temp_icp_config=$(mktemp)

    # write JSON content to the temp file
    echo "$ICP_CONFIG_JSON" > "$temp_icp_config"
}

# creates a single sig AID
function create_aid() {
    NAME=$1
    SALT=$2
    PASSCODE=$3
    CONFIG_DIR=$4
    CONFIG_FILE=$5
    ICP_FILE=$6

    # Check if exists
    exists=$(kli list --name "${NAME}" --passcode "${PASSCODE}")
    if [[ ! "$exists" =~ "Keystore must already exist" ]]; then
        print_dark_gray "AID ${NAME} already exists"
        return
    fi

    kli init \
        --name "${NAME}" \
        --salt "${SALT}" \
        --passcode "${PASSCODE}" \
        --config-dir "${CONFIG_DIR}" \
        --config-file "${CONFIG_FILE}" >/dev/null 2>&1
    kli incept \
        --name "${NAME}" \
        --alias "${NAME}" \
        --passcode "${PASSCODE}" \
        --file "${ICP_FILE}" >/dev/null 2>&1
    PREFIX=$(kli status  --name "${NAME}"  --alias "${NAME}"  --passcode "${PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )
    # Need this since resolving with bootstrap config file isn't working
    print_dark_gray "Created AID: ${NAME} with prefix: ${PREFIX}"
    print_green $'\tPrefix:'" ${PREFIX}"
    resolve_credential_oobis "${NAME}" "${PASSCODE}"    
}

function resolve_credential_oobis() {
    # Need this function because for some reason resolving more than 8 OOBIs with the bootstrap config file doesn't work
    NAME=$1
    PASSCODE=$2
    print_dark_gray "Resolving credential OOBIs for ${NAME}"
    # LE
    kli oobi resolve \
        --name "${NAME}" \
        --passcode "${PASSCODE}" \
        --oobi "${SCHEMA_SERVER}/oobi/${LE_SCHEMA}" >/dev/null 2>&1
    # LE ECR
    kli oobi resolve \
        --name "${NAME}" \
        --passcode "${PASSCODE}" \
        --oobi "${SCHEMA_SERVER}/oobi/${ECR_SCHEMA}" >/dev/null 2>&1
}

# 2. GAR: Create single Sig AIDs (2)
function create_aids() {
    print_green "-----Creating AIDs-----"
    create_temp_icp_cfg
    create_aid "${GEDA_PT1}" "${GEDA_PT1_SALT}" "${GEDA_PT1_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${GEDA_PT2}" "${GEDA_PT2_SALT}" "${GEDA_PT2_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${GIDA_PT1}" "${GIDA_PT1_SALT}" "${GIDA_PT1_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${GIDA_PT2}" "${GIDA_PT2_SALT}" "${GIDA_PT2_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${QAR_PT1}"  "${QAR_PT1_SALT}"  "${QAR_PT1_PASSCODE}"  "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${QAR_PT2}"  "${QAR_PT2_SALT}"  "${QAR_PT2_PASSCODE}"  "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${PERSON}"   "${PERSON_SALT}"   "${PERSON_PASSCODE}"   "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${SALLY}"    "${SALLY_SALT}"    "${SALLY_PASSCODE}"    "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    rm "$temp_icp_config"
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
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${PERSON}"   --passcode "${GEDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GIDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GIDA_PT2}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for GEDA 2"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GEDA_PT1}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT2}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT1}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${PERSON}"   --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GIDA_PT1}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GIDA_PT2}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"

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
    kli oobi resolve --name "${QAR_PT1}" --oobi-alias "${QAR_PT2}"   --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${QAR_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT1}" --oobi-alias "${GEDA_PT1}"  --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT1}" --oobi-alias "${GEDA_PT2}"  --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT1}" --oobi-alias "${PERSON}"    --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT1}" --oobi-alias "${GIDA_PT1}"  --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT1}" --oobi-alias "${GIDA_PT2}"  --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT1}" --oobi-alias "$SALLY"       --passcode "${QAR_PT1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for QAR 2"
    kli oobi resolve --name "${QAR_PT2}" --oobi-alias "${QAR_PT1}"   --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${QAR_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT2}" --oobi-alias "${GEDA_PT2}"  --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT2}" --oobi-alias "${GEDA_PT1}"  --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT2}" --oobi-alias "${PERSON}"    --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT2}" --oobi-alias "${GIDA_PT1}"  --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT2}" --oobi-alias "${GIDA_PT2}"  --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR_PT2}" --oobi-alias "$SALLY"       --passcode "${QAR_PT2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for Person"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${QAR_PT1}"   --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${QAR_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${QAR_PT2}"   --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${QAR_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${GEDA_PT1}"  --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${GEDA_PT2}"  --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${GIDA_PT1}"  --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${GIDA_PT2}"  --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    
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
    kli challenge respond --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --recipient "${QAR_PT1}" --words "${words_qar1_to_qar2}"
    kli challenge verify  --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --signer "${QAR_PT2}"    --words "${words_qar1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> QAR 1"
    words_qar2_to_qar1=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --recipient "${QAR_PT2}" --words "${words_qar2_to_qar1}"
    kli challenge verify  --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --signer "${QAR_PT1}"    --words "${words_qar2_to_qar1}"

    print_dark_gray "---Challenge responses between GEDA and QAR---"
    
    print_dark_gray "Challenge: GEDA 1 -> QAR 1"
    words_geda1_to_qar1=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --recipient "${GEDA_PT1}" --words "${words_geda1_to_qar1}"
    kli challenge verify  --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --signer "${QAR_PT1}"    --words "${words_geda1_to_qar1}"

    print_dark_gray "Challenge: QAR 1 -> GEDA 1"
    words_qar1_to_geda1=$(kli challenge generate --out string)
    kli challenge respond --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --recipient "${QAR_PT1}" --words "${words_qar1_to_geda1}"
    kli challenge verify  --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --signer "${GEDA_PT1}"    --words "${words_qar1_to_geda1}"

    print_dark_gray "Challenge: GEDA 2 -> QAR 2"
    words_geda1_to_qar2=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --recipient "${GEDA_PT1}" --words "${words_geda1_to_qar2}"
    kli challenge verify  --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --signer "${QAR_PT2}"    --words "${words_geda1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> GEDA 1"
    words_qar2_to_geda1=$(kli challenge generate --out string)
    kli challenge respond --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --recipient "${QAR_PT2}" --words "${words_qar2_to_geda1}"
    kli challenge verify  --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --signer "${GEDA_PT1}"    --words "${words_qar2_to_geda1}"

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
    kli challenge verify  --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --signer "${GIDA_PT1}"    --words "${words_qar1_to_gida1}"

    print_dark_gray "Challenge: GIDA 1 -> QAR 1"
    words_gida1_to_qar1=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --recipient "${GIDA_PT1}" --words "${words_gida1_to_qar1}"
    kli challenge verify  --name "${GIDA_PT1}" --alias "${GIDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" --signer "${QAR_PT1}"    --words "${words_gida1_to_qar1}"

    print_dark_gray "Challenge: QAR 2 -> GIDA 2"
    words_qar2_to_gida2=$(kli challenge generate --out string)
    kli challenge respond --name "${GIDA_PT2}" --alias "${GIDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --recipient "${QAR_PT2}" --words "${words_qar2_to_gida2}"
    kli challenge verify  --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --signer "${GIDA_PT2}"    --words "${words_qar2_to_gida2}"

    print_dark_gray "Challenge: GIDA 2 -> QAR 2"
    words_gida2_to_qar2=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --recipient "${GIDA_PT2}" --words "${words_gida2_to_qar2}"
    kli challenge verify  --name "${GIDA_PT2}" --alias "${GIDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --signer "${QAR_PT2}"    --words "${words_gida2_to_qar2}" 

    print_green "-----Finished challenge and response-----"
}
challenge_response

# 4. GAR: Create Multisig AID (GEDA)
function create_geda_multisig() {
    exists=$(kli list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | grep "${GEDA_MS}")
    if [[ "$exists" =~ "${GEDA_MS}" ]]; then
        print_dark_gray "[External] GEDA Multisig AID ${GEDA_MS} already exists"
        return
    fi

    echo
    print_yellow "[External] Multisig Inception for GEDA"

    echo
    read -r -d '' MULTISIG_ICP_CONFIG_JSON << EOM
{
  "aids": [
    "${GEDA_PT1_PRE}",
    "${GEDA_PT2_PRE}"
  ],
  "transferable": true,
  "wits": ["${WAN_PRE}"],
  "toad": 1,
  "isith": "2",
  "nsith": "2"
}
EOM

    print_lcyan "[External] multisig inception config:"
    print_lcyan "${MULTISIG_ICP_CONFIG_JSON}"

    # create temporary file to store json
    temp_multisig_config=$(mktemp)

    # write JSON content to the temp file
    echo "$MULTISIG_ICP_CONFIG_JSON" > "$temp_multisig_config"

    # The following multisig commands run in parallel
    print_yellow "[External] Multisig Inception from ${GEDA_PT1}: ${GEDA_PT1_PRE}"
    kli multisig incept --name ${GEDA_PT1} --alias ${GEDA_PT1} \
        --passcode ${GEDA_PT1_PASSCODE} \
        --group ${GEDA_MS} \
        --file "${temp_multisig_config}" &
    pid=$!
    PID_LIST+=" $pid"

    echo

    kli multisig join --name ${GEDA_PT2} \
        --passcode ${GEDA_PT2_PASSCODE} \
        --group ${GEDA_MS} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    echo
    print_yellow "[External] Multisig Inception { ${GEDA_PT1}, ${GEDA_PT2} } - wait for signatures"
    echo
    wait $PID_LIST

    exists=$(kli list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | grep "${GEDA_MS}")
    if [[ ! "$exists" =~ "${GEDA_MS}" ]]; then
        print_red "[External] GEDA Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name ${GEDA_PT1} --alias ${GEDA_MS} --passcode ${GEDA_PT1_PASSCODE} | awk '/Identifier:/ {print $2}')
    print_green "[External] GEDA Multisig AID ${GEDA_MS} with prefix: ${ms_prefix}"

    rm "$temp_multisig_config"

    touch $HOME/.keri/full-chain-geda-ms
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

    echo
    print_yellow "[Internal] Multisig Inception temp config file."
    read -r -d '' MULTISIG_ICP_CONFIG_JSON << EOM
{
  "aids": [
    "${GIDA_PT1_PRE}",
    "${GIDA_PT2_PRE}"
  ],
  "transferable": true,
  "wits": ["${WAN_PRE}"],
  "toad": 1,
  "isith": "2",
  "nsith": "2"
}
EOM

    print_lcyan "[Internal] Using temporary multisig config file as heredoc:"
    print_lcyan "${MULTISIG_ICP_CONFIG_JSON}"

    # create temporary file to store json
    temp_multisig_config=$(mktemp)

    # write JSON content to the temp file
    echo "$MULTISIG_ICP_CONFIG_JSON" > "$temp_multisig_config"

    # Follow commands run in parallel
    print_yellow "[Internal] Multisig Inception from ${GIDA_PT1}: ${GIDA_PT1_PRE}"
    kli multisig incept --name ${GIDA_PT1} --alias ${GIDA_PT1} \
        --passcode ${GIDA_PT1_PASSCODE} \
        --group ${GIDA_MS} \
        --file "${temp_multisig_config}" &
    pid=$!
    PID_LIST+=" $pid"

    echo

    kli multisig join --name ${GIDA_PT2} \
        --passcode ${GIDA_PT2_PASSCODE} \
        --group ${GIDA_MS} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    echo
    print_yellow "[Internal] Multisig Inception { ${GIDA_PT1}, ${GIDA_PT2} } - wait for signatures"
    echo
    wait $PID_LIST

    exists=$(kli list --name "${GIDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" | grep "${GIDA_MS}")
    if [[ ! "$exists" =~ "${GIDA_MS}" ]]; then
        print_red "[Internal] GIDA Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name ${GIDA_PT1} --alias ${GIDA_MS} --passcode ${GIDA_PT1_PASSCODE} | awk '/Identifier:/ {print $2}')
    print_green "[Internal] GIDA Multisig AID ${GIDA_MS} with prefix: ${ms_prefix}"

    rm "$temp_multisig_config"

    touch $HOME/.keri/full-chain-gida-ms
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
    exists=$(kli contacts list --name "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GEDA_MS}")
    if [[ "$exists" =~ "${GEDA_MS}" ]]; then
        print_yellow "GEDA OOBIs already resolved"
        return
    fi

    GEDA_OOBI=$(kli oobi generate --name ${GEDA_PT1} --passcode ${GEDA_PT1_PASSCODE} --alias ${GEDA_MS} --role witness)
    echo "GEDA OOBI: ${GEDA_OOBI}"
    kli oobi resolve --name "${QAR_PT1}" --oobi-alias "${GEDA_MS}" --passcode "${QAR_PT1_PASSCODE}" --oobi "${GEDA_OOBI}"
    kli oobi resolve --name "${QAR_PT2}" --oobi-alias "${GEDA_MS}" --passcode "${QAR_PT2_PASSCODE}" --oobi "${GEDA_OOBI}"
}
resolve_geda_oobis

# 10. QAR: Create delegated multisig QVI AID
# 11. QVI: Create delegated AID with GEDA as delegator
# 12. GEDA: delegate to QVI
function create_qvi_multisig() {
    exists=$(kli list --name "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" | grep "${QVI_MS}")
    if [[ "$exists" =~ "${QVI_MS}" ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_MS} already exists"
        return
    fi

    echo
    print_yellow "[QVI] delegated multisig inception from ${GEDA_MS} | ${GEDA_PRE}"

    echo
    read -r -d '' MULTISIG_ICP_CONFIG_JSON << EOM
{
  "delpre": "${GEDA_PRE}",
  "aids": [
    "${QAR_PT1_PRE}",
    "${QAR_PT2_PRE}"
  ],
  "transferable": true,
  "wits": ["${WAN_PRE}"],
  "toad": 1,
  "isith": "2",
  "nsith": "2"
}
EOM

    print_lcyan "[QVI] delegated multisig inception config"
    print_lcyan "${MULTISIG_ICP_CONFIG_JSON}"

    # create temporary file to store json
    temp_multisig_config=$(mktemp)

    # write JSON content to the temp file
    echo "$MULTISIG_ICP_CONFIG_JSON" > "$temp_multisig_config"

    # Follow commands run in parallel
    echo
    print_yellow "[QVI] delegated multisig inception started by ${QAR_PT1}: ${QAR_PT1_PRE}"

    PID_LIST=""
    kli multisig incept --name ${QAR_PT1} --alias ${QAR_PT1} \
        --passcode ${QAR_PT1_PASSCODE} \
        --group ${QVI_MS} \
        --file "${temp_multisig_config}" &
    pid=$!
    PID_LIST+=" $pid"

    echo

    kli multisig incept --name ${QAR_PT2} --alias ${QAR_PT2} \
        --passcode ${QAR_PT2_PASSCODE} \
        --group ${QVI_MS} \
        --file "${temp_multisig_config}" &
    pid=$!
    PID_LIST+=" $pid"

    echo
    print_yellow "[QVI] delegated multisig Inception { ${QAR_PT1}, ${QAR_PT2} } - wait for signatures"
    sleep 5
    echo

    exists=$(kli list --name "${QAR_PT1} --passcode ${QAR_PT1_PASSCODE}" | grep "${QVI_MS}")
    if [ ! $exists == "*${QVI_MS}*" ]; then
        print_red "[QVI] Multisig inception failed"
        exit 1
    fi

    print_lcyan "[External] GEDA members approve delegated inception with 'kli delegate confirm'"
    echo

    kli delegate confirm --name ${GEDA_PT1} --alias ${GEDA_PT1} --passcode ${GEDA_PT1_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"
    
    kli delegate confirm --name ${GEDA_PT2} --alias ${GEDA_PT2} --passcode ${GEDA_PT2_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    rm "$temp_multisig_config"

    echo
    print_lcyan "[QVI] Show multisig status for ${QAR_PT1}"
    kli status --name ${QAR_PT1} --alias ${QVI_MS} --passcode ${QAR_PT1_PASSCODE}
    echo

    ms_prefix=$(kli status --name ${QAR_PT1} --alias ${QVI_MS} --passcode ${QAR_PT1_PASSCODE} | awk '/Identifier:/ {print $2}')
    print_green "[QVI] Multisig AID ${QVI_MS} with prefix: ${ms_prefix}"
}
create_qvi_multisig

# 13. QVI: (skip) Perform endpoint role authorizations

# 14. QVI: Generate OOBI for QVI to send to GEDA
QVI_OOBI=$(kli oobi generate --name ${QAR_PT1} --passcode ${QAR_PT1_PASSCODE} --alias ${QVI_MS} --role witness)

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
    kli oobi resolve --name "${PERSON}"   --oobi-alias "${QVI_MS}" --passcode "${PERSON_PASSCODE}"   --oobi "${QVI_OOBI}"
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
    NONCE=$(kli nonce)
    PID_LIST=""
    kli vc registry incept \
        --name ${GEDA_PT1} \
        --alias ${GEDA_MS} \
        --passcode ${GEDA_PT1_PASSCODE} \
        --usage "QVI Credential Registry for GEDA" \
        --nonce ${NONCE} \
        --registry-name ${GEDA_REGISTRY} &
    pid=$!
    PID_LIST+=" $pid"

    kli vc registry incept \
        --name ${GEDA_PT2} \
        --alias ${GEDA_MS} \
        --passcode ${GEDA_PT2_PASSCODE} \
        --usage "QVI Credential Registry for GEDA" \
        --nonce ${NONCE} \
        --registry-name ${GEDA_REGISTRY} & 
    pid=$!
    PID_LIST+=" $pid"
    wait $PID_LIST

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

    echo "$QVI_CRED_DATA" > ./qvi-cred-data.json

    print_lcyan "QVI Credential Data"
    print_lcyan "$(cat ./qvi-cred-data.json)"
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
    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name ${GEDA_PT1} \
        --alias ${GEDA_MS} \
        --passcode ${GEDA_PT1_PASSCODE} \
        --registry-name ${GEDA_REGISTRY} \
        --schema "${QVI_SCHEMA}" \
        --recipient ${QVI_PRE} \
        --data @./qvi-cred-data.json \
        --rules @./rules.json \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name ${GEDA_PT2} \
        --alias ${GEDA_MS} \
        --passcode ${GEDA_PT2_PASSCODE} \
        --registry-name ${GEDA_REGISTRY} \
        --schema "${QVI_SCHEMA}" \
        --recipient ${QVI_PRE} \
        --data @./qvi-cred-data.json \
        --rules @./rules.json \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_lcyan "[External] QVI Credential created for GEDA"
    echo
}
create_qvi_credential

# 17. GEDA: IPEX Grant QVI credential to QVI
function grant_qvi_credential() {
    QVI_GRANT_SAID=$(kli ipex list \
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
        --schema "${QVI_SCHEMA}")

    echo
    print_yellow $'[External] IPEX GRANTing QVI credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"
    KLI_TIME=$(kli time)
    kli ipex grant \
        --name ${GEDA_PT1} \
        --passcode ${GEDA_PT1_PASSCODE} \
        --alias ${GEDA_MS} \
        --said ${SAID} \
        --recipient ${QVI_PRE} \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name ${GEDA_PT2} \
        --passcode ${GEDA_PT2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[External] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "[QVI] Polling for QVI Credential in ${QAR_PT1}..."
    kli ipex list \
            --name "${QAR_PT1}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT1_PASSCODE}" \
            --poll \
            --said
    QVI_GRANT_SAID=$?
    if [ -z "${QVI_GRANT_SAID}" ]; then
        print_red "[QVI] QVI Credential not granted - exiting"
        exit 1
    fi

    print_green "[QVI] Polling for QVI Credential in ${QAR_PT2}..."
    kli ipex list \
            --name "${QAR_PT2}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT2_PASSCODE}" \
            --poll \
            --said
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
    VC_SAID=$(kli vc list \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --said \
        --schema "${QVI_SCHEMA}")
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] QVI Credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --poll \
        --said)

    echo
    print_yellow "[QVI] Admitting QVI Credential ${SAID} from GEDA"

    KLI_TIME=$(kli time)
    kli ipex admit \
        --name ${QAR_PT1} \
        --passcode ${QAR_PT1_PASSCODE} \
        --alias ${QVI_MS} \
        --said ${SAID} \
        --time "${KLI_TIME}" & 
    pid=$!
    PID_LIST+=" $pid"

    print_green "[QVI] Admitting QVI Credential as ${QVI_MS} from GEDA"
    kli ipex join \
        --name ${QAR_PT2} \
        --passcode ${QAR_PT2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_green "[QVI] Admitted QVI credential"
    echo
}
admit_qvi_credential

# 18.5 Create QVI credential registry
function create_qvi_reg() {
    # Check if QVI credential registry already exists
    REGISTRY=$(kli vc registry list \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" | awk '{print $1}')
    if [ ! -z "${REGISTRY}" ]; then
        print_dark_gray "[QVI] QVI registry already created"
        return
    fi

    echo
    print_yellow "[QVI] Creating QVI registry"
    NONCE=$(kli nonce)
    PID_LIST=""
    kli vc registry incept \
        --name ${QAR_PT1} \
        --alias ${QVI_MS} \
        --passcode ${QAR_PT1_PASSCODE} \
        --usage "Credential Registry for QVI" \
        --nonce ${NONCE} \
        --registry-name ${QVI_REGISTRY} &
    pid=$!
    PID_LIST+=" $pid"

    kli vc registry incept \
        --name ${QAR_PT2} \
        --alias ${QVI_MS} \
        --passcode ${QAR_PT2_PASSCODE} \
        --usage "Credential Registry for QVI" \
        --nonce ${NONCE} \
        --registry-name ${QVI_REGISTRY} & 
    pid=$!
    PID_LIST+=" $pid"
    wait $PID_LIST

    echo
    print_green "[QVI] Credential Registry created for QVI"
    echo
}
create_qvi_reg

# 18.6 QVI OOBIs with GIDA
function resolve_gida_and_qvi_oobis() {
    if test -f $HOME/.keri/full-chain-gida-qvi-oobi; then
        print_dark_gray "GIDA and QVI OOBIs already resolved"
        return
    fi

    echo
    GIDA_OOBI=$(kli oobi generate --name ${GIDA_PT1} --passcode ${GIDA_PT1_PASSCODE} --alias ${GIDA_MS} --role witness)
    echo "GIDA OOBI: ${GIDA_OOBI}"
    kli oobi resolve --name "${QAR_PT1}" --oobi-alias "${GIDA_MS}" --passcode "${QAR_PT1_PASSCODE}" --oobi "${GIDA_OOBI}"
    kli oobi resolve --name "${QAR_PT2}" --oobi-alias "${GIDA_MS}" --passcode "${QAR_PT2_PASSCODE}" --oobi "${GIDA_OOBI}"
    
    echo

    touch $HOME/.keri/full-chain-gida-qvi-oobi
}
resolve_gida_and_qvi_oobis

# 19. QVI: Prepare, create, and Issue LE credential to GEDA

# 19.1 Prepare LE edge data
function prepare_qvi_edge() {
    QVI_SAID=$(kli vc list \
        --name ${QAR_PT1} \
        --alias ${QVI_MS} \
        --passcode "${QAR_PT1_PASSCODE}" \
        --said \
        --schema ${QVI_SCHEMA})
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
    echo "$QVI_EDGE_JSON" > ./qvi-edge.json

    kli saidify --file ./qvi-edge.json
    
    print_lcyan "Legal Entity edge Data"
    print_lcyan "$(cat ./qvi-edge.json | jq )"
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
    NONCE=$(kli nonce)
    PID_LIST=""
    kli vc registry incept \
        --name ${GIDA_PT1} \
        --alias ${GIDA_MS} \
        --passcode ${GIDA_PT1_PASSCODE} \
        --usage "Legal Entity Credential Registry for GIDA (LE)" \
        --nonce ${NONCE} \
        --registry-name ${GIDA_REGISTRY} &
    pid=$!
    PID_LIST+=" $pid"

    kli vc registry incept \
        --name ${GIDA_PT2} \
        --alias ${GIDA_MS} \
        --passcode ${GIDA_PT2_PASSCODE} \
        --usage "Legal Entity Credential Registry for GIDA (LE)" \
        --nonce ${NONCE} \
        --registry-name ${GIDA_REGISTRY} & 
    pid=$!
    PID_LIST+=" $pid"
    wait $PID_LIST

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

    echo "$LE_CRED_DATA" > ./legal-entity-data.json

    print_lcyan "[QVI] Legal Entity Credential Data"
    print_lcyan "$(cat ./legal-entity-data.json)"
}
prepare_le_cred_data

# 19.3 Create LE credential in QVI
function create_le_credential() {
    # Check if LE credential already exists
    SAID=$(kli vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema ${LE_SCHEMA})
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[QVI] LE credential already created"
        return
    fi

    echo
    print_green "[QVI] creating LE credential"

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name ${QAR_PT1} \
        --alias ${QVI_MS} \
        --passcode ${QAR_PT1_PASSCODE} \
        --registry-name ${QVI_REGISTRY} \
        --schema "${LE_SCHEMA}" \
        --recipient ${GIDA_PRE} \
        --data @./legal-entity-data.json \
        --edges @./qvi-edge.json \
        --rules @./rules.json \
        --time ${KLI_TIME} &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name ${QAR_PT2} \
        --alias ${QVI_MS} \
        --passcode ${QAR_PT2_PASSCODE} \
        --registry-name ${QVI_REGISTRY} \
        --schema "${LE_SCHEMA}" \
        --recipient ${GIDA_PRE} \
        --data @./legal-entity-data.json \
        --edges @./qvi-edge.json \
        --rules @./rules.json \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

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
        --said)
    if [ ! -z "${LE_GRANT_SAID}" ]; then
        print_dark_gray "[GIDA] LE credential already granted"
        return
    fi
    SAID=$(kli vc list \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --issued \
        --said \
        --schema ${LE_SCHEMA})

    echo
    print_yellow $'[QVI] IPEX GRANTing LE credential with\n\tSAID'" ${SAID}"$'\n\tto GIDA'" ${GIDA_PRE}"
    KLI_TIME=$(kli time)
    kli ipex grant \
        --name ${QAR_PT1} \
        --passcode ${QAR_PT1_PASSCODE} \
        --alias ${QVI_MS} \
        --said ${SAID} \
        --recipient ${GIDA_PRE} \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name ${QAR_PT2} \
        --passcode ${QAR_PT2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[QVI] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "[Internal] Polling for LE Credential in ${GIDA_PT1}..."
    kli ipex list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said
    LE_GRANT_SAID=$?
    if [ -z "${LE_GRANT_SAID}" ]; then
        print_red "LE Credential not granted"
        exit 1
    fi

    print_green "[Internal] Polling for LE Credential in ${GIDA_PT2}..."
    kli ipex list \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --type "grant" \
        --poll \
        --said
    LE_GRANT_SAID=$?
    if [ -z "${LE_GRANT_SAID}" ]; then 
        print_red "LE Credential not granted"
        exit 1
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
        --schema ${LE_SCHEMA})
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
        --said)

    echo
    print_yellow "[Internal] Admitting LE Credential ${SAID} to ${GIDA_MS} as ${GIDA_PT1}"

    KLI_TIME=$(kli time)
    kli ipex admit \
        --name ${GIDA_PT1} \
        --passcode ${GIDA_PT1_PASSCODE} \
        --alias ${GIDA_MS} \
        --said ${SAID} \
        --time "${KLI_TIME}" & 
    pid=$!
    PID_LIST+=" $pid"

    print_green "[Internal] Admitting LE Credential ${SAID} to ${GIDA_MS} as ${GIDA_PT2}"
    kli ipex join \
        --name ${GIDA_PT2} \
        --passcode ${GIDA_PT2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

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
        --schema ${LE_SCHEMA})
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

    echo "$LE_EDGE_JSON" > ./legal-entity-edge.json
    kli saidify --file ./legal-entity-edge.json
    
    print_lcyan "[Internal] Legal Entity edge JSON"
    print_lcyan "$(cat ./legal-entity-edge.json | jq)"
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

    echo "$ECR_AUTH_DATA_JSON" > ./ecr-auth-data.json
    print_lcyan "[Internal] ECR Auth data JSON"
    print_lcyan "$(cat ./ecr-auth-data.json)"
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
        --schema "${ECR_AUTH_SCHEMA}")
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[Internal] ECR Auth credential already created"
        return
    fi

    echo
    print_green "[Internal] GIDA creating ECR Auth credential"

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name ${GIDA_PT1} \
        --alias ${GIDA_MS} \
        --passcode ${GIDA_PT1_PASSCODE} \
        --registry-name ${GIDA_REGISTRY} \
        --schema ${ECR_AUTH_SCHEMA} \
        --recipient ${QVI_PRE} \
        --data @./ecr-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./ecr-auth-rules.json \
        --time ${KLI_TIME} &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name ${GIDA_PT2} \
        --alias ${GIDA_MS} \
        --passcode ${GIDA_PT2_PASSCODE} \
        --registry-name ${GIDA_REGISTRY} \
        --schema ${ECR_AUTH_SCHEMA} \
        --recipient ${QVI_PRE} \
        --data @./ecr-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./ecr-auth-rules.json \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_lcyan "[Internal] GIDA created ECR Auth credential"
    echo
}
create_ecr_auth_credential

# 21.4 Grant ECR Auth credential to QVI
function grant_ecr_auth_credential() {
    # This relies on there being only one grant in the list for the GEDA
    GRANT_COUNT=$(kli ipex list \
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
        --schema ${ECR_AUTH_SCHEMA})

    echo
    print_yellow $'[Internal] IPEX GRANTing ECR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI '"${QVI_PRE}"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex grant \
        --name ${GIDA_PT1} \
        --passcode ${GIDA_PT1_PASSCODE} \
        --alias ${GIDA_MS} \
        --said ${SAID} \
        --recipient ${QVI_PRE} \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name ${GIDA_PT2} \
        --passcode ${GIDA_PT2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[Internal] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "[QVI] Polling for ECR Auth Credential in ${QAR_PT1}..."
    kli ipex list \
            --name "${QAR_PT1}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT1_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    print_green "[QVI] Polling for ECR Auth Credential in ${QAR_PT2}..."
    kli ipex list \
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
    VC_SAID=$(kli vc list \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --said \
        --schema ${ECR_AUTH_SCHEMA})
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] ECR Auth Credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | \
        tail -1) # get the last grant, which should be the ECR Auth credential

    echo
    print_yellow "[QVI] Admitting ECR Auth Credential ${SAID} from GIDA LE"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex admit \
        --name ${QAR_PT1} \
        --passcode ${QAR_PT1_PASSCODE} \
        --alias ${QVI_MS} \
        --said ${SAID} \
        --time "${KLI_TIME}" & 
    pid=$!
    PID_LIST+=" $pid"

    print_green "[QVI] Admitting ECR Auth Credential as ${QVI_MS} from GIDA LE"
    kli ipex join \
        --name ${QAR_PT2} \
        --passcode ${QAR_PT2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

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

    echo "$OOR_AUTH_DATA_JSON" > ./oor-auth-data.json
    print_lcyan "[Internal] OOR Auth data JSON"
    print_lcyan "$(cat ./oor-auth-data.json)"
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
        --schema "${OOR_AUTH_SCHEMA}")
    if [ ! -z "${SAID}" ]; then
        print_yellow "[QVI] OOR Auth credential already created"
        return
    fi

    echo
    print_green "[Internal] GIDA creating OOR Auth credential"

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name ${GIDA_PT1} \
        --alias ${GIDA_MS} \
        --passcode ${GIDA_PT1_PASSCODE} \
        --registry-name ${GIDA_REGISTRY} \
        --schema ${OOR_AUTH_SCHEMA} \
        --recipient ${QVI_PRE} \
        --data @./oor-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./rules.json \
        --time ${KLI_TIME} &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name ${GIDA_PT2} \
        --alias ${GIDA_MS} \
        --passcode ${GIDA_PT2_PASSCODE} \
        --registry-name ${GIDA_REGISTRY} \
        --schema ${OOR_AUTH_SCHEMA} \
        --recipient ${QVI_PRE} \
        --data @./oor-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./rules.json \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_lcyan "[Internal] GIDA created OOR Auth credential"
    echo
}
create_oor_auth_credential



# 21.8 Grant OOR Auth credential to QVI
function grant_oor_auth_credential() {
    # This relies on the last grant being the OOR Auth credential
    GRANT_COUNT=$(kli ipex list \
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
        tail -1) # get the last credential, the OOR Auth credential

    echo
    print_yellow $'[Internal] IPEX GRANTing OOR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex grant \
        --name ${GIDA_PT1} \
        --passcode ${GIDA_PT1_PASSCODE} \
        --alias ${GIDA_MS} \
        --said ${SAID} \
        --recipient ${QVI_PRE} \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name ${GIDA_PT2} \
        --passcode ${GIDA_PT2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[Internal] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "[QVI] Polling for OOR Auth Credential in ${QAR_PT1}..."
    kli ipex list \
            --name "${QAR_PT1}" \
            --alias "${QVI_MS}" \
            --passcode "${QAR_PT1_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    print_green "[QVI] Polling for OOR Auth Credential in ${QAR_PT2}..."
    kli ipex list \
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
    VC_SAID=$(kli vc list \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --said \
        --schema ${OOR_AUTH_SCHEMA})
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] OOR Auth Credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | \
        tail -1) # get the last grant, which should be the ECR Auth credential

    echo
    print_yellow "[QVI] Admitting OOR Auth Credential ${SAID} from GIDA LE"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex admit \
        --name ${QAR_PT1} \
        --passcode ${QAR_PT1_PASSCODE} \
        --alias ${QVI_MS} \
        --said ${SAID} \
        --time "${KLI_TIME}" & 
    pid=$!
    PID_LIST+=" $pid"

    print_green "[QVI] Admitting OOR Auth Credential as ${QVI_MS} from GIDA LE"
    kli ipex join \
        --name ${QAR_PT2} \
        --passcode ${QAR_PT2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_green "[QVI] OOR Auth Credential admitted"
    echo
}
admit_oor_auth_credential


# 23. QVI: Create and Issue ECR credential to Person
# 23.1 Prepare ECR Auth edge data
function prepare_ecr_auth_edge() {
    ECR_AUTH_SAID=$(kli vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --said \
        --schema "${ECR_AUTH_SCHEMA}")
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
    echo "$ECR_AUTH_EDGE_JSON" > ./ecr-auth-edge.json

    kli saidify --file ./ecr-auth-edge.json
    
    print_lcyan "[QVI] ECR Auth edge Data"
    print_lcyan "$(cat ./ecr-auth-edge.json | jq )"
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

    echo "${ECR_CRED_DATA}" > ./ecr-data.json

    print_lcyan "[QVI] ECR Credential Data"
    print_lcyan "$(cat ./ecr-data.json)"
}
prepare_ecr_cred_data

# 23.3 Create ECR credential in QVI, issued to the Person
function create_ecr_credential() {
    # Check if ECR credential already exists
    SAID=$(kli vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema "${ECR_SCHEMA}")
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[QVI] ECR credential already created"
        return
    fi

    echo
    print_green "[QVI] creating ECR credential"

    KLI_TIME=$(kli time)
    CRED_NONCE=$(kli nonce)
    SUBJ_NONCE=$(kli nonce)
    PID_LIST=""
    kli vc create \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --private-credential-nonce "${CRED_NONCE}" \
        --private-subject-nonce "${SUBJ_NONCE}" \
        --private \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${ECR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @./ecr-data.json \
        --edges @./ecr-auth-edge.json \
        --rules @./ecr-rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --private \
        --private-credential-nonce "${CRED_NONCE}" \
        --private-subject-nonce "${SUBJ_NONCE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${ECR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @./ecr-data.json \
        --edges @./ecr-auth-edge.json \
        --rules @./ecr-rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

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
        tail -1) # get the last grant
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
        --schema "${ECR_SCHEMA}")

    echo
    print_yellow $'[QVI] IPEX GRANTing ECR credential with\n\tSAID'" ${SAID}"$'\n\tto'" ${PERSON} ${PERSON_PRE}"
    KLI_TIME=$(kli time)
    kli ipex grant \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[QVI] Waiting for IPEX messages to be witnessed"
    sleep 5

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
        --schema "${ECR_SCHEMA}")
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
        --said)

    echo
    print_yellow "[PERSON] Admitting ECR credential ${SAID} to ${PERSON}"

    kli ipex admit \
        --name ${PERSON} \
        --passcode ${PERSON_PASSCODE} \
        --alias ${PERSON} \
        --said ${SAID}  & 
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_green "ECR Credential admitted"
    echo
}
admit_ecr_credential

# 24. QVI: Issue, grant OOR to Person and Person admits OOR
# 24.1 Prepare OOR Auth edge data
function prepare_oor_auth_edge() {
    OOR_AUTH_SAID=$(kli vc list \
        --name ${QAR_PT1} \
        --alias ${QVI_MS} \
        --passcode "${QAR_PT1_PASSCODE}" \
        --said \
        --schema ${OOR_AUTH_SCHEMA})
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
    echo "$OOR_AUTH_EDGE_JSON" > ./oor-auth-edge.json

    kli saidify --file ./oor-auth-edge.json
    
    print_lcyan "[QVI] OOR Auth edge Data"
    print_lcyan "$(cat ./oor-auth-edge.json | jq )"
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

    echo "${OOR_CRED_DATA}" > ./oor-data.json

    print_lcyan "[QVI] OOR Credential Data"
    print_lcyan "$(cat ./oor-data.json)"
}
prepare_oor_cred_data

# 24.3 Create OOR credential in QVI, issued to the Person
function create_oor_credential() {
    # Check if OOR credential already exists
    SAID=$(kli vc list \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema "${OOR_SCHEMA}")
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[QVI] OOR credential already created"
        return
    fi

    echo
    print_green "[QVI] creating OOR credential"

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name "${QAR_PT1}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${OOR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @./oor-data.json \
        --edges @./oor-auth-edge.json \
        --rules @./oor-rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${QAR_PT2}" \
        --alias "${QVI_MS}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${OOR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @./oor-data.json \
        --edges @./oor-auth-edge.json \
        --rules @./oor-rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_lcyan "[QVI] OOR credential created"
    echo
}
create_oor_credential


# 24.4 QVI Grant OOR credential to PERSON
function grant_oor_credential() {
    # This only works the last grant is the OOR credential
    GRANT_COUNT=$(kli ipex list \
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
    SAID=$(kli vc list \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --issued \
        --said \
        --schema "${OOR_SCHEMA}")

    echo
    print_yellow $'[QVI] IPEX GRANTing OOR credential with\n\tSAID'" ${SAID}"$'\n\tto'" ${PERSON} ${PERSON_PRE}"
    kli ipex grant \
        --name "${QAR_PT1}" \
        --passcode "${QAR_PT1_PASSCODE}" \
        --alias "${QVI_MS}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name "${QAR_PT2}" \
        --passcode "${QAR_PT2_PASSCODE}" \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[QVI] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "[PERSON] Polling for OOR Credential in ${PERSON}..."
    kli ipex list \
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
    VC_SAID=$(kli vc list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --said \
        --schema "${OOR_SCHEMA}")
    if [ ! -z "${VC_SAID}" ]; then
        print_yellow "[PERSON] OOR credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${PERSON}" \
        --alias "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | tail -1) # get the last grant, which should be the OOR credential

    echo
    print_yellow "[PERSON] Admitting OOR credential ${SAID} to ${PERSON}"

    kli ipex admit \
        --name "${PERSON}" \
        --passcode "${PERSON_PASSCODE}" \
        --alias "${PERSON}" \
        --said "${SAID}"  & 
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_green "OOR Credential admitted"
    echo
}
admit_oor_credential

# 25. QVI: Present issued ECR Auth and OOR Auth to Sally (vLEI Reporting API)

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
        --web-hook http://127.0.0.1:9923 \
        --auth "${GEDA_PRE}" & # who will be presenting the credential
    SALLY_PID=$!

    sleep 5
}
sally_setup

function present_le_cred_to_sally() {
    print_yellow "[QVI] Presenting LE Credential to Sally"
    LE_SAID=$(kli vc list --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --said --schema "${LE_SCHEMA}")

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