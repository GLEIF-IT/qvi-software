#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yaml"
KEEP_ARTIFACTS=false
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-180}"

KEYSTORE_DIR="${SCRIPT_DIR}/docker-keystores"
EVENTS_DIR="${SCRIPT_DIR}/events"
QVI_DATA_DIR="${SCRIPT_DIR}/qvi-data"

export KERI_IMAGE="${KERI_IMAGE:-weboftrust/keri}"
export KERI_IMAGE_TAG="${KERI_IMAGE_TAG:-1.2.13}"
export KERIA_IMAGE="${KERIA_IMAGE:-weboftrust/keria}"
export KERIA_IMAGE_TAG="${KERIA_IMAGE_TAG:-0.4.0}"

WAN_PRE="BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha"
WAN_CONTROLLER_OOBI="http://witness-demo:5642/oobi/${WAN_PRE}/controller?name=Wan&tag=witness"
GEDA_NAME="geda"

GAR1="accolon"
GAR1_SALT="0AA2-S2YS4KqvlSzO7faIEpH"
GAR1_PASSCODE="18b2c88fd050851c45c67"

GAR2="bedivere"
GAR2_SALT="0ADD292rR7WEU4GPpaYK4Z6h"
GAR2_PASSCODE="b26ef3dd5c85f67c51be8"

GEDA_PRE=""
GEDA_OOBI=""

usage() {
  cat <<USAGE
Usage: ./version-compat.sh [--keep-artifacts]

Runs SignifyPy and SignifyTS 2-of-3 delegation regressions from clean state.
Overrides: KERI_IMAGE, KERI_IMAGE_TAG, KERIA_IMAGE, KERIA_IMAGE_TAG,
           WAIT_TIMEOUT_SECONDS
USAGE
}

case "${1:-}" in
  "") ;;
  --keep-artifacts) KEEP_ARTIFACTS=true ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 1; }

log() {
  echo "[$(date -u +%H:%M:%S)] $*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

compose() {
  docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" "$@"
}

remove_helper_containers() {
  docker rm -f gar1-geda gar1-confirm gar2-confirm >/dev/null 2>&1 || true
}

clean_runtime_dirs() {
  local dir
  for dir in "${KEYSTORE_DIR}" "${EVENTS_DIR}" "${QVI_DATA_DIR}"; do
    mkdir -p "${dir}"
    find "${dir}" -mindepth 1 ! -name '.gitkeep' -exec rm -rf -- {} + >/dev/null 2>&1 || true
  done
}

cleanup() {
  remove_helper_containers
  if ${KEEP_ARTIFACTS}; then
    log "Keeping compose stack and artifacts (--keep-artifacts set)."
    return
  fi
  compose down -v >/dev/null 2>&1 || true
  clean_runtime_dirs
}
trap cleanup EXIT

validate_host_tools() {
  local command
  for command in docker jq timeout; do
    command -v "${command}" >/dev/null 2>&1 || fail "${command} is required"
  done
  docker info >/dev/null 2>&1 || fail "Docker is not running"
  docker compose version >/dev/null 2>&1 || fail "docker compose is required"
}

kli() {
  compose run --rm -T kli "$@"
}

kli_detached() {
  local cname=$1
  shift
  compose run -d --name "${cname}" kli "$@" >/dev/null
}

wait_container() {
  local cname=$1
  local exit_code

  exit_code=$(timeout "${WAIT_TIMEOUT_SECONDS}s" docker wait "${cname}" 2>/dev/null || echo 124)
  if [[ "${exit_code}" != "0" ]]; then
    echo "----- logs: ${cname} -----" >&2
    docker logs "${cname}" >&2 || true
    docker rm -f "${cname}" >/dev/null 2>&1 || true
    fail "container ${cname} failed or timed out with exit code ${exit_code}"
  fi
  docker rm -f "${cname}" >/dev/null 2>&1 || true
}

validate_versions() {
  local kli_version
  local keria_keri_version

  kli_version=$(kli version | awk -F': ' '/Library version:/ {print $2; exit}')
  [[ "${kli_version}" == 1.2.* ]] \
    || fail "KLI image must run KERIpy 1.2.x, got ${kli_version:-unknown}"
  log "KLI image ${KERI_IMAGE}:${KERI_IMAGE_TAG} reports KERIpy ${kli_version}"

  keria_keri_version=$(compose exec -T keria sh -c \
    'python -c "import keri; print(keri.__version__)" 2>/dev/null || python3 -c "import keri; print(keri.__version__)"')
  [[ "${keria_keri_version}" == 1.2.* ]] \
    || fail "KERIA image must import KERI 1.2.x, got ${keria_keri_version:-unknown}"
  log "KERIA image ${KERIA_IMAGE}:${KERIA_IMAGE_TAG} imports KERI ${keria_keri_version}"
}

aid_prefix() {
  local name=$1
  local alias=$2
  local passcode=$3
  kli aid --name "${name}" --alias "${alias}" --passcode "${passcode}" | tr -d '[:space:]'
}

create_aid() {
  local name=$1
  local salt=$2
  local passcode=$3
  local pre

  log "Creating KLI member AID ${name}"
  kli init --name "${name}" --salt "${salt}" --passcode "${passcode}" \
    --config-dir /config --config-file habery-config-docker.json
  kli oobi resolve --name "${name}" --oobi-alias wan --passcode "${passcode}" \
    --oobi "${WAN_CONTROLLER_OOBI}"
  kli incept --name "${name}" --alias "${name}" --passcode "${passcode}" \
    --file /events/single-sig-incept-config.json
  pre=$(aid_prefix "${name}" "${name}" "${passcode}")
  [[ -n "${pre}" ]] || fail "failed to create AID ${name}"
  log "Created ${name}: ${pre}"
}

resolve_oobi() {
  local name=$1
  local passcode=$2
  local alias=$3
  local prefix=$4
  kli oobi resolve --name "${name}" --oobi-alias "${alias}" --passcode "${passcode}" \
    --oobi "http://witness-demo:5642/oobi/${prefix}/witness/${WAN_PRE}" >/dev/null
}

join_group_auto() {
  local name=$1
  local group=$2
  local passcode=$3
  local log_file="${EVENTS_DIR}/join-${name}-${group}.log"

  set +o pipefail
  yes Y | kli multisig join --name "${name}" --group "${group}" \
    --passcode "${passcode}" --auto >"${log_file}" 2>&1
  local rc=$?
  set -o pipefail
  if [[ ${rc} -ne 0 ]]; then
    cat "${log_file}" >&2 || true
    fail "multisig join failed for ${name}/${group}"
  fi
}

create_geda_multisig() {
  local gar1_pre
  local gar2_pre
  gar1_pre=$(aid_prefix "${GAR1}" "${GAR1}" "${GAR1_PASSCODE}")
  gar2_pre=$(aid_prefix "${GAR2}" "${GAR2}" "${GAR2_PASSCODE}")
  [[ -n "${gar1_pre}" && -n "${gar2_pre}" ]] || fail "GAR member prefixes are required"

  jq --arg gar1 "${gar1_pre}" --arg gar2 "${gar2_pre}" --arg wan "${WAN_PRE}" \
    '.aids = [$gar1, $gar2] | .wits = [$wan]' \
    "${SCRIPT_DIR}/config/template-multi-sig-incept-config.jq" \
    > "${EVENTS_DIR}/geda-incept-config.json"

  log "Creating 2-of-2 KLI GEDA delegator"
  kli_detached gar1-geda multisig incept --name "${GAR1}" --alias "${GAR1}" \
    --passcode "${GAR1_PASSCODE}" --group "${GEDA_NAME}" --file /events/geda-incept-config.json
  sleep 2
  if [[ "$(docker inspect --format '{{.State.Status}}' gar1-geda 2>/dev/null || echo missing)" != "running" ]]; then
    docker logs gar1-geda >&2 || true
    fail "GEDA proposer exited before GAR2 joined"
  fi
  join_group_auto "${GAR2}" "${GEDA_NAME}" "${GAR2_PASSCODE}"
  wait_container gar1-geda

  GEDA_PRE=$(aid_prefix "${GAR1}" "${GEDA_NAME}" "${GAR1_PASSCODE}")
  [[ -n "${GEDA_PRE}" ]] || fail "unable to determine GEDA prefix"
  GEDA_OOBI=$(kli oobi generate --name "${GAR1}" --passcode "${GAR1_PASSCODE}" \
    --alias "${GEDA_NAME}" --role witness | awk 'NF {print; exit}')
  [[ -n "${GEDA_OOBI}" ]] \
    || GEDA_OOBI="http://witness-demo:5642/oobi/${GEDA_PRE}/witness/${WAN_PRE}"
  log "Created GEDA ${GEDA_PRE}"
}

build_kli_delegator() {
  jq --arg wan "${WAN_PRE}" '.wits = [$wan]' \
    "${SCRIPT_DIR}/config/template-single-sig-incept-config.jq" \
    > "${EVENTS_DIR}/single-sig-incept-config.json"
  create_aid "${GAR1}" "${GAR1_SALT}" "${GAR1_PASSCODE}"
  create_aid "${GAR2}" "${GAR2_SALT}" "${GAR2_PASSCODE}"

  local gar1_pre
  local gar2_pre
  gar1_pre=$(aid_prefix "${GAR1}" "${GAR1}" "${GAR1_PASSCODE}")
  gar2_pre=$(aid_prefix "${GAR2}" "${GAR2}" "${GAR2_PASSCODE}")
  resolve_oobi "${GAR1}" "${GAR1_PASSCODE}" "${GAR2}" "${gar2_pre}"
  resolve_oobi "${GAR2}" "${GAR2_PASSCODE}" "${GAR1}" "${gar1_pre}"
  create_geda_multisig
}

approve_pending_delegation() {
  local label=$1
  log "Approving ${label} delegated inception from both GEDA members"
  kli_detached gar1-confirm delegate confirm --name "${GAR1}" --alias "${GEDA_NAME}" \
    --passcode "${GAR1_PASSCODE}" --interact --auto
  kli_detached gar2-confirm delegate confirm --name "${GAR2}" --alias "${GEDA_NAME}" \
    --passcode "${GAR2_PASSCODE}" --interact --auto
  wait_container gar1-confirm
  wait_container gar2-confirm
}

run_scenario() {
  local label=$1
  local service=$2
  log "Running ${label} delegate setup"
  compose run --rm -T -e GEDA_PRE="${GEDA_PRE}" -e GEDA_OOBI="${GEDA_OOBI}" "${service}" setup
  approve_pending_delegation "${label}"
  log "Running ${label} delegate completion"
  compose run --rm -T "${service}" complete
}

main() {
  validate_host_tools
  log "Clearing prior containers, volumes, and runtime artifacts"
  remove_helper_containers
  compose down -v >/dev/null 2>&1 || true
  clean_runtime_dirs
  log "Building runner images"
  compose build signifypy-runner signify-ts-runner
  log "Starting witness-demo and KERIA"
  compose up -d --wait witness-demo keria
  validate_versions
  build_kli_delegator
  run_scenario "SignifyPy" signifypy-runner
  run_scenario "SignifyTS" signify-ts-runner
  echo "PASS: multisig KLI delegator approved SignifyPy and SignifyTS 2-of-3 delegated inceptions"
}

main "$@"
