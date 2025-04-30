#!/usr/bin/env bash
# qvi-workflow-kli.sh
# See the README.md document accompanying this script for more information.
# Runs the entire QVI issuance workflow end to end starting from multisig AID creation of the
# GLEIF External Delegated multisig AID (GEDA) and Qualified vLEI Issuer (QVI) multisig AID,
# all the way to OOR and ECR credential issuance to the Person AID for usage in presenting
# credentials to the vLEI Reporting API (Sally).
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
#
# WARNING: This currently depends on v0.10.1+ of Sally being available on the PATH which uses a different
#          version of KERI (1.2.6) than the KLI (1.1.32) here uses. Be sure to install the KLI first and
#          then install sally globally on your machine prior to running this script.
#
# in order to complete successfully. This script also runs the webhook with "sally hook demo" that
# Sally sends a webhook call to.

source ./color-printing.sh

KEYSTORE_DIR=${1:-$HOME/.keri}
NO_CHALLENGE=${2:-true}
DIRECT_MODE_SALLY=${3:-false}

if $NO_CHALLENGE; then
    print_dark_gray "skipping challenge and response"
fi

SALLY_PID=""
WEBHOOK_PID=""

START_TIME=$(date +%s)

# send sigterm to sally PID
function sally_teardown() {
  if [ -n "$SALLY_PID" ]; then
    kill -SIGTERM $SALLY_PID
  fi
  if [ -n "$WEBHOOK_PID" ]; then
    kill -SIGTERM $WEBHOOK_PID
  fi
}

trap interrupt INT

function interrupt() {
  # Triggered on Control + C, cleans up resources the script uses
  print_red "Caught Ctrl+C, Exiting script..."
  cleanup
  exit 0
}

function cleanup() {
    sally_teardown
}

echo
print_bg_blue "------------------------------vLEI QVI Workflow Script (KLI)------------------------------"
echo

# Prepare environment
print_dark_gray "KEYSTORE_DIR: ${KEYSTORE_DIR}"
echo

CONFIG_DIR=./config
INIT_CFG=common-habery-config.json
WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
WIT_HOST=http://127.0.0.1:5642
SCHEMA_SERVER=http://127.0.0.1:7723

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

# Legal Entity AIDs
LAR1=elaine
LAR1_PRE=ELTDtBrcFsHTMpfYHIJFvuH6awXY1rKq4w6TBlGyucoF
LAR1_SALT=0AB90ainJghoJa8BzFmGiEWa
LAR1_PASSCODE=tcc6Yj4JM8MfTDs1IiidP

LAR2=finn
LAR2_PRE=EBpwQouCaOlglS6gYo0uD0zLbuAto5sUyy7AK9_O0aI1
LAR2_SALT=0AA4m2NxBxn0w5mM9oZR2kHz
LAR2_PASSCODE=2pNNtRkSx8jFd7HWlikcg

LE_MS_NAME=gareth
LE_MS_PRE=EBsmQ6zMqopxMWhfZ27qXVpRKIsRNKbTS_aXMtWt67eb

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
QVI_REGISTRY=vLEI-qvi
LE_REGISTRY=vLEI-internal

# Credentials
QVI_SCHEMA=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
LE_SCHEMA=ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY
OOR_AUTH_SCHEMA=EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E
ECR_AUTH_SCHEMA=EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g
OOR_SCHEMA=EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy
ECR_SCHEMA=EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw

SALLY_HOST=http://127.0.0.1:9723

function test_dependencies() {
  # check that sally is installed and available on the PATH
  command -v kli >/dev/null 2>&1 || { print_red "kli is not installed or not available on the PATH. Aborting."; exit 1; }
  command -v tsx >/dev/null 2>&1 || { print_red "tsx is not installed or not available on the PATH. Aborting."; exit 1; }
  command -v jq >/dev/null 2>&1 || { print_red "jq is not installed or not available on the PATH. Aborting."; exit 1; }
  command -v sally >/dev/null 2>&1 || { print_red "sally is not installed or not available on the PATH. Aborting."; exit 1; }

  # check that witnesses are up
  curl ${WIT_HOST}/oobi/${WAN_PRE} >/dev/null 2>&1
  status=$?
  if [ $status -ne 0 ]; then
      print_red "Witness server not running at ${WIT_HOST}"
      cleanup
      exit 0
  fi

  # Check that vLEI-server is up
  curl ${SCHEMA_SERVER}/oobi/${QVI_SCHEMA} >/dev/null 2>&1
  status=$?
  if [ $status -ne 0 ]; then
      print_red "vLEI-server not running at ${SCHEMA_SERVER}"
      cleanup
      exit 0
  fi
}
test_dependencies

################# Functions
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
function create_keystore_and_aid() {
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

    echo
    print_lcyan "Bootstrapping keystore (Habery) for ${NAME}..."
    kli init \
        --name "${NAME}" \
        --salt "${SALT}" \
        --passcode "${PASSCODE}" \
        --config-dir "${CONFIG_DIR}" \
        --config-file "${CONFIG_FILE}"
    echo
    print_lcyan "Creating single signature identifier for ${NAME}..."
    kli incept \
        --name "${NAME}" \
        --alias "${NAME}" \
        --passcode "${PASSCODE}" \
        --file "${ICP_FILE}"
    PREFIX=$(kli status  --name "${NAME}"  --alias "${NAME}"  --passcode "${PASSCODE}" | awk '/Identifier:/ {print $2}' | tr -d " \t\n\r" )
    # Need this since resolving with bootstrap config file isn't working
    print_dark_gray "Created AID: ${NAME} with prefix: ${PREFIX}"
    print_green $'\tPrefix:'" ${PREFIX}"
}

# GAR: Create single Sig AIDs (2)
function create_aids() {
    print_green "------------------------------Creating Autonomic Identifiers (AIDs)------------------------------"
    create_temp_icp_cfg
    create_keystore_and_aid "${GAR1}"   "${GAR1_SALT}"   "${GAR1_PASSCODE}"   "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_keystore_and_aid "${GAR2}"   "${GAR2_SALT}"   "${GAR2_PASSCODE}"   "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_keystore_and_aid "${LAR1}"   "${LAR1_SALT}"   "${LAR1_PASSCODE}"   "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_keystore_and_aid "${LAR2}"   "${LAR2_SALT}"   "${LAR2_PASSCODE}"   "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_keystore_and_aid "${QAR1}"   "${QAR1_SALT}"   "${QAR1_PASSCODE}"   "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_keystore_and_aid "${QAR2}"   "${QAR2_SALT}"   "${QAR2_PASSCODE}"   "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_keystore_and_aid "${PERSON}" "${PERSON_SALT}" "${PERSON_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_keystore_and_aid "${SALLY}"  "${SALLY_SALT}"  "${SALLY_PASSCODE}"  "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    rm "$temp_icp_config"
}
create_aids

# Indirect mode Sally
SALLY_OOBI="${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"
function sally_setup() {
    print_yellow "[GLEIF] setting up webhook"
    sally hook demo & # For the webhook Sally will call upon credential presentation
    WEBHOOK_PID=$!

    if $DIRECT_MODE_SALLY; then
      print_yellow "[GLEIF] starting sally on ${SALLY_HOST} in direct mode"
      sally server start \
        --name $SALLY \
        --alias $SALLY \
        --salt $SALLY_SALT \
        --config-dir sally \
        --config-file sally-habery.json \
        --incept-file sally-incept.json \
        --passcode $SALLY_PASSCODE \
        --web-hook http://127.0.0.1:9923 \
        --auth "${GEDA_PRE}" & # who will be presenting the credential
      SALLY_PID=$!
    else
      print_yellow "[GLEIF] starting sally on ${SALLY_HOST} in indirect (mailbox) mode"
      sally server start \
        --name $SALLY \
        --alias $SALLY \
        --salt $SALLY_SALT \
        --config-dir sally \
        --config-file sally-habery.json \
        --passcode $SALLY_PASSCODE \
        --web-hook http://127.0.0.1:9923 \
        --auth "${GEDA_PRE}" & # who will be presenting the credential
      SALLY_PID=$!
    fi
    print_yellow "[GLEIF] waiting 8 seconds for Sally to start..."
    sleep 8
}
sally_setup

print_yellow "[GLEIF] waiting for Sally to start..."
# Direct mode Sally
#SALLY_OOBI="http://127.0.0.1:9723/oobi/ECu-Lt62sUHkdZPnhIBoSuQrJWbi4Rqf_xUBOOJqAR7K/controller"

# GAR: OOBI resolutions between single sig AIDs
function resolve_oobis() {
    exists=$(kli contacts list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GAR2}")
    if [[ "$exists" =~ "${GAR2}" ]]; then
        print_yellow "OOBIs already resolved"
        return
    fi

    echo
    print_green "------------------------------Connecting Keystores with OOBI Resolutions------------------------------"
    print_yellow "Resolving OOBIs for GAR1"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${GAR2}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR1}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${QAR2}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${LAR1}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${LAR2}"   --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "$SALLY"    --passcode "${GAR1_PASSCODE}" --oobi "${SALLY_OOBI}"
    kli oobi resolve --name "${GAR1}" --oobi-alias "${PERSON}" --passcode "${GAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for GAR2"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${GAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${QAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR1}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${LAR2}"   --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "$SALLY"    --passcode "${GAR2_PASSCODE}" --oobi "${SALLY_OOBI}"
    kli oobi resolve --name "${GAR2}" --oobi-alias "${PERSON}" --passcode "${GAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for LE 1"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${LAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${GAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR1}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${QAR2}"   --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR1}" --oobi-alias "${PERSON}" --passcode "${LAR1_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for LE 2"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${LAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${GAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR1}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${QAR2}"   --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${LAR2}" --oobi-alias "${PERSON}" --passcode "${LAR2_PASSCODE}" --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"

    print_yellow "Resolving OOBIs for QAR 1"
    kli oobi resolve --name "${QAR1}" --oobi-alias "${QAR2}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR1}" --oobi-alias "${GAR1}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR1}" --oobi-alias "${GAR2}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR1}" --oobi-alias "${LAR1}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR1}" --oobi-alias "${LAR2}"   --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR1}" --oobi-alias "${PERSON}" --passcode "${QAR1_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR1}" --oobi-alias "$SALLY"    --passcode "${QAR1_PASSCODE}"  --oobi "${SALLY_OOBI}"

    print_yellow "Resolving OOBIs for QAR 2"
    kli oobi resolve --name "${QAR2}" --oobi-alias "${QAR1}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR2}" --oobi-alias "${GAR2}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR2}" --oobi-alias "${GAR1}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR2}" --oobi-alias "${LAR1}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR2}" --oobi-alias "${LAR2}"   --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR2}" --oobi-alias "${PERSON}" --passcode "${QAR2_PASSCODE}"  --oobi "${WIT_HOST}/oobi/${PERSON_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${QAR2}" --oobi-alias "$SALLY"    --passcode "${QAR2_PASSCODE}"  --oobi "${SALLY_OOBI}"

    print_yellow "Resolving OOBIs for Person"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${GAR1}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${GAR2}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${GAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${QAR1}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${QAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${QAR2}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${QAR2_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${LAR1}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${LAR1_PRE}/witness/${WAN_PRE}"
    kli oobi resolve --name "${PERSON}"  --oobi-alias "${LAR2}" --passcode "${PERSON_PASSCODE}"   --oobi "${WIT_HOST}/oobi/${LAR2_PRE}/witness/${WAN_PRE}"
    
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

    print_green "------------------------------Authenticating Keystore control with Challenge Responses------------------------------"

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
    kli challenge respond --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --recipient "${QAR1}" --words "${words_qar1_to_qar2}"
    kli challenge verify  --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --signer "${QAR2}"    --words "${words_qar1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> QAR 1"
    words_qar2_to_qar1=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --recipient "${QAR2}" --words "${words_qar2_to_qar1}"
    kli challenge verify  --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --signer "${QAR1}"    --words "${words_qar2_to_qar1}"

    print_dark_gray "---Challenge responses between GARs and QARs---"
    
    print_dark_gray "Challenge: GAR1 -> QAR 1"
    words_gar1_to_qar1=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --recipient "${GAR1}" --words "${words_gar1_to_qar1}"
    kli challenge verify  --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --signer "${QAR1}"    --words "${words_gar1_to_qar1}"

    print_dark_gray "Challenge: QAR 1 -> GAR1"
    words_qar1_to_gar1=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --recipient "${QAR1}" --words "${words_qar1_to_gar1}"
    kli challenge verify  --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --signer "${GAR1}"    --words "${words_qar1_to_gar1}"

    print_dark_gray "Challenge: GAR2 -> QAR 2"
    words_gar1_to_qar2=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --recipient "${GAR1}" --words "${words_gar1_to_qar2}"
    kli challenge verify  --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --signer "${QAR2}"    --words "${words_gar1_to_qar2}"

    print_dark_gray "Challenge: QAR 2 -> GAR1"
    words_qar2_to_gar1=$(kli challenge generate --out string)
    kli challenge respond --name "${GAR1}" --alias "${GAR1}" --passcode "${GAR1_PASSCODE}" --recipient "${QAR2}" --words "${words_qar2_to_gar1}"
    kli challenge verify  --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --signer "${GAR1}"    --words "${words_qar2_to_gar1}"

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
    kli challenge verify  --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --signer "${LAR1}"    --words "${words_qar1_to_lar1}"

    print_dark_gray "Challenge: LAR 1 -> QAR 1"
    words_lar1_to_qar1=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --recipient "${LAR1}" --words "${words_lar1_to_qar1}"
    kli challenge verify  --name "${LAR1}" --alias "${LAR1}" --passcode "${LAR1_PASSCODE}" --signer "${QAR1}"    --words "${words_lar1_to_qar1}"

    print_dark_gray "Challenge: QAR 2 -> LAR 2"
    words_qar2_to_lar2=$(kli challenge generate --out string)
    kli challenge respond --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --recipient "${QAR2}" --words "${words_qar2_to_lar2}"
    kli challenge verify  --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --signer "${LAR2}"    --words "${words_qar2_to_lar2}"

    print_dark_gray "Challenge: LAR 2 -> QAR 2"
    words_lar2_to_qar2=$(kli challenge generate --out string)
    kli challenge respond --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --recipient "${LAR2}" --words "${words_lar2_to_qar2}"
    kli challenge verify  --name "${LAR2}" --alias "${LAR2}" --passcode "${LAR2_PASSCODE}" --signer "${QAR2}"    --words "${words_lar2_to_qar2}"

    print_green "-----Finished challenge and response-----"
}
if [[ $NO_CHALLENGE ]]; then
    print_yellow "Skipping challenge and response"
else
    challenge_response
fi

# GAR: Create Multisig AID (GEDA)
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

# QAR: Resolve GEDA OOBI
function resolve_geda_oobis() {
    exists=$(kli contacts list --name "${QAR1}" --passcode "${QAR1_PASSCODE}" | jq .alias | tr -d '"' | grep "${GEDA_NAME}")
    if [[ "$exists" =~ "${GEDA_NAME}" ]]; then
        print_yellow "GEDA OOBIs already resolved"
        return
    fi

    GEDA_OOBI=$(kli oobi generate --name ${GAR1} --passcode ${GAR1_PASSCODE} --alias ${GEDA_NAME} --role witness)
    echo "GEDA OOBI: ${GEDA_OOBI}"
    kli oobi resolve --name "${QAR1}" --oobi-alias "${GEDA_NAME}" --passcode "${QAR1_PASSCODE}" --oobi "${GEDA_OOBI}"
    kli oobi resolve --name "${QAR2}" --oobi-alias "${GEDA_NAME}" --passcode "${QAR2_PASSCODE}" --oobi "${GEDA_OOBI}"
}
resolve_geda_oobis

echo
print_green "------------------------------GEDA Delegating to QVI identifier------------------------------"
echo

# QARs: Create delegated multisig QVI AID with GEDA as delegator
function create_qvi_multisig() {
    exists=$(kli list --name "${QAR1}" --passcode "${QAR1_PASSCODE}" | grep "${QVI_NAME}")
    if [[ "$exists" =~ "${QVI_NAME}" ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_NAME} already exists"
        return
    fi

    echo
    print_yellow "[QVI] delegated multisig inception from ${GEDA_NAME} | ${GEDA_PRE}"

    echo
    read -r -d '' MULTISIG_ICP_CONFIG_JSON << EOM
{
  "delpre": "${GEDA_PRE}",
  "aids": [
    "${QAR1_PRE}",
    "${QAR2_PRE}"
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
    print_yellow "[QVI] delegated multisig inception started by ${QAR1}: ${QAR1_PRE}"

    PID_LIST=""
    kli multisig incept --name ${QAR1} --alias ${QAR1} \
        --passcode ${QAR1_PASSCODE} \
        --group ${QVI_NAME} \
        --file "${temp_multisig_config}" &
    pid=$!
    PID_LIST+=" $pid"

    echo

    kli multisig incept --name ${QAR2} --alias ${QAR2} \
        --passcode ${QAR2_PASSCODE} \
        --group ${QVI_NAME} \
        --file "${temp_multisig_config}" &
    pid=$!
    PID_LIST+=" $pid"

    echo
    print_yellow "[QVI] delegated multisig Inception { ${QAR1}, ${QAR2} } - wait for signatures"
    sleep 5
    echo

    exists=$(kli list --name "${QAR1} --passcode ${QAR1_PASSCODE}" | grep "${QVI_NAME}")
    if [ ! $exists == "*${QVI_NAME}*" ]; then
        print_red "[QVI] Multisig inception failed"
        exit 1
    fi

    print_lcyan "[External] GEDA members approve delegated inception with 'kli delegate confirm'"
    echo


    print_lcyan "[External] GAR1 approves delegation"
    kli delegate confirm --name ${GAR1} --alias ${GAR1} --passcode ${GAR1_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"

    print_lcyan "[External] GAR 2 approves delegation"
    kli delegate confirm --name ${GAR2} --alias ${GAR2} --passcode ${GAR2_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"

    print_yellow "[QVI] Query GEDA multisig participants to discover anchor and complete delegation for KERIpy 1.2.x+"
    print_yellow "[QVI] QAR1 querying GEDA multisig for delegation anchor"
    kli query --name ${QAR1} --alias ${QAR1} --passcode ${QAR1_PASSCODE} --prefix "${GEDA_PRE}" &
    pid=$!
    PID_LIST+=" $pid"
    print_yellow "[QVI] QAR2 querying GEDA multisig for delegation anchor"
    kli query --name ${QAR2} --alias ${QAR2} --passcode ${QAR2_PASSCODE} --prefix "${GEDA_PRE}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    rm "$temp_multisig_config"

    # QVI multisig participants query GEDA multisig participants to discover anchor and complete delegation
    # only needed for KERIpy 1.2.x+ though won't hurt for 1.1.x and lower

    echo
    print_lcyan "[QVI] Show multisig status for ${QAR1}"
    kli status --name ${QAR1} --alias ${QVI_NAME} --passcode ${QAR1_PASSCODE}
    echo

    ms_prefix=$(kli status --name ${QAR1} --alias ${QVI_NAME} --passcode ${QAR1_PASSCODE} | awk '/Identifier:/ {print $2}')
    print_green "[QVI] Multisig AID ${QVI_NAME} with prefix: ${ms_prefix}"
}
create_qvi_multisig

# QVI & GEDA: perform multisig delegated rotation
function qvi_rotate() {
    QVI_MULTISIG_SEQ_NO=$(kli status --name ${QAR1} --alias ${QVI_NAME} --passcode ${QAR1_PASSCODE} | awk '/Seq No:/ {print $3}')
    if [[ "$QVI_MULTISIG_SEQ_NO" -gt 0 ]]; then
        print_yellow "[QVI] Multisig AID ${QVI_NAME} already rotated, at SN ${QVI_MULTISIG_SEQ_NO}"
        return
    fi

    print_green "------------------------------QVI Multisig Rotation------------------------------"
    print_lcyan "Rotating QAR single sigs"
    # QARs rotate their single sig AIDs
    kli rotate --name ${QAR1} --alias ${QAR1} --passcode ${QAR1_PASSCODE} >/dev/null 2>&1
    kli rotate --name ${QAR2} --alias ${QAR2} --passcode ${QAR2_PASSCODE} >/dev/null 2>&1

    # QARs query each other's keystate
    print_lcyan "QARs update each other keystates"
    kli query --name ${QAR1} --alias ${QAR1} --passcode ${QAR1_PASSCODE} --prefix "${QAR2_PRE}" >/dev/null 2>&1
    kli query --name ${QAR2} --alias ${QAR2} --passcode ${QAR2_PASSCODE} --prefix "${QAR1_PRE}" >/dev/null 2>&1

    # QARs begin rotation
    print_yellow "[QVI] Rotating delegated multisig AID"
    kli multisig rotate \
      --name ${QAR1} \
      --alias ${QVI_NAME} \
      --passcode ${QAR1_PASSCODE} \
      --isith "2" \
      --smids $QAR1_PRE --smids $QAR2_PRE \
      --nsith "2" \
      --rmids $QAR1_PRE --rmids $QAR2_PRE &
    pid=$!
    PID_LIST+=" $pid"

    kli multisig rotate \
      --name ${QAR2} \
      --alias ${QVI_NAME} \
      --passcode ${QAR2_PASSCODE} \
      --isith '2' \
      --smids $QAR1_PRE --smids $QAR2_PRE \
      --nsith '2' \
      --rmids $QAR1_PRE --rmids $QAR2_PRE &
    pid=$!
    PID_LIST+=" $pid"

    print_yellow "[GEDA] GARs confirm delegated multisig rotation"
    kli delegate confirm --name ${GAR1} --alias ${GEDA_NAME} --passcode ${GAR1_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"
    kli delegate confirm --name ${GAR2} --alias ${GEDA_NAME} --passcode ${GAR2_PASSCODE} --interact --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST
    PID_LIST=""

    # GARs query QARs latest keystate
    print_lcyan "GARs query QARs latest keystate"
    kli query --name ${GAR1} --alias ${GAR1} --passcode ${GAR1_PASSCODE} --prefix "${QAR1_PRE}" >/dev/null 2>&1
    kli query --name ${GAR1} --alias ${GAR1} --passcode ${GAR1_PASSCODE} --prefix "${QAR2_PRE}" >/dev/null 2>&1

    kli query --name ${GAR2} --alias ${GAR2} --passcode ${GAR2_PASSCODE} --prefix "${QAR1_PRE}" >/dev/null 2>&1
    kli query --name ${GAR2} --alias ${GAR2} --passcode ${GAR2_PASSCODE} --prefix "${QAR2_PRE}" >/dev/null 2>&1

    # QARs refresh keystate from GARs
    print_lcyan "QARs refresh keystate from GARs"
    kli query --name ${QAR1} --alias ${QAR1} --passcode ${QAR1_PASSCODE} --prefix "${GAR1_PRE}" >/dev/null 2>&1
    kli query --name ${QAR1} --alias ${QAR1} --passcode ${QAR1_PASSCODE} --prefix "${GAR2_PRE}" >/dev/null 2>&1

    kli query --name ${QAR2} --alias ${QAR2} --passcode ${QAR2_PASSCODE} --prefix "${GAR1_PRE}" >/dev/null 2>&1
    kli query --name ${QAR2} --alias ${QAR2} --passcode ${QAR2_PASSCODE} --prefix "${GAR2_PRE}" >/dev/null 2>&1
}
qvi_rotate

# QVI: (skip) Perform endpoint role authorizations - done automatically in KLI

# QVI: Generate OOBI for QVI to send to GEDA and LE
QVI_OOBI=$(kli oobi generate --name ${QAR1} --passcode ${QAR1_PASSCODE} --alias ${QVI_NAME} --role witness)

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
    kli oobi resolve --name "${PERSON}"   --oobi-alias "${QVI_NAME}" --passcode "${PERSON_PASSCODE}"   --oobi "${QVI_OOBI}"
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
    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./acdc-info/temp-data/qvi-cred-data.json \
        --rules @./acdc-info/rules/qvi-cred-rules.json \
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
        --data @./acdc-info/temp-data/qvi-cred-data.json \
        --rules @./acdc-info/rules/qvi-cred-rules.json \
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
    print_yellow "[External] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "[QVI] Polling for QVI Credential in ${QAR1}..."
    kli ipex list \
            --name "${QAR1}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR1_PASSCODE}" \
            --poll \
            --said
    QVI_GRANT_SAID=$?
    if [ -z "${QVI_GRANT_SAID}" ]; then
        print_red "[QVI] QVI Credential not granted - exiting"
        exit 1
    fi

    print_green "[QVI] Polling for QVI Credential in ${QAR2}..."
    kli ipex list \
            --name "${QAR2}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR2_PASSCODE}" \
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

# QVI: Admit QVI credential from GEDA
function admit_qvi_credential() {
    VC_SAID=$(kli vc list \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --said \
        --schema "${QVI_SCHEMA}")
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] QVI Credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --poll \
        --said)

    echo
    print_yellow "[QVI] Admitting QVI Credential ${SAID} from GEDA"

    KLI_TIME=$(kli time)
    kli ipex admit \
        --name ${QAR1} \
        --passcode ${QAR1_PASSCODE} \
        --alias ${QVI_NAME} \
        --said ${SAID} \
        --time "${KLI_TIME}" & 
    pid=$!
    PID_LIST+=" $pid"

    print_green "[QVI] Admitting QVI Credential as ${QVI_NAME} from GEDA"
    kli ipex join \
        --name ${QAR2} \
        --passcode ${QAR2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_green "[QVI] Admitted QVI credential"
    echo
}
admit_qvi_credential

# QVI: Present issued ECR Auth and OOR Auth to Sally (vLEI Reporting API)
function present_qvi_cred_to_sally() {
    print_yellow "[QVI] Presenting QVI Credential to Sally"
    QVI_SAID=$(kli vc list --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --said --schema "${QVI_SCHEMA}")

    PID_LIST=""
    kli ipex grant \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --said "${QVI_SAID}" \
        --recipient "${SALLY}" &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --auto &
    pid=$!
    PID_LIST+=" $pid"
    wait $PID_LIST

    print_green "[QVI] QVI Credential presented to Sally"
    print_dark_gray "[QVI] Waiting 15 s for Sally to call webhook"

}
present_qvi_cred_to_sally

# Create QVI credential registry
function create_qvi_reg() {
    # Check if QVI credential registry already exists
    REGISTRY=$(kli vc registry list \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" | awk '{print $1}')
    if [ ! -z "${REGISTRY}" ]; then
        print_dark_gray "[QVI] QVI registry already created"
        return
    fi

    echo
    print_yellow "[QVI] Creating QVI registry"
    NONCE=$(kli nonce)
    PID_LIST=""
    kli vc registry incept \
        --name ${QAR1} \
        --alias ${QVI_NAME} \
        --passcode ${QAR1_PASSCODE} \
        --usage "Credential Registry for QVI" \
        --nonce ${NONCE} \
        --registry-name ${QVI_REGISTRY} &
    pid=$!
    PID_LIST+=" $pid"

    kli vc registry incept \
        --name ${QAR2} \
        --alias ${QVI_NAME} \
        --passcode ${QAR2_PASSCODE} \
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

# QVI: Prepare, create, and Issue LE credential to GEDA

# Prepare LE edge data
function prepare_qvi_edge() {
    QVI_SAID=$(kli vc list \
        --name ${QAR1} \
        --alias ${QVI_NAME} \
        --passcode "${QAR1_PASSCODE}" \
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
    echo "$QVI_EDGE_JSON" > ./acdc-info/temp-data/qvi-edge.json

    kli saidify --file ./acdc-info/temp-data/qvi-edge.json
    
    print_lcyan "Legal Entity edge Data"
    print_lcyan "$(cat ./acdc-info/temp-data/qvi-edge.json | jq )"
}
prepare_qvi_edge

# Create Multisig Legal Entity identifier
function create_le_multisig() {
    exists=$(kli list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" | grep "${LE_MS_NAME}")
    if [[ "$exists" =~ "${LE_MS_NAME}" ]]; then
        print_dark_gray "[LE] LE Multisig AID ${LE_MS_NAME} already exists"
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
        --group ${LE_MS_NAME} \
        --file "${temp_multisig_config}" &
    pid=$!
    PID_LIST+=" $pid"

    echo

    kli multisig join --name ${LAR2} \
        --passcode ${LAR2_PASSCODE} \
        --group ${LE_MS_NAME} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    echo
    print_yellow "[LE] Multisig Inception { ${LAR1}, ${LAR2} } - wait for signatures"
    echo
    wait $PID_LIST

    exists=$(kli list --name "${LAR1}" --passcode "${LAR1_PASSCODE}" | grep "${LE_MS_NAME}")
    if [[ ! "$exists" =~ "${LE_MS_NAME}" ]]; then
        print_red "[LE] LE Multisig inception failed"
        exit 1
    fi

    ms_prefix=$(kli status --name ${LAR1} --alias ${LE_MS_NAME} --passcode ${LAR1_PASSCODE} | awk '/Identifier:/ {print $2}')
    print_green "[LE] LE Multisig AID ${LE_MS_NAME} with prefix: ${ms_prefix}"

    rm "$temp_multisig_config"
}
create_le_multisig

# QVI OOBIs with LE
function resolve_le_and_qvi_oobis() {
    echo
    LE_OOBI=$(kli oobi generate --name ${LAR1} --passcode ${LAR1_PASSCODE} --alias ${LE_MS_NAME} --role witness)
    echo "LE OOBI: ${LE_OOBI}"
    kli oobi resolve --name "${QAR1}" --oobi-alias "${LE_MS_NAME}" --passcode "${QAR1_PASSCODE}" --oobi "${LE_OOBI}"
    kli oobi resolve --name "${QAR2}" --oobi-alias "${LE_MS_NAME}" --passcode "${QAR2_PASSCODE}" --oobi "${LE_OOBI}"

    echo
}
resolve_le_and_qvi_oobis

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
        --name ${LAR1} \
        --alias ${LE_MS_NAME} \
        --passcode ${LAR1_PASSCODE} \
        --usage "Legal Entity Credential Registry for LE" \
        --nonce ${NONCE} \
        --registry-name ${LE_REGISTRY} &
    pid=$!
    PID_LIST+=" $pid"

    kli vc registry incept \
        --name ${LAR2} \
        --alias ${LE_MS_NAME} \
        --passcode ${LAR2_PASSCODE} \
        --usage "Legal Entity Credential Registry for LE" \
        --nonce ${NONCE} \
        --registry-name ${LE_REGISTRY} & 
    pid=$!
    PID_LIST+=" $pid"
    wait $PID_LIST

    echo
    print_green "[LE] Legal Entity Credential Registry created for LE"
    echo
}
create_le_reg

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
    SAID=$(kli vc list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
        --name ${QAR1} \
        --alias ${QVI_NAME} \
        --passcode ${QAR1_PASSCODE} \
        --registry-name ${QVI_REGISTRY} \
        --schema "${LE_SCHEMA}" \
        --recipient ${LE_MS_PRE} \
        --data @./acdc-info/temp-data/legal-entity-data.json \
        --edges @./acdc-info/temp-data/qvi-edge.json \
        --rules @./acdc-info/rules/qvi-cred-rules.json \
        --time ${KLI_TIME} &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name ${QAR2} \
        --alias ${QVI_NAME} \
        --passcode ${QAR2_PASSCODE} \
        --registry-name ${QVI_REGISTRY} \
        --schema "${LE_SCHEMA}" \
        --recipient ${LE_MS_PRE} \
        --data @./acdc-info/temp-data/legal-entity-data.json \
        --edges @./acdc-info/temp-data/qvi-edge.json \
        --rules @./acdc-info/rules/qvi-cred-rules.json \
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
        --name "${LAR1}" \
        --alias "${LE_MS_NAME}" \
        --type "grant" \
        --passcode "${LAR1_PASSCODE}" \
        --poll \
        --said)
    if [ ! -z "${LE_GRANT_SAID}" ]; then
        print_dark_gray "[LE] LE credential already granted"
        return
    fi
    SAID=$(kli vc list \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --issued \
        --said \
        --schema ${LE_SCHEMA})

    echo
    print_yellow $'[QVI] IPEX GRANTing LE credential with\n\tSAID'" ${SAID}"$'\n\tto LE'" ${LE_MS_PRE}"
    KLI_TIME=$(kli time)
    kli ipex grant \
        --name ${QAR1} \
        --passcode ${QAR1_PASSCODE} \
        --alias ${QVI_NAME} \
        --said ${SAID} \
        --recipient ${LE_MS_PRE} \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name ${QAR2} \
        --passcode ${QAR2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[QVI] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "[LE] Polling for LE Credential in ${LAR1}..."
    kli ipex list \
        --name "${LAR1}" \
        --alias "${LE_MS_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said
    LE_GRANT_SAID=$?
    if [ -z "${LE_GRANT_SAID}" ]; then
        print_red "LE Credential not granted"
        exit 1
    fi

    print_green "[LE] Polling for LE Credential in ${LAR2}..."
    kli ipex list \
        --name "${LAR2}" \
        --alias "${LE_MS_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --type "grant" \
        --poll \
        --said
    LE_GRANT_SAID=$?
    if [ -z "${LE_GRANT_SAID}" ]; then 
        print_red "LE Credential not granted"
        exit 1
    fi

    echo
    print_green "[QVI] LE Credential granted to LE"
    echo
}
grant_le_credential

# LE: Admit LE credential from QVI
function admit_le_credential() {
    VC_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_MS_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --said \
        --schema ${LE_SCHEMA})
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[LE] LE Credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${LAR1}" \
        --alias "${LE_MS_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said)

    echo
    print_yellow "[LE] Admitting LE Credential ${SAID} to ${LE_MS_NAME} as ${LAR1}"

    KLI_TIME=$(kli time)
    kli ipex admit \
        --name ${LAR1} \
        --passcode ${LAR1_PASSCODE} \
        --alias ${LE_MS_NAME} \
        --said ${SAID} \
        --time "${KLI_TIME}" & 
    pid=$!
    PID_LIST+=" $pid"

    print_green "[LE] Admitting LE Credential ${SAID} to ${LE_MS_NAME} as ${LAR2}"
    kli ipex join \
        --name ${LAR2} \
        --passcode ${LAR2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_green "[LE] Admitted LE credential"
    echo
}
admit_le_credential

# LE: Prepare, create, and Issue ECR Auth & OOR Auth credential to QVI

# prepare LE edge to ECR auth cred
function prepare_le_edge() {
    LE_SAID=$(kli vc list \
        --name ${LAR1} \
        --alias ${LE_MS_NAME} \
        --passcode "${LAR1_PASSCODE}" \
        --said \
        --schema ${LE_SCHEMA})
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
    kli saidify --file ./acdc-info/temp-data/legal-entity-edge.json
    
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
        --alias "${LE_MS_NAME}" \
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

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name ${LAR1} \
        --alias ${LE_MS_NAME} \
        --passcode ${LAR1_PASSCODE} \
        --registry-name ${LE_REGISTRY} \
        --schema ${ECR_AUTH_SCHEMA} \
        --recipient ${QVI_PRE} \
        --data @./acdc-info/temp-data/ecr-auth-data.json \
        --edges @./acdc-info/temp-data/legal-entity-edge.json \
        --rules @./acdc-info/rules/ecr-auth-rules.json \
        --time ${KLI_TIME} &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name ${LAR2} \
        --alias ${LE_MS_NAME} \
        --passcode ${LAR2_PASSCODE} \
        --registry-name ${LE_REGISTRY} \
        --schema ${ECR_AUTH_SCHEMA} \
        --recipient ${QVI_PRE} \
        --data @./acdc-info/temp-data/ecr-auth-data.json \
        --edges @./acdc-info/temp-data/legal-entity-edge.json \
        --rules @./acdc-info/rules/ecr-auth-rules.json \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_lcyan "[LE] LE created ECR Auth credential"
    echo
}
create_ecr_auth_credential

# Grant ECR Auth credential to QVI
function grant_ecr_auth_credential() {
    # This relies on there being only one grant in the list for the GEDA
    GRANT_COUNT=$(kli ipex list \
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
        --alias "${LE_MS_NAME}" \
        --issued \
        --said \
        --schema ${ECR_AUTH_SCHEMA})

    echo
    print_yellow $'[LE] IPEX GRANTing ECR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI '"${QVI_PRE}"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex grant \
        --name ${LAR1} \
        --passcode ${LAR1_PASSCODE} \
        --alias ${LE_MS_NAME} \
        --said ${SAID} \
        --recipient ${QVI_PRE} \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name ${LAR2} \
        --passcode ${LAR2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[LE] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "[QVI] Polling for ECR Auth Credential in ${QAR1}..."
    kli ipex list \
            --name "${QAR1}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR1_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    print_green "[QVI] Polling for ECR Auth Credential in ${QAR2}..."
    kli ipex list \
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
    VC_SAID=$(kli vc list \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --said \
        --schema ${ECR_AUTH_SCHEMA})
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] ECR Auth Credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | \
        tail -1) # get the last grant, which should be the ECR Auth credential

    echo
    print_yellow "[QVI] Admitting ECR Auth Credential ${SAID} from LE"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex admit \
        --name ${QAR1} \
        --passcode ${QAR1_PASSCODE} \
        --alias ${QVI_NAME} \
        --said ${SAID} \
        --time "${KLI_TIME}" & 
    pid=$!
    PID_LIST+=" $pid"

    print_green "[QVI] Admitting ECR Auth Credential as ${QVI_NAME} from LE"
    kli ipex join \
        --name ${QAR2} \
        --passcode ${QAR2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

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
        --alias "${LE_MS_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${OOR_AUTH_SCHEMA}")
    if [ ! -z "${SAID}" ]; then
        print_yellow "[QVI] OOR Auth credential already created"
        return
    fi

    echo
    print_green "[LE] LE creating OOR Auth credential"

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name ${LAR1} \
        --alias ${LE_MS_NAME} \
        --passcode ${LAR1_PASSCODE} \
        --registry-name ${LE_REGISTRY} \
        --schema ${OOR_AUTH_SCHEMA} \
        --recipient ${QVI_PRE} \
        --data @./acdc-info/temp-data/oor-auth-data.json \
        --edges @./acdc-info/temp-data/legal-entity-edge.json \
        --rules @./acdc-info/rules/qvi-cred-rules.json \
        --time ${KLI_TIME} &

    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name ${LAR2} \
        --alias ${LE_MS_NAME} \
        --passcode ${LAR2_PASSCODE} \
        --registry-name ${LE_REGISTRY} \
        --schema ${OOR_AUTH_SCHEMA} \
        --recipient ${QVI_PRE} \
        --data @./acdc-info/temp-data/oor-auth-data.json \
        --edges @./acdc-info/temp-data/legal-entity-edge.json \
        --rules @./acdc-info/rules/qvi-cred-rules.json \
        --time ${KLI_TIME} &
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
        --alias "${LE_MS_NAME}" \
        --issued \
        --said \
        --schema ${OOR_AUTH_SCHEMA} | \
        tail -1) # get the last credential, the OOR Auth credential

    echo
    print_yellow $'[LE] IPEX GRANTing OOR Auth credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex grant \
        --name ${LAR1} \
        --passcode ${LAR1_PASSCODE} \
        --alias ${LE_MS_NAME} \
        --said ${SAID} \
        --recipient ${QVI_PRE} \
        --time ${KLI_TIME} &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name ${LAR2} \
        --passcode ${LAR2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_yellow "[LE] Waiting for IPEX messages to be witnessed"
    sleep 5

    echo
    print_green "[QVI] Polling for OOR Auth Credential in ${QAR1}..."
    kli ipex list \
            --name "${QAR1}" \
            --alias "${QVI_NAME}" \
            --passcode "${QAR1_PASSCODE}" \
            --type "grant" \
            --poll \
            --said

    print_green "[QVI] Polling for OOR Auth Credential in ${QAR2}..."
    kli ipex list \
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
    VC_SAID=$(kli vc list \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --said \
        --schema ${OOR_AUTH_SCHEMA})
    if [ ! -z "${VC_SAID}" ]; then
        print_dark_gray "[QVI] OOR Auth Credential already admitted"
        return
    fi
    SAID=$(kli ipex list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --type "grant" \
        --poll \
        --said | \
        tail -1) # get the last grant, which should be the ECR Auth credential

    echo
    print_yellow "[QVI] Admitting OOR Auth Credential ${SAID} from LE"

    KLI_TIME=$(kli time) # Use consistent time so SAID of grant is same
    kli ipex admit \
        --name ${QAR1} \
        --passcode ${QAR1_PASSCODE} \
        --alias ${QVI_NAME} \
        --said ${SAID} \
        --time "${KLI_TIME}" & 
    pid=$!
    PID_LIST+=" $pid"

    print_green "[QVI] Admitting OOR Auth Credential as ${QVI_NAME} from LE"
    kli ipex join \
        --name ${QAR2} \
        --passcode ${QAR2_PASSCODE} \
        --auto &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_green "[QVI] OOR Auth Credential admitted"
    echo
}
admit_oor_auth_credential

# QVI: Create and Issue ECR credential to Person
# Prepare ECR Auth edge data
function prepare_ecr_auth_edge() {
    ECR_AUTH_SAID=$(kli vc list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
    echo "$ECR_AUTH_EDGE_JSON" > ./acdc-info/temp-data/ecr-auth-edge.json

    kli saidify --file ./acdc-info/temp-data/ecr-auth-edge.json
    
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
    SAID=$(kli vc list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --private-credential-nonce "${CRED_NONCE}" \
        --private-subject-nonce "${SUBJ_NONCE}" \
        --private \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${ECR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @./acdc-info/temp-data/ecr-data.json \
        --edges @./acdc-info/temp-data/ecr-auth-edge.json \
        --rules @./acdc-info/rules/ecr-rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --private \
        --private-credential-nonce "${CRED_NONCE}" \
        --private-subject-nonce "${SUBJ_NONCE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${ECR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @./acdc-info/temp-data/ecr-data.json \
        --edges @./acdc-info/temp-data/ecr-auth-edge.json \
        --rules @./acdc-info/rules/ecr-rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

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
        tail -1) # get the last grant
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
        --schema "${ECR_SCHEMA}")

    echo
    print_yellow $'[QVI] IPEX GRANTing ECR credential with\n\tSAID'" ${SAID}"$'\n\tto'" ${PERSON} ${PERSON_PRE}"
    KLI_TIME=$(kli time)
    kli ipex grant \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
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

# Person: Admit ECR credential from QVI
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

# QVI: Issue, grant OOR to Person and Person admits OOR
# Prepare OOR Auth edge data
function prepare_oor_auth_edge() {
    OOR_AUTH_SAID=$(kli vc list \
        --name ${QAR1} \
        --alias ${QVI_NAME} \
        --passcode "${QAR1_PASSCODE}" \
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
    echo "$OOR_AUTH_EDGE_JSON" > ./acdc-info/temp-data/oor-auth-edge.json

    kli saidify --file ./acdc-info/temp-data/oor-auth-edge.json
    
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
    SAID=$(kli vc list \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
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
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${OOR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @./acdc-info/temp-data/oor-data.json \
        --edges @./acdc-info/temp-data/oor-auth-edge.json \
        --rules @./acdc-info/rules/oor-rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    kli vc create \
        --name "${QAR2}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR2_PASSCODE}" \
        --registry-name "${QVI_REGISTRY}" \
        --schema "${OOR_SCHEMA}" \
        --recipient "${PERSON_PRE}" \
        --data @./acdc-info/temp-data/oor-data.json \
        --edges @./acdc-info/temp-data/oor-auth-edge.json \
        --rules @./acdc-info/rules/oor-rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_lcyan "[QVI] OOR credential created"
    echo
}
create_oor_credential

# QVI Grant OOR credential to PERSON
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
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --issued \
        --said \
        --schema "${OOR_SCHEMA}")

    echo
    print_yellow $'[QVI] IPEX GRANTing OOR credential with\n\tSAID'" ${SAID}"$'\n\tto'" ${PERSON} ${PERSON_PRE}"
    kli ipex grant \
        --name "${QAR1}" \
        --passcode "${QAR1_PASSCODE}" \
        --alias "${QVI_NAME}" \
        --said "${SAID}" \
        --recipient "${PERSON_PRE}" &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
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

# Person: Admit OOR credential from QVI
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

# QVI: Present issued ECR Auth and OOR Auth to Sally (vLEI Reporting API)

function present_le_cred_to_sally() {
    print_yellow "[QVI] Presenting LE Credential to Sally"
    LE_SAID=$(kli vc list --name "${LAR1}" \
        --alias "${LE_MS_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --said --schema "${LE_SCHEMA}")

    PID_LIST=""
    kli ipex grant \
        --name "${QAR1}" \
        --alias "${QVI_NAME}" \
        --passcode "${QAR1_PASSCODE}" \
        --said "${LE_SAID}" \
        --recipient "${SALLY}" &
    pid=$!
    PID_LIST+=" $pid"

    kli ipex join \
        --name "${QAR2}" \
        --passcode "${QAR2_PASSCODE}" \
        --auto &
    pid=$!
    PID_LIST+=" $pid"
    wait $PID_LIST

    print_green "[QVI] LE Credential presented to Sally"
    print_dark_gray "[QVI] Waiting 15 s for Sally to call webhook"
    sleep 15
}
present_le_cred_to_sally

function present_oor_cred_to_sally() {
  # remember to add the --issued flag to find the issued credential in the QVI's registry
  OOR_SAID=$(kli vc list \
      --name "${QAR1}" \
      --alias "${QVI_NAME}" \
      --passcode "${QAR1_PASSCODE}" \
      --issued \
      --said \
      --schema "${OOR_SCHEMA}")

  PID_LIST=""
  kli ipex grant \
      --name "${QAR1}" \
      --alias "${QVI_NAME}" \
      --passcode "${QAR1_PASSCODE}" \
      --said "${OOR_SAID}" \
      --recipient "${SALLY}" &
  pid=$!
  PID_LIST+=" $pid"

  kli ipex join \
      --name "${QAR2}" \
      --passcode "${QAR2_PASSCODE}" \
      --auto &
  pid=$!
  PID_LIST+=" $pid"
  wait $PID_LIST

  print_green "[QVI] OOR Credential presented to Sally"
  print_dark_gray "[QVI] Waiting 15 s for Sally to call webhook"
  sleep 15
}
present_oor_cred_to_sally

cleanup
print_lcyan "Full chain workflow completed"
END_TIME=$(date +%s)
SCRIPT_TIME=$(($END_TIME - $START_TIME))
print_lcyan "Script took ${SCRIPT_TIME} seconds to run"

# TODO QVI: Revoke ECR Auth and OOR Auth credentials
# TODO QVI: Present revoked credentials to Sally
