#!/usr/bin/env zsh
# Single sig version of qvi-workflow-keria_signify_qvi-docker.sh

function create_geda_reg_single_gar() {
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

    klid gar1 vc registry incept \
        --name ${GAR1} \
        --alias ${GEDA_NAME} \
        --passcode ${GAR1_PASSCODE} \
        --usage "QVI Credential Registry for GEDA" \
        --registry-name ${GEDA_REGISTRY}

    docker wait gar1
    docker rm gar1

    echo
    print_green "QVI Credential Registry created for GEDA"
    echo
}
create_geda_reg_single_gar

function create_qvi_credential_single_gar() {
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

    klid gar1 vc create \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --registry-name "${GEDA_REGISTRY}" \
        --schema "${QVI_SCHEMA}" \
        --recipient "${QVI_PRE}" \
        --data @/data/qvi-cred-data.json \
        --rules @/data/rules.json

    echo
    print_yellow "[External] GEDA creating QVI credential - wait for signatures"
    echo
    print_dark_gray "waiting on Docker container gar1"
    docker wait gar1
    docker logs gar1
    docker rm gar1

    echo
    print_lcyan "[External] QVI Credential created for GEDA"
    echo
}
create_qvi_credential_single_gar

function grant_qvi_credential_single_gar() {
    SAID=$(kli vc list \
        --name "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d '[:space:]')

    echo
    print_yellow $'[External] IPEX GRANTing QVI credential with\n\tSAID'" ${SAID}"$'\n\tto QVI'" ${QVI_PRE}"
    klid gar1 ipex grant \
        --name "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --said "${SAID}" \
        --recipient "${QVI_PRE}"

    echo
    print_yellow "[External] Waiting for IPEX messages to be witnessed"
    echo
    print_dark_gray "waiting on Docker container gar1"
    docker wait gar1
    docker logs gar1
    docker rm gar1

    echo
    print_green "[External] QVI Credential issued to QVI"
    echo
}
grant_qvi_credential_single_gar


function admit_qvi_credential_single_qar() {
    set -x
    QVI_CRED_SAID=$(kli vc list \
        --name "${GAR1}" \
        --alias "${GEDA_NAME}" \
        --passcode "${GAR1_PASSCODE}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d " \t\n\r")

    echo
    print_yellow "[QVI] Admitting QVI Credential ${QVI_CRED_SAID} from GEDA"
    tsx "${QVI_SIGNIFY_DIR}/qars/qars-admit-credential-qvi-single-qar.ts" \
      "${ENVIRONMENT}" \
      "${QVI_MS}" \
      "${SIGTS_AIDS}" \
      "${GEDA_PRE}" \
      "${QVI_CRED_SAID}"

    echo
    print_green "[QVI] Admitted QVI credential"
    echo
    set +x
}
admit_qvi_credential_single_qar

function present_qvi_cred_to_sally_signify_single_sig() {
  set -x
  print_yellow "[QVI] Presenting QVI Credential to Sally"

  tsx "${QVI_SIGNIFY_DIR}/qars/qars-present-credential-single-qar.ts" \
    "${ENVIRONMENT}" \
    "${QVI_MS}" \
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
      print_red "[QVI] TIMEOUT - Sally did not receive the QVI Credential for ${QVI_MS} | ${QVI_PRE}"
      break;
    fi
  done

  print_green "[QVI] QVI Credential presented to Sally"
  set +x
}
present_qvi_cred_to_sally_signify_single_sig

function present_qvi_cred_to_sally_kli_single_gar() {
    SAID=$(kli vc list \
        --name "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --issued \
        --said \
        --schema "${QVI_SCHEMA}" | tr -d '[:space:]')

    echo
    print_yellow $'[External] IPEX GRANTing QVI credential with\n\tSAID'" ${SAID}"$'\n\tto Sally'" ${SALLY_PRE}"
    klid gar1 ipex grant \
        --name "${GAR1}" \
        --passcode "${GAR1_PASSCODE}" \
        --alias "${GEDA_NAME}" \
        --said "${SAID}" \
        --recipient "${SALLY_PRE}"

    echo
    print_yellow "[External] Waiting for IPEX messages to be witnessed"
    echo
    print_dark_gray "waiting on Docker container gar1"
    docker wait gar1
    docker logs gar1
    docker rm gar1

    echo
    print_green "[External] QVI Credential issued to QVI"
    echo
}
present_qvi_cred_to_sally_kli_single_gar