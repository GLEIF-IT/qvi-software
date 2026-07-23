#!/usr/bin/env bash
# version-compat.sh
# Checks that version 1.2.13 KERIpy works with version 0.4.0 KERIA that also uses KERIpy 1.2.13

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yaml"
NETWORK_NAME="${NETWORK_NAME:-qvi-keria-signify-delegation}"

KEEP_ARTIFACTS=false
CLEAR=false
DEBUG=false
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-180}"

KEYSTORE_DIR="${SCRIPT_DIR}/docker-keystores"
EVENTS_DIR="${SCRIPT_DIR}/events"
QVI_DATA_DIR="${SCRIPT_DIR}/qvi-data"

export KERI_IMAGE="${KERI_IMAGE:-weboftrust/keri}"
export KERI_IMAGE_TAG="${KERI_IMAGE_TAG:-1.2.13}"
export KERIA_IMAGE="${KERIA_IMAGE:-weboftrust/keria}"
export KERIA_IMAGE_TAG="${KERIA_IMAGE_TAG:-0.4.0}"
export NETWORK_NAME

KLI_IMAGE="${KERI_IMAGE}:${KERI_IMAGE_TAG}"

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
Usage: ./version-compat.sh [--clear] [--keep-artifacts] [--debug]

Runs two delegation regressions against the same KLI/KERIA stack:
- SignifyPy multisig delegate approved by KERIpy KLI multisig delegator
- SignifyTS multisig delegate approved by KERIpy KLI multisig delegator

Environment overrides:
  KERI_IMAGE, KERI_IMAGE_TAG
  KERIA_IMAGE, KERIA_IMAGE_TAG
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clear)
      CLEAR=true
      shift
      ;;
    --keep-artifacts)
      KEEP_ARTIFACTS=true
      shift
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

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

clean_runtime_dirs() {
  mkdir -p "${KEYSTORE_DIR}" "${EVENTS_DIR}" "${QVI_DATA_DIR}"
  find "${KEYSTORE_DIR}" -mindepth 1 ! -name '.gitkeep' -exec rm -rf {} + >/dev/null 2>&1 || true
  find "${EVENTS_DIR}" -mindepth 1 ! -name '.gitkeep' -exec rm -rf {} + >/dev/null 2>&1 || true
  find "${QVI_DATA_DIR}" -mindepth 1 ! -name '.gitkeep' -exec rm -rf {} + >/dev/null 2>&1 || true
}

cleanup() {
  docker rm -f \
    gar1-geda \
    gar1-confirm \
    gar2-confirm >/dev/null 2>&1 || true

  if ${KEEP_ARTIFACTS}; then
    log "Keeping compose stack and artifacts (--keep-artifacts set)."
    return
  fi

  compose down -v >/dev/null 2>&1 || true
  clean_runtime_dirs
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

validate_host_tools() {
  require_command docker
  require_command jq
  docker info >/dev/null 2>&1 || fail "Docker is not running"
  docker compose version >/dev/null 2>&1 || fail "docker compose is required"
}

validate_versions() {
  local kli_version
  local keria_keri_version

  kli_version=$(docker run --rm "${KLI_IMAGE}" version | awk -F': ' '/Library version:/ {print $2; exit}')
  [[ "${kli_version}" == 1.2.* ]] || fail "KLI container ${KLI_IMAGE} must run KERIpy 1.2.x, got ${kli_version:-unknown}"
  log "KLI image ${KLI_IMAGE} reports KERIpy ${kli_version}"

  keria_keri_version=$(compose exec -T keria sh -c \
    'python -c "import keri; print(keri.__version__)" 2>/dev/null || python3 -c "import keri; print(keri.__version__)"')
  [[ "${keria_keri_version}" == 1.2.* ]] || fail "KERIA image must import KERI 1.2.x, got ${keria_keri_version:-unknown}"
  log "KERIA image ${KERIA_IMAGE}:${KERIA_IMAGE_TAG} imports KERI ${keria_keri_version}"
}

kli() {
  docker run --rm -i \
    --network "${NETWORK_NAME}" \
    -v "${KEYSTORE_DIR}:/usr/local/var/keri" \
    -v "${SCRIPT_DIR}/config:/config:ro" \
    -v "${EVENTS_DIR}:/events" \
    -e PYTHONWARNINGS=ignore::SyntaxWarning \
    "${KLI_IMAGE}" "$@"
}

kli_detached() {
  local cname=$1
  shift
  docker rm -f "${cname}" >/dev/null 2>&1 || true
  docker run -d \
    --name "${cname}" \
    --network "${NETWORK_NAME}" \
    -v "${KEYSTORE_DIR}:/usr/local/var/keri" \
    -v "${SCRIPT_DIR}/config:/config:ro" \
    -v "${EVENTS_DIR}:/events" \
    -e PYTHONWARNINGS=ignore::SyntaxWarning \
    "${KLI_IMAGE}" "$@" >/dev/null
}

dump_container_logs() {
  local cname=$1
  echo "----- logs: ${cname} -----" >&2
  docker logs "${cname}" >&2 || true
}

wait_container() {
  local cname=$1
  local exit_code

  exit_code=$(timeout "${WAIT_TIMEOUT_SECONDS}s" docker wait "${cname}" 2>/dev/null || echo 124)
  if [[ "${exit_code}" != "0" ]]; then
    dump_container_logs "${cname}"
    docker rm -f "${cname}" >/dev/null 2>&1 || true
    fail "container ${cname} failed or timed out with exit code ${exit_code}"
  fi

  if ${DEBUG}; then
    dump_container_logs "${cname}"
  fi
  docker rm -f "${cname}" >/dev/null 2>&1 || true
}

aid_prefix() {
  local name=$1
  local alias=$2
  local passcode=$3

  kli aid --name "${name}" --alias "${alias}" --passcode "${passcode}" \
    | tr -d '[:space:]'
}

create_single_sig_config() {
  jq --arg wan "${WAN_PRE}" '.wits = [$wan]' \
    "${SCRIPT_DIR}/config/template-single-sig-incept-config.jq" \
    > "${EVENTS_DIR}/single-sig-incept-config.json"
}

create_aid() {
  local name=$1
  local salt=$2
  local passcode=$3
  local list_out
  local pre

  list_out=$(kli list --name "${name}" --passcode "${passcode}" 2>&1 || true)
  if [[ "${list_out}" != *"Keystore must already exist"* ]]; then
    pre=$(aid_prefix "${name}" "${name}" "${passcode}")
    log "AID ${name} already exists: ${pre}"
    return
  fi

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
  yes Y | kli multisig join --name "${name}" --group "${group}" --passcode "${passcode}" --auto >"${log_file}" 2>&1
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
    dump_container_logs gar1-geda
    fail "GEDA proposer exited before GAR2 joined"
  fi
  join_group_auto "${GAR2}" "${GEDA_NAME}" "${GAR2_PASSCODE}"
  wait_container gar1-geda

  GEDA_PRE=$(aid_prefix "${GAR1}" "${GEDA_NAME}" "${GAR1_PASSCODE}")
  [[ -n "${GEDA_PRE}" ]] || fail "unable to determine GEDA prefix"
  GEDA_OOBI=$(kli oobi generate --name "${GAR1}" --passcode "${GAR1_PASSCODE}" --alias "${GEDA_NAME}" --role witness \
    | awk 'NF {print; exit}')
  [[ -n "${GEDA_OOBI}" ]] || GEDA_OOBI="http://witness-demo:5642/oobi/${GEDA_PRE}/witness/${WAN_PRE}"

  printf '%s\n' "${GEDA_PRE}" > "${EVENTS_DIR}/geda-prefix.txt"
  printf '%s\n' "${GEDA_OOBI}" > "${EVENTS_DIR}/geda-oobi.txt"
  log "Created GEDA ${GEDA_PRE}"
}

build_kli_delegator() {
  create_single_sig_config
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

run_signifypy_scenario() {
  log "Running SignifyPy delegate setup"
  compose run --rm -e GEDA_PRE="${GEDA_PRE}" -e GEDA_OOBI="${GEDA_OOBI}" signifypy-runner setup
  approve_pending_delegation "SignifyPy"
  log "Running SignifyPy delegate completion"
  compose run --rm -e GEDA_PRE="${GEDA_PRE}" -e GEDA_OOBI="${GEDA_OOBI}" signifypy-runner complete
}

run_signify_ts_scenario() {
  log "Running SignifyTS delegate setup"
  compose run --rm -e GEDA_PRE="${GEDA_PRE}" -e GEDA_OOBI="${GEDA_OOBI}" signify-ts-runner npm run setup
  approve_pending_delegation "SignifyTS"
  log "Running SignifyTS delegate completion"
  compose run --rm -e GEDA_PRE="${GEDA_PRE}" -e GEDA_OOBI="${GEDA_OOBI}" signify-ts-runner npm run complete
}

start_stack() {
  docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1 || docker network create "${NETWORK_NAME}" >/dev/null
  log "Building runner images"
  compose build signifypy-runner signify-ts-runner
  log "Starting witness-demo and KERIA"
  compose up -d --wait witness-demo keria
}

main() {
  validate_host_tools
  mkdir -p "${KEYSTORE_DIR}" "${EVENTS_DIR}" "${QVI_DATA_DIR}"

  if ${CLEAR}; then
    log "Clearing prior containers, volumes, and runtime artifacts"
    compose down -v >/dev/null 2>&1 || true
    clean_runtime_dirs
  fi

  start_stack
  validate_versions
  build_kli_delegator
  run_signifypy_scenario
  run_signify_ts_scenario
  echo "PASS: multisig KLI delegator approved multisig KERIA SignifyPy and SignifyTS delegated inceptions"
}

main "$@"
