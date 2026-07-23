#!/usr/bin/env bash
#
# run-multisig-catchup.sh
# KERIpy KLI late-joiner export/ingest compatibility harness for QVI schema use.
#
# Purpose:
#   Prove that a late multisig joiner can learn the current group KEL but still
#   lacks pre-existing registry TELs and ACDCs until another member exports CESR
#   material and the joiner ingests it with `kli import --cesr-in`.
#
# Flow:
#   - Default: m1/m2 create group g, registry r1, and one issued ACDC; m3 joins
#     later, demonstrates missing prior material, ingests m1's CESR export,
#     renames the imported registry to r1, verifies visibility, then leads a
#     revocation on the prior credential.
#   - With --stress-chain: A-F churn through repeated add/remove rotations.
#     Each newest joiner ingests current material, proves old active credentials
#     are visible, creates new registry/credential material, and revokes prior
#     issuances after the original A/B/C members have been removed.
#
# Runtime dependencies:
#   - Raw globally installed `kli` from the KERIpy branch under test.
#   - `jq` for generated JSON config files.
#   - `kli witness demo` running locally; this script uses witnesses 5642-5644.
#   - vLEI server on 127.0.0.1:7723 serving the QVI schema OOBI, for example
#     from the vLEI repo root:
#       vLEI-server -s ./schema/acdc -c ./samples/acdc/ -o ./samples/oobis/
#
# State model:
#   - All JSON configs are generated under a temp artifact directory.
#   - KLI stores use short bases like `base-m1`; cleanup removes matching
#     `~/.keri/{ks,db,reg,cf}/base-*` stores owned by this script.
#   - `--keep-artifacts` preserves logs, generated configs, and CESR bundles.

set -euo pipefail
export PYTHONUNBUFFERED=1

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)

echo "=== SCRIPT TRACE START $(date) ==="

### CLI options and runtime state

KEEP_ARTIFACTS=0  # preserves logs, generated configs, and CESR bundle files
VERBOSE=0         # verbose log output
KLI_DEBUG=true    # show traceback when a Python error occurs in the KLI KERIpy code
STRESS_CHAIN=0    # run the longer D - F part of the chain.

# Directories used for temp config files and artifact outputs.
WORK_DIR=""
BASE_DIR=""
BASE_PREFIX=""
ARTIFACT_DIR=""
CONFIG_DIR=""
HABERY_CONFIG_DIR=""
HABERY_CONFIG_NAME="qvi-witness-oobis"
HABERY_CONFIG_FILE=""
SINGLE_AID_CONFIG=""
GROUP_CONFIG=""
CRED_DATA=""

PUSHD_DONE=0

### Deterministic material, witnesses, schema, and recipient data

# Default-path salts are fixed so m1/m2/m3 prefixes are reproducible when
# witnesses are clean. Stress mode randomizes these before any controller init.
M1_SALT="0ACDEyMzQ1Njc4OWxtbm9aBc"
M2_SALT="0ACDEyMzQ1Njc4OWdoaWpsaw"
M3_SALT="0ACYprXj2rKgDoTLJplGwWfr"

A_SALT="$M1_SALT"
B_SALT="$M2_SALT"
C_SALT="$M3_SALT"
D_SALT="0AAzG1qHUie7TSKfGN31cEQ6"
E_SALT="0AAtdhqCqhS4yeHhcTUTGp5u"
F_SALT="0ADctVsyJUvqCs2cOg-9S1sp"

RECP_SALT="0ACTDn1f2jWv7UwOWHi9AKug"

# Expected witness AIDs
WIT1="BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha"
WIT2="BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM"
WIT3="BIKKuvBwpmDVA4Ds-EpL5bt9OqPzWPja2LigFYZN2YfX"

# Expected witness HTTP endpoints
WIT1_URL="http://127.0.0.1:5642"
WIT2_URL="http://127.0.0.1:5643"
WIT3_URL="http://127.0.0.1:5644"

QVI_SCHEMA_SAID="EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao"
QVI_SCHEMA_OOBI="http://127.0.0.1:7723/oobi/$QVI_SCHEMA_SAID"
CRED_LEI="5493001KJTIIGC8Y1R17"

# Nonces for registries (deterministic registry creation)
R1_NONCE="AHSNDV3ABI6U8OIgKaj3aky91ZpNL54I5_7-qwtC6q2s"
R2_NONCE="0ADspHaRexCSNsuvfpvzi6gj"
R3_NONCE="0AAw_XfV0LH_Wzz6XhjQBJLQ"
R4_NONCE="0ACwXHR4wQK-8M4iwX1FOvOr"

# Vars for AIDs, registry SAIDs, credential SAIDs, Sequence Number, and PIDs
M1_AID=""
M2_AID=""
M3_AID=""
A_AID=""
B_AID=""
C_AID=""
D_AID=""
E_AID=""
F_AID=""
G_AID=""
RECP_AID=""
R1_REGK=""
R2_REGK=""
R3_REGK=""
R4_REGK=""
CRED_SAID=""
VC1_SAID=""
VC2_SAID=""
VC3_SAID=""
VC4_SAID=""
VC5_SAID=""
GROUP_SN=0
JOIN_PIDS=()

GAP_REPRODUCED=0

log() { echo ">>> $*"; }
step() { echo ""; echo "=== $* ==="; }

usage() {
  cat <<'USAGE'
Usage:
  cd test-scripts/multisig-catchup
  ./run-multisig-catchup.sh [--keep-artifacts] [--verbose] [--stress-chain]

Options:
  --keep-artifacts   Keep generated configs, CESR bundles, and operation logs.
  --verbose, -v      Reserve flag for noisy debugging output.
  --stress-chain     Run the A-F churn scenario instead of the default m1/m2/m3 flow.

Prerequisites:
  1. raw globally installed `kli` and `jq`
  2. `kli witness demo`
  3. vLEI-server -s ./schema/acdc -c ./samples/acdc/ -o ./samples/oobis/

Examples:
  test-scripts/multisig-catchup/run-multisig-catchup.sh --keep-artifacts
  test-scripts/multisig-catchup/run-multisig-catchup.sh --stress-chain --keep-artifacts

Automation:
  Set AUTO=1, CI=1, or NONINTERACTIVE=1 to skip the readiness prompt.
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep-artifacts) KEEP_ARTIFACTS=1; shift ;;
      --verbose|-v) VERBOSE=1; shift ;;
      --stress-chain) STRESS_CHAIN=1; shift ;;
      --help|-h)
        usage
        exit 0
        ;;
      *) echo "Unknown arg: $1"; usage; exit 1 ;;
    esac
  done
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' not found on PATH."
    exit 1
  fi
}

require_default_mode() {
  local caller="$1"
  if [[ $STRESS_CHAIN -eq 1 ]]; then
    echo "ERROR: $caller is default m1/m2/m3-only and must not run during --stress-chain." >&2
    return 1
  fi
}

new_salt() {
  kli nonce
}

randomize_stress_material() {
  A_SALT=$(new_salt)
  B_SALT=$(new_salt)
  C_SALT=$(new_salt)
  D_SALT=$(new_salt)
  E_SALT=$(new_salt)
  F_SALT=$(new_salt)
  RECP_SALT=$(new_salt)

  R1_NONCE=$(new_salt)
  R2_NONCE=$(new_salt)
  R3_NONCE=$(new_salt)
  R4_NONCE=$(new_salt)
}

wait_all() {
  local rc=0
  local pid

  for pid in "$@"; do
    wait "$pid" || rc=$?
  done

  return "$rc"
}

### Runtime setup and cleanup

cleanup() {
  if [[ $PUSHD_DONE -eq 1 ]]; then
    popd >/dev/null 2>&1 || true
  fi

  if [[ -n "${BASE_PREFIX:-}" ]]; then
    for pfx in m1 m2 m3 a b c d e f recp; do
      rm -rf \
        ~/.keri/ks/"${BASE_PREFIX}-${pfx}" \
        ~/.keri/db/"${BASE_PREFIX}-${pfx}" \
        ~/.keri/reg/"${BASE_PREFIX}-${pfx}" \
        ~/.keri/cf/"${BASE_PREFIX}-${pfx}" \
        2>/dev/null || true
    done
  fi

  if [[ $KEEP_ARTIFACTS -eq 1 ]]; then
    if [[ -n "${ARTIFACT_DIR:-}" ]]; then
      log "Keeping artifacts at: $ARTIFACT_DIR (and work dir $WORK_DIR)"
    fi
  else
    if [[ -n "${WORK_DIR:-}" ]]; then
      rm -rf "$WORK_DIR"
    fi
  fi
}

setup_workdirs() {
  WORK_DIR=$(mktemp -d -t qvi-multisig-catchup-XXXXXX)
  BASE_DIR="$WORK_DIR/base"
  ARTIFACT_DIR="$WORK_DIR/artifacts"
  CONFIG_DIR="$ARTIFACT_DIR/config"
  HABERY_CONFIG_DIR="$CONFIG_DIR/habery"
  HABERY_CONFIG_FILE="$HABERY_CONFIG_DIR/keri/cf/$HABERY_CONFIG_NAME.json"
  SINGLE_AID_CONFIG="$CONFIG_DIR/single-aid-incept.json"
  GROUP_CONFIG="$CONFIG_DIR/group-g-incept.json"
  CRED_DATA="$CONFIG_DIR/credential-data.json"

  mkdir -p "$BASE_DIR" "$CONFIG_DIR" "$(dirname "$HABERY_CONFIG_FILE")"

  # KLI base handling expects relative base names in several paths. Keep the
  # process cwd in a private temp dir and use short `base-*` names for every
  # script-owned controller store.
  pushd "$WORK_DIR" >/dev/null
  PUSHD_DONE=1
  BASE_PREFIX="base"

  for pfx in m1 m2 m3 a b c d e f recp; do
    rm -rf \
      ~/.keri/ks/"${BASE_PREFIX}-${pfx}" \
      ~/.keri/db/"${BASE_PREFIX}-${pfx}" \
      ~/.keri/reg/"${BASE_PREFIX}-${pfx}" \
      ~/.keri/cf/"${BASE_PREFIX}-${pfx}" \
      2>/dev/null || true
  done
}

### Generated config writers

write_habery_config() {
  jq -n \
    --arg dt "$(date -Iseconds -u)" \
    --arg iurl1 "$WIT1_URL/oobi/$WIT1/controller" \
    --arg iurl2 "$WIT2_URL/oobi/$WIT2/controller" \
    --arg iurl3 "$WIT3_URL/oobi/$WIT3/controller" \
    "$(cat <<'JQ'
{
  dt: $dt,
  iurls: [$iurl1, $iurl2, $iurl3]
}
JQ
)" > "$HABERY_CONFIG_FILE"
}

write_single_aid_config() {
  jq -n \
    --arg wit1 "$WIT1" \
    --arg wit2 "$WIT2" \
    --arg wit3 "$WIT3" \
    "$(cat <<'JQ'
{
  transferable: true,
  wits: [$wit1, $wit2, $wit3],
  toad: 2,
  icount: 1,
  ncount: 1,
  isith: "1",
  nsith: "1"
}
JQ
)" > "$SINGLE_AID_CONFIG"
}

write_credential_data() {
  jq -n \
    --arg lei "$CRED_LEI" \
    "$(cat <<'JQ'
{
  LEI: $lei
}
JQ
)" > "$CRED_DATA"
}

write_group_config() {
  require_aid "M1_AID" "$M1_AID"
  require_aid "M2_AID" "$M2_AID"

  jq -n \
    --arg m1 "$M1_AID" \
    --arg m2 "$M2_AID" \
    --arg wit1 "$WIT1" \
    --arg wit2 "$WIT2" \
    --arg wit3 "$WIT3" \
    "$(cat <<'JQ'
{
  aids: [$m2, $m1],
  transferable: true,
  wits: [$wit1, $wit2, $wit3],
  toad: 3,
  isith: "2",
  nsith: "2"
}
JQ
)" > "$GROUP_CONFIG"
}

write_generated_configs() {
  step "WRITE GENERATED CONFIGS"
  write_habery_config
  write_single_aid_config
  write_credential_data

  for file in "$HABERY_CONFIG_FILE" "$SINGLE_AID_CONFIG" "$CRED_DATA"; do
    jq -e . "$file" >/dev/null
    log "Generated $(basename "$file"): $file"
  done
}

### Generic KLI helpers and assertions

init_controller() {
  local name="$1"
  local salt="$2"
  local base="${BASE_PREFIX}-${name}"

  kli init \
    --name "$name" \
    --base "$base" \
    --salt "$salt" --nopasscode \
    --config-dir "$HABERY_CONFIG_DIR" \
    --config-file "$HABERY_CONFIG_NAME"

  kli incept --name "$name" --alias "$name" \
    --base "$base" \
    --file "$SINGLE_AID_CONFIG"
}

aid_for() {
  local name="$1"
  local alias="$2"
  local base="${BASE_PREFIX}-${name}"

  kli aid --name "$name" --alias "$alias" --base "$base"
}

require_aid() {
  local label="$1"
  local value="$2"

  if [[ -z "$value" ]] || echo "$value" | grep -qiE "ERR:|not a valid alias|does not exist|Traceback|error"; then
    echo "ERROR: failed to capture valid AID for $label: $value"
    exit 1
  fi
}

require_value() {
  local label="$1"
  local value="$2"

  if [[ -z "$value" ]] || echo "$value" | grep -qiE "ERR:|Traceback|error"; then
    echo "ERROR: failed to capture valid value for $label: $value"
    exit 1
  fi
}

clear_notifications() {
  local name="$1"
  local base="${BASE_PREFIX}-${name}"

  # `kli multisig join --auto` acts on pending notifications. Repro runs create
  # several expected stale notices, so clear only these temp script stores before
  # starting responder joiners.
  log "Clearing stale notifications for $name."
  printf 'y\n' | kli notifications rem --name "$name" --base "$base" --all >/dev/null || true
}

registry_said_for() {
  local name="$1"
  local registry_name="$2"
  local base="${BASE_PREFIX}-${name}"

  kli vc registry list --name "$name" --base "$base" |
    awk -v registry_name="$registry_name" '$1 == registry_name && $2 == ":" {print $3; exit}'
}

query_aid_expect_seq() {
  local name="$1"
  local alias="$2"
  local prefix="$3"
  local expected_seq="$4"
  local base="${BASE_PREFIX}-${name}"
  local query_out
  local actual_seq

  # Sequence assertions are protocol checkpoints: every registry incept,
  # issuance, revocation, and group rotation should anchor exactly one group KEL
  # event in this script's expected schedule.
  query_out=$(kli query --name "$name" --alias "$alias" --prefix "$prefix" --base "$base" 2>&1)
  echo "$query_out"

  actual_seq=$(echo "$query_out" | awk '/Seq No:/ {print $3; exit}')
  if [[ "$actual_seq" != "$expected_seq" ]]; then
    echo "ERROR: expected $prefix to be at sequence $expected_seq for $name/$alias, got '${actual_seq:-unknown}'."
    echo "ERROR: witness state may be stale or OOBI resolution may not have completed; restart/clean demo witnesses and rerun if this persists."
    return 1
  fi
}

issued_credential_said_for() {
  local name="$1"
  local alias="$2"
  local base="${BASE_PREFIX}-${name}"

  kli vc list --name "$name" --alias "$alias" --issued --said --base "$base" |
    awk 'NF && $0 !~ /ERR:|Traceback|error/ {print; exit}'
}

### Default m1/m2/m3 scenario

init_controllers() {
  step "INIT CONTROLLERS (m1, m2 existing members; m3 late joiner; recp QVI cred recipient)"
  init_controller m1 "$M1_SALT"
  init_controller m2 "$M2_SALT"
  init_controller m3 "$M3_SALT"

  init_controller recp "$RECP_SALT"

  M1_AID=$(aid_for m1 m1)
  M2_AID=$(aid_for m2 m2)
  M3_AID=$(aid_for m3 m3)
  RECP_AID=$(aid_for recp recp)

  require_aid "M1_AID" "$M1_AID"
  require_aid "M2_AID" "$M2_AID"
  require_aid "M3_AID" "$M3_AID"
  require_aid "RECP_AID" "$RECP_AID"

  log "m1 AID: $M1_AID"
  log "m2 AID: $M2_AID"
  log "m3 AID: $M3_AID"
  log "recp AID: $RECP_AID"
}

resolve_oobi() {
  local name="$1"
  local alias="$2"
  local aid="$3"

  kli oobi resolve --name "$name" --oobi-alias "$alias" \
    --oobi "$WIT1_URL/oobi/$aid/witness/$WIT1" \
    --base "${BASE_PREFIX}-${name}"
}

resolve_member_oobis() {
  if [[ $# -gt 0 ]]; then
    local resolver="$1"
    shift
    local resolver_name
    local target
    local target_name
    resolver_name=$(member_name "$resolver")

    for target in "$@"; do
      if [[ "$target" == "$resolver" ]]; then
        continue
      fi
      target_name=$(member_name "$target")
      resolve_oobi "$resolver_name" "$target_name" "$(member_aid "$target")"
    done
    return
  fi

  step "OOBI EXCHANGE"
  resolve_oobi m1 m2 "$M2_AID"
  resolve_oobi m1 m3 "$M3_AID"
  resolve_oobi m2 m1 "$M1_AID"
  resolve_oobi m2 m3 "$M3_AID"
  resolve_oobi m3 m1 "$M1_AID"
  resolve_oobi m3 m2 "$M2_AID"

  resolve_oobi m1 recp "$RECP_AID"
  resolve_oobi m2 recp "$RECP_AID"
  resolve_oobi m3 recp "$RECP_AID"

  log "Querying current member key states before group inception."
  query_aid_expect_seq m1 m1 "$M2_AID" 0
  query_aid_expect_seq m2 m2 "$M1_AID" 0
}

resolve_schema_oobis() {
  step "SCHEMA OOBI (vLEI-server path)"
  log "Resolving schema OOBI: $QVI_SCHEMA_OOBI"

  kli oobi resolve --name m1 --oobi-alias vc --oobi "$QVI_SCHEMA_OOBI" --base "${BASE_PREFIX}-m1"
  kli oobi resolve --name m2 --oobi-alias vc --oobi "$QVI_SCHEMA_OOBI" --base "${BASE_PREFIX}-m2"
  kli oobi resolve --name m3 --oobi-alias vc --oobi "$QVI_SCHEMA_OOBI" --base "${BASE_PREFIX}-m3"
  kli oobi resolve --name recp --oobi-alias vc --oobi "$QVI_SCHEMA_OOBI" --base "${BASE_PREFIX}-recp"
}

create_group() {
  step "CREATE MULTISIG GROUP (m1 + m2)"
  write_group_config
  jq -e . "$GROUP_CONFIG" >/dev/null
  log "Generated group config: $GROUP_CONFIG"

  local pids=()
  kli multisig incept --name m1 --alias m1 --group g --file "$GROUP_CONFIG" --base "${BASE_PREFIX}-m1" &
  pids+=("$!")
  kli multisig incept --name m2 --alias m2 --group g --file "$GROUP_CONFIG" --base "${BASE_PREFIX}-m2" &
  pids+=("$!")

  wait_all "${pids[@]}"

  G_AID=$(aid_for m1 g)
  require_aid "G_AID" "$G_AID"

  log "Group AID: $G_AID"
  kli status --name m1 --alias g --base "${BASE_PREFIX}-m1"
}

incept_registry() {
  step "REGISTRY INCEPT (group g)"

  local pids=()
  kli vc registry incept --name m1 --alias g --registry-name r1 \
    --usage "Repro registry for late-join test" --nonce "$R1_NONCE" \
    --base "${BASE_PREFIX}-m1" &
  pids+=("$!")
  kli vc registry incept --name m2 --alias g --registry-name r1 \
    --usage "Repro registry for late-join test" --nonce "$R1_NONCE" \
    --base "${BASE_PREFIX}-m2" &
  pids+=("$!")

  wait_all "${pids[@]}"

  log "Registry list from m1:"
  kli vc registry list --name m1 --base "${BASE_PREFIX}-m1"
  R1_REGK=$(registry_said_for m1 r1)
  require_value "R1_REGK" "$R1_REGK"
  log "Registry r1 SAID: $R1_REGK"
}

issue_credential() {
  step "ISSUE CREDENTIAL on registry r1"

  local issued_at
  issued_at=$(date -Iseconds -u)

  local pids=()
  kli vc create --name m1 --alias g --registry-name r1 \
    --schema "$QVI_SCHEMA_SAID" \
    --recipient "$RECP_AID" \
    --data @"$CRED_DATA" \
    --time "$issued_at" --base "${BASE_PREFIX}-m1" &
  pids+=("$!")
  kli vc create --name m2 --alias g --registry-name r1 \
    --schema "$QVI_SCHEMA_SAID" \
    --recipient "$RECP_AID" \
    --data @"$CRED_DATA" \
    --time "$issued_at" --base "${BASE_PREFIX}-m2" &
  pids+=("$!")

  wait_all "${pids[@]}"

  CRED_SAID=$(issued_credential_said_for m1 g)
  require_value "CRED_SAID" "$CRED_SAID"

  log "Credential SAID: $CRED_SAID"
  log "Credential list from m1:"
  kli vc list --name m1 --alias g --issued --base "${BASE_PREFIX}-m1"
}

rotate_current_group_members() {
  step "ROTATE CURRENT MEMBER AIDs (m1 + m2)"

  kli rotate --name m1 --alias m1 --base "${BASE_PREFIX}-m1"
  kli query --name m2 --alias m2 --prefix "$M1_AID" --base "${BASE_PREFIX}-m2"

  kli rotate --name m2 --alias m2 --base "${BASE_PREFIX}-m2"
  kli query --name m1 --alias m1 --prefix "$M2_AID" --base "${BASE_PREFIX}-m1"

  resolve_oobi m3 m1 "$M1_AID"
  resolve_oobi m3 m2 "$M2_AID"
}

late_join_m3() {
  step "LATE JOIN: rotate g to add m3, then m3 performs multisig join"

  local pids=()
  local rc=0

  rotate_current_group_members

  kli multisig rotate --name m1 --alias g \
    --smids "$M3_AID" \
    --smids "$M2_AID" \
    --smids "$M1_AID" \
    --isith '["1/2","1/2","1/2"]' \
    --nsith '["1/2","1/2","1/2"]' \
    --rmids "$M3_AID" \
    --rmids "$M2_AID" \
    --rmids "$M1_AID" \
    --base "${BASE_PREFIX}-m1" &
  pids+=("$!")

  kli multisig rotate --name m2 --alias g \
    --smids "$M3_AID" \
    --smids "$M2_AID" \
    --smids "$M1_AID" \
    --isith '["1/2","1/2","1/2"]' \
    --nsith '["1/2","1/2","1/2"]' \
    --rmids "$M3_AID" \
    --rmids "$M2_AID" \
    --rmids "$M1_AID" \
    --base "${BASE_PREFIX}-m2" &
  pids+=("$!")

  log "m3 resolves OOBI for group g and joins."
  kli oobi resolve --name m3 --oobi-alias g \
    --oobi "$WIT1_URL/oobi/$G_AID/witness/$WIT1" \
    --base "${BASE_PREFIX}-m3" || rc=$?

  if [[ $rc -eq 0 ]]; then
    kli multisig join --name m3 --group g --auto --base "${BASE_PREFIX}-m3" || rc=$?
  fi

  wait_all "${pids[@]}" || rc=$?

  if [[ $rc -ne 0 ]]; then
    return "$rc"
  fi

  kli status --name m3 --alias g --base "${BASE_PREFIX}-m3"
}

pre_ingest_checks() {
  require_default_mode "pre_ingest_checks"
  step "PRE-INGEST CHECKS (THE GAP WE ARE REPRODUCING)"

  local reg_list_out
  local vc_list_out

  echo ""
  echo "=== REGISTRY LIST FROM NEW MEMBER (m3) ==="
  reg_list_out=$(kli vc registry list --name m3 --base "${BASE_PREFIX}-m3" 2>&1 || true)
  echo "$reg_list_out"

  echo ""
  echo "=== VC LIST FROM NEW MEMBER (m3) ==="
  vc_list_out=$(kli vc list --name m3 --alias g --issued --base "${BASE_PREFIX}-m3" 2>&1 || true)
  echo "$vc_list_out"

  if echo "$reg_list_out" | grep -qi "r1"; then
    echo "Unexpected: r1 is already visible before ingest. The repro may be running against a patched tree or reused state."
    GAP_REPRODUCED=0
  else
    echo ""
    echo "=== GAP REPRODUCED: new member (m3) does not see prior registry state for group g ==="
    echo "=== GAP REPRODUCED: vc list also lacks the pre-existing ACDC(s) ==="
    GAP_REPRODUCED=1
  fi
}

### Export/ingest sync flow

export_prior_materials() {
  local exporter_name="$1"
  local exporter_alias="$2"

  local bundle_dir="$ARTIFACT_DIR/state-bundle"
  local exporter_aid
  mkdir -p "$bundle_dir"

  exporter_aid=$(kli aid --name "$exporter_name" --alias "$exporter_alias" --base "${BASE_PREFIX}-$exporter_name")
  require_aid "exporter group AID" "$exporter_aid"

  step "EXPORT PRIOR MATERIALS"
  log "Exporting full pre-existing state from $exporter_name (alias=$exporter_alias) ..."

  (cd "$bundle_dir" && \
    kli vc export -n "$exporter_name" -a "$exporter_alias" \
      --all-registries --all-credentials --include-revoked --full --files \
      --base "${BASE_PREFIX}-$exporter_name") || true

  (cd "$bundle_dir" && \
    kli export -n "$exporter_name" -a "$exporter_alias" --ends --files \
      --base "${BASE_PREFIX}-$exporter_name") || true

  kli ends export -n "$exporter_name" --aid "$exporter_aid" \
    --base "${BASE_PREFIX}-$exporter_name" > "$bundle_dir/ends-group.cesr" 2>/dev/null || true

  log "Exported Files in $bundle_dir"
  ls -lt "$bundle_dir"
}

ingest_materials() {
  local ingester_name="$1"
  local ingester_alias="$2"

  local bundle_dir="$ARTIFACT_DIR/state-bundle"

  log "ingesting bundle into $ingester_name (targeting group alias=$ingester_alias) ..."
  require_value "R1_REGK" "$R1_REGK"
  kli import -n "$ingester_name" --base "${BASE_PREFIX}-$ingester_name" \
    --cesr-in "$bundle_dir"

  kli vc registry rename -n "$ingester_name" --base "${BASE_PREFIX}-$ingester_name" \
    --registry-name "$R1_REGK" --new-name r1

  sleep 0.5
  kli vc registry list --name "$ingester_name" --base "${BASE_PREFIX}-$ingester_name" >/dev/null 2>&1 || true
}

apply_export_ingest_sync() {
  local exporter_name="$1"
  local exporter_alias="$2"
  local ingester_name="$3"
  local ingester_alias="$4"

  export_prior_materials $exporter_name $exporter_alias
  ingest_materials $ingester_name $ingester_alias
}

post_ingest_checks() {
  require_default_mode "post_ingest_checks"
  step "POST-INGEST CHECKS (should now succeed)"

  local reg_list_after
  local vc_list_after
  local ingested_cred_said
  local success=0

  echo ""
  echo "=== REGISTRY LIST FROM NEW MEMBER (m3) AFTER INGEST ==="
  reg_list_after=$(kli vc registry list --name m3 --base "${BASE_PREFIX}-m3" 2>&1 || true)
  echo "$reg_list_after"

  echo ""
  echo "=== VC LIST FROM NEW MEMBER (m3) AFTER INGEST ==="
  vc_list_after=$(kli vc list --name m3 --alias g --issued --base "${BASE_PREFIX}-m3" 2>&1 || true)
  echo "$vc_list_after"

  ingested_cred_said=$(issued_credential_said_for m3 g)
  require_value "ingested credential SAID" "$ingested_cred_said"

  if echo "$reg_list_after" | grep -qi "r1"; then
    if [[ "$ingested_cred_said" == "$CRED_SAID" ]] && echo "$vc_list_after" | grep -qi "Status: Issued"; then
      success=1
    fi
  fi

  echo ""
  if [[ $success -eq 1 ]]; then
    echo "=== EXPORT/INGEST SYNC SUCCESS: new member (m3) now sees pre-existing registry + ACDC state for group g ==="
  else
    echo "=== EXPORT/INGEST SYNC NOT YET COMPLETE (visibility still limited after ingest). Check logs and bundle. ==="
    echo "Artifacts: $ARTIFACT_DIR"
    return 1
  fi
}

revoke_from_late_joiner() {
  require_default_mode "revoke_from_late_joiner"
  step "REVOKE PRIOR CREDENTIAL WITH LATE JOINER AS LEAD (m3)"

  local pids=()
  local rc=0
  local lead_name
  local revoked_at
  local vc_list_after_revocation

  require_value "CRED_SAID" "$CRED_SAID"

  revoked_at=$(date -Iseconds -u)
  log "m3 leads revocation for credential: $CRED_SAID"

  clear_notifications m1
  clear_notifications m2

  kli multisig join --name m1 --group g --auto --base "${BASE_PREFIX}-m1" &
  pids+=("$!")
  kli multisig join --name m2 --group g --auto --base "${BASE_PREFIX}-m2" &
  pids+=("$!")

  sleep 1

  kli vc revoke --name m3 --alias g --registry-name r1 --said "$CRED_SAID" \
    --time "$revoked_at" --base "${BASE_PREFIX}-m3" &
  pids+=("$!")

  wait_all "${pids[@]}" || rc=$?
  if [[ $rc -ne 0 ]]; then
    return "$rc"
  fi

  echo ""
  echo "=== VC LIST FROM NEW MEMBER (m3) AFTER REVOCATION ==="
  vc_list_after_revocation=$(kli vc list --name m3 --alias g --issued --base "${BASE_PREFIX}-m3" 2>&1)
  echo "$vc_list_after_revocation"

  if echo "$vc_list_after_revocation" | grep -q "$CRED_SAID" && \
     echo "$vc_list_after_revocation" | grep -qi "Status: Revoked"; then
    echo ""
    echo "=== REVOCATION SUCCESS: m3 led the multisig revocation and now sees the ACDC as revoked ==="
  else
    echo ""
    echo "=== REVOCATION NOT COMPLETE: m3 does not show the credential as revoked ==="
    echo "Artifacts: $ARTIFACT_DIR"
    return 1
  fi
}

### Stress-chain member helpers

member_name() {
  case "$1" in
    A|a) echo "a" ;;
    B|b) echo "b" ;;
    C|c) echo "c" ;;
    D|d) echo "d" ;;
    E|e) echo "e" ;;
    F|f) echo "f" ;;
    *) echo "ERROR: unknown stress member label '$1'" >&2; return 1 ;;
  esac
}

member_salt() {
  case "$1" in
    A|a) echo "$A_SALT" ;;
    B|b) echo "$B_SALT" ;;
    C|c) echo "$C_SALT" ;;
    D|d) echo "$D_SALT" ;;
    E|e) echo "$E_SALT" ;;
    F|f) echo "$F_SALT" ;;
    *) echo "ERROR: unknown stress member label '$1'" >&2; return 1 ;;
  esac
}

member_aid() {
  case "$1" in
    A|a) echo "$A_AID" ;;
    B|b) echo "$B_AID" ;;
    C|c) echo "$C_AID" ;;
    D|d) echo "$D_AID" ;;
    E|e) echo "$E_AID" ;;
    F|f) echo "$F_AID" ;;
    *) echo "ERROR: unknown stress member label '$1'" >&2; return 1 ;;
  esac
}

set_member_aid() {
  local label="$1"
  local aid="$2"

  case "$label" in
    A|a) A_AID="$aid" ;;
    B|b) B_AID="$aid" ;;
    C|c) C_AID="$aid" ;;
    D|d) D_AID="$aid" ;;
    E|e) E_AID="$aid" ;;
    F|f) F_AID="$aid" ;;
    *) echo "ERROR: unknown stress member label '$label'" >&2; return 1 ;;
  esac
}

member_base() {
  local name
  name=$(member_name "$1")
  echo "${BASE_PREFIX}-${name}"
}

registry_key_for_name() {
  case "$1" in
    r1) echo "$R1_REGK" ;;
    r2) echo "$R2_REGK" ;;
    r3) echo "$R3_REGK" ;;
    r4) echo "$R4_REGK" ;;
    *) echo "ERROR: unknown registry name '$1'" >&2; return 1 ;;
  esac
}

init_member() {
  local label="$1"
  local salt="$2"
  local name
  local aid

  name=$(member_name "$label")
  init_controller "$name" "$salt"

  aid=$(aid_for "$name" "$name")
  require_aid "${label}_AID" "$aid"
  set_member_aid "$label" "$aid"
  log "$label ($name) AID: $aid"
}

aid_for_member() {
  local label="$1"
  local name

  name=$(member_name "$label")
  aid_for "$name" "$name"
}

write_group_config_for() {
  local file="$1"
  local weights_json="$2"
  shift 2

  local aids=()
  local label
  local aids_json

  for label in "$@"; do
    aids+=("$(member_aid "$label")")
  done

  aids_json=$(printf '%s\n' "${aids[@]}" | jq -R . | jq -s .)

  jq -n \
    --argjson aids "$aids_json" \
    --argjson weights "$weights_json" \
    --arg wit1 "$WIT1" \
    --arg wit2 "$WIT2" \
    --arg wit3 "$WIT3" \
    "$(cat <<'JQ'
{
  aids: $aids,
  transferable: true,
  wits: [$wit1, $wit2, $wit3],
  toad: 3,
  isith: $weights,
  nsith: $weights
}
JQ
)" > "$file"
}

resolve_all_stress_oobis() {
  step "STRESS OOBI EXCHANGE"

  local resolver
  local resolver_name
  local target
  local target_name

  for resolver in A B C D E F; do
    resolve_member_oobis "$resolver" A B C D E F
    resolver_name=$(member_name "$resolver")
    resolve_oobi "$resolver_name" recp "$RECP_AID"
  done

  for resolver in A B C D E F; do
    resolver_name=$(member_name "$resolver")
    for target in A B C D E F; do
      if [[ "$resolver" == "$target" ]]; then
        continue
      fi
      target_name=$(member_name "$target")
      query_aid_expect_seq "$resolver_name" "$resolver_name" "$(member_aid "$target")" 0
    done
  done
}

resolve_stress_schema_oobis() {
  step "STRESS SCHEMA OOBIS"

  local label
  local name

  for label in A B C D E F; do
    name=$(member_name "$label")
    kli oobi resolve --name "$name" --oobi-alias vc --oobi "$QVI_SCHEMA_OOBI" --base "${BASE_PREFIX}-${name}"
  done
  kli oobi resolve --name recp --oobi-alias vc --oobi "$QVI_SCHEMA_OOBI" --base "${BASE_PREFIX}-recp"
}

assert_group_sn() {
  local expected_sn="$1"
  shift

  local label
  local name

  for label in "$@"; do
    name=$(member_name "$label")
    query_aid_expect_seq "$name" "$name" "$G_AID" "$expected_sn"
  done

  GROUP_SN="$expected_sn"
  log "Group sequence asserted at $GROUP_SN for observers: $*"
}

prepare_member_rotations_for_group_rotation() {
  local joiner="$1"
  shift

  local signer
  local signer_name
  local observer
  local observer_name
  local joiner_name

  joiner_name=$(member_name "$joiner")

  # Group rotations that add a new weighted member can fail if current member
  # AID rotations are not known to the other signers and to the joiner. Rotate
  # the overlapping signer AIDs first, then query them from every participant
  # that must validate the group rotation.
  for signer in "$@"; do
    signer_name=$(member_name "$signer")
    log "Rotating current member AID $signer before group rotation."
    kli rotate --name "$signer_name" --alias "$signer_name" --base "$(member_base "$signer")"

    for observer in "$@"; do
      if [[ "$observer" == "$signer" ]]; then
        continue
      fi

      observer_name=$(member_name "$observer")
      kli query --name "$observer_name" --alias "$observer_name" \
        --prefix "$(member_aid "$signer")" --base "$(member_base "$observer")"
    done

    if [[ "$joiner" != "$signer" ]]; then
      resolve_oobi "$joiner_name" "$signer_name" "$(member_aid "$signer")"
      kli query --name "$joiner_name" --alias "$joiner_name" \
        --prefix "$(member_aid "$signer")" --base "$(member_base "$joiner")"
    fi
  done
}

run_joiners_except() {
  local lead="$1"
  shift

  local label
  local name

  JOIN_PIDS=()
  for label in "$@"; do
    if [[ "$label" == "$lead" ]]; then
      continue
    fi

    name=$(member_name "$label")
    clear_notifications "$name"
    kli multisig join --name "$name" --group g --auto --base "${BASE_PREFIX}-${name}" &
    JOIN_PIDS+=("$!")
  done
}

run_registry_joiners_except() {
  local lead="$1"
  local registry_name="$2"
  shift 2

  local label
  local name
  local join_log

  JOIN_PIDS=()
  for label in "$@"; do
    if [[ "$label" == "$lead" ]]; then
      continue
    fi

    name=$(member_name "$label")
    join_log="$ARTIFACT_DIR/${registry_name}-${name}-registry-join.log"
    kli multisig join --name "$name" --group g --auto --registry-name "$registry_name" \
      --base "${BASE_PREFIX}-${name}" > "$join_log" 2>&1 &
    JOIN_PIDS+=("$!")
  done
}

wait_processes_with_logs() {
  local label="$1"
  local log_pattern="$2"
  shift 2
  local pids=("$@")
  local deadline=$((SECONDS + 120))
  local pid
  local running
  local log_file

  # Multisig registry, issue, and revoke commands can otherwise hang silently.
  # Keep logs per participant and dump them on timeout so the failed EXN/TEL/KEL
  # phase is visible in the artifact directory.
  while true; do
    running=0
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        running=1
        break
      fi
    done

    if [[ $running -eq 0 ]]; then
      wait_all "${pids[@]}"
      return "$?"
    fi

    if [[ $SECONDS -ge $deadline ]]; then
      echo "ERROR: timed out waiting for $label."
      for log_file in $log_pattern; do
        [[ -f "$log_file" ]] || continue
        echo ""
        echo "=== $(basename "$log_file") ==="
        cat "$log_file"
      done

      for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
      done
      wait_all "${pids[@]}" || true
      return 124
    fi

    sleep 1
  done
}

wait_registry_processes() {
  local registry_name="$1"
  shift

  wait_processes_with_logs "registry inception $registry_name" \
    "$ARTIFACT_DIR/$registry_name-*-registry-*.log" "$@"
}

### Stress-chain scenario operations

create_stress_group() {
  step "STRESS GROUP INCEPT (A + B)"

  local pids=()

  write_group_config_for "$GROUP_CONFIG" '["1/2","1/2"]' A B
  jq -e . "$GROUP_CONFIG" >/dev/null
  log "Generated stress group config: $GROUP_CONFIG"

  kli multisig incept --name a --alias a --group g --file "$GROUP_CONFIG" --base "${BASE_PREFIX}-a" &
  pids+=("$!")
  kli multisig incept --name b --alias b --group g --file "$GROUP_CONFIG" --base "${BASE_PREFIX}-b" &
  pids+=("$!")

  wait_all "${pids[@]}"

  G_AID=$(aid_for a g)
  require_aid "G_AID" "$G_AID"
  log "Stress group AID: $G_AID"
  assert_group_sn 0 A B
}

rotate_group_members() {
  local expected_sn="$1"
  shift

  local current_members=()
  local new_members=()
  local label
  local overlap=()
  local joiner="${1:-}"
  local rc=0
  local pids=()
  local weights_json='["1/2","1/2","1/2"]'

  while [[ $# -gt 0 && "$1" != "--" ]]; do
    current_members+=("$1")
    shift
  done
  shift
  while [[ $# -gt 0 ]]; do
    new_members+=("$1")
    shift
  done

  joiner="${new_members[0]}"
  step "STRESS ROTATE GROUP TO MEMBERS: ${new_members[*]}"

  for label in "${current_members[@]}"; do
    local new_label
    for new_label in "${new_members[@]}"; do
      if [[ "$label" == "$new_label" ]]; then
        overlap+=("$label")
        break
      fi
    done
  done

  if [[ ${#overlap[@]} -lt 2 ]]; then
    echo "ERROR: need at least two overlapping current members to rotate; got ${overlap[*]}"
    return 1
  fi

  prepare_member_rotations_for_group_rotation "$joiner" "${overlap[@]:0:2}"

  for label in "${overlap[@]:0:2}"; do
    local name
    local cmd
    name=$(member_name "$label")
    cmd=(kli multisig rotate --name "$name" --alias g)
    for new_label in "${new_members[@]}"; do
      cmd+=(--smids "$(member_aid "$new_label")")
    done
    cmd+=(--isith "$weights_json" --nsith "$weights_json")
    for new_label in "${new_members[@]}"; do
      cmd+=(--rmids "$(member_aid "$new_label")")
    done
    cmd+=(--base "${BASE_PREFIX}-${name}")
    "${cmd[@]}" &
    pids+=("$!")
  done

  clear_notifications "$(member_name "$joiner")"
  log "$joiner resolves OOBI for group g and joins."
  kli oobi resolve --name "$(member_name "$joiner")" --oobi-alias g \
    --oobi "$WIT1_URL/oobi/$G_AID/witness/$WIT1" \
    --base "$(member_base "$joiner")" || rc=$?

  if [[ $rc -eq 0 ]]; then
    kli multisig join --name "$(member_name "$joiner")" --group g --auto --base "$(member_base "$joiner")" || rc=$?
  fi

  wait_all "${pids[@]}" || rc=$?
  if [[ $rc -ne 0 ]]; then
    return "$rc"
  fi

  assert_group_sn "$expected_sn" "${new_members[@]}"
}

create_registry() {
  local lead="$1"
  local registry_name="$2"
  local nonce="$3"
  local out_regk_var="$4"
  local expected_sn="$5"
  shift 5

  local lead_name
  local pids=()
  local regk

  lead_name=$(member_name "$lead")
  step "STRESS REGISTRY INCEPT $registry_name (lead $lead)"

  local label
  local name
  local log_file
  for label in "$@"; do
    name=$(member_name "$label")
    clear_notifications "$name"
    log_file="$ARTIFACT_DIR/${registry_name}-${name}-registry-incept.log"

    kli vc registry incept --name "$name" --alias g --registry-name "$registry_name" \
      --usage "Stress-chain registry $registry_name" --nonce "$nonce" \
      --base "${BASE_PREFIX}-${name}" > "$log_file" 2>&1 &
    pids+=("$!")
  done

  wait_registry_processes "$registry_name" "${pids[@]}"

  regk=$(registry_said_for "$lead_name" "$registry_name")
  require_value "${out_regk_var}" "$regk"
  printf -v "$out_regk_var" '%s' "$regk"
  log "Registry $registry_name SAID: $regk"
  assert_group_sn "$expected_sn" "$@"
}

issue_stress_credential() {
  local lead="$1"
  local registry_name="$2"
  local out_vc_var="$3"
  local expected_sn="$4"
  shift 4

  local issued_at
  local lead_log
  local pids=()
  local label
  local name
  local log_file
  local said

  lead_name=$(member_name "$lead")
  issued_at=$(date -Iseconds -u)
  lead_log="$ARTIFACT_DIR/${out_vc_var}-${lead_name}-create.log"
  step "STRESS ISSUE $out_vc_var on $registry_name (lead $lead)"

  for label in "$@"; do
    name=$(member_name "$label")
    clear_notifications "$name"
    log_file="$ARTIFACT_DIR/${out_vc_var}-${name}-create.log"

    kli vc create --name "$name" --alias g --registry-name "$registry_name" \
      --schema "$QVI_SCHEMA_SAID" \
      --recipient "$RECP_AID" \
      --data @"$CRED_DATA" \
      --time "$issued_at" --base "${BASE_PREFIX}-${name}" > "$log_file" 2>&1 &
    pids+=("$!")
  done

  wait_processes_with_logs "credential issue $out_vc_var" \
    "$ARTIFACT_DIR/${out_vc_var}-*-create.log" "${pids[@]}"
  cat "$lead_log"

  said=$(awk '/has been created[.]$/ {print $1; exit}' "$lead_log")
  require_value "$out_vc_var" "$said"
  printf -v "$out_vc_var" '%s' "$said"
  log "$out_vc_var SAID: $said"
  assert_group_sn "$expected_sn" "$@"
}

revoke_credential() {
  local lead="$1"
  local registry_name="$2"
  local vc_said="$3"
  local expected_sn="$4"
  shift 4

  local revoked_at
  local pids=()
  local label
  local name
  local log_file

  lead_name=$(member_name "$lead")
  revoked_at=$(date -Iseconds -u)
  step "STRESS REVOKE $vc_said from $registry_name (lead $lead)"

  for label in "$@"; do
    name=$(member_name "$label")
    clear_notifications "$name"
    log_file="$ARTIFACT_DIR/${vc_said}-${name}-revoke.log"

    kli vc revoke --name "$name" --alias g --registry-name "$registry_name" --said "$vc_said" \
      --time "$revoked_at" --base "${BASE_PREFIX}-${name}" > "$log_file" 2>&1 &
    pids+=("$!")
  done

  wait_processes_with_logs "credential revocation $vc_said" \
    "$ARTIFACT_DIR/$vc_said-*-revoke.log" "${pids[@]}"
  assert_group_sn "$expected_sn" "$@"
  assert_credential_status "$lead" "$vc_said" Revoked
}

export_stress_materials() {
  local exporter="$1"
  local include_revoked="$2"
  local bundle_dir="$3"
  local exporter_name
  local exporter_aid
  local include_args=()

  exporter_name=$(member_name "$exporter")
  exporter_aid=$(kli aid --name "$exporter_name" --alias g --base "${BASE_PREFIX}-${exporter_name}")
  require_aid "exporter group AID" "$exporter_aid"

  rm -rf "$bundle_dir"
  mkdir -p "$bundle_dir"

  if [[ "$include_revoked" -eq 1 ]]; then
    include_args+=(--include-revoked)
  fi

  log "Exporting stress bundle from $exporter_name to $bundle_dir (include_revoked=$include_revoked)"
  (cd "$bundle_dir" && \
    kli vc export -n "$exporter_name" -a g \
      --all-registries --all-credentials "${include_args[@]}" --full --files \
      --base "${BASE_PREFIX}-${exporter_name}")

  (cd "$bundle_dir" && \
    kli export -n "$exporter_name" -a g --ends --files \
      --base "${BASE_PREFIX}-${exporter_name}") || true

  kli ends export -n "$exporter_name" --aid "$exporter_aid" \
    --base "${BASE_PREFIX}-${exporter_name}" > "$bundle_dir/ends-group.cesr" 2>/dev/null || true

  ls -lt "$bundle_dir"
}

sync_materials() {
  local exporter="$1"
  local ingester="$2"
  local include_revoked="$3"
  shift 3

  local exporter_name
  local ingester_name
  local bundle_dir
  local registry_name
  local regk

  exporter_name=$(member_name "$exporter")
  ingester_name=$(member_name "$ingester")
  bundle_dir="$ARTIFACT_DIR/state-bundles/${exporter_name}-to-${ingester_name}"

  # include_revoked=0 exports active credentials only; registry TEL history still
  # travels through --all-registries so the joiner can operate on the registry.
  # This is the stress-chain default because each hop should see current issued
  # material, not every prior revoked credential.
  step "STRESS SYNC $exporter TO $ingester"
  export_stress_materials "$exporter" "$include_revoked" "$bundle_dir"

  log "Ingesting stress bundle into $ingester_name."
  kli import -n "$ingester_name" --base "${BASE_PREFIX}-${ingester_name}" \
    --cesr-in "$bundle_dir"

  for registry_name in "$@"; do
    regk=$(registry_key_for_name "$registry_name")
    require_value "$registry_name registry key" "$regk"
    kli vc registry rename -n "$ingester_name" --base "${BASE_PREFIX}-${ingester_name}" \
      --registry-name "$regk" --new-name "$registry_name"
  done

  sleep 0.5
  kli vc registry list --name "$ingester_name" --base "${BASE_PREFIX}-${ingester_name}"
}

assert_registry_visible() {
  local member="$1"
  local registry_name="$2"
  local regk="$3"
  local name
  local output

  name=$(member_name "$member")
  output=$(kli vc registry list --name "$name" --base "${BASE_PREFIX}-${name}" 2>&1 || true)
  echo "$output"

  if ! echo "$output" | grep -q "$regk"; then
    echo "ERROR: expected $member to see $registry_name ($regk)."
    return 1
  fi
}

assert_registry_missing() {
  local member="$1"
  local registry_name="$2"
  local regk="$3"
  local name
  local output

  name=$(member_name "$member")
  output=$(kli vc registry list --name "$name" --base "${BASE_PREFIX}-${name}" 2>&1 || true)
  echo "$output"

  if echo "$output" | grep -q "$regk"; then
    echo "ERROR: expected $member not to see $registry_name ($regk)."
    return 1
  fi
}

assert_credential_status() {
  local member="$1"
  local vc_said="$2"
  local expected_status="$3"
  local name
  local output

  name=$(member_name "$member")
  output=$(kli vc list --name "$name" --alias g --issued --base "${BASE_PREFIX}-${name}" 2>&1 || true)
  echo "$output"

  if ! echo "$output" | awk -v said="$vc_said" -v status="Status: $expected_status" '
    index($0, "Credential #") && index($0, said) { found = 1; next }
    found && index($0, status) { ok = 1; exit }
    index($0, "Credential #") { found = 0 }
    END { exit(ok ? 0 : 1) }
  '; then
    echo "ERROR: expected $member to see credential $vc_said with status $expected_status."
    return 1
  fi
}

assert_credential_missing() {
  local member="$1"
  local vc_said="$2"
  local name
  local output

  name=$(member_name "$member")
  output=$(kli vc list --name "$name" --alias g --issued --said --base "${BASE_PREFIX}-${name}" 2>&1 || true)
  echo "$output"

  if echo "$output" | grep -q "$vc_said"; then
    echo "ERROR: expected $member not to see credential $vc_said."
    return 1
  fi
}

assert_final_stress_membership() {
  step "STRESS FINAL MEMBERSHIP ASSERTION"

  assert_group_sn 17 D E F
  assert_credential_status F "$VC5_SAID" Issued
  log "Final operational signing set is D/E/F; A/B/C have been removed by rotations through sequence 17."
}

init_stress_controllers() {
  step "STRESS INIT CONTROLLERS (A-F + recp)"

  local label

  for label in A B C D E F; do
    init_member "$label" "$(member_salt "$label")"
  done

  init_controller recp "$RECP_SALT"
  RECP_AID=$(aid_for recp recp)
  require_aid "RECP_AID" "$RECP_AID"
  log "recp AID: $RECP_AID"
}

# Expected group sequence schedule:
#   0      A/B group inception
#   1-2    R1, VC1
#   3      add C
#   4-5    revoke VC1, issue VC2
#   6      add D, remove A
#   7-9    R2, VC3, revoke VC2
#   10     add E, remove B
#   11-13  R3, VC4, revoke VC3
#   14     add F, remove C
#   15-17  R4, VC5, revoke VC4
run_stress_chain() {
  step "A-F MULTISIG LATE-JOIN STRESS CHAIN"

  init_stress_controllers
  resolve_all_stress_oobis
  resolve_stress_schema_oobis

  create_stress_group

  create_registry A r1 "$R1_NONCE" R1_REGK 1 A B
  issue_stress_credential A r1 VC1_SAID 2 A B

  rotate_group_members 3 A B -- C B A
  assert_registry_missing C r1 "$R1_REGK"
  assert_credential_missing C "$VC1_SAID"

  sync_materials A C 0 r1
  assert_registry_visible C r1 "$R1_REGK"
  assert_credential_status C "$VC1_SAID" Issued

  revoke_credential C r1 "$VC1_SAID" 4 C B A
  issue_stress_credential C r1 VC2_SAID 5 C B A

  rotate_group_members 6 A B C -- D C B
  assert_registry_missing D r1 "$R1_REGK"
  assert_credential_missing D "$VC2_SAID"

  sync_materials C D 0 r1
  assert_registry_visible D r1 "$R1_REGK"
  assert_credential_status D "$VC2_SAID" Issued
  assert_credential_missing D "$VC1_SAID"

  create_registry D r2 "$R2_NONCE" R2_REGK 7 D C B
  issue_stress_credential D r2 VC3_SAID 8 D C B
  revoke_credential D r1 "$VC2_SAID" 9 D C B

  rotate_group_members 10 B C D -- E D C
  assert_registry_missing E r2 "$R2_REGK"
  assert_credential_missing E "$VC3_SAID"

  sync_materials D E 0 r1 r2
  assert_registry_visible E r1 "$R1_REGK"
  assert_registry_visible E r2 "$R2_REGK"
  assert_credential_status E "$VC3_SAID" Issued
  assert_credential_missing E "$VC1_SAID"
  assert_credential_missing E "$VC2_SAID"

  create_registry E r3 "$R3_NONCE" R3_REGK 11 E D C
  issue_stress_credential E r3 VC4_SAID 12 E D C
  revoke_credential E r2 "$VC3_SAID" 13 E D C

  rotate_group_members 14 C D E -- F E D
  assert_registry_missing F r3 "$R3_REGK"
  assert_credential_missing F "$VC4_SAID"

  sync_materials E F 0 r1 r2 r3
  assert_registry_visible F r1 "$R1_REGK"
  assert_registry_visible F r2 "$R2_REGK"
  assert_registry_visible F r3 "$R3_REGK"
  assert_credential_status F "$VC4_SAID" Issued
  assert_credential_missing F "$VC1_SAID"
  assert_credential_missing F "$VC2_SAID"
  assert_credential_missing F "$VC3_SAID"

  create_registry F r4 "$R4_NONCE" R4_REGK 15 F E D
  issue_stress_credential F r4 VC5_SAID 16 F E D
  revoke_credential F r3 "$VC4_SAID" 17 F E D

  assert_final_stress_membership
}

### Entrypoints

wait_for_wits_and_vlei() {
  step "WITNESSES AND vLEI-SERVER"
  log "You should have 'kli witness demo' and 'vLEI-server -s ...' each running in another terminal."
  if [[ "${AUTO:-0}" == "1" || "${CI:-0}" == "1" || -n "${NONINTERACTIVE:-}" ]]; then
    log "AUTO mode: proceeding without prompt."
    sleep 3
  else
    log "Press enter when ready, or the OOBI resolves below will fail."
    if ! read -r -p "Ready? [enter] " _; then
      log "No stdin available for readiness prompt; proceeding."
    fi
  fi
}

run_default_scenario() {
  require_default_mode "run_default_scenario"

  init_controllers
  resolve_member_oobis
  resolve_schema_oobis
  create_group
  incept_registry
  issue_credential
  late_join_m3
  pre_ingest_checks
  apply_export_ingest_sync m1 g m3 g
  post_ingest_checks
  revoke_from_late_joiner
}

main() {
  parse_args "$@"
  require_cmd kli
  require_cmd jq
  if [[ $STRESS_CHAIN -eq 1 ]]; then
    # Stress mode uses fresh salts/nonces to avoid witness-state collisions
    # across repeated long runs. The default path stays deterministic.
    randomize_stress_material
  fi
  setup_workdirs
  trap cleanup EXIT

  wait_for_wits_and_vlei
  write_generated_configs

  if [[ $STRESS_CHAIN -eq 1 ]]; then
    run_stress_chain
    echo ""
    echo "=== STRESS CHAIN SCRIPT COMPLETE ==="
  else
    run_default_scenario
    echo ""
    echo "=== SCRIPT COMPLETE ==="
  fi
}

main "$@"
