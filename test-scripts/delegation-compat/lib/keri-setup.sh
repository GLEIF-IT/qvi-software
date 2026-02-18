#!/usr/bin/env bash
# keri-setup.sh - KERI-specific identifier setup and baseline state initialization.

# Resolve an identifier prefix from `kli status` output.
function aid_prefix() {
  local cmd=$1 # command wrapper to run (kli_gleif | kli_qvi)
  local name=$2 # keystore name
  local alias=$3 # identifier alias in that keystore
  local passcode=$4 # keystore passcode

  ${cmd} status --name "${name}" --alias "${alias}" --passcode "${passcode}" \
    | awk '/Identifier:/ {print $2; exit}' | tr -d '[:space:]'
}

# Resolve current sequence number from `kli status` output.
function aid_seq() {
  local cmd=$1 # command wrapper to run (kli_gleif | kli_qvi)
  local name=$2 # keystore name
  local alias=$3 # identifier alias in that keystore
  local passcode=$4 # keystore passcode

  ${cmd} status --name "${name}" --alias "${alias}" --passcode "${passcode}" \
    | awk '/Seq No:/ {print $3; exit}' | tr -d '[:space:]'
}

# Assert a sequence increment happened exactly once.
function assert_seq_incremented() {
  local before=$1 # sequence number before operation
  local after=$2 # sequence number after operation
  local label=$3 # user-facing label for assertion error messages
  local expected=$((before + 1)) # expected increment-by-one sequence

  [[ "${after}" =~ ^[0-9]+$ ]] || fail "${label}: non-numeric after sequence (${after})"
  [[ ${after} -eq ${expected} ]] || fail "${label}: expected seq ${expected}, got ${after}"
}

# Build single-sig inception config used for creating GAR/QAR participant AIDs.
function create_single_sig_icp_config() {
  jq ".wits = [\"${WAN_PRE}\"]" \
    "${SCRIPT_DIR}/config/template-single-sig-incept-config.jq" \
    > "${SCRIPT_DIR}/config/single-sig-incept-config.json"
}

# Initialize and incept a participant AID when it does not already exist.
function create_aid() {
  local cmd=$1 # command wrapper to run (kli_gleif | kli_qvi)
  local name=$2 # keystore name and default alias
  local salt=$3 # deterministic salt for keystore bootstrap
  local passcode=$4 # passcode used by the keystore
  local list_out # output from `kli list` used for existence detection

  list_out=$(${cmd} list --name "${name}" --passcode "${passcode}" 2>&1 || true)
  if [[ "${list_out}" != *"Keystore must already exist"* ]]; then
    log "AID ${name} already exists"
    return
  fi

  ${cmd} init --name "${name}" --salt "${salt}" --passcode "${passcode}" --config-dir /config --config-file habery-config-docker.json
  ${cmd} incept --name "${name}" --alias "${name}" --passcode "${passcode}" --file /config/single-sig-incept-config.json

  local pre # created identifier prefix for confirmation logging
  pre=$(aid_prefix "${cmd}" "${name}" "${name}" "${passcode}")
  [[ -n "${pre}" ]] || fail "Failed to create AID ${name}"
  log "Created AID ${name}: ${pre}"
}

# Resolve witness OOBI contact from one participant to another.
function resolve_oobi() {
  local cmd=$1 # command wrapper to run (kli_gleif | kli_qvi)
  local name=$2 # local keystore name performing the resolve
  local passcode=$3 # local keystore passcode
  local alias=$4 # alias name to store for the resolved contact
  local prefix=$5 # remote identifier prefix for witness OOBI URL

  ${cmd} oobi resolve --name "${name}" --oobi-alias "${alias}" --passcode "${passcode}" \
    --oobi "${WIT_HOST}/oobi/${prefix}/witness/${WAN_PRE}" >/dev/null
}

# Refresh globally tracked prefixes from restored or newly built keystores.
function refresh_known_prefixes_from_keystore() {
  GAR1_PRE=$(aid_prefix kli_gleif "${GAR1}" "${GAR1}" "${GAR1_PASSCODE}")
  GAR2_PRE=$(aid_prefix kli_gleif "${GAR2}" "${GAR2}" "${GAR2_PASSCODE}")
  QAR1_PRE=$(aid_prefix kli_qvi "${QAR1}" "${QAR1}" "${QAR1_PASSCODE}")
  QAR2_PRE=$(aid_prefix kli_qvi "${QAR2}" "${QAR2}" "${QAR2_PASSCODE}")
  GEDA_PRE=$(aid_prefix kli_gleif "${GAR1}" "${GEDA_NAME}" "${GAR1_PASSCODE}")
  QVI_PRE=$(aid_prefix kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}")
}

# Build full baseline KERI state used by rotation workflow tests.
function build_common_setup_from_scratch() {
  log "Building common setup from scratch"
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
  refresh_known_prefixes_from_keystore
  save_checkpoint
}
