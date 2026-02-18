#!/usr/bin/env bash
# kli-commands.sh - KERIpy commands for delegation compatibility tests

KEYSTORE_DIR=${1:-./docker-keystores}
NETWORK_NAME=${NETWORK_NAME:-vlei-delegation-test}

if [ ! -d "${KEYSTORE_DIR}" ]; then
  mkdir -p "${KEYSTORE_DIR}"
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
KLI_CONFIG_DIR="${SCRIPT_DIR}/config"
EVENTS_DIR="${SCRIPT_DIR}/events"

mkdir -p "${EVENTS_DIR}"

KLI_GLEIF_IMAGE="gleif/keri:1.1.42"
KLI_QVI_IMAGE="gleif/keri:1.2.11"

function kli_gleif() {
  docker run --rm -i \
    --network "${NETWORK_NAME}" \
    -v "${KEYSTORE_DIR}":/usr/local/var/keri \
    -v "${KLI_CONFIG_DIR}":/config \
    -v "${EVENTS_DIR}":/events \
    -e PYTHONWARNINGS="ignore::SyntaxWarning" \
    "${KLI_GLEIF_IMAGE}" "$@"
}

function kli_gleif_d() {
  local name=$1
  shift
  docker run -d \
    --network "${NETWORK_NAME}" \
    --name "${name}" \
    -v "${KEYSTORE_DIR}":/usr/local/var/keri \
    -v "${KLI_CONFIG_DIR}":/config \
    -v "${EVENTS_DIR}":/events \
    -e PYTHONWARNINGS="ignore::SyntaxWarning" \
    "${KLI_GLEIF_IMAGE}" "$@"
}

function kli_qvi() {
  docker run --rm -i \
    --network "${NETWORK_NAME}" \
    -v "${KEYSTORE_DIR}":/usr/local/var/keri \
    -v "${KLI_CONFIG_DIR}":/config \
    -v "${EVENTS_DIR}":/events \
    -e PYTHONWARNINGS="ignore::SyntaxWarning" \
    "${KLI_QVI_IMAGE}" "$@"
}

function kli_qvi_d() {
  local name=$1
  shift
  docker run -d \
    --network "${NETWORK_NAME}" \
    --name "${name}" \
    -v "${KEYSTORE_DIR}":/usr/local/var/keri \
    -v "${KLI_CONFIG_DIR}":/config \
    -v "${EVENTS_DIR}":/events \
    -e PYTHONWARNINGS="ignore::SyntaxWarning" \
    "${KLI_QVI_IMAGE}" "$@"
}

export -f kli_gleif
export -f kli_gleif_d
export -f kli_qvi
export -f kli_qvi_d
