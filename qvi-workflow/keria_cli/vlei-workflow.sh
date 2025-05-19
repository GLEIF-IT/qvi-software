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

source color-printing.sh
echo
print_bg_blue "------------------------------vLEI QVI Workflow Script (KERIA & SignifyTS locally)------------------------------"
echo

ENVIRONMENT=local

# Prepare environment
KEYSTORE_DIR=${1:-$HOME/.keri}
QVI_SIGNIFY_DIR=$(dirname "$0")/signify_qvi
QVI_DATA_DIR="${QVI_SIGNIFY_DIR}/qvi_data"
print_yellow "KEYSTORE_DIR: ${KEYSTORE_DIR}"
print_yellow "Using $ENVIRONMENT configuration files"

CONFIG_DIR=./config
INIT_CFG=habery-config-docker.json
WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
WIT_HOST=http://127.0.0.1:5642
SCHEMA_SERVER=http://127.0.0.1:7723
KERIA_SERVER=http://127.0.0.1:3903

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


# Legal Entity AIDs
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


# QAR AIDs - filled in later after KERIA setup
QAR1=galahad
QAR1_PRE=
QAR1_SALT=0ACgCmChLaw_qsLycbqBoxDK

QAR2=lancelot
QAR2_PRE=
QAR2_SALT=0ACaYJJv0ERQmy7xUfKgR6a4

QAR3=tristan
QAR3_SALT=0AAzX0tS638c9SEf5LnxTlj4

QVI_MS=percival
QVI_PRE=

# Person AID
PERSON_NAME="Mordred Delacqs"
PERSON=mordred
PERSON_PRE=
PERSON_SALT=0ABlXAYDE2TkaNDk4UXxxtaN
PERSON_ECR="Consultant"
PERSON_OOR="Advisor"


# Sally - vLEI Reporting API
WEBHOOK_HOST=http://127.0.0.1:9923
SALLY_HOST=http://127.0.0.1:9723
SALLY=sally
SALLY_PASSCODE=VVmRdBTe5YCyLMmYRqTAi
SALLY_SALT=0AD45YWdzWSwNREuAoitH_CC
SALLY_PRE=EHLWiN8Q617zXqb4Se4KfEGteHbn_way2VG5mcHYh5bm

# Registries
GEDA_REGISTRY=vLEI-external
LE_REGISTRY=vLEI-internal
QVI_REGISTRY=vLEI-qvi

# Credentials
QVI_SCHEMA=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
LE_SCHEMA=ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY
ECR_AUTH_SCHEMA=EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g
OOR_AUTH_SCHEMA=EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E
ECR_SCHEMA=EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw
OOR_SCHEMA=EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy

# Assume Sally and Webhook are already running via Docker Compose and entrypoints

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
        print_red "KERIA server not running at ${KERIA_SERVER}"
        cleanup
    fi

    curl ${SALLY_HOST}/health >/dev/null 2>&1
    status=$?
    if [ $status -ne 0 ]; then
        print_red "Sally server not running at ${SALLY_HOST}"
        cleanup
    fi

    curl ${WEBHOOK_HOST}/health >/dev/null 2>&1
    status=$?
    if [ $status -ne 0 ]; then
        print_red "Demo Webhook server not running at ${WEBHOOK_HOST}"
        cleanup
    fi
}
test_dependencies

# KERIA SignifyTS QVI salts
SIGTS_AIDS="qar1|$QAR1|$QAR1_SALT,qar2|$QAR2|$QAR2_SALT,qar3|$QAR3|$QAR3_SALT,person|$PERSON|$PERSON_SALT"

print_yellow "Creating QVI and Person Identifiers from SignifyTS + KERIA"
tsx "${QVI_SIGNIFY_DIR}/qars/qars-and-person-setup.ts" $ENVIRONMENT $QVI_DATA_DIR $SIGTS_AIDS
print_green "QVI and Person Identifiers from SignifyTS + KERIA are "
qvi_setup_data=$(cat "${QVI_DATA_DIR}"/qars-and-person-info.json)
echo $qvi_setup_data | jq
QAR1_PRE=$(echo $qvi_setup_data | jq -r ".QAR1.aid" | tr -d '"')
QAR2_PRE=$(echo $qvi_setup_data | jq -r ".QAR2.aid" | tr -d '"')
QAR3_PRE=$(echo $qvi_setup_data | jq -r ".QAR3.aid" | tr -d '"')
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

# GAR: Create single Sig AIDs (2)
function create_aids() {
    print_green "-----Creating AIDs-----"

    create_temp_icp_cfg
    print_lcyan "Using temporary AID config file heredoc:"
    print_lcyan "${temp_icp_config}"

    create_aid "${GAR1}" "${GAR1_SALT}" "${GAR1_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${GAR2}" "${GAR2_SALT}" "${GAR2_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${LAR1}" "${LAR1_SALT}" "${LAR1_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${LAR2}" "${LAR2_SALT}" "${LAR2_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${SALLY}"    "${SALLY_SALT}"    "${SALLY_PASSCODE}"    "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    rm "$temp_icp_config"
}
create_aids

# GAR: OOBI resolutions between single sig AIDs
function resolve_oobis() {
    exists=$(kli contacts list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GAR2}")
    if [[ "$exists" =~ "${GAR2}" ]]; then
        print_yellow "OOBIs already resolved"
        return
    fi

    GAR1_OOBI="${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    GAR2_OOBI="${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    LAR1_OOBI="${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    LAR2_OOBI="${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
#    SALLY_OOBI="${SALLY_HOST}/oobi" # TODO switch to direct mode self-oobi once it is ready
    SALLY_OOBI="${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"

    OOBIS_FOR_KERIA="gar1|$GAR1_OOBI,gar2|$GAR2_OOBI,lar1|$LAR1_OOBI,lar2|$LAR2_OOBI,sally|$SALLY_OOBI"

    tsx "${QVI_SIGNIFY_DIR}/qars/qars-person-single-sig-oobis-setup.ts" $ENVIRONMENT $SIGTS_AIDS $OOBIS_FOR_KERIA

    echo
    print_lcyan "-----Resolving OOBIs-----"
    print_yellow "Resolving OOBIs for GEDA 1"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${GAR2}" --passcode "${GAR1_PASSCODE}" --oobi "${GAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR1}" --oobi-alias "${LAR1}" --passcode "${GAR1_PASSCODE}" --oobi "${LAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR1}" --oobi-alias "${LAR2}" --passcode "${GAR1_PASSCODE}" --oobi "${LAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR1}"  --passcode "${GAR1_PASSCODE}" --oobi "${QAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR2}"  --passcode "${GAR1_PASSCODE}" --oobi "${QAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR3}"  --passcode "${GAR1_PASSCODE}" --oobi "${QAR3_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR1}" --oobi-alias "${PERSON}"   --passcode "${GAR1_PASSCODE}" --oobi "${PERSON_OOBI}" >/dev/null 2>&1

    print_yellow "Resolving OOBIs for GEDA 2"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${GAR1}" --passcode "${GAR2_PASSCODE}" --oobi "${GAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR1}" --passcode "${GAR2_PASSCODE}" --oobi "${LAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR2}" --passcode "${GAR2_PASSCODE}" --oobi "${LAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR1}"  --passcode "${GAR2_PASSCODE}" --oobi "${QAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR2}"  --passcode "${GAR2_PASSCODE}" --oobi "${QAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR3}"  --passcode "${GAR2_PASSCODE}" --oobi "${QAR3_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${GAR2}" --oobi-alias "${PERSON}"   --passcode "${GAR2_PASSCODE}" --oobi "${PERSON_OOBI}" >/dev/null 2>&1

    print_yellow "Resolving OOBIs for LAR 1"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${LAR2}" --passcode "${LAR1_PASSCODE}" --oobi "${LAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR1}" --passcode "${LAR1_PASSCODE}" --oobi "${GAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR2}" --passcode "${LAR1_PASSCODE}" --oobi "${GAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR1}"  --passcode "${LAR1_PASSCODE}" --oobi "${QAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR2}"  --passcode "${LAR1_PASSCODE}" --oobi "${QAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR3}"  --passcode "${LAR1_PASSCODE}" --oobi "${QAR3_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR1}" --oobi-alias "${PERSON}"   --passcode "${LAR1_PASSCODE}" --oobi "${PERSON_OOBI}" >/dev/null 2>&1

    print_yellow "Resolving OOBIs for LAR 2"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${LAR1}" --passcode "${LAR2_PASSCODE}" --oobi "${LAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR1}" --passcode "${LAR2_PASSCODE}" --oobi "${GAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR2}" --passcode "${LAR2_PASSCODE}" --oobi "${GAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR1}"  --passcode "${LAR2_PASSCODE}" --oobi "${QAR1_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR2}"  --passcode "${LAR2_PASSCODE}" --oobi "${QAR2_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR3}"  --passcode "${LAR2_PASSCODE}" --oobi "${QAR3_OOBI}" >/dev/null 2>&1
    kli oobi resolve --name "${LAR2}" --oobi-alias "${PERSON}"   --passcode "${LAR2_PASSCODE}" --oobi "${PERSON_OOBI}" >/dev/null 2>&1
    
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

    print_dark_gray "Challenge: GEDA 1 -> GEDA 2"
    words_gar1_to_gar2=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR2}" --alias "${GAR2}" --passcode "${GAR2_PASSCODE}" --recipient "${GAR1}" --words "${words_gar1_to_gar2}"
    kli challenge verify  --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --signer "${GAR2}"    --words "${words_gar1_to_gar2}"

    print_dark_gray "Challenge: GEDA 2 -> GEDA 1"
    words_gar2_to_gar1=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --recipient "${GAR2}" --words "${words_gar2_to_gar1}"
    kli challenge verify  --name "${GAR2}" --alias "${GAR2}" --passcode "${GAR2_PASSCODE}" --signer "${GAR1}"    --words "${words_gar2_to_gar1}"

    print_dark_gray "---Challenge responses for QAR---"

    # TODO add qars-challenge-each-other.ts
    print_dark_gray "Challenge: QAR 1 -> QAR 2"
    words_qar1_to_qar2=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --recipient "${QAR1}" --words "${words_qar1_to_qar2}"
    kli challenge verify  --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --signer "${QAR2}"    --words "${words_qar1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> QAR 1"
    words_qar2_to_qar1=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --recipient "${QAR2}" --words "${words_qar2_to_qar1}"
    kli challenge verify  --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --signer "${QAR1}"    --words "${words_qar2_to_qar1}"

    print_dark_gray "---Challenge responses between GEDA and QAR---"

    print_dark_gray "Challenge: GEDA 1 -> QAR 1"
    words_gar1_to_qar1=$(kli challenge generate --out string)
    # TODO add qars-challenge-respond.ts
    # kli challenge respond --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --recipient "${GAR1}" --words "${words_gar1_to_qar1}"
    kli challenge verify  --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --signer "${QAR1}"    --words "${words_gar1_to_qar1}"

    print_dark_gray "Challenge: QAR 1 -> GEDA 1"
    words_qar1_to_gar1=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --recipient "${QAR1}" --words "${words_qar1_to_gar1}"
    # TODO add qars-challenge-verify.ts
    # kli challenge verify  --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --signer "${GAR1}"    --words "${words_qar1_to_gar1}"

    print_dark_gray "Challenge: GEDA 2 -> QAR 2"
    words_gar1_to_qar2=$(kli challenge generate --out string)
    # TODO add qars-challenge-respond.ts
    # kli challenge respond --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --recipient "${GAR1}" --words "${words_gar1_to_qar2}"
    kli challenge verify  --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --signer "${QAR2}"    --words "${words_gar1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> GEDA 1"
    words_qar2_to_gar1=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --recipient "${QAR2}" --words "${words_qar2_to_gar1}"
    # TODO add qars-challenge-verify.ts
    # kli challenge verify  --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --signer "${GAR1}"    --words "${words_qar2_to_gar1}"

    print_dark_gray "---Challenge responses for LE---"

    print_dark_gray "Challenge: LAR 1 -> LAR 2"
    words_lar1_to_lar2=$(kli challenge generate --out string)
    kli challenge respond --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --recipient "${LAR1}" --words "${words_lar1_to_lar2}"
    kli challenge verify  --name "${LAR1}" --alias "${LAR1}" --passcode "${LAR1_PASSCODE}" --signer "${LAR2}"    --words "${words_lar1_to_lar2}"

    print_dark_gray "Challenge: LAR 2 -> LAR 1"
    words_lar2_to_lar1=$(kli challenge generate --out string)
    kli challenge respond --name "${LAR1}" --alias "${LAR1}" --passcode "${LAR1_PASSCODE}" --recipient "${LAR2}" --words "${words_lar2_to_lar1}"
    kli challenge verify  --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --signer "${LAR1}"    --words "${words_lar2_to_lar1}"

    print_dark_gray "---Challenge responses between QAR and LE---"

    print_dark_gray "Challenge: QAR 1 -> LAR 1"
    words_qar1_to_lar1=$(kli challenge generate --out string)
    kli challenge respond --name "${LAR1}" --alias "${LAR1}" --passcode "${LAR1_PASSCODE}" --recipient "${QAR1}" --words "${words_qar1_to_lar1}"
    # TODO add qars-challenge-verify.ts
    # kli challenge verify  --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --signer "${LAR1}"    --words "${words_qar1_to_lar1}"

    print_dark_gray "Challenge: LAR 1 -> QAR 1"
    words_lar1_to_qar1=$(kli challenge generate --out string)
    # TODO add qars-challenge-respond.ts
    # kli challenge respond --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --recipient "${LAR1}" --words "${words_lar1_to_qar1}"
    kli challenge verify  --name "${LAR1}" --alias "${LAR1}" --passcode "${LAR1_PASSCODE}" --signer "${QAR1}"    --words "${words_lar1_to_qar1}"

    print_dark_gray "Challenge: QAR 2 -> LAR 2"
    words_qar2_to_lar2=$(kli challenge generate --out string)
    kli challenge respond --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --recipient "${QAR2}" --words "${words_qar2_to_lar2}"
    # TODO add qars-challenge-verify.ts
    # kli challenge verify  --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --signer "${LAR2}"    --words "${words_qar2_to_lar2}"

    print_dark_gray "Challenge: LAR 2 -> QAR 2"
    words_lar2_to_qar2=$(kli challenge generate --out string)
    # TODO add qars-challenge-respond.ts
    # kli challenge respond --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --recipient "${LAR2}" --words "${words_lar2_to_qar2}"
    kli challenge verify  --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --signer "${QAR2}"    --words "${words_lar2_to_qar2}"

    print_green "-----Finished challenge and response-----"
}
# TODO enable this after challenge response with SignifyTS is integrated
#challenge_response

# 4. GAR: Create Multisig AID (GEDA)
function create_geda_multisig() {
    exists=$(kli list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | grep "${GEDA_NAME}")
    if [[ "$exists" =~ "${GEDA_NAME}" ]]; then
        print_dark_gray "[External] GEDA Multisig AID ${GEDA_NAME} already exists"
        return
    fi

    echo
    print_yellow "[External] Multisig Inception for GEDA"

    echo
    read -r -d '' MULTISIG_ICP_CONFIG_JSON << EOM
{
  "aids": [
    "${GAR1_PRE}",
    "${GAR2_PRE}"
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
    print_yellow "[External] Multisig Inception from ${GAR1}: ${GAR1_PRE}"
    kli multisig incept --name ${GAR1} --alias ${GAR1} \
        --passcode ${GAR1_PASSCODE} \
        --group ${GEDA_NAME} \
        --file "${temp_multisig_config}" &
    pid=$!
    PID_LIST+=" $pid"

    echo

    kli multisig join --name ${GAR2} \
        --passcode ${GAR2_PASSCODE} \
        --group ${GEDA_NAME} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    echo
    print_yellow "[External] Multisig Inception { ${GAR1}, ${GAR2} } - wait for signatures"
    echo
    wait $PID_LIST

    exists=$(kli list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | grep "${GEDA_NAME}")
    if [[ ! "$exists" =~ "${GEDA_NAME}" ]]; then
        print_red "[External] GEDA Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name ${GAR1} --alias ${GEDA_NAME} --passcode ${GAR1_PASSCODE} | awk '/Identifier:/ {print $2}')
    print_green "[External] GEDA Multisig AID ${GEDA_NAME} with prefix: ${ms_prefix}"

    rm "$temp_multisig_config"
}
create_geda_multisig

# Create Legal Entity Multisig
function create_le_multisig() {
    exists=$(kli list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" | grep "${LE_NAME}")
    if [[ "$exists" =~ "${LE_NAME}" ]]; then
        print_dark_gray "[LE] LE Multisig AID ${LE_NAME} already exists"
        return
    fi

    echo
    print_yellow "[LE] Multisig Inception for LE"

    echo
    print_yellow "[LE] Multisig Inception temp config file."
    read -r -d '' MULTISIG_ICP_CONFIG_JSON << EOM
{
  "aids": [
    "${LAR1_PRE}",
    "${LAR2_PRE}"
  ],
  "transferable": true,
  "wits": ["${WAN_PRE}"],
  "toad": 1,
  "isith": "2",
  "nsith": "2"
}
EOM

    print_lcyan "[LE] Using temporary multisig config file as heredoc:"
    print_lcyan "${MULTISIG_ICP_CONFIG_JSON}"

    # create temporary file to store json
    temp_multisig_config=$(mktemp)

    # write JSON content to the temp file
    echo "$MULTISIG_ICP_CONFIG_JSON" > "$temp_multisig_config"

    # Follow commands run in parallel
    print_yellow "[LE] Multisig Inception from ${LAR1}: ${LAR1_PRE}"
    kli multisig incept --name ${LAR1} --alias ${LAR1} \
        --passcode ${LAR1_PASSCODE} \
        --group ${LE_NAME} \
        --file "${temp_multisig_config}" &
    pid=$!
    PID_LIST+=" $pid"

    echo

    kli multisig join --name ${LAR2} \
        --passcode ${LAR2_PASSCODE} \
        --group ${LE_NAME} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    echo
    print_yellow "[LE] Multisig Inception { ${LAR1}, ${LAR2} } - wait for signatures"
    echo
    wait $PID_LIST

    exists=$(kli list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" | grep "${LE_NAME}")
    if [[ ! "$exists" =~ "${LE_NAME}" ]]; then
        print_red "[LE] LE Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name ${LAR1} --alias ${LE_NAME} --passcode ${LAR1_PASSCODE} | awk '/Identifier:/ {print $2}')
    print_green "[LE] LE Multisig AID ${LE_NAME} with prefix: ${ms_prefix}"

    rm "$temp_multisig_config"
}
create_le_multisig

# GAR: Generate  and resolve OOBI for GEDA
GEDA_OOBI=""
LE_OOBI=""
function resolve_geda_and_LE_OOBIs() {
    GEDA_OOBI=$(kli oobi generate --name ${GAR1} --passcode ${GAR1_PASSCODE} --alias ${GEDA_NAME} --role witness)
    LE_OOBI=$(kli oobi generate --name ${LAR1} --passcode ${LAR1_PASSCODE} --alias ${LE_NAME} --role witness)
    MULTISIG_OOBIS="gedaName|$GEDA_OOBI,leName|$LE_OOBI"
    echo "GEDA OOBI: ${GEDA_OOBI}"
    echo "LE OOBI: ${LE_OOBI}"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-resolve-geda-and-le-oobis.ts" $ENVIRONMENT $SIGTS_AIDS $MULTISIG_OOBIS
}
resolve_geda_and_LE_OOBIs

# Create delegated multisig QVI AID
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
    local delegator_prefix=$(kli status --name ${GAR1} --alias ${GEDA_NAME} --passcode ${GAR1_PASSCODE} | awk '/Identifier:/ {print $2}')
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

    print_yellow "GAR1 confirm delegated inception"
    kli delegate confirm --name ${GAR1} --alias ${GEDA_NAME} --passcode ${GAR1_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"
    print_yellow "GAR2 confirm delegated inception"
    kli delegate confirm --name ${GAR2} --alias ${GEDA_NAME} --passcode ${GAR2_PASSCODE} --interact --auto &
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

# QVI: Perform endpoint role authorizations and generate OOBI for QVI to send to GEDA
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

# Delegated multisig rotation
function qvi_rotate() {
  QVI_MULTISIG_SEQ_NO=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}"
      )
    if [[ "$QVI_MULTISIG_SEQ_NO" -ge 1 ]]; then
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


    # GEDA participants Query keystate from QARs
    print_yellow "[GEDA] Query QVI multisig participants to discover new delegated rotation and complete delegation for KERIpy 1.1.x+"
    print_yellow "[GEDA] GAR1 querying QAR1, 2, and 3 multisig for new key state"
    kli query --name ${GAR1} --alias ${GAR1} --passcode ${GAR1_PASSCODE} --prefix "${QAR1_PRE}" &
    pid=$!
    PID_LIST+=" $pid"
    kli query --name ${GAR1} --alias ${GAR1} --passcode ${GAR1_PASSCODE} --prefix "${QAR2_PRE}" &
    pid=$!
    PID_LIST+=" $pid"
    kli query --name ${GAR1} --alias ${GAR1} --passcode ${GAR1_PASSCODE} --prefix "${QAR3_PRE}" &
    pid=$!
    PID_LIST+=" $pid"


    print_yellow "[GEDA] GAR2 querying QAR1, 2, and 3 multisig for new key state"
    kli query --name ${GAR2} --alias ${GAR2} --passcode ${GAR2_PASSCODE} --prefix "${QAR1_PRE}" &
    pid=$!
    PID_LIST+=" $pid"
    kli query --name ${GAR2} --alias ${GAR2} --passcode ${GAR2_PASSCODE} --prefix "${QAR2_PRE}" &
    pid=$!
    PID_LIST+=" $pid"
    kli query --name ${GAR2} --alias ${GAR2} --passcode ${GAR2_PASSCODE} --prefix "${QAR3_PRE}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    print_yellow "GAR1 confirm delegated rotation"
    kli delegate confirm --name ${GAR1} --alias ${GEDA_NAME} --passcode ${GAR1_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"

    print_yellow "GAR2 confirm delegated rotation"
    kli delegate confirm --name ${GAR2} --alias ${GEDA_NAME} --passcode ${GAR2_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"

    print_yellow "[GEDA] Waiting 5s on delegated rotation completion"
    wait $PID_LIST
    sleep 5

    print_lcyan "[QVI] QARs refresh GEDA multisig keystate to discover GEDA approval of delegated rotation"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-refresh-geda-multisig-state.ts" $ENVIRONMENT $SIGTS_AIDS $GEDA_PRE

    print_yellow "[QVI] Waiting 8s for QARs to refresh GEDA keystate and complete delegation"
    sleep 8
}
qvi_rotate


# GEDA and LE: Resolve QVI OOBI
function resolve_qvi_oobi() {
    exists=$(kli contacts list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${QVI_MS}")
    if [[ "$exists" =~ "${QVI_MS}" ]]; then
        print_yellow "QVI OOBIs already resolved"
        return
    fi

    echo
    echo "QVI OOBI: ${QVI_OOBI}"
    print_yellow "Resolving QVI OOBI for GEDA and LE"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QVI_MS}" --passcode "${GAR1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QVI_MS}" --passcode "${GAR2_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QVI_MS}" --passcode "${LAR1_PASSCODE}" --oobi "${QVI_OOBI}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QVI_MS}" --passcode "${LAR2_PASSCODE}" --oobi "${QVI_OOBI}"

    print_yellow "Resolving QVI OOBI for Person"
    tsx "${QVI_SIGNIFY_DIR}/person-resolve-qvi-oobi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${QVI_OOBI}"
    echo
}
resolve_qvi_oobi

function qvi_resolve_sally_oobi() {
  # SALLY_OOBI="${SALLY_HOST}/oobi" # TODO switch to direct mode self-oobi once it is ready
  SALLY_OOBI="${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"
  alias="sally"

  tsx "${QVI_SIGNIFY_DIR}/qars/qvi-resolve-oobi.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${alias}" \
      "${SALLY_OOBI}"
}
qvi_resolve_sally_oobi

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
    PID_LIST=""
    kli vc registry incept \
        --name ${GAR1} \
        --alias ${GEDA_NAME} \
        --passcode ${GAR1_PASSCODE} \
        --usage "QVI Credential Registry for GEDA" \
        --nonce ${NONCE} \
        --registry-name ${GEDA_REGISTRY} &
    pid=$!
    PID_LIST+=" $pid"

    kli vc registry incept \
        --name ${GAR2} \
        --alias ${GEDA_NAME} \
        --passcode ${GAR2_PASSCODE} \
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

# GEDA: Create QVI credential
function prepare_qvi_cred_data() {
    print_bg_blue "[External] Preparing QVI credential data"
    read -r -d '' QVI_CRED_DATA << EOM
{
    "LEI": "${LE_LEI}"
}
EOM

    echo "$QVI_CRED_DATA" > ./qvi-cred-data.json
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
    print_lcyan "[External] QVI Credential Data"
    print_lcyan "$(cat ./qvi-cred-data.json)"

    KLI_TIME=$(kli time) # use consistent time for both invocations of `kli vc create` so they compute the same event digest (SAID).
    PID_LIST=""
    kli vc create \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./qvi-cred-data.json \
        --rules @./rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${GAR2}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR2_PASSCODE}" \
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
        --schema "${QVI_SCHEMA}")

    echo
    print_yellow $'[External] IPEX GRANTing QVI credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"
    KLI_TIME=$(kli time)
    kli ipex grant \
        --name ${GAR1} \
        --passcode ${GAR1_PASSCODE} \
        --alias ${GEDA_NAME} \
        --said ${SAID} \
        --recipient ${QVI_PRE} \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name ${GAR2} \
        --passcode ${GAR2_PASSCODE} \
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

# QVI: Admit QVI credential from GEDA
function admit_qvi_credential() {
    QVI_CRED_SAID=$(kli vc list \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
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

# Create QVI credential registry
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

# QVI: Prepare, create, and Issue LE credential to GEDA
# Prepare LE edge data
function prepare_qvi_edge() {
    QVI_CRED_SAID=$(kli vc list \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
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

# Prepare LE credential data
function prepare_le_cred_data() {
    print_yellow "[QVI] Preparing LE credential data"
    read -r -d '' LE_CRED_DATA << EOM
{
    "LEI": "${LE_LEI}"
}
EOM

    echo "$LE_CRED_DATA" > ./legal-entity-data.json
}
prepare_le_cred_data

# Create LE credential in QVI
function create_and_grant_le_credential() {
    # Check if LE credential already exists
    le_said=$(tsx "${QVI_SIGNIFY_DIR}/qars/qar-check-issued-credential.ts" \
      $ENVIRONMENT \
      $QVI_MS \
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
    print_lcyan "$(cat ./qvi-edge.json | jq )"

    print_lcyan "[QVI] Legal Entity Credential Data"
    print_lcyan "$(cat ./legal-entity-data.json)"

    tsx "${QVI_SIGNIFY_DIR}/qars/qars-le-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "./" \
      "${SIGTS_AIDS}" \
      "${LE_PRE}" \
      "${QVI_SAID}"

    echo
    print_lcyan "[QVI] LE Credential created"
    print_dark_gray "Waiting 10 seconds for LE credential to be witnessed..."
    sleep 10
    echo
}
create_and_grant_le_credential

# LE: Admit LE credential from QVI
function admit_le_credential() {
    VC_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --said \
        --schema "${LE_SCHEMA}")
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
        --said | uniq) # there are three grant messages, one from each QAR, yet all share the same SAID, so uniq condenses them to one

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
    kli ipex admit \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    print_green "[LE] Admitting LE Credential ${SAID} to ${LE_NAME} as ${LAR2}"
    kli ipex join \
        --name "${LAR2}" \
        --passcode "${LAR2_PASSCODE}" \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    print_yellow "[LE] Waiting 8s for LE IPEX messages to be witnessed"
    sleep 8

    echo
    print_green "[LE] Admitted LE credential"
    echo
}
admit_le_credential

# LE: Create LE credential registry
function create_le_reg() {
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
    NONCE=$(kli nonce)
    PID_LIST=""
    kli vc registry incept \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --usage "Legal Entity Credential Registry for LE" \
        --nonce "${NONCE}" \
        --registry-name "${LE_REGISTRY}" &
    pid=$!
    PID_LIST+=" $pid"

    kli vc registry incept \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --usage "Legal Entity Credential Registry for LE" \
        --nonce "${NONCE}" \
        --registry-name "${LE_REGISTRY}" &
    pid=$!
    PID_LIST+=" $pid"
    wait $PID_LIST

    echo
    print_green "[LE] Legal Entity Credential Registry created for LE"
    echo
}
create_le_reg

# LE: Prepare, create, and Issue ECR Auth & OOR Auth credential to QVI
# prepare LE edge to ECR auth cred
function prepare_le_edge() {
    LE_SAID=$(kli vc list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --said \
        --schema "${LE_SCHEMA}")
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

    echo "$LE_EDGE_JSON" > ./legal-entity-edge.json
    kli saidify --file ./legal-entity-edge.json
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

    echo "$ECR_AUTH_DATA_JSON" > ./ecr-auth-data.json
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
        --schema "${ECR_AUTH_SCHEMA}")
    if [ ! -z "${SAID}" ]; then
        print_dark_gray "[LE] ECR Auth credential already created"
        return
    fi

    echo
    print_green "[LE] LE creating ECR Auth credential"

    print_lcyan "[LE] Legal Entity edge JSON"
    print_lcyan "$(cat ./legal-entity-edge.json | jq)"

    print_lcyan "[LE] ECR Auth data JSON"
    print_lcyan "$(cat ./ecr-auth-data.json)"

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./ecr-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./ecr-auth-rules.json \
        --time "${KLI_TIME}" &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
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
    print_yellow "[LE] Waiting 8s ECR Auth for IPEX messages to be witnessed"
    sleep 8

    echo
    print_lcyan "[LE] LE created ECR Auth credential"
    echo
}
create_ecr_auth_credential

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
    if [ "${GRANT_COUNT}" -ge 1 ]; then
        print_dark_gray "[LE] ECR Auth credential grant already granted"
        return
    fi
    SAID=$(kli vc list \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --issued \
        --said \
        --schema ${ECR_AUTH_SCHEMA})

    echo
    print_yellow $'[LE] IPEX GRANTing ECR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI '"${QVI_PRE}"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex grant \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

#    kli ipex join \
#        --name "${LAR2}" \
#        --passcode "${LAR2_PASSCODE}" \
#        --auto &
    kli ipex grant \
        --name "${LAR2}" \
        --passcode "${LAR2_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[LE] Waiting for IPEX ECR Auth grant messages to be witnessed"
    sleep 8

    echo
    print_green "[LE] ECR Auth Credential granted to QVI"
    echo
}
grant_ecr_auth_credential

# Admit ECR Auth credential from LE
function admit_ecr_auth_credential() {
    ECR_AUTH_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
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
    print_yellow "[QVI] Admitting ECR Auth Credential ${ECR_AUTH_SAID} from LE"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${LE_PRE}" \
      "${ECR_AUTH_SAID}"

    print_yellow "[QVI] Waiting 8s for IPEX admit messages to be witnessed"
    sleep 8

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

    echo "$OOR_AUTH_DATA_JSON" > ./oor-auth-data.json
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
        --schema "${OOR_AUTH_SCHEMA}")
    if [ ! -z "${SAID}" ]; then
        print_yellow "[QVI] OOR Auth credential already created"
        return
    fi

    print_lcyan "[LE] OOR Auth data JSON"
    print_lcyan "$(cat ./oor-auth-data.json)"

    echo
    print_green "[LE] LE creating OOR Auth credential"

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${OOR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./oor-auth-data.json \
        --edges @./legal-entity-edge.json \
        --rules @./rules.json \
        --time "${KLI_TIME}" &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
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
    print_lcyan "[LE] LE created OOR Auth credential"
    echo
}
create_oor_auth_credential

# Grant OOR Auth credential to QVI
function grant_oor_auth_credential() {
    # This relies on the last grant being the OOR Auth credential
    GRANT_COUNT=$(kli ipex list \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --type "grant" \
        --passcode "${LAR1_PASSCODE}" \
        --sent \
        --said | wc -l | tr -d ' ') # get grant count, remove whitespace
    if [ "${GRANT_COUNT}" -ge 2 ]; then
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
        tail -1) # get the last credential, the OOR Auth credential

    echo
    print_yellow $'[LE] IPEX GRANTing OOR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex grant \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

#    kli ipex join \
#        --name "${LAR2}" \
#        --passcode "${LAR2_PASSCODE}" \
#        --auto &
    kli ipex grant \
        --name "${LAR2}" \
        --passcode "${LAR2_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[LE] Waiting for OOR Auth IPEX grant messages to be witnessed"
    sleep 5

    echo
    print_green "[LE] Granted OOR Auth credential to QVI"
    echo
}
grant_oor_auth_credential

# QVI: Admit OOR Auth credential
function admit_oor_auth_credential() {
    OOR_AUTH_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
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
    print_yellow "[QVI] Admitting OOR Auth Credential ${OOR_AUTH_SAID} from LE"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${LE_PRE}" \
      "${OOR_AUTH_SAID}"

    print_yellow "[QVI] Waiting for OOR Auth IPEX admit messages to be witnessed"
    sleep 8

    echo
    print_green "[QVI] Admitted OOR Auth Credential"
    echo
}
admit_oor_auth_credential

# Create and Issue ECR credential to Person
# Prepare ECR Auth edge data
function prepare_ecr_auth_edge() {
    ECR_AUTH_SAID=$(kli vc list \
        --name ${LAR1} \
        --alias ${LE_NAME} \
        --passcode "${LAR1_PASSCODE}" \
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

    echo "${ECR_CRED_DATA}" > ./ecr-data.json
}
prepare_ecr_cred_data

# Create ECR credential in QVI, issued to the Person
# QVI Grant ECR credential to PERSON
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

# Person: Admit ECR credential from QVI
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

# QVI: Issue, grant OOR to Person and Person admits OOR
# Prepare OOR Auth edge data
function prepare_oor_auth_edge() {
    OOR_AUTH_SAID=$(kli vc list \
        --name ${LAR1} \
        --alias ${LE_NAME} \
        --passcode "${LAR1_PASSCODE}" \
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

    echo "${OOR_CRED_DATA}" > ./oor-data.json
}
prepare_oor_cred_data

# Create OOR credential in QVI, issued to the Person
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

# Person: Admit OOR credential from QVI
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

# present credentials to Sally
# QVI: Present LE credential Sally (vLEI Reporting API)

function present_le_cred_to_sally() {
  print_yellow "[QVI] Presenting LE Credential to Sally"

  tsx "${QVI_SIGNIFY_DIR}/qars/qars-present-credential.ts" \
    "${ENVIRONMENT}" \
    "${QVI_MS}" \
    "${SIGTS_AIDS}" \
    "${LE_SCHEMA}" \
    "${QVI_PRE}" \
    "${LE_PRE}"\
    "${SALLY_PRE}"

  start=$(date +%s)
  present_result=0
  print_dark_gray "[QVI] Waiting for Sally to receive the LE Credential"
  while [ $present_result -ne 200 ]; do
    present_result=$(curl -s -o /dev/null -w "%{http_code}" "${SALLY_HOST}/?holder=${LE_PRE}")
    print_dark_gray "[QVI] received ${present_result} from Sally"
    sleep 1
    if (( $(date +%s)-start > 25 )); then
      print_red "[QVI] TIMEOUT - Sally did not receive the LE Credential for ${LE_NAME} | ${LE_PRE}"
      break;
    fi # 25 seconds timeout
  done

  print_green "[PERSON] OOR Credential presented to Sally"

}
present_le_cred_to_sally

# PERSON: Present OOR credential to Sally (vLEI Reporting API)
function present_oor_cred_to_sally() {
    print_yellow "[QVI] Presenting OOR Credential to Sally"

    tsx "${QVI_SIGNIFY_DIR}/person/person-grant-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${OOR_SCHEMA}" \
      "${QVI_PRE}" \
      "${SALLY_PRE}"

    start=$(date +%s)
    present_result=0
    print_dark_gray "[PERSON] Waiting for Sally to receive the OOR Credential"
    while [ $present_result -ne 200 ]; do
      present_result=$(curl -s -o /dev/null -w "%{http_code}" "${SALLY_HOST}/?holder=${PERSON_PRE}")
      print_dark_gray "[PERSON] received ${present_result} from Sally"
      sleep 1
      if (( $(date +%s)-start > 25 )); then
        print_red "[PERSON] TIMEOUT - Sally did not receive the OOR Credential for ${PERSON_NAME} | ${PERSON_PRE}"
        break;
      fi # 25 seconds timeout
    done

    print_green "[PERSON] OOR Credential presented to Sally"
}
present_oor_cred_to_sally

# TODO Add OOR and ECR credential revocation by the QVI
# TODO Add presentation of revoked OOR and ECR credentials to Sally

# QVI: Revoke ECR Auth and OOR Auth credentials
# QVI: Present revoked credentials to Sally

print_lcyan "Full chain workflow completed"