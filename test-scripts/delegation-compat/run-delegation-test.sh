#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-delegation-compat.yaml"
NETWORK_NAME="vlei-delegation-test"

KEEP_ARTIFACTS=false
VERBOSE=false
KEYSTORE_DIR="${SCRIPT_DIR}/docker-keystores"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-artifacts)
      KEEP_ARTIFACTS=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      cat <<USAGE
Usage: ./run-delegation-test.sh [KEYSTORE_DIR] [--keep-artifacts] [--verbose]

Runs a cross-version KLI delegation test:
- GLEIF side: gleif/keri:1.1.42
- QVI side:   gleif/keri:1.2.11
- Witnesses:  gleif/keri:1.2.11
USAGE
      exit 0
      ;;
    *)
      KEYSTORE_DIR="$1"
      shift
      ;;
  esac
done

mkdir -p "${KEYSTORE_DIR}"
KEYSTORE_DIR=$(cd "${KEYSTORE_DIR}" && pwd)

export NETWORK_NAME
source "${SCRIPT_DIR}/kli-commands.sh" "${KEYSTORE_DIR}"

WIT_HOST="http://witness-demo:5642"
WAN_PRE="BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha"

GAR1="accolon"
GAR1_SALT="0AA2-S2YS4KqvlSzO7faIEpH"
GAR1_PASSCODE="18b2c88fd050851c45c67"

GAR2="bedivere"
GAR2_SALT="0ADD292rR7WEU4GPpaYK4Z6h"
GAR2_PASSCODE="b26ef3dd5c85f67c51be8"

GEDA_NAME="geda"

QAR1="galahad"
QAR1_SALT="0ACgCmChLaw_qsLycbqBoxDK"
QAR1_PASSCODE="e6b3402845de8185abe94"

QAR2="lancelot"
QAR2_SALT="0ACaYJJv0ERQmy7xUfKgR6a4"
QAR2_PASSCODE="bdf1565a750ff3f76e4fc"

QVI_NAME="qvi"

function log() {
  echo "[delegation-compat] $*"
}

function fail() {
  echo "[delegation-compat] ERROR: $*" >&2
  exit 1
}

function cleanup() {
  if ${KEEP_ARTIFACTS}; then
    log "Keeping artifacts (--keep-artifacts set)."
    return
  fi

  log "Cleaning up containers, volumes, and keystores"
  docker rm -f gar1 gar2 qvi1 qvi2 >/dev/null 2>&1 || true
  docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" down -v >/dev/null 2>&1 || true

  if [[ -d "${KEYSTORE_DIR}" ]]; then
    find "${KEYSTORE_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

function check_dependencies() {
  command -v docker >/dev/null 2>&1 || fail "docker is required"
  command -v jq >/dev/null 2>&1 || fail "jq is required"
}

function remove_if_exists() {
  local c
  for c in "$@"; do
    docker rm -f "${c}" >/dev/null 2>&1 || true
  done
}

function wait_and_collect() {
  local failed=0
  local c

  for c in "$@"; do
    if ! docker wait "${c}" >/dev/null; then
      failed=1
    fi
  done

  for c in "$@"; do
    if ${VERBOSE} || [[ ${failed} -ne 0 ]]; then
      echo "----- logs: ${c} -----"
      docker logs "${c}" || true
    fi
    docker rm "${c}" >/dev/null 2>&1 || true
  done

  [[ ${failed} -eq 0 ]] || fail "One or more delegated workflow containers failed"
}

function aid_prefix() {
  local cmd=$1
  local name=$2
  local alias=$3
  local passcode=$4

  ${cmd} status --name "${name}" --alias "${alias}" --passcode "${passcode}" \
    | awk '/Identifier:/ {print $2}' | tr -d '[:space:]'
}

function create_single_sig_icp_config() {
  jq ".wits = [\"${WAN_PRE}\"]" \
    "${SCRIPT_DIR}/config/template-single-sig-incept-config.jq" \
    > "${SCRIPT_DIR}/config/single-sig-incept-config.json"
}

function create_aid() {
  local cmd=$1
  local name=$2
  local salt=$3
  local passcode=$4

  local list_out
  list_out=$(${cmd} list --name "${name}" --passcode "${passcode}" 2>&1 || true)
  if [[ "${list_out}" != *"Keystore must already exist"* ]]; then
    log "AID ${name} already exists"
    return
  fi

  ${cmd} init   --name "${name}" --salt "${salt}"  --passcode "${passcode}" --config-dir /config --config-file habery-config-docker.json
  ${cmd} incept --name "${name}" --alias "${name}" --passcode "${passcode}" --file /config/single-sig-incept-config.json

  local pre
  pre=$(aid_prefix "${cmd}" "${name}" "${name}" "${passcode}")
  [[ -n "${pre}" ]] || fail "Failed to create AID ${name}"
  log "Created AID ${name}: ${pre}"
}

function resolve_oobi() {
  local cmd=$1
  local name=$2
  local passcode=$3
  local alias=$4
  local prefix=$5

  ${cmd} oobi resolve --name "${name}" --oobi-alias "${alias}" --passcode "${passcode}" \
    --oobi "${WIT_HOST}/oobi/${prefix}/witness/${WAN_PRE}" >/dev/null
}

function start_stack() {
  docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1 || docker network create "${NETWORK_NAME}" >/dev/null
  docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" up -d --wait witness-demo >/dev/null
}

function create_geda_multisig() {
  local gar1_pre gar2_pre
  gar1_pre=$(aid_prefix kli_gleif "${GAR1}" "${GAR1}" "${GAR1_PASSCODE}")
  gar2_pre=$(aid_prefix kli_gleif "${GAR2}" "${GAR2}" "${GAR2_PASSCODE}")

  jq ".aids = [\"${gar1_pre}\",\"${gar2_pre}\"]" "${SCRIPT_DIR}/config/template-multi-sig-incept-config.jq" \
    | jq ".wits = [\"${WAN_PRE}\"]" > "${SCRIPT_DIR}/config/multi-sig-incept-config.json"

  remove_if_exists gar1 gar2

  kli_gleif_d gar1 multisig incept --name "${GAR1}" --alias "${GAR1}" \
    --passcode "${GAR1_PASSCODE}" --group "${GEDA_NAME}" --file /config/multi-sig-incept-config.json >/dev/null
  kli_gleif_d gar2 multisig join --name "${GAR2}" --passcode "${GAR2_PASSCODE}" --group "${GEDA_NAME}" --auto >/dev/null

  wait_and_collect gar1 gar2

  local exists
  exists=$(kli_gleif list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | grep "${GEDA_NAME}" || true)
  [[ -n "${exists}" ]] || fail "GEDA multisig inception failed"

  GEDA_PRE=$(aid_prefix kli_gleif "${GAR1}" "${GEDA_NAME}" "${GAR1_PASSCODE}")
  [[ -n "${GEDA_PRE}" ]] || fail "Unable to determine GEDA prefix"
  log "Created GEDA multisig ${GEDA_NAME}: ${GEDA_PRE}"
}

function resolve_geda_for_qvi() {
  local geda_oobi
  geda_oobi=$(kli_gleif oobi generate --name "${GAR1}" --passcode "${GAR1_PASSCODE}" --alias "${GEDA_NAME}" --role witness)

  kli_qvi oobi resolve --name "${QAR1}" --oobi-alias "${GEDA_NAME}" --passcode "${QAR1_PASSCODE}" --oobi "${geda_oobi}" >/dev/null
  kli_qvi oobi resolve --name "${QAR2}" --oobi-alias "${GEDA_NAME}" --passcode "${QAR2_PASSCODE}" --oobi "${geda_oobi}" >/dev/null
}

function create_delegated_qvi_multisig() {
  local qar1_pre qar2_pre
  qar1_pre=$(aid_prefix kli_qvi "${QAR1}" "${QAR1}" "${QAR1_PASSCODE}")
  qar2_pre=$(aid_prefix kli_qvi "${QAR2}" "${QAR2}" "${QAR2_PASSCODE}")

  jq ".delpre = \"${GEDA_PRE}\"" "${SCRIPT_DIR}/config/template-multi-sig-delegated-incept-config.jq" \
    | jq ".aids = [\"${qar1_pre}\",\"${qar2_pre}\"]" \
    | jq ".wits = [\"${WAN_PRE}\"]" > "${SCRIPT_DIR}/config/multi-sig-delegated-incept-config.json"

  remove_if_exists qvi1 qvi2 gar1 gar2

  kli_qvi_d qvi1 multisig incept --name "${QAR1}" --alias "${QAR1}" \
    --passcode "${QAR1_PASSCODE}" --group "${QVI_NAME}" --file /config/multi-sig-delegated-incept-config.json >/dev/null

  kli_qvi_d qvi2 multisig incept --name "${QAR2}" --alias "${QAR2}" \
    --passcode "${QAR2_PASSCODE}" --group "${QVI_NAME}" --file /config/multi-sig-delegated-incept-config.json >/dev/null

  kli_gleif_d gar1 delegate confirm --name "${GAR1}" --alias "${GAR1}" \
    --passcode "${GAR1_PASSCODE}" --interact --auto >/dev/null

  kli_gleif_d gar2 delegate confirm --name "${GAR2}" --alias "${GAR2}" \
    --passcode "${GAR2_PASSCODE}" --interact --auto >/dev/null

  wait_and_collect qvi1 qvi2 gar1 gar2

  local exists status
  exists=$(kli_qvi list --name "${QAR1}" --passcode "${QAR1_PASSCODE}" | grep "${QVI_NAME}" || true)
  [[ -n "${exists}" ]] || fail "QVI delegated multisig alias not found"

  status=$(kli_qvi status --name "${QAR1}" --alias "${QVI_NAME}" --passcode "${QAR1_PASSCODE}")
  echo "${status}"

  echo "${status}" | grep -q "Identifier:" || fail "QVI status does not show identifier"
  echo "${status}" | grep -q "${GEDA_PRE}" || fail "QVI delegated status does not reference GEDA delegator ${GEDA_PRE}"
}

GEDA_PRE=""

log "Starting delegation compatibility test"
check_dependencies
create_single_sig_icp_config
start_stack

create_aid kli_gleif "${GAR1}" "${GAR1_SALT}" "${GAR1_PASSCODE}"
create_aid kli_gleif "${GAR2}" "${GAR2_SALT}" "${GAR2_PASSCODE}"
create_aid kli_qvi "${QAR1}" "${QAR1_SALT}" "${QAR1_PASSCODE}"
create_aid kli_qvi "${QAR2}" "${QAR2_SALT}" "${QAR2_PASSCODE}"

GAR1_PRE=$(aid_prefix kli_gleif "${GAR1}" "${GAR1}" "${GAR1_PASSCODE}")
GAR2_PRE=$(aid_prefix kli_gleif "${GAR2}" "${GAR2}" "${GAR2_PASSCODE}")
QAR1_PRE=$(aid_prefix kli_qvi "${QAR1}" "${QAR1}" "${QAR1_PASSCODE}")
QAR2_PRE=$(aid_prefix kli_qvi "${QAR2}" "${QAR2}" "${QAR2_PASSCODE}")

resolve_oobi kli_gleif "${GAR1}" "${GAR1_PASSCODE}" "${GAR2}" "${GAR2_PRE}"
resolve_oobi kli_gleif "${GAR1}" "${GAR1_PASSCODE}" "${QAR1}" "${QAR1_PRE}"
resolve_oobi kli_gleif "${GAR1}" "${GAR1_PASSCODE}" "${QAR2}" "${QAR2_PRE}"

resolve_oobi kli_gleif "${GAR2}" "${GAR2_PASSCODE}" "${GAR1}" "${GAR1_PRE}"
resolve_oobi kli_gleif "${GAR2}" "${GAR2_PASSCODE}" "${QAR1}" "${QAR1_PRE}"
resolve_oobi kli_gleif "${GAR2}" "${GAR2_PASSCODE}" "${QAR2}" "${QAR2_PRE}"

resolve_oobi kli_qvi "${QAR1}" "${QAR1_PASSCODE}" "${QAR2}" "${QAR2_PRE}"
resolve_oobi kli_qvi "${QAR1}" "${QAR1_PASSCODE}" "${GAR1}" "${GAR1_PRE}"
resolve_oobi kli_qvi "${QAR1}" "${QAR1_PASSCODE}" "${GAR2}" "${GAR2_PRE}"

resolve_oobi kli_qvi "${QAR2}" "${QAR2_PASSCODE}" "${QAR1}" "${QAR1_PRE}"
resolve_oobi kli_qvi "${QAR2}" "${QAR2_PASSCODE}" "${GAR1}" "${GAR1_PRE}"
resolve_oobi kli_qvi "${QAR2}" "${QAR2_PASSCODE}" "${GAR2}" "${GAR2_PRE}"

create_geda_multisig
resolve_geda_for_qvi
create_delegated_qvi_multisig

log "PASS: QVI multisig delegation from GLEIF succeeded (1.2.11 <- 1.1.42)"
