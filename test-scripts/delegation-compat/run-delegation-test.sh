#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-delegation-compat.yaml"
NETWORK_NAME="vlei-delegation-test"

KEEP_ARTIFACTS=false
VERBOSE=false
ROTATE_JOIN_ONLY=false
DELEGATE_CONFIRM_ONLY=false
CLEAR_CHECKPOINT=false
MULTISIG_INTERACT_ONLY=false
LOG_LEVEL="normal"

KEYSTORE_DIR="${SCRIPT_DIR}/docker-keystores"
EVENTS_DIR="${SCRIPT_DIR}/events"
CHECKPOINTS_DIR="${SCRIPT_DIR}/checkpoints"
CHECKPOINT_META_FILE="${CHECKPOINTS_DIR}/checkpoint.meta.json"
CHECKPOINT_KEYSTORE_ARCHIVE="${CHECKPOINTS_DIR}/keystores.tar.gz"
CHECKPOINT_WITNESS_ARCHIVE="${CHECKPOINTS_DIR}/witness-volume.tar.gz"
CHECKPOINT_VERSION=2
ROTATION_ANCHOR_FILE="${EVENTS_DIR}/multi-sig-delegated-rot-anchor.json"
TRACE_LOG_PIDS=()

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
    --rotate-join-only)
      ROTATE_JOIN_ONLY=true
      shift
      ;;
    --delegate-confirm-only)
      DELEGATE_CONFIRM_ONLY=true
      shift
      ;;
    --multisig-interact-only)
      MULTISIG_INTERACT_ONLY=true
      shift
      ;;
    --clear)
      CLEAR_CHECKPOINT=true
      shift
      ;;
    --log-level)
      [[ $# -ge 2 ]] || { echo "Missing value for --log-level" >&2; exit 1; }
      LOG_LEVEL="$2"
      shift 2
      ;;
    -h|--help)
      cat <<USAGE
Usage: ./run-delegation-test.sh [KEYSTORE_DIR] [--keep-artifacts] [--verbose] [--rotate-join-only] [--delegate-confirm-only] [--multisig-interact-only] [--clear] [--log-level LEVEL]

Runs a cross-version KLI delegation test:
- GLEIF side: gleif/keri:1.1.42
- QVI side:   gleif/keri:1.2.11
- Witnesses:  gleif/keri:1.2.11

LEVEL values: quiet, normal, debug, trace
USAGE
      exit 0
      ;;
    *)
      KEYSTORE_DIR="$1"
      shift
      ;;
  esac
done

if ${VERBOSE}; then
  LOG_LEVEL="debug"
fi

case "${LOG_LEVEL}" in
  quiet|normal|debug|trace) ;;
  *) echo "Unsupported log level: ${LOG_LEVEL}" >&2; exit 1 ;;
esac

mkdir -p "${KEYSTORE_DIR}"
KEYSTORE_DIR=$(cd "${KEYSTORE_DIR}" && pwd)
mkdir -p "${EVENTS_DIR}" "${CHECKPOINTS_DIR}"

if ${DELEGATE_CONFIRM_ONLY} && ${MULTISIG_INTERACT_ONLY}; then
  echo "--delegate-confirm-only and --multisig-interact-only are mutually exclusive" >&2
  exit 1
fi

export NETWORK_NAME
source "${SCRIPT_DIR}/kli-commands.sh" "${KEYSTORE_DIR}"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/container-processes.sh"
source "${SCRIPT_DIR}/lib/checkpointing.sh"
source "${SCRIPT_DIR}/lib/context-setup.sh"
source "${SCRIPT_DIR}/lib/keri-setup.sh"

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

# Cleanup runtime resources unless the caller asked to keep artifacts.
function cleanup() {
  stop_trace_logs

  if ${KEEP_ARTIFACTS}; then
    log "Keeping artifacts (--keep-artifacts set)."
    return
  fi

  log "Cleaning up containers, volumes, keystores, and event artifacts"
  docker rm -f gar1 gar2 qvi1 qvi2 >/dev/null 2>&1 || true
  docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" down -v >/dev/null 2>&1 || true

  if [[ -d "${KEYSTORE_DIR}" ]]; then
    find "${KEYSTORE_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + >/dev/null 2>&1 || true
  fi

  if [[ -d "${EVENTS_DIR}" ]]; then
    find "${EVENTS_DIR}" -maxdepth 1 -type f -name '*.json' -delete >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Create the GEDA multisig identifier from GAR participants.
function create_geda_multisig() {
  local gar1_pre # GAR1 participant prefix used in the multisig inception config
  local gar2_pre # GAR2 participant prefix used in the multisig inception config
  local exists # grep result used to confirm group alias exists after inception

  gar1_pre=$(aid_prefix kli_gleif "${GAR1}" "${GAR1}" "${GAR1_PASSCODE}")
  gar2_pre=$(aid_prefix kli_gleif "${GAR2}" "${GAR2}" "${GAR2_PASSCODE}")

  jq ".aids = [\"${gar1_pre}\",\"${gar2_pre}\"]" "${SCRIPT_DIR}/config/template-multi-sig-incept-config.jq" \
    | jq ".wits = [\"${WAN_PRE}\"]" > "${SCRIPT_DIR}/config/multi-sig-incept-config.json"

  remove_if_exists gar1 gar2

  kli_gleif_d gar1 multisig incept --name "${GAR1}" --alias "${GAR1}" \
    --passcode "${GAR1_PASSCODE}" --group "${GEDA_NAME}" --file /config/multi-sig-incept-config.json >/dev/null

  ensure_container_running gar1
  complete_join_while_proposer_running kli_gleif "${GAR2}" "${GEDA_NAME}" "${GAR2_PASSCODE}" gar1
  wait_and_collect gar1

  exists=$(kli_gleif list --name "${GAR1}" --passcode "${GAR1_PASSCODE}" | grep "${GEDA_NAME}" || true)
  [[ -n "${exists}" ]] || fail "GEDA multisig inception failed"

  GEDA_PRE=$(aid_prefix kli_gleif "${GAR1}" "${GEDA_NAME}" "${GAR1_PASSCODE}")
  [[ -n "${GEDA_PRE}" ]] || fail "Unable to determine GEDA prefix"
  log "Created GEDA multisig ${GEDA_NAME}: ${GEDA_PRE}"
}

# Resolve the GEDA group OOBI into both QAR keystores.
function resolve_geda_for_qvi() {
  local geda_oobi # witness-role OOBI URL generated from GEDA group identifier

  geda_oobi=$(kli_gleif oobi generate --name "${GAR1}" --passcode "${GAR1_PASSCODE}" --alias "${GEDA_NAME}" --role witness)

  kli_qvi oobi resolve --name "${QAR1}" --oobi-alias "${GEDA_NAME}" --passcode "${QAR1_PASSCODE}" --oobi "${geda_oobi}" >/dev/null
  kli_qvi oobi resolve --name "${QAR2}" --oobi-alias "${GEDA_NAME}" --passcode "${QAR2_PASSCODE}" --oobi "${geda_oobi}" >/dev/null
}

# Create delegated QVI multisig and complete delegation with GAR confirmations.
function create_delegated_qvi_multisig() {
  local qar1_pre # QAR1 participant prefix for delegated group inception config
  local qar2_pre # QAR2 participant prefix for delegated group inception config
  local exists # grep result used to verify qvi alias exists
  local status # status output used for post-inception delegated checks

  qar1_pre=$(aid_prefix kli_qvi "${QAR1}" "${QAR1}" "${QAR1_PASSCODE}")
  qar2_pre=$(aid_prefix kli_qvi "${QAR2}" "${QAR2}" "${QAR2_PASSCODE}")

  jq ".delpre = \"${GEDA_PRE}\"" "${SCRIPT_DIR}/config/template-multi-sig-delegated-incept-config.jq" \
    | jq ".aids = [\"${qar1_pre}\",\"${qar2_pre}\"]" \
    | jq ".wits = [\"${WAN_PRE}\"]" > "${SCRIPT_DIR}/config/multi-sig-delegated-incept-config.json"

  remove_if_exists qvi1 qvi2 gar1 gar2

  kli_qvi_d qvi2 multisig join --name "${QAR2}" --group "${QVI_NAME}" --passcode "${QAR2_PASSCODE}" --auto >/dev/null

  kli_qvi_d qvi1 multisig incept --name "${QAR1}" --alias "${QAR1}" \
    --passcode "${QAR1_PASSCODE}" --group "${QVI_NAME}" --file /config/multi-sig-delegated-incept-config.json >/dev/null

  ensure_container_running qvi1

  kli_gleif_d gar1 delegate confirm --name "${GAR1}" --alias "${GAR1}" \
    --passcode "${GAR1_PASSCODE}" --interact --auto >/dev/null

  kli_gleif_d gar2 delegate confirm --name "${GAR2}" --alias "${GAR2}" \
    --passcode "${GAR2_PASSCODE}" --interact --auto >/dev/null

  wait_and_collect qvi1 qvi2 gar1 gar2
  query_geda_keystate_from_qvi_delegates

  exists=$(kli_qvi list --name "${QAR1}" --passcode "${QAR1_PASSCODE}" | grep "${QVI_NAME}" || true)
  [[ -n "${exists}" ]] || fail "QVI delegated multisig alias not found"

  status=$(kli_qvi status --name "${QAR1}" --alias "${QVI_NAME}" --passcode "${QAR1_PASSCODE}")
  echo "${status}"

  echo "${status}" | grep -q "Identifier:" || fail "QVI status does not show identifier"
  echo "${status}" | grep -q "${GEDA_PRE}" || fail "QVI delegated status does not reference GEDA delegator ${GEDA_PRE}"
  echo "${status}" | grep -q "Not Anchored" && fail "QVI delegated inception is not anchored"
  echo "${status}" | grep -q "Anchored" || fail "QVI delegated inception was not confirmed anchored"

  QVI_PRE=$(aid_prefix kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}")
  [[ -n "${QVI_PRE}" ]] || fail "Unable to determine QVI group prefix"
}

# Rotate both QAR participant AIDs and exchange key state before group rotate.
function rotate_member_aids_for_qvi() {
  log "Rotating QVI member AIDs"
  remove_if_exists qvi-rot1 qvi-rot2 qvi-qry1 qvi-qry2

  kli_qvi_d qvi-rot1 rotate --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" >/dev/null
  kli_qvi_d qvi-rot2 rotate --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" >/dev/null
  wait_and_collect qvi-rot1 qvi-rot2

  kli_qvi_d qvi-qry1 query --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --prefix "${QAR2_PRE}" >/dev/null
  kli_qvi_d qvi-qry2 query --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --prefix "${QAR1_PRE}" >/dev/null
  wait_and_collect qvi-qry1 qvi-qry2
}

# Start delegate rotate/join containers but do not wait for completion.
function start_delegate_rotate_join_for_qvi() {
  local qar1_seq # current QAR1 sequence used to bind smids to concrete key state
  local qar2_seq # current QAR2 sequence used to bind smids to concrete key state

  qar1_seq=$(aid_seq kli_qvi "${QAR1}" "${QAR1}" "${QAR1_PASSCODE}")
  qar2_seq=$(aid_seq kli_qvi "${QAR2}" "${QAR2}" "${QAR2_PASSCODE}")
  [[ "${qar1_seq}" =~ ^[0-9]+$ ]] || fail "Invalid ${QAR1} sequence: ${qar1_seq}"
  [[ "${qar2_seq}" =~ ^[0-9]+$ ]] || fail "Invalid ${QAR2} sequence: ${qar2_seq}"

  log "Running delegated QVI multisig rotate/join"
  remove_if_exists qvi1 qvi2

  kli_qvi_d qvi2 multisig join --name "${QAR2}" --group "${QVI_NAME}" --passcode "${QAR2_PASSCODE}" --auto >/dev/null

  kli_qvi_d qvi1 multisig rotate --name "${QAR1}" --alias "${QVI_NAME}" --passcode "${QAR1_PASSCODE}" \
    --smids "${QAR1_PRE}:${qar1_seq}" --smids "${QAR2_PRE}:${qar2_seq}" \
    --isith '["1/2", "1/2"]' --nsith '["1/2", "1/2"]' \
    --rmids "${QAR1_PRE}" --rmids "${QAR2_PRE}" >/dev/null

  ensure_container_running qvi1
}

# Run delegated rotate/join in either confirm-approval or standalone mode.
function run_delegate_rotate_join_for_qvi() {
  local approve_with_delegate_confirm=${1:-false} # when true, start GAR delegate confirmations
  local wait_for_joiner=${2:-false} # when true, require qvi2 to finish too

  start_delegate_rotate_join_for_qvi

  if [[ "${approve_with_delegate_confirm}" == "true" ]]; then
    remove_if_exists gar1 gar2
    kli_gleif_d gar1 delegate confirm --name "${GAR1}" --alias "${GAR1}" \
      --passcode "${GAR1_PASSCODE}" --interact --auto >/dev/null
    kli_gleif_d gar2 delegate confirm --name "${GAR2}" --alias "${GAR2}" \
      --passcode "${GAR2_PASSCODE}" --interact --auto >/dev/null
    wait_and_collect qvi1 qvi2 gar1 gar2
  elif [[ "${wait_for_joiner}" == "true" ]]; then
    wait_and_collect qvi1 qvi2
  else
    wait_and_collect qvi1
    remove_if_exists qvi2
  fi
}

# Run only delegated rotate+join for fast isolation/debug iterations.
function run_rotate_join_only_mode() {
  local before_seq # qvi sequence before rotate+join
  local after_seq # qvi sequence after rotate+join

  before_seq=$(aid_seq kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}")
  [[ "${before_seq}" =~ ^[0-9]+$ ]] || fail "Invalid starting QVI sequence for rotate-join-only mode: ${before_seq}"

  log "Running rotate-join-only isolation mode"
  rotate_member_aids_for_qvi
  run_delegate_rotate_join_for_qvi false true

  after_seq=$(aid_seq kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}")
  assert_seq_incremented "${before_seq}" "${after_seq}" "QVI delegated rotate+join"

  write_isolation_debug_snapshots
  log "PASS: delegated rotate+join isolation mode completed"
}

# Query delegator key state from both delegates to discover delegation anchors.
function query_geda_keystate_from_qvi_delegates() {
  log "QAR delegates querying GEDA keystate for delegation approval discovery"
  kli_qvi query --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --prefix "${GEDA_PRE}" >/dev/null
  kli_qvi query --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --prefix "${GEDA_PRE}" >/dev/null
}

# Try delegator key-state queries with short per-command timeouts to avoid lock stalls.
function try_query_geda_keystate_from_qvi_delegates() {
  local query_timeout=3 # max seconds per delegate query attempt

  timeout "${query_timeout}s" \
    kli_qvi query --name "${QAR1}" --alias "${QAR1}" --passcode "${QAR1_PASSCODE}" --prefix "${GEDA_PRE}" >/dev/null 2>&1 || return 1
  timeout "${query_timeout}s" \
    kli_qvi query --name "${QAR2}" --alias "${QAR2}" --passcode "${QAR2_PASSCODE}" --prefix "${GEDA_PRE}" >/dev/null 2>&1 || return 1
  return 0
}

# Keep querying delegator key state while delegate rotate/join containers are in flight.
function query_geda_keystate_while_delegates_running() {
  local poll_timeout=${WAIT_TIMEOUT_SECONDS:-15} # max seconds to keep polling
  local elapsed=0 # elapsed seconds within polling loop
  local attempted_while_running=0 # set when at least one in-flight query attempt is made
  local queried_while_running=0 # set when at least one successful in-flight query completed

  log "Polling GEDA keystate from delegates while rotate/join is in flight"
  while [[ ${elapsed} -lt ${poll_timeout} ]]; do
    if container_is_running qvi1 || container_is_running qvi2; then
      attempted_while_running=1
      if try_query_geda_keystate_from_qvi_delegates; then
        queried_while_running=1
      fi
    elif [[ ${attempted_while_running} -ne 0 ]]; then
      return
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [[ ${attempted_while_running} -eq 0 ]]; then
    log "No in-flight delegate keystate query attempt occurred within ${poll_timeout}s"
    return 1
  fi
  if [[ ${queried_while_running} -eq 0 ]]; then
    log "No successful in-flight delegate keystate query occurred within ${poll_timeout}s (attempted under lock contention)"
  fi
  return 0
}

# Assert delegated QVI rotated sequence and anchored delegation state.
function assert_qvi_rotated_and_anchored() {
  local expected_seq=$1 # expected qvi sequence after rotation
  local max_attempts=${2:-6} # status polling attempts for anchor propagation
  local attempt=1 # current polling attempt counter
  local status="" # latest qvi status output

  while [[ ${attempt} -le ${max_attempts} ]]; do
    query_geda_keystate_from_qvi_delegates
    status=$(kli_qvi status --name "${QAR1}" --alias "${QVI_NAME}" --passcode "${QAR1_PASSCODE}")

    if echo "${status}" | grep -Eq "Seq No:[[:space:]]*${expected_seq}" \
      && echo "${status}" | grep -q "${GEDA_PRE}" \
      && ! echo "${status}" | grep -q "Not Anchored" \
      && echo "${status}" | grep -q "Anchored"; then
      return
    fi

    sleep 2
    attempt=$((attempt + 1))
  done

  echo "${status}"
  fail "QVI delegated rotation not anchored after ${max_attempts} polling attempts"
}

# Parse the latest drt JSON object from `kli status --verbose` text.
function extract_drt_json_from_status_verbose() {
  local status_verbose=$1 # full verbose status output

  printf '%s\n' "${status_verbose}" | awk '
    /^[[:space:]]*{/ {
      capture=1
      depth=0
      event=""
    }
    capture {
      event = event $0 ORS
      line=$0
      opens=gsub(/{/, "{", line)
      closes=gsub(/}/, "}", line)
      depth += (opens - closes)
      if (depth == 0) {
        capture=0
        printf "%s\n", event
      }
    }
  ' | jq -cs 'map(select(type == "object" and .t == "drt")) | last' 2>/dev/null || true
}

# Attempt to extract latest delegated rotation (drt) seal into ROTATION_ANCHOR_FILE.
function try_extract_latest_qvi_rotation_seal() {
  local expected_seq=${1:-} # expected delegated rotation sequence for this workflow
  local status_timeout=3 # max seconds for live status reads before snapshot fallback
  local member_name # member name used to pull qvi group verbose status
  local member_passcode # member passcode used with member_name
  local status_verbose # verbose qvi status output containing raw KERI events
  local drt_json # parsed latest drt event JSON object
  local i # event identifier prefix in seal
  local s # sequence number in seal
  local d # SAID digest in seal
  local snapshot_dir # temporary keystore copy used for fallback reads when live DB is locked

  # Primary path: read live keystores first for freshest state. We check both QAR
  # members because either local store may observe the delegated rotation first.
  for member_name in "${QAR1}" "${QAR2}"; do
    if [[ "${member_name}" == "${QAR1}" ]]; then
      member_passcode="${QAR1_PASSCODE}"
    else
      member_passcode="${QAR2_PASSCODE}"
    fi

    status_verbose=$(timeout "${status_timeout}s" \
      kli_qvi status --name "${member_name}" --alias "${QVI_NAME}" --passcode "${member_passcode}" --verbose 2>/dev/null || true)
    [[ -n "${status_verbose}" ]] || continue
    echo "${status_verbose}" | grep -q "mdb_txn_begin: Resource temporarily unavailable" && continue

    drt_json=$(extract_drt_json_from_status_verbose "${status_verbose}")
    [[ -n "${drt_json}" && "${drt_json}" != "null" ]] || continue

    # Pull out delegated rotation seal fields: identifier ('i'), sequence ('s'), SAID ('d').
    i=$(printf '%s\n' "${drt_json}" | jq -r '.i' 2>/dev/null || true)
    s=$(printf '%s\n' "${drt_json}" | jq -r '.s' 2>/dev/null || true)
    d=$(printf '%s\n' "${drt_json}" | jq -r '.d' 2>/dev/null || true)
    [[ -n "${i}" && "${i}" != "null" && -n "${s}" && "${s}" != "null" && -n "${d}" && "${d}" != "null" ]] || continue

    # Ensure we anchor only the current QVI rotation event.
    [[ -z "${QVI_PRE}" || "${i}" == "${QVI_PRE}" ]] || continue
    if [[ -n "${expected_seq}" ]]; then
      [[ "${s}" =~ ^[0-9]+$ ]] || continue
      [[ "${s}" -eq "${expected_seq}" ]] || continue
    fi

    # Success path: write the single-event seal payload consumed by GAR multisig interact.
    jq -n --arg i "${i}" --arg s "${s}" --arg d "${d}" '[{i: $i, s: $s, d: $d}]' > "${ROTATION_ANCHOR_FILE}" || return 1
    return 0
  done

  # Fallback path: copy keystores and re-read from the snapshot to bypass transient
  # LMDB contention with in-flight rotate/join containers.
  snapshot_dir=$(mktemp -d "${EVENTS_DIR}/keystore-snapshot.XXXXXX")
  cp -a "${KEYSTORE_DIR}/." "${snapshot_dir}/" >/dev/null 2>&1 || {
    rm -rf "${snapshot_dir}" >/dev/null 2>&1 || true
    return 1
  }

  # Repeat the same two-member scan against the snapshot so behavior stays symmetric
  # with the primary path, just without live keystore lock pressure.
  for member_name in "${QAR1}" "${QAR2}"; do
    if [[ "${member_name}" == "${QAR1}" ]]; then
      member_passcode="${QAR1_PASSCODE}"
    else
      member_passcode="${QAR2_PASSCODE}"
    fi

    status_verbose=$(KEYSTORE_DIR="${snapshot_dir}" kli_qvi status --name "${member_name}" --alias "${QVI_NAME}" --passcode "${member_passcode}" --verbose 2>/dev/null || true)
    [[ -n "${status_verbose}" ]] || continue

    drt_json=$(extract_drt_json_from_status_verbose "${status_verbose}")
    [[ -n "${drt_json}" && "${drt_json}" != "null" ]] || continue

    i=$(printf '%s\n' "${drt_json}" | jq -r '.i' 2>/dev/null || true)
    s=$(printf '%s\n' "${drt_json}" | jq -r '.s' 2>/dev/null || true)
    d=$(printf '%s\n' "${drt_json}" | jq -r '.d' 2>/dev/null || true)
    [[ -n "${i}" && "${i}" != "null" && -n "${s}" && "${s}" != "null" && -n "${d}" && "${d}" != "null" ]] || continue
    [[ -z "${QVI_PRE}" || "${i}" == "${QVI_PRE}" ]] || continue
    if [[ -n "${expected_seq}" ]]; then
      [[ "${s}" =~ ^[0-9]+$ ]] || continue
      [[ "${s}" -eq "${expected_seq}" ]] || continue
    fi

    jq -n --arg i "${i}" --arg s "${s}" --arg d "${d}" '[{i: $i, s: $s, d: $d}]' > "${ROTATION_ANCHOR_FILE}" || {
      rm -rf "${snapshot_dir}" >/dev/null 2>&1 || true
      return 1
    }
    rm -rf "${snapshot_dir}" >/dev/null 2>&1 || true
    return 0 # seal extracted and written successfully
  done

  rm -rf "${snapshot_dir}" >/dev/null 2>&1 || true
  return 1 # no valid drt seal found in either live or snapshot reads
}

# Extract rotation seal and fail hard when it cannot be found.
function extract_latest_qvi_rotation_seal() {
  try_extract_latest_qvi_rotation_seal || fail "Could not locate delegated rotation event (drt) for QVI"
  log "Wrote delegated rotation anchor seal to ${ROTATION_ANCHOR_FILE}"
}

# Start GAR multisig interact approvals using rotation seal data.
function approve_qvi_rotation_with_multisig_interact() {
  [[ -f "${ROTATION_ANCHOR_FILE}" ]] || fail "Rotation anchor file missing: ${ROTATION_ANCHOR_FILE}"

  log "Approving delegated rotation with geda multisig interact"
  remove_if_exists gar1 gar2

  kli_gleif_d gar1 multisig interact --name "${GAR1}" --alias "${GEDA_NAME}" \
    --passcode "${GAR1_PASSCODE}" --data @/events/$(basename "${ROTATION_ANCHOR_FILE}") >/dev/null

  kli_gleif_d gar2 multisig interact --name "${GAR2}" --alias "${GEDA_NAME}" \
    --passcode "${GAR2_PASSCODE}" --data @/events/$(basename "${ROTATION_ANCHOR_FILE}") >/dev/null
}

# Run non-confirm delegated rotation approval with concurrent rotate/join + interact.
function run_rotation_workflow_multisig_interact_concurrent() {
  local expected_seq=$1 # delegated qvi sequence that the extracted drt must match
  local seal_timeout=${WAIT_TIMEOUT_SECONDS:-15} # max seconds to discover drt seal while in flight
  local elapsed=0 # elapsed seconds while polling for seal extraction
  local query_pid # background PID used to enforce in-flight delegate keystate query after interact

  remove_if_exists gar1 gar2
  start_delegate_rotate_join_for_qvi

  log "Waiting for delegated rotation seal while delegate rotate/join is in flight"
  while [[ ${elapsed} -lt ${seal_timeout} ]]; do
    if try_extract_latest_qvi_rotation_seal "${expected_seq}"; then
      log "Wrote delegated rotation anchor seal to ${ROTATION_ANCHOR_FILE}"
      break
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [[ ! -s "${ROTATION_ANCHOR_FILE}" ]]; then
    print_container_diagnostics qvi1
    print_container_diagnostics qvi2
    dump_container_logs qvi1 qvi2
    write_isolation_debug_snapshots
    fail "Failed to derive delegated rotation seal for seq ${expected_seq} within ${seal_timeout}s"
  fi

  approve_qvi_rotation_with_multisig_interact
  query_geda_keystate_while_delegates_running &
  query_pid=$!
  wait_and_collect qvi1 qvi2 gar1 gar2
  wait "${query_pid}" || fail "Delegate keystate polling failed during concurrent multisig interact approval"
}

# Verify QVI group can still emit a normal multisig interaction after rotation.
function exercise_qvi_multisig_interact() {
  local tag=$1 # tag inserted into arbitrary interaction data payload
  local before # qvi sequence before multisig interact
  local after # qvi sequence after multisig interact
  local data # interaction payload inserted into event `a` section

  before=$(aid_seq kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}")
  data=$(jq -nc --arg tag "${tag}" '{test:"qvi-post-rotation", tag:$tag}')

  log "Exercising QVI multisig interact (${tag})"
  remove_if_exists qvi1 qvi2

  kli_qvi_d qvi1 multisig interact --name "${QAR1}" --alias "${QVI_NAME}" \
    --passcode "${QAR1_PASSCODE}" --data "${data}" >/dev/null

  kli_qvi_d qvi2 multisig interact --name "${QAR2}" --alias "${QVI_NAME}" \
    --passcode "${QAR2_PASSCODE}" --data "${data}" >/dev/null

  wait_and_collect qvi1 qvi2

  after=$(aid_seq kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}")
  assert_seq_incremented "${before}" "${after}" "QVI multisig interact"
}

# Verify GEDA group can still emit a normal multisig interaction after approvals.
function exercise_geda_multisig_interact() {
  local tag=$1 # tag inserted into arbitrary interaction data payload
  local before # geda sequence before multisig interact
  local after # geda sequence after multisig interact
  local data # interaction payload inserted into event `a` section

  before=$(aid_seq kli_gleif "${GAR1}" "${GEDA_NAME}" "${GAR1_PASSCODE}")
  data=$(jq -nc --arg tag "${tag}" '{test:"geda-post-rotation", tag:$tag}')

  log "Exercising GEDA multisig interact (${tag})"
  remove_if_exists gar1 gar2

  kli_gleif_d gar1 multisig interact --name "${GAR1}" --alias "${GEDA_NAME}" \
    --passcode "${GAR1_PASSCODE}" --data "${data}" >/dev/null

  kli_gleif_d gar2 multisig interact --name "${GAR2}" --alias "${GEDA_NAME}" \
    --passcode "${GAR2_PASSCODE}" --data "${data}" >/dev/null

  wait_and_collect gar1 gar2

  after=$(aid_seq kli_gleif "${GAR1}" "${GEDA_NAME}" "${GAR1_PASSCODE}")
  assert_seq_incremented "${before}" "${after}" "GEDA multisig interact"
}

# Delegated rotation approval flow using GAR `delegate confirm`.
function test_rotation_workflow_delegate_confirm() {
  local before_seq # qvi sequence before running this rotation workflow

  before_seq=$(aid_seq kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}")
  [[ "${before_seq}" =~ ^[0-9]+$ ]] || fail "Invalid starting QVI sequence: ${before_seq}"

  log "Starting delegated rotation workflow: delegate confirm approval"
  rotate_member_aids_for_qvi
  run_delegate_rotate_join_for_qvi true
  query_geda_keystate_from_qvi_delegates
  assert_qvi_rotated_and_anchored "$((before_seq + 1))"

  exercise_qvi_multisig_interact "after-confirm-approval"
  exercise_geda_multisig_interact "after-confirm-approval"
}

# Delegated rotation approval flow using GAR multisig interact with rotation seal.
function test_rotation_workflow_multisig_interact() {
  local before_seq # qvi sequence before running this rotation workflow
  local expected_seq # expected qvi sequence after this rotation workflow

  before_seq=$(aid_seq kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}")
  [[ "${before_seq}" =~ ^[0-9]+$ ]] || fail "Invalid starting QVI sequence: ${before_seq}"
  expected_seq=$((before_seq + 1))

  log "Starting delegated rotation workflow: geda multisig interact approval"
  rotate_member_aids_for_qvi
  run_rotation_workflow_multisig_interact_concurrent "${expected_seq}"
  query_geda_keystate_from_qvi_delegates
  assert_qvi_rotated_and_anchored "${expected_seq}"

  exercise_qvi_multisig_interact "after-interact-approval"
  exercise_geda_multisig_interact "after-interact-approval"
}

# Initialize baseline state either from checkpoint or by rebuilding from scratch.
function initialize_common_setup() {
  local restored=false # toggled when checkpoint restore succeeds

  if ${CLEAR_CHECKPOINT}; then
    log "--clear set, deleting existing checkpoint and runtime state"
    clear_checkpoint_artifacts
    clear_runtime_state
    prepare_events_dir
  fi

  create_single_sig_icp_config
  start_stack

  if ! ${CLEAR_CHECKPOINT} && checkpoint_exists; then
    if restore_checkpoint_if_available; then
      restored=true
      log "Restored common setup from checkpoint"
    else
      log "Checkpoint invalid or restore failed, rebuilding common setup"
      clear_checkpoint_artifacts
      find "${KEYSTORE_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + >/dev/null 2>&1 || true
    fi
  fi

  if ! ${restored}; then
    build_common_setup_from_scratch
  fi
}

# Reset mutable test state back to the saved multisig baseline checkpoint.
function reset_to_checkpoint_baseline() {
  checkpoint_exists || fail "Checkpoint artifacts missing; cannot reset baseline between workflows"
  remove_if_exists gar1 gar2 qvi1 qvi2
  restore_checkpoint_if_available || fail "Failed to restore checkpoint baseline between workflows"
  refresh_known_prefixes_from_keystore
  log "Reset workflow state from checkpoint baseline"
}

GEDA_PRE=""
QVI_PRE=""
GAR1_PRE=""
GAR2_PRE=""
QAR1_PRE=""
QAR2_PRE=""

log "Starting delegation compatibility test"
check_dependencies
prepare_events_dir
initialize_common_setup

if ${ROTATE_JOIN_ONLY}; then
  run_rotate_join_only_mode
  exit 0
fi

if ${DELEGATE_CONFIRM_ONLY}; then
  test_rotation_workflow_delegate_confirm
  log "PASS: delegate confirm rotation workflow succeeded"
  exit 0
fi

if ${MULTISIG_INTERACT_ONLY}; then
  test_rotation_workflow_multisig_interact
  log "PASS: multisig interact rotation workflow succeeded"
  exit 0
fi

test_rotation_workflow_delegate_confirm
reset_to_checkpoint_baseline
test_rotation_workflow_multisig_interact

log "PASS: QVI delegated multisig rotation approval succeeded with delegate confirm and multisig interact (1.2.11 <- 1.1.42)"
