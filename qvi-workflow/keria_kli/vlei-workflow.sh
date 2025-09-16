#!/usr/bin/env bash
# vlei-workflow.sh for KERIA for the QVI and Person participants and the KLI for the GEDA and LE participants.

# Runs the entire QVI issuance workflow end to end starting from multisig AID creation including the
# GLEIF External Delegated AID (GEDA) creation all the way to OOR and ECR credential issuance to the
# Person AID for usage in the iXBRL data attestation.
#
# Note:
# This script uses a local installation of KERIA, witnesses, the vLEI-server for vLEI schemas,
# and NodeJS scripts for the SignifyTS creation of both QVI QAR AIDs and the Person AID.
#
# To run this script you need to run the following command in a separate terminals:
# from the KERIpy repo within a Python virtual environment run:
#   > kli witness demo
# and from the vLEI repo within a Python virtual environment run:
#   > vLEI-server -s ./schema/acdc -c ./samples/acdc/ -o ./samples/oobis/
# and from the keria repo within a Python virtual environment run:
#   > keria start --config-dir scripts --config-file keria --loglevel INFO
# and from the sally repo within a Python virtual environment run:
#   > sally server start --direct --http 9723 --salt 0AD45YWdzWSwNREuAoitH_CC --name sally --alias sally --config-dir scripts --config-file sally.json --incept-file sally-incept.json --passcode VVmRdBTe5YCyLMmYRqTAi --web-hook http://127.0.0.1:9923 --auth EMCRBKH4Kvj03xbEVzKmOIrg0sosqHUF9VG2vzT9ybzv --loglevel INFO
# and make sure to perform "npm install" in this directory to be able to run the NodeJS scripts.

source color-printing.sh

SALLY_PID=""
WEBHOOK_PID=""
INDIRECT_MODE_SALLY=false

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

PAUSE_ENABLED=false
function pause() {
    if [[ $PAUSE_ENABLED == true ]]; then
        read -p "$*"
    else
        print_dark_gray "Skipping pause ${*}"
    fi
}

#### prepare environment ####
source vlei-env.sh # Load URLs, AID names, prefixes, salts, passcodes, schemas,  config dir, and registries

# environment selector for the SignifyTS scripts
ENVIRONMENT=local-single-keria
print_yellow "Using SignifyTS environment: $ENVIRONMENT"

# Directory for the SignifyTS scripts
SIG_TS_WALLETS_DIR=$(dirname "$0")/../sig_ts_wallets/src

# Data directory where the QVI and Person from SignifyTS will use for storing data
QVI_DATA_DIR="./qvi_data"

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
}

# KERIA SignifyTS QVI salts
export SIGTS_AIDS="qar1|$QAR1|$QAR1_SALT,qar2|$QAR2|$QAR2_SALT,qar3|$QAR3|$QAR3_SALT,person|$PERSON|$PERSON_SALT"

function create_signifyts_aids() {
  print_yellow "Creating QVI and Person Identifiers from SignifyTS + KERIA"
  tsx "${SIG_TS_WALLETS_DIR}/qars/qars-and-person-setup.ts" $ENVIRONMENT $QVI_DATA_DIR $SIGTS_AIDS
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
}

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
    print_dark_gray "Created AID: ${NAME} with prefix: ${PREFIX}"
    print_green $'\tPrefix:'" ${PREFIX}"
}

# GAR: Create single Sig AIDs (2)
function create_aids() {
    print_green "-----Creating AIDs-----"

    create_temp_icp_cfg
    print_lcyan "Using temporary AID config file heredoc:"
    print_lcyan "${temp_icp_config}"

    create_aid "${GAR1}"  "${GAR1_SALT}"  "${GAR1_PASSCODE}"  "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${GAR2}"  "${GAR2_SALT}"  "${GAR2_PASSCODE}"  "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${LAR1}"  "${LAR1_SALT}"  "${LAR1_PASSCODE}"  "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${LAR2}"  "${LAR2_SALT}"  "${LAR2_PASSCODE}"  "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    create_aid "${SALLY}" "${SALLY_SALT}" "${SALLY_PASSCODE}" "${CONFIG_DIR}" "${INIT_CFG}" "${temp_icp_config}"
    rm "$temp_icp_config"
}

function check_sally_up() {
  curl ${SALLY_HOST}/oobi >/dev/null 2>&1
  status=$?
  if [ $status -ne 0 ]; then
    echo "1"
  else
    echo "0"
  fi
}

function check_webhook_up() {
  curl ${WEBHOOK_HOST}/health >/dev/null 2>&1
  status=$?
  if [ $status -ne 0 ]; then
    echo "1"
  else
    echo "0"
  fi
}

INDIRECT_MODE_SALLY=false
function sally_setup() {
    export SALLY_OOBI="http://127.0.0.1:9723/oobi"

    # skip setup if already running
    if [[ $(check_sally_up) -eq 0 ]]; then
      print_yellow "Sally already running on ${SALLY_HOST}"
      if [[ $(check_webhook_up) -eq 0 ]]; then
        print_yellow "Webhook already running on ${WEBHOOK_HOST}"
        return
      fi
    fi

    print_yellow "Setting up webhook on ${WEBHOOK_HOST}"
    sally hook demo & # For the webhook Sally will call upon credential presentation
    WEBHOOK_PID=$!

    # defaults to direct mode
    if [[ $INDIRECT_MODE_SALLY = true ]] ; then
      print_yellow "Starting sally on ${SALLY_HOST} in indirect (mailbox) mode"
      sally server start \
        --name "${SALLY}" \
        --alias "${SALLY}" \
        --salt "${SALLY_SALT}" \
        --config-dir sally \
        --config-file sally.json \
        --passcode "${SALLY_PASSCODE}" \
        --web-hook http://127.0.0.1:9923 \
        --auth "${GEDA_PRE}" & # who will be presenting the credential
      SALLY_PID=$!
      export SALLY_OOBI="${WIT_HOST}/oobi/${SALLY_PRE}/witness/${WAN_PRE}"
    else
      print_yellow "Starting sally on ${SALLY_HOST} in direct mode"
      sally server start \
        --direct \
        --name "${SALLY}" \
        --alias "${SALLY}" \
        --salt "${SALLY_SALT}" \
        --config-dir sally \
        --config-file sally.json \
        --incept-file sally-incept.json \
        --passcode "${SALLY_PASSCODE}" \
        --web-hook http://127.0.0.1:9923 \
        --auth "${GEDA_PRE}" & # who will be presenting the credential
      SALLY_PID=$!
      export SALLY_OOBI="http://127.0.0.1:9723/oobi"
    fi
    print_yellow "Waiting 3 seconds for Sally to start..."
    sleep 3
}

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

    OOBIS_FOR_KERIA="gar1|$GAR1_OOBI,gar2|$GAR2_OOBI,lar1|$LAR1_OOBI,lar2|$LAR2_OOBI,direct-sally|$SALLY_OOBI"

    tsx "${SIG_TS_WALLETS_DIR}/qars/resolve-oobi-gars-lars-sally.ts" $ENVIRONMENT "${SIGTS_AIDS}" "${OOBIS_FOR_KERIA}"

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

# GAR: Challenge responses between single sig AIDs
function challenge_response() {
    if [[ ! $CHALLENGE_ENABLED ]]; then
        print_yellow "Skipping challenge and response"
        return
    fi
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

# GAR: Generate and resolve OOBI for GEDA
function resolve_geda_oobi() {
    GEDA_OOBI=""
    GEDA_OOBI=$(kli oobi generate --name ${GAR1} --passcode ${GAR1_PASSCODE} --alias ${GEDA_NAME} --role witness)
    echo "GEDA OOBI: ${GEDA_OOBI}"
    tsx "${SIG_TS_WALLETS_DIR}/qars/qvi-resolve-oobi.ts" $ENVIRONMENT "${SIGTS_AIDS}" "${GEDA_NAME}" "${GEDA_OOBI}"
}

# Create delegated multisig QVI AID
function create_qvi_multisig() {
    tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${QVI_DATA_DIR}"
    QVI_MULTISIG_SEQ_NO=$(cat "${QVI_DATA_DIR}"/qvi-sequence-no.json | jq .sequenceNo | tr -d '"')
    if [[ "$QVI_MULTISIG_SEQ_NO" -gt -1 ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_NAME} already exists"
        return
    fi

    print_yellow "Creating QVI multisig"
    local delegator_prefix=$(kli status --name ${GAR1} --alias ${GEDA_NAME} --passcode ${GAR1_PASSCODE} | awk '/Identifier:/ {print $2}')
    print_yellow "Delegator Prefix: ${delegator_prefix}"
    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-create-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
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
    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-complete-multisig-incept.ts" $ENVIRONMENT $SIGTS_AIDS $GEDA_PRE

    MULTISIG_INFO=$(cat $QVI_DATA_DIR/qvi-multisig-info.json)
    QVI_PRE=$(echo $MULTISIG_INFO | jq .msPrefix | tr -d '"')
    print_green "[QVI] Multisig AID ${QVI_NAME} with prefix: ${QVI_PRE}"
}

# QVI: Perform endpoint role authorizations and generate OOBI for QVI to send to GEDA
function authorize_qvi_multisig_agent_endpoint_role(){
    QVI_OOBI=""
    print_yellow "Authorizing QVI multisig agent endpoint role"
    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-authorize-endroles-get-qvi-oobi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${QVI_DATA_DIR}" \
      "${SIGTS_AIDS}"
    QVI_OOBI=$(cat "${QVI_DATA_DIR}/qvi-oobi.json" | jq .oobi | tr -d '"')
    print_green "QVI Agent OOBI: ${QVI_OOBI}"
}

# Delegated multisig rotation
function qvi_rotate() {
    tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${QVI_DATA_DIR}"
    QVI_MULTISIG_SEQ_NO=$(cat "${QVI_DATA_DIR}"/qvi-sequence-no.json | jq .sequenceNo | tr -d '"')
    if [[ "$QVI_MULTISIG_SEQ_NO" -ge 1 ]]; then
        print_dark_gray "[QVI] Multisig AID ${QVI_NAME} already rotated with SN=${QVI_MULTISIG_SEQ_NO}"
        return
    fi
    print_yellow "[QVI] Rotating QVI Multisig"
    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-rotate-qvi-multisig.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
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
    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-refresh-geda-multisig-state.ts" $ENVIRONMENT $SIGTS_AIDS $GEDA_PRE

    print_yellow "[QVI] Waiting 8s for QARs to refresh GEDA keystate and complete delegation"
    sleep 8
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
    tsx "${SIG_TS_WALLETS_DIR}/person-resolve-qvi-oobi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${QVI_OOBI}"
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
        print_dark_gray "[External] GEDA QVI credential already created"
        return
    fi

    echo
    print_green "[External] GEDA creating QVI credential"
    print_lcyan "[External] QVI Credential Data"
    print_lcyan "$(cat ./acdc-info/temp-data/qvi-cred-data.json)"

    KLI_TIME=$(kli time) # use consistent time for both invocations of `kli vc create` so they compute the same event digest (SAID).
    PID_LIST=""
    kli vc create \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./acdc-info/temp-data/qvi-cred-data.json \
        --rules @./acdc-info/rules/rules.json \
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
        --rules @./acdc-info/rules/rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

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

# QVI: Admit QVI credential from GEDA
function admit_qvi_credential() {
    QVI_CRED_SAID=$(kli vc list \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}")
    received=$(tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-received-credential.ts" \
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
    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-admit-credential-qvi.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${SIGTS_AIDS}" \
      "${GEDA_PRE}" \
      "${QVI_CRED_SAID}"

    echo
    print_green "[QVI] Admitted QVI credential"
    echo
}

function present_qvi_cred_to_sally() {
  print_yellow "[QVI] Presenting QVI Credential to Sally"

  tsx "${SIG_TS_WALLETS_DIR}/qars/qars-present-credential.ts" \
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
    present_result=$(curl -s -o /dev/null -w "%{http_code}" "${WEBHOOK_HOST}/?holder=${QVI_PRE}")
    print_dark_gray "[QVI] received ${present_result} from Sally"
    sleep 1
    if (( $(date +%s)-start > 25 )); then
      print_red "[QVI] TIMEOUT - Sally did not receive the QVI Credential for ${QVI_NAME} | ${QVI_PRE}"
      break;
    fi # 25 seconds timeout
  done

  print_green "[QVI] QVI Credential presented to Sally"
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

# GAR: Generate  and resolve OOBI for GEDA
function resolve_le_oobi() {
    LE_OOBI=""
    LE_OOBI=$(kli oobi generate --name ${LAR1} --passcode ${LAR1_PASSCODE} --alias ${LE_NAME} --role witness)
    echo "LE OOBI: ${LE_OOBI}"
    tsx "${SIG_TS_WALLETS_DIR}/qars/qvi-resolve-oobi.ts" $ENVIRONMENT "${SIGTS_AIDS}" "${LE_NAME}" "${LE_OOBI}"
}

# Create QVI credential registry
function create_qvi_reg() {
    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-registry-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "${QVI_REGISTRY}" \
      "${QVI_DATA_DIR}" \
      "${SIGTS_AIDS}"
    QVI_REG_REGK=$(cat "${QVI_DATA_DIR}/qvi-registry-info.json" | jq .registryRegk | tr -d '"')
    print_green "[QVI] Credential Registry created for QVI with regk: ${QVI_REG_REGK}"
}

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
    echo "$QVI_EDGE_JSON" > ./acdc-info/temp-data/qvi-edge.json

    kli saidify --file ./acdc-info/temp-data/qvi-edge.json
}

# Prepare LE credential data
function prepare_le_cred_data() {
    print_yellow "[QVI] Preparing LE credential data"
    read -r -d '' LE_CRED_DATA << EOM
{
    "LEI": "${LE_LEI}"
}
EOM

    echo "$LE_CRED_DATA" > ./acdc-info/temp-data/legal-entity-data.json
}

# Create LE credential in QVI
function create_and_grant_le_credential() {
    # Check if LE credential already exists
    le_said=$(tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-issued-credential.ts" \
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

    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-le-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "./acdc-info/" \
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
    print_yellow "[LE] LAR1 Admitting LE Credential ${SAID} to ${LE_NAME} as ${LAR1}"

    KLI_TIME=$(kli time)
    kli ipex admit \
        --name "${LAR1}" \
        --passcode "${LAR1_PASSCODE}" \
        --alias "${LE_NAME}" \
        --said "${SAID}" \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    print_green "[LE] LAR2 Joining Admit LE Credential ${SAID} to ${LE_NAME} as ${LAR2}"
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

function present_le_cred_to_sally() {
  print_yellow "[QVI] Presenting LE Credential to Sally"

  tsx "${SIG_TS_WALLETS_DIR}/qars/qars-present-credential.ts" \
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
    present_result=$(curl -s -o /dev/null -w "%{http_code}" "${WEBHOOK_HOST}/?holder=${LE_PRE}")
    print_dark_gray "[QVI] received ${present_result} from Sally"
    sleep 1
    if (( $(date +%s)-start > 25 )); then
      print_red "[QVI] TIMEOUT - Sally did not receive the LE Credential for ${LE_NAME} | ${LE_PRE}"
      break;
    fi # 25 seconds timeout
  done

  print_green "[QVI] LE Credential presented to Sally"
}

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

    echo "$LE_EDGE_JSON" > ./acdc-info/temp-data/legal-entity-edge.json
    kli saidify --file ./acdc-info/temp-data/legal-entity-edge.json
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
    print_lcyan "$(cat ./acdc-info/temp-data/oor-auth-data.json)"

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
        --data @./acdc-info/temp-data/oor-auth-data.json \
        --edges @./acdc-info/temp-data/legal-entity-edge.json \
        --rules @./acdc-info/rules/rules.json \
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
        --data @./acdc-info/temp-data/oor-auth-data.json \
        --edges @./acdc-info/temp-data/legal-entity-edge.json \
        --rules @./acdc-info/rules/rules.json \
        --time "${KLI_TIME}" &
    pid=$!
    PID_LIST+=" $pid"

    wait $PID_LIST

    echo
    print_lcyan "[LE] LE created OOR Auth credential"
    echo
}

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

# QVI: Admit OOR Auth credential
function admit_oor_auth_credential() {
    OOR_AUTH_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --issued \
        --said \
        --schema ${OOR_AUTH_SCHEMA})
    received=$(tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-received-credential.ts" \
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
    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-admit-credential-qvi.ts" \
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
    echo "$OOR_AUTH_EDGE_JSON" > ./acdc-info/temp-data/oor-auth-edge.json

    kli saidify --file ./acdc-info/temp-data/oor-auth-edge.json
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
    oor_said=$(tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-issued-credential.ts" \
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

    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-oor-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "./acdc-info" \
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
    oor_said=$(tsx "${SIG_TS_WALLETS_DIR}/person/person-check-received-credential.ts" \
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
    oor_said=$(tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_NAME" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$OOR_SCHEMA"
    )

    echo
    print_yellow "[PERSON] Admitting OOR credential ${oor_said} to ${PERSON}"

    tsx "${SIG_TS_WALLETS_DIR}/person/person-admit-credential.ts" \
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

    tsx "${SIG_TS_WALLETS_DIR}/person/person-grant-credential.ts" \
      "${ENVIRONMENT}" \
      "${SIGTS_AIDS}" \
      "${OOR_SCHEMA}" \
      "${QVI_PRE}" \
      "${SALLY_PRE}"

    start=$(date +%s)
    present_result=0
    print_dark_gray "[PERSON] Waiting for Sally to receive the OOR Credential"
    while [ $present_result -ne 200 ]; do
      present_result=$(curl -s -o /dev/null -w "%{http_code}" "${WEBHOOK_HOST}/?holder=${PERSON_PRE}")
      print_dark_gray "[PERSON] received ${present_result} from Sally"
      sleep 1
      if (( $(date +%s)-start > 25 )); then
        print_red "[PERSON] TIMEOUT - Sally did not receive the OOR Credential for ${PERSON_NAME} | ${PERSON_PRE}"
        break;
      fi # 25 seconds timeout
    done

    print_green "[PERSON] OOR Credential presented to Sally"
}

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
        --schema "${ECR_AUTH_SCHEMA}")
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

    KLI_TIME=$(kli time)
    PID_LIST=""
    kli vc create \
        --name "${LAR1}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR1_PASSCODE}" \
        --registry-name "${LE_REGISTRY}" \
        --schema "${ECR_AUTH_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @./acdc-info/temp-data/ecr-auth-data.json \
        --edges @./acdc-info/temp-data/legal-entity-edge.json \
        --rules @./acdc-info/rules/ecr-auth-rules.json \
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
        --data @./acdc-info/temp-data/ecr-auth-data.json \
        --edges @./acdc-info/temp-data/legal-entity-edge.json \
        --rules @./acdc-info/rules/ecr-auth-rules.json \
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

# Admit ECR Auth credential from LE
function admit_ecr_auth_credential() {
    ECR_AUTH_SAID=$(kli vc list \
        --name "${LAR2}" \
        --alias "${LE_NAME}" \
        --passcode "${LAR2_PASSCODE}" \
        --issued \
        --said \
        --schema ${ECR_AUTH_SCHEMA})
    received=$(tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-received-credential.ts" \
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
    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-admit-credential-qvi.ts" \
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
    echo "$ECR_AUTH_EDGE_JSON" > ./acdc-info/temp-data/ecr-auth-edge.json

    kli saidify --file ./acdc-info/temp-data/ecr-auth-edge.json
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

# Create ECR credential in QVI, issued to the Person
# QVI Grant ECR credential to PERSON
function create_and_grant_ecr_credential() {
    # Check if ECR credential already exists
    ecr_said=$(tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-issued-credential.ts" \
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

    tsx "${SIG_TS_WALLETS_DIR}/qars/qars-ecr-credential-create.ts" \
      "${ENVIRONMENT}" \
      "${QVI_NAME}" \
      "./acdc-info" \
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
    ecr_said=$(tsx "${SIG_TS_WALLETS_DIR}/person/person-check-received-credential.ts" \
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
    ecr_said=$(tsx "${SIG_TS_WALLETS_DIR}/qars/qar-check-issued-credential.ts" \
      "$ENVIRONMENT" \
      "$QVI_NAME" \
      "$SIGTS_AIDS" \
      "$PERSON_PRE" \
      "$ECR_SCHEMA"
    )

    echo
    print_yellow "[PERSON] Admitting ECR credential ${ecr_said} to ${PERSON}"

    tsx "${SIG_TS_WALLETS_DIR}/person/person-admit-credential.ts" \
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

# TODO Add OOR and ECR credential revocation by the QVI
# TODO Add presentation of revoked OOR and ECR credentials to Sally

# QVI: Revoke ECR Auth and OOR Auth credentials
# QVI: Present revoked credentials to Sally

# ------------------------------ workflow functions ------------------------------
function setup() {
  test_dependencies
  create_signifyts_aids
  create_aids
  sally_setup
  resolve_oobis
#  challenge_response
}

function geda_delegation_to_qvi(){
  create_geda_multisig
  create_geda_reg
  resolve_geda_oobi
  create_qvi_multisig
  authorize_qvi_multisig_agent_endpoint_role
}

function qvi_credential() {
  prepare_qvi_cred_data
  create_qvi_credential
  grant_qvi_credential
  admit_qvi_credential
}

function le_credential() {
  create_qvi_reg
  prepare_qvi_edge
  prepare_le_cred_data
  create_and_grant_le_credential
  admit_le_credential
}

function oor_auth_cred() {
  prepare_oor_auth_data
  create_oor_auth_credential
  grant_oor_auth_credential
  admit_oor_auth_credential
}

function oor_cred () {
  prepare_oor_auth_edge
  prepare_oor_cred_data
  create_and_grant_oor_credential
  admit_oor_credential
}

function oor_auth_and_oor_cred() {
  oor_auth_cred
  oor_cred
}

function ecr_auth_cred() {
  prepare_ecr_auth_data
  create_ecr_auth_credential
  grant_ecr_auth_credential
  admit_ecr_auth_credential
}

function ecr_cred() {
  prepare_ecr_auth_edge
  prepare_ecr_cred_data
  create_and_grant_ecr_credential
  admit_ecr_credential
}

function ecr_auth_and_ecr_cred() {
  ecr_auth_cred
  ecr_cred
}

function main_flow() {
  print_lcyan "--------------------------------------------------------------------------------"
  print_lcyan "                   KERIA and KLI vLEI Workflow script - Main Flow"
  print_lcyan "--------------------------------------------------------------------------------"

  setup
  pause "Press [enter] to continue with challenge and response section"
  challenge_response
  pause "Press [enter] to continue with GEDA delegation to QVI"
  geda_delegation_to_qvi
  pause "Press [enter] to continue with QVI identifier rotation"
  qvi_rotate
  resolve_qvi_oobi

  pause "Press [enter] to continue with QVI credential creation"
  qvi_credential
  pause "Press [enter] to continue with QVI credential presentation to Sally"
  present_qvi_cred_to_sally

  create_le_multisig
  resolve_le_oobi

  le_credential
  present_le_cred_to_sally

  create_le_reg
  prepare_le_edge

  oor_auth_and_oor_cred
  pause "Press [enter] to present oor credential to Sally"
  present_oor_cred_to_sally

  ecr_auth_and_ecr_cred
  pause "Press [enter] to present ecr credential to Sally"
  present_ecr_cred_to_sally
}

function debug_flow() {
  print_red "--------------------------------------------------------------------------------"
  print_red "                   KERIA and KLI vLEI Workflow script - Debug Flow"
  print_red "--------------------------------------------------------------------------------"

  setup
  geda_delegation_to_qvi
#  qvi_rotate
  resolve_qvi_oobi
}


# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -k, --keystore-dir DIR  Specify keystore directory directory (default: ./docker-keystores)"
    echo "  -a, --alias ALIAS       OOBI alias for target Sally deployment (default: alternate)"
    echo "      --challenge         Use challenge and response section of workflow"
    echo "      --indirect          Use indirect mode Sally (verification agent)"
    echo "  -d, --debug             Run the Debug workflow"
    echo "  -c, --clear             Clear all containers, keystores, and networks"
    echo "  -h, --help              Display this help message"
    echo "  --pause                 Enable pausing between steps"
    exit 1
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--clear)
            cleanup
            ;;
        -h|--help)
            usage
            ;;
        --challenge)
            CHALLENGE_ENABLED=true
            shift
            ;;
        --indirect)
            INDIRECT_MODE_SALLY=true
            shift
            ;;
        --pause)
            PAUSE_ENABLED=true
            shift
            ;;
        -k|--keystore-dir)
            if [[ -z $2 ]]; then
                KEYSTORE_DIR="${HOME}/.keri"
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
        -d|--debug)
            debug_flow
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

main_flow