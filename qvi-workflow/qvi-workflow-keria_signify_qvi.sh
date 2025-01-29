#!/usr/bin/env bash
# qvi-workflow-keria_signify_qvi.sh
# Runs the entire QVI issuance workflow end to end starting from multisig AID creatin including the
# GLEIF External Delegated AID (GEDA) creation all the way to OOR and ECR credential issuance to the
# Person AID for usage in the iXBRL data attestation.
#
# Note:
# This script uses a local installation of KERIA, witnesses, the vLEI-server for vLEI schemas,
# and NodeJS scripts for the SignifyTS creation of both QVI QAR AIDs and the Person AID.
#
# To run this script you need to run the following command in a separate terminals:
#   > kli witness demo
# and from the vLEI repo run:
#   > vLEI-server -s ./schema/acdc -c ./samples/acdc/ -o ./samples/oobis/
# and from the keria repo run:
#   > keria start --config-dir scripts --config-file keria --loglevel INFO
# and make sure to perform "npm install" in this directory to be able to run the NodeJS scripts.

SALLY_PID=""
WEBHOOK_PID=""

function sally_teardown() {
  if [ -n "$SALLY_PID" ]; then
    kill -SIGTERM $SALLY_PID
  fi
  if [ -n "$WEBHOOK_PID" ]; then
    kill -SIGTERM $WEBHOOK_PID
  fi
}

function cleanup() {
    # Triggered on Control + C, cleans up resources the script uses
    echo
    print_red "Exit or Caught Ctrl+C, Exiting script..."
    sally_teardown
    exit 0
}
trap cleanup INT
trap cleanup EXIT

source ./script-utils.sh
echo
print_bg_blue "------------------------------vLEI QVI Workflow Script (KERIA & SignifyTS locally)------------------------------"
echo

ENVIRONMENT=local

# 1. GAR: Prepare environment
KEYSTORE_DIR=${1:-$HOME/.keri}
QVI_SIGNIFY_DIR=$(dirname "$0")/signify_qvi
QVI_DATA_DIR="${QVI_SIGNIFY_DIR}/qvi_data"
print_yellow "KEYSTORE_DIR: ${KEYSTORE_DIR}"
print_yellow "Using $ENVIRONMENT configuration files"

CONFIG_DIR=./config
DATA_DIR=./data
INIT_CFG=qvi-workflow-init-config-dev-local.json
WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
WIT_HOST=http://127.0.0.1:5642
SCHEMA_SERVER=http://127.0.0.1:7723
KERIA_SERVER=http://127.0.0.1:3903

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


# QAR AIDs - filled in later after KERIA setup
QAR_PT1=galahad
QAR_PT1_PRE=
QAR_PT1_SALT=0ACgCmChLaw_qsLycbqBoxDK

QAR_PT2=lancelot
QAR_PT2_PRE=
QAR_PT2_SALT=0ACaYJJv0ERQmy7xUfKgR6a4

QAR_PT3=tristan
QAR_PT3_SALT=0AAzX0tS638c9SEf5LnxTlj4

QVI_MS=percival
QVI_PRE=
QVI_MS_SALT=0AA2sMML7K-XdQLrgzOfIvf3
QVI_MS_PASSCODE=97542531221a214cc0a55


# Person AID
PERSON_NAME="Mordred Delacqs"
PERSON=mordred
PERSON_PRE=
PERSON_SALT=0ABlXAYDE2TkaNDk4UXxxtaN
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

# ensure services are up
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

    curl ${KERIA_SERVER}/health >/dev/null 2>&1
    status=$?
    if [ $status -ne 0 ]; then
        print_red "Keria server not running at ${KERIA_SERVER}"
        cleanup
    fi
}
test_dependencies

# KERIA SignifyTS QVI salts
SIGTS_AIDS="qar1|$QAR_PT1|$QAR_PT1_SALT,qar2|$QAR_PT2|$QAR_PT2_SALT,qar3|$QAR_PT3|$QAR_PT3_SALT,person|$PERSON|$PERSON_SALT"

tsx "${QVI_SIGNIFY_DIR}/qars/qars-and-person-setup.ts" $ENVIRONMENT $QVI_DATA_DIR $SIGTS_AIDS
echo "QVI and Person Identifiers from SignifyTS + KERIA are "
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
    print_lcyan "Using temporary AID config file heredoc:"
    print_lcyan "${temp_icp_config}"

    create_aid "${GEDA_PT1}" "${GEDA_PT1_SALT}" "${GEDA_PT1_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${GEDA_PT2}" "${GEDA_PT2_SALT}" "${GEDA_PT2_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${GIDA_PT1}" "${GIDA_PT1_SALT}" "${GIDA_PT1_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${GIDA_PT2}" "${GIDA_PT2_SALT}" "${GIDA_PT2_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
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

    GEDA1_OOBI="${WIT_HOST}/oobi/${GEDA_PT1_PRE}/witness/${WAN_PRE}"
    GEDA2_OOBI="${WIT_HOST}/oobi/${GEDA_PT2_PRE}/witness/${WAN_PRE}"
    GIDA1_OOBI="${WIT_HOST}/oobi/${GIDA_PT1_PRE}/witness/${WAN_PRE}"
    GIDA2_OOBI="${WIT_HOST}/oobi/${GIDA_PT2_PRE}/witness/${WAN_PRE}"
    SALLY_OOBI="${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"

    OOBIS_FOR_KERIA="geda1|$GEDA1_OOBI,geda2|$GEDA2_OOBI,gida1|$GIDA1_OOBI,gida2|$GIDA2_OOBI,sally|$SALLY_OOBI"

    tsx "${QVI_SIGNIFY_DIR}/qars/qars-person-single-sig-oobis-setup.ts" $ENVIRONMENT $SIGTS_AIDS $OOBIS_FOR_KERIA

    echo
    print_lcyan "-----Resolving OOBIs-----"
    print_yellow "Resolving OOBIs for GEDA 1"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GEDA_PT2}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${GEDA2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GIDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${GIDA1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${GIDA_PT2}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${GIDA2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QAR_PT1}"  --passcode "${GEDA_PT1_PASSCODE}" --oobi "${QAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QAR_PT2}"  --passcode "${GEDA_PT1_PASSCODE}" --oobi "${QAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QAR_PT3}"  --passcode "${GEDA_PT1_PASSCODE}" --oobi "${QAR3_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${PERSON}"   --passcode "${GEDA_PT1_PASSCODE}" --oobi "${PERSON_OOBI}" >/dev/null 2>&1

    print_yellow "Resolving OOBIs for GEDA 2"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GEDA_PT1}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${GEDA1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GIDA_PT1}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${GIDA1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${GIDA_PT2}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${GIDA2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT1}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${QAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT2}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${QAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QAR_PT3}"  --passcode "${GEDA_PT2_PASSCODE}" --oobi "${QAR3_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${PERSON}"   --passcode "${GEDA_PT2_PASSCODE}" --oobi "${PERSON_OOBI}" >/dev/null 2>&1

    print_yellow "Resolving OOBIs for GIDA 1"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${GIDA_PT2}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${GIDA2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${GEDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${GEDA1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${GEDA_PT2}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${GEDA2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QAR_PT1}"  --passcode "${GIDA_PT1_PASSCODE}" --oobi "${QAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QAR_PT2}"  --passcode "${GIDA_PT1_PASSCODE}" --oobi "${QAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QAR_PT3}"  --passcode "${GIDA_PT1_PASSCODE}" --oobi "${QAR3_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${PERSON}"   --passcode "${GIDA_PT1_PASSCODE}" --oobi "${PERSON_OOBI}" >/dev/null 2>&1

    print_yellow "Resolving OOBIs for GIDA 2"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${GIDA_PT1}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${GIDA1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${GEDA_PT1}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${GEDA1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${GEDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${GEDA2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QAR_PT1}"  --passcode "${GIDA_PT2_PASSCODE}" --oobi "${QAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QAR_PT2}"  --passcode "${GIDA_PT2_PASSCODE}" --oobi "${QAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QAR_PT3}"  --passcode "${GIDA_PT2_PASSCODE}" --oobi "${QAR3_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${PERSON}"   --passcode "${GIDA_PT2_PASSCODE}" --oobi "${PERSON_OOBI}" >/dev/null 2>&1
    
    echo
}
resolve_oobis

# 3.5 GAR: Challenge responses between single sig AIDs
function challenge_response() {
    chall_length=$(kli contacts list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | jq "select(.alias == \"${GEDA_PT2}\") | .challenges | length")
    if [[ "$chall_length" -gt 0 ]]; then
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

    # TODO add qars-challenge-each-other.ts
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
    # TODO add qars-challenge-respond.ts
    # kli challenge respond --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --recipient "${GEDA_PT1}" --words "${words_geda1_to_qar1}"
    kli challenge verify  --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --signer "${QAR_PT1}"    --words "${words_geda1_to_qar1}"

    print_dark_gray "Challenge: QAR 1 -> GEDA 1"
    words_qar1_to_geda1=$(kli challenge generate --out string)
    kli challenge respond --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --recipient "${QAR_PT1}" --words "${words_qar1_to_geda1}"
    # TODO add qars-challenge-verify.ts
    # kli challenge verify  --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --signer "${GEDA_PT1}"    --words "${words_qar1_to_geda1}"

    print_dark_gray "Challenge: GEDA 2 -> QAR 2"
    words_geda1_to_qar2=$(kli challenge generate --out string)
    # TODO add qars-challenge-respond.ts
    # kli challenge respond --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --recipient "${GEDA_PT1}" --words "${words_geda1_to_qar2}"
    kli challenge verify  --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --signer "${QAR_PT2}"    --words "${words_geda1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> GEDA 1"
    words_qar2_to_geda1=$(kli challenge generate --out string)
    kli challenge respond --name "${GEDA_PT1}" --alias "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" --recipient "${QAR_PT2}" --words "${words_qar2_to_geda1}"
    # TODO add qars-challenge-verify.ts
    # kli challenge verify  --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --signer "${GEDA_PT1}"    --words "${words_qar2_to_geda1}"

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
    # TODO add qars-challenge-verify.ts
    # kli challenge verify  --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --signer "${GIDA_PT1}"    --words "${words_qar1_to_gida1}"

    print_dark_gray "Challenge: GIDA 1 -> QAR 1"
    words_gida1_to_qar1=$(kli challenge generate --out string)
    # TODO add qars-challenge-respond.ts
    # kli challenge respond --name "${QAR_PT1}" --alias "${QAR_PT1}" --passcode "${QAR_PT1_PASSCODE}" --recipient "${GIDA_PT1}" --words "${words_gida1_to_qar1}"
    kli challenge verify  --name "${GIDA_PT1}" --alias "${GIDA_PT1}" --passcode "${GIDA_PT1_PASSCODE}" --signer "${QAR_PT1}"    --words "${words_gida1_to_qar1}"

    print_dark_gray "Challenge: QAR 2 -> GIDA 2"
    words_qar2_to_gida2=$(kli challenge generate --out string)
    kli challenge respond --name "${GIDA_PT2}" --alias "${GIDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --recipient "${QAR_PT2}" --words "${words_qar2_to_gida2}"
    # TODO add qars-challenge-verify.ts
    # kli challenge verify  --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --signer "${GIDA_PT2}"    --words "${words_qar2_to_gida2}"

    print_dark_gray "Challenge: GIDA 2 -> QAR 2"
    words_gida2_to_qar2=$(kli challenge generate --out string)
    # TODO add qars-challenge-respond.ts
    # kli challenge respond --name "${QAR_PT2}" --alias "${QAR_PT2}" --passcode "${QAR_PT2_PASSCODE}" --recipient "${GIDA_PT2}" --words "${words_gida2_to_qar2}"
    kli challenge verify  --name "${GIDA_PT2}" --alias "${GIDA_PT2}" --passcode "${GIDA_PT2_PASSCODE}" --signer "${QAR_PT2}"    --words "${words_gida2_to_qar2}" 

    print_green "-----Finished challenge and response-----"
}
# TODO enable this after challenge response with SignifyTS is integrated
#challenge_response

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
    local delegator_prefix=$(kli status --name ${GEDA_PT1} --alias ${GEDA_MS} --passcode ${GEDA_PT1_PASSCODE} | awk '/Identifier:/ {print $2}')
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

# 13. QVI: (skip) Perform endpoint role authorizations
# 14. QVI: Generate OOBI for QVI to send to GEDA
QVI_OOBI=""
function authorize_qvi_multisig_agent_endpoint_role(){
    print_yellow "Authorizing QVI multisig agent endpoint role"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-authorize-endroles-get-qvi-oobi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${QVI_DATA_DIR}" \
      "${SIGTS_AIDS}"
    QVI_OOBI=$(cat "${QVI_DATA_DIR}/qvi-oobi.json" | jq .oobi | tr -d '"')
}
authorize_qvi_multisig_agent_endpoint_role
print_green "QVI Agent OOBI: ${QVI_OOBI}"

# 15. GEDA and GIDA: Resolve QVI OOBI
function resolve_qvi_oobi() {
    exists=$(kli contacts list --name "${GEDA_PT1}" --passcode "${GEDA_PT1_PASSCODE}" | jq .alias | tr -d '"' | grep "${QVI_MS}")
    if [[ "$exists" =~ "${QVI_MS}" ]]; then
        print_yellow "QVI OOBIs already resolved"
        return
    fi

    echo
    echo "QVI OOBI: ${QVI_OOBI}"
    print_yellow "Resolving QVI OOBI for GEDA and GIDA"
    kli oobi resolve --name "${GEDA_PT1}" --oobi-alias "${QVI_MS}" --passcode "${GEDA_PT1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GEDA_PT2}" --oobi-alias "${QVI_MS}" --passcode "${GEDA_PT2_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GIDA_PT1}" --oobi-alias "${QVI_MS}" --passcode "${GIDA_PT1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GIDA_PT2}" --oobi-alias "${QVI_MS}" --passcode "${GIDA_PT2_PASSCODE}" --oobi "${QVI_OOBI}"

    print_yellow "Resolving QVI OOBI for Person"
    tsx "${QVI_SIGNIFY_DIR}/person-resolve-qvi-oobi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${QVI_OOBI}"
    echo
}
resolve_qvi_oobi

#read -p "Press [ENTER] to rotate the QVI AID"

# 18.1 QVI: Delegated multisig rotation() {
function qvi_rotate() {
  QVI_MULTISIG_SEQ_NO=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}"
      )
    if [[ "$QVI_MULTISIG_SEQ_NO" -gt 1 ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_MS} already rotated with SN=${QVI_MULTISIG_SEQ_NO}"
        return
    fi
    print_yellow "[QVI] Rotating QVI Multisig"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-rotate-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}"
    QVI_PREFIX=$(cat "${QVI_DATA_DIR}/qvi-multisig-info.json" | jq .msPrefix | tr -d '"')
    print_green "[QVI] Rotated QVI Multisig with prefix: ${QVI_PREFIX}"

    # create interaction event
    read -r -d '' ANCHOR << EOM
{"i": "$QVI_PREFIX","s": "1","d": "$QVI_PREFIX"}
EOM

    # create temporary file to store json
    temp_anchor=$(mktemp)

    # write JSON content to the temp file
    echo "$ANCHOR" > "$temp_anchor"

    print_bg_blue "[QVI] QVI Multisig rotation anchor"
    cat $temp_anchor | jq

    read -p "Press [ENTER] to confirm the QVI rotation"
    print_yellow "GEDA1 confirm delegated rotation"
    kli delegate confirm --name ${GEDA_PT1} --alias ${GEDA_MS} --passcode ${GEDA_PT1_PASSCODE} --interact --auto &
#    kli multisig interact --name ${GEDA_PT1} --alias ${GEDA_MS} --passcode ${GEDA_PT1_PASSCODE} --data "$ANCHOR" &
    pid=$!
    PID_LIST+=" $pid"

    print_yellow "GEDA2 confirm delegated rotation"
    kli delegate confirm --name ${GEDA_PT2} --alias ${GEDA_MS} --passcode ${GEDA_PT2_PASSCODE} --interact --auto &
#    kli multisig interact --name ${GEDA_PT2} --alias ${GEDA_MS} --passcode ${GEDA_PT2_PASSCODE} --data "$ANCHOR" &
    pid=$!
    PID_LIST+=" $pid"

    print_yellow "[GEDA] Waiting 5s on delegated rotation completion"
    wait $PID_LIST
    sleep 5

    print_lcyan "[QVI] QARs refresh GEDA multisig keystate to discover GEDA approval of delegated rotation"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-refresh-geda-multisig-state.ts" $ENVIRONMENT $SIGTS_AIDS $GEDA_PRE

    print_yellow "[QVI] Waiting 8s for QARs to refresh GEDA keystate and complete delegation"
    sleep 8
    rm "$temp_anchor"
}
#qvi_rotate

#read -p "Press [ENTER] to create GEDA registry"

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
    print_lcyan "[External] QVI Credential Data"
    print_lcyan "$(cat ./qvi-cred-data.json)"

    KLI_TIME=$(kli time) # use consistent time for both invocations of `kli vc create` so they compute the same event digest (SAID).
    PID_LIST=""
    kli vc create \
        --name "${GEDA_PT1}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT1_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./qvi-cred-data.json \
        --rules @./rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${GEDA_PT2}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT2_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./qvi-cred-data.json \
        --rules @./rules.json \
        --time "${KLI_TIME}" &
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
        --name "${GEDA_PT1}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT1_PASSCODE}" \
        --sent \
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
    print_yellow "[External] Waiting 8s for QVI Credentials IPEX messages to be witnessed"
    sleep 8
    echo
    print_green "[External] QVI Credential issued to QVI"
    echo
}
grant_qvi_credential

# 18. QVI: Admit QVI credential from GEDA
function admit_qvi_credential() {
    QVI_CRED_SAID=$(kli vc list \
        --name "${GEDA_PT1}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}")
    received=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-received-credential.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${QVI_CRED_SAID}"
    )
    if [[ "$received" == "true" ]]; then
        print_dark_gray "[QVI] QVI Credential ${QVI_CRED_SAID} already admitted"
        return
    fi

    echo
    print_yellow "[QVI] Admitting QVI Credential ${QVI_CRED_SAID} from GEDA"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${GEDA_PRE}" \
      "${QVI_CRED_SAID}"

    echo
    print_green "[QVI] Admitted QVI credential"
    echo
}
admit_qvi_credential

#read -p "Press [ENTER] to create the QVI registry"

# 18.5 Create QVI credential registry
function create_qvi_reg() {
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-registry-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${QVI_REGISTRY}" \
      "${QVI_DATA_DIR}" \
      "${SIGTS_AIDS}"
    QVI_REG_REGK=$(cat "${QVI_DATA_DIR}/qvi-registry-info.json" | jq .registryRegk | tr -d '"')
    print_green "[QVI] Credential Registry created for QVI with regk: ${QVI_REG_REGK}"
}
create_qvi_reg

# 18.6 QVI OOBIs with GIDA (already done in step 9)

# 19. QVI: Prepare, create, and Issue LE credential to GEDA

# 19.1 Prepare LE edge data
function prepare_qvi_edge() {
    QVI_CRED_SAID=$(kli vc list \
        --name "${GEDA_PT1}" \
        --alias "${GEDA_MS}" \
        --passcode "${GEDA_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}")
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
    echo "$QVI_EDGE_JSON" > ./qvi-edge.json

    kli saidify --file ./qvi-edge.json
}
prepare_qvi_edge

# 19.2 Prepare LE credential data
function prepare_le_cred_data() {
    print_yellow "[QVI] Preparing LE credential data"
    read -r -d '' LE_CRED_DATA << EOM
{
    "LEI": "${GEDA_LEI}"
}
EOM

    echo "$LE_CRED_DATA" > ./legal-entity-data.json
}
prepare_le_cred_data

# 19.3 Create LE credential in QVI
function create_and_grant_le_credential() {
    # Check if LE credential already exists
    le_said=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      $ENVIRONMENT \
      $QVI_MS \
      $SIGTS_AIDS \
      $GIDA_PRE \
      $LE_SCHEMA
    )
    if [[ ! "$le_said" =~ "false" ]]; then
        print_dark_gray "[QVI] LE Credential already created"
        return
    fi

    echo
    print_green "[QVI] creating LE credential"

    print_lcyan "[QVI] Legal Entity edge Data"
    print_lcyan "$(cat ./qvi-edge.json | jq )"

    print_lcyan "[QVI] Legal Entity Credential Data"
    print_lcyan "$(cat ./legal-entity-data.json)"

    tsx "${QVI_SIGNIFY_DIR}/qars/qars-le-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "./" \
      "${SIGTS_AIDS}" \
      "${GIDA_PRE}" \
      "${QVI_SAID}"

    echo
    print_lcyan "[QVI] LE Credential created"
    print_dark_gray "Waiting 10 seconds for LE credential to be witnessed..."
    sleep 10
    echo
}
create_and_grant_le_credential

# 19.4. GIDA (LE): Admit LE credential from QVI
function admit_le_credential() {
    VC_SAID=$(kli vc list \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --said \
        --schema "${LE_SCHEMA}")
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[Internal] LE Credential already admitted"
        return
    fi

    print_dark_gray "Listing IPEX Grants for GIDA 1"
    SAID=$(kli ipex list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | uniq) # there are three grant messages, one from each QAR, yet all share the same SAID, so uniq condenses them to one

    print_dark_gray "Listing IPEX Grants for GIDA 2"
    # prime the mailbox to properly receive the messages.
    kli ipex list \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | uniq

    echo
    print_yellow "[Internal] Admitting LE Credential ${SAID} to ${GIDA_MS} as ${GIDA_PT1}"

    KLI_TIME=$(kli time)
    kli ipex admit \
        --name "${GIDA_PT1}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" & 
    pid=$!
    PID_LIST+=" $pid"

    print_green "[Internal] Admitting LE Credential ${SAID} to ${GIDA_MS} as ${GIDA_PT2}"
    kli ipex join \
        --name "${GIDA_PT2}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    print_yellow "[Internal] Waiting 8s for LE IPEX messages to be witnessed"
    sleep 8

    echo
    print_green "[Internal] Admitted LE credential"
    echo
}
admit_le_credential

# 20. GIDA (LE): Create GIDA credential registry
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
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --usage "Legal Entity Credential Registry for GIDA (LE)" \
        --nonce "${NONCE}" \
        --registry-name "${GIDA_REGISTRY}" &
    pid=$!
    PID_LIST+=" $pid"

    kli vc registry incept \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --usage "Legal Entity Credential Registry for GIDA (LE)" \
        --nonce "${NONCE}" \
        --registry-name "${GIDA_REGISTRY}" &
    pid=$!
    PID_LIST+=" $pid"
    wait $PID_LIST

    echo
    print_green "[Internal] Legal Entity Credential Registry created for GIDA"
    echo
}
create_gida_reg

#read -p "Press [ENTER] to issue the ECR Auth credential"

# 21. GIDA (LE): Prepare, create, and Issue ECR Auth & OOR Auth credential to QVI
# 21.1 prepare LE edge to ECR auth cred
function prepare_le_edge() {
    LE_SAID=$(kli vc list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --said \
        --schema "${LE_SCHEMA}")
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

    print_lcyan "[Internal] Legal Entity edge JSON"
    print_lcyan "$(cat ./legal-entity-edge.json | jq)"

    print_lcyan "[Internal] ECR Auth data JSON"
    print_lcyan "$(cat ./ecr-auth-data.json)"

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --registry-name "${GIDA_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./ecr-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./ecr-auth-rules.json \
        --time "${KLI_TIME}" &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --registry-name "${GIDA_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./ecr-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./ecr-auth-rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[Internal] Waiting 8s ECR Auth for IPEX messages to be witnessed"
    sleep 8

    echo
    print_lcyan "[Internal] GIDA created ECR Auth credential"
    echo
}
create_ecr_auth_credential

#read -p "Press [ENTER] to grant the ECR Auth credential"

# 21.4 Grant ECR Auth credential to QVI
function grant_ecr_auth_credential() {
    # This relies on there being only one grant in the list for the GEDA
    GRANT_COUNT=$(kli ipex list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --type "grant" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --sent \
        --said | wc -l | tr -d ' ') # get the last grant
    if [ "${GRANT_COUNT}" -ge 1 ]; then
        print_dark_gray "[GIDA] ECR Auth credential grant already granted"
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
        --name "${GIDA_PT1}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

#    kli ipex join \
#        --name "${GIDA_PT2}" \
#        --passcode "${GIDA_PT2_PASSCODE}" \
#        --auto &
    kli ipex grant \
        --name "${GIDA_PT2}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[Internal] Waiting for IPEX ECR Auth grant messages to be witnessed"
    sleep 8

    echo
    print_green "[Internal] ECR Auth Credential granted to QVI"
    echo
}
grant_ecr_auth_credential

#read -p "Press [ENTER] to admit the ECR Auth credential"

# 21.5 (part of 22) Admit ECR Auth credential from GIDA
function admit_ecr_auth_credential() {
    ECR_AUTH_SAID=$(kli vc list \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --issued \
        --said \
        --schema ${ECR_AUTH_SCHEMA})
    received=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-received-credential.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${ECR_AUTH_SAID}"
    )
    if [[ "$received" == "true" ]]; then
        print_dark_gray "[QVI] ECR Auth Credential already admitted"
        return
    fi

    echo
    print_yellow "[QVI] Admitting ECR Auth Credential ${ECR_AUTH_SAID} from GIDA"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${GIDA_PRE}" \
      "${ECR_AUTH_SAID}"

    print_yellow "[QVI] Waiting 8s for IPEX admit messages to be witnessed"
    sleep 8

    echo
    print_green "[QVI] Admitted ECR Auth Credential"
    echo
}
admit_ecr_auth_credential

#read -p "Press [ENTER] to issue the OOR Auth credential"

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

    print_lcyan "[Internal] OOR Auth data JSON"
    print_lcyan "$(cat ./oor-auth-data.json)"

    echo
    print_green "[Internal] GIDA creating OOR Auth credential"

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --registry-name "${GIDA_REGISTRY}" \
        --schema "${OOR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./oor-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./rules.json \
        --time "${KLI_TIME}" &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --registry-name "${GIDA_REGISTRY}" \
        --schema "${OOR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./oor-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_lcyan "[Internal] GIDA created OOR Auth credential"
    echo
}
create_oor_auth_credential

#read -p "Press [ENTER] to grant the OOR Auth credential"

# 21.8 Grant OOR Auth credential to QVI
function grant_oor_auth_credential() {
    # This relies on the last grant being the OOR Auth credential
    GRANT_COUNT=$(kli ipex list \
        --name "${GIDA_PT1}" \
        --alias "${GIDA_MS}" \
        --type "grant" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --sent \
        --said | wc -l | tr -d ' ') # get grant count, remove whitespace
    if [ "${GRANT_COUNT}" -ge 2 ]; then
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
        --name "${GIDA_PT1}" \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

#    kli ipex join \
#        --name "${GIDA_PT2}" \
#        --passcode "${GIDA_PT2_PASSCODE}" \
#        --auto &
    kli ipex grant \
        --name "${GIDA_PT2}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --alias "${GIDA_MS}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[Internal] Waiting for OOR Auth IPEX grant messages to be witnessed"
    sleep 5

    echo
    print_green "[Internal] Granted OOR Auth credential to QVI"
    echo
}
grant_oor_auth_credential

#read -p "Press [ENTER] to admit OOR Auth credential"

# 22. QVI: Admit OOR Auth credential
function admit_oor_auth_credential() {
    OOR_AUTH_SAID=$(kli vc list \
        --name "${GIDA_PT2}" \
        --alias "${GIDA_MS}" \
        --passcode "${GIDA_PT2_PASSCODE}" \
        --issued \
        --said \
        --schema ${OOR_AUTH_SCHEMA})
    received=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-received-credential.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${OOR_AUTH_SAID}"
    )
    if [[ "$received" == "true" ]]; then
        print_dark_gray "[QVI] OOR Auth Credential already admitted"
        return
    fi

    echo
    print_yellow "[QVI] Admitting OOR Auth Credential ${OOR_AUTH_SAID} from GIDA"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${GIDA_PRE}" \
      "${OOR_AUTH_SAID}"

    print_yellow "[QVI] Waiting for OOR Auth IPEX admit messages to be witnessed"
    sleep 8

    echo
    print_green "[QVI] Admitted OOR Auth Credential"
    echo
}
admit_oor_auth_credential

#read -p "Press [ENTER] to  issue the ECR credential"

# 23. QVI: Create and Issue ECR credential to Person
# 23.1 Prepare ECR Auth edge data
function prepare_ecr_auth_edge() {
    ECR_AUTH_SAID=$(kli vc list \
        --name ${GIDA_PT1} \
        --alias ${GIDA_MS} \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --issued \
        --said \
        --schema ${ECR_AUTH_SCHEMA})
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
}
prepare_ecr_cred_data

# TODO add a Typescript script to resolve the QVI OOBI for the person
# kli oobi resolve --name "${PERSON}"   --oobi-alias "${QVI_MS}" --passcode "${PERSON_PASSCODE}"   --oobi "${QVI_OOBI}"

#read -p "Press [ENTER] to issue and grant the ECR credential"

# 23.3 Create ECR credential in QVI, issued to the Person
# 23.4 QVI Grant ECR credential to PERSON
function create_and_grant_ecr_credential() {
    # Check if ECR credential already exists
    ecr_said=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_MS" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$ECR_SCHEMA"
    )
    if [[ ! "$ecr_said" =~ "false" ]]; then
        print_dark_gray "[QVI] ECR Credential already created"
        return
    fi

    print_lcyan "[QVI] ECR Auth edge Data"
    print_lcyan "$(cat ./ecr-auth-edge.json | jq )"

    print_lcyan "[QVI] ECR Credential Data"
    print_lcyan "$(cat ./ecr-data.json)"

    echo
    print_green "[QVI] creating and granting ECR credential"

    tsx "${QVI_SIGNIFY_DIR}/qars/qars-ecr-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "./" \
      "${SIGTS_AIDS}" \
      "${PERSON_PRE}" \
      "${QVI_SAID}"

    print_yellow "[QVI] Waiting for ECR IPEX messages to be witnessed"
    sleep 8

    echo
    print_lcyan "[QVI] ECR credential created and granted"
    echo
}
create_and_grant_ecr_credential

#read -p "Press [ENTER] to admit the ECR credential"

# 23.5. Person: Admit ECR credential from QVI
function admit_ecr_credential() {
    # check if ECR has been admitted to receiver
    ecr_said=$(tsx "${QVI_SIGNIFY_DIR}/person/person-check-received-credential.ts" \
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
    ecr_said=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_MS" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$ECR_SCHEMA"
    )

    echo
    print_yellow "[PERSON] Admitting ECR credential ${ecr_said} to ${PERSON}"

    tsx "${QVI_SIGNIFY_DIR}/person/person-admit-credential.ts" \
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
admit_ecr_credential

# 24. QVI: Issue, grant OOR to Person and Person admits OOR
# 24.1 Prepare OOR Auth edge data
function prepare_oor_auth_edge() {
    OOR_AUTH_SAID=$(kli vc list \
        --name ${GIDA_PT1} \
        --alias ${GIDA_MS} \
        --passcode "${GIDA_PT1_PASSCODE}" \
        --issued \
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
}
prepare_oor_cred_data

#read -p "Press [ENTER] to issue and grant the OOR credential"

# 24.3 Create OOR credential in QVI, issued to the Person
function create_and_grant_oor_credential() {
    # Check if OOR credential already exists
    oor_said=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_MS" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$OOR_SCHEMA"
    )
    if [[ ! "$oor_said" =~ "false" ]]; then
        print_dark_gray "[QVI] OOR Credential already created"
        return
    fi

    print_lcyan "[QVI] OOR Auth edge Data"
    print_lcyan "$(cat ./oor-auth-edge.json | jq )"

    print_lcyan "[QVI] OOR Credential Data"
    print_lcyan "$(cat ./oor-data.json)"

    echo
    print_green "[QVI] creating and granting OOR credential"

    tsx "${QVI_SIGNIFY_DIR}/qars/qars-oor-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "./" \
      "${SIGTS_AIDS}" \
      "${PERSON_PRE}" \
      "${QVI_SAID}"

    print_yellow "[QVI] Waiting for OOR IPEX messages to be witnessed"
    sleep 5

    echo
    print_lcyan "[QVI] OOR credential created"
    echo
}
create_and_grant_oor_credential

#read -p "Press [ENTER] to admit the OOR credential"

# 24.5. Person: Admit OOR credential from QVI
function admit_oor_credential() {
    # check if OOR has been admitted to receiver
    oor_said=$(tsx "${QVI_SIGNIFY_DIR}/person/person-check-received-credential.ts" \
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
    oor_said=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_MS" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$OOR_SCHEMA"
    )

    echo
    print_yellow "[PERSON] Admitting OOR credential ${oor_said} to ${PERSON}"

    tsx "${QVI_SIGNIFY_DIR}/person/person-admit-credential.ts" \
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
admit_oor_credential

#read -p "Press [ENTER] to present the OOR credential to Sally"
# 25. QVI: Present issued ECR Auth and OOR Auth to Sally (vLEI Reporting API)


function sally_setup() {
    print_yellow "[GLEIF] setting up sally"
    print_yellow "[GLEIF] setting up webhook"
    sally hook demo & # For the webhook Sally will call upon credential presentation
    WEBHOOK_PID=$!

    sleep 3

    print_yellow "[GLEIF] starting sally"
    sally server start \
        --name $SALLY \
        --alias $SALLY \
        --passcode $SALLY_PASSCODE \
        --web-hook http://127.0.0.1:9923 \
        --auth ${GEDA_PRE} & # who will be presenting the credential
    SALLY_PID=$!

    sleep 5
}
sally_setup

#read -p "Press [ENTER] to present the OOR credential to Sally"

function present_oor_cred_to_sally() {
    print_yellow "[QVI] Presenting OOR Credential to Sally"

    tsx "${QVI_SIGNIFY_DIR}/person/person-grant-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${OOR_SCHEMA}" \
      "${QVI_PRE}" \
      "${SALLY_PRE}" \

    start=$EPOCHSECONDS
    present_result=0
    print_dark_gray "[PERSON] Waiting for Sally to receive the OOR Credential"
    while [ $present_result -ne 200 ]; do
      present_result=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:9923/?holder=${PERSON_PRE}")
      print_dark_gray "[PERSON] received ${present_result} from Sally"
      sleep 1
      if (( EPOCHSECONDS-start > 25 )); then
        print_red "[PERSON] TIMEOUT - Sally did not receive the OOR Credential for ${PERSON_NAME} | ${PERSON_PRE}"
        break;
      fi # 15 seconds timeout
    done

    print_green "[PERSON] OOR Credential presented to Sally"
}
present_oor_cred_to_sally

# TODO Add OOR and ECR credential revocation by the QVI
# TODO Add presentation of revoked OOR and ECR credentials to Sally

read -p "Press [Enter] to end the script"

# 26. QVI: Revoke ECR Auth and OOR Auth credentials

# 27. QVI: Present revoked credentials to Sally

print_lcyan "Full chain workflow completed"