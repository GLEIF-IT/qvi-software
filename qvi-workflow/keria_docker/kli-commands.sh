#!/bin/bash

##################################################################
##                                                              ##
##          KLI Commands proxied by Docker Containers           ##
##                                                              ##
##################################################################

KEYSTORE_DIR=${1:-./docker-keystores}

if [ ! -d "${KEYSTORE_DIR}" ]; then
    echo "Creating Keystore directory ${KEYSTORE_DIR}"
    mkdir -p "${KEYSTORE_DIR}"
fi

# Set current working directory for all scripts that must access files
KLI1IMAGE="weboftrust/keri:1.1.32"
KLI2IMAGE="gleif/keri:1.2.8-rc1"

LOCAL_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export KLI_DATA_DIR="${LOCAL_DIR}/acdc-info"
export KLI_CONFIG_DIR="${LOCAL_DIR}/config"

# Separate function enables different version of KERIpy to be used for some identifiers.
function kli() {
  docker run -it --rm \
    --network vlei \
    -v "${KEYSTORE_DIR}":/usr/local/var/keri \
    -v "${KLI_CONFIG_DIR}:/config" \
    -v "${KLI_DATA_DIR}":/acdc-info \
    -e PYTHONWARNINGS="ignore::SyntaxWarning" \
    "${KLI1IMAGE}" "$@"
}

export -f kli

# Runs the KLI command in a detached container which is expected to be used in conjunction with
# `docker wait` to wait for the container to finish before continuing with further steps.
function klid() {
  name=$1
  # must pull first arg off to use as container name
  shift 1
  # pass remaining args to docker run
  docker run -d \
    --network vlei \
    --name $name \
    -v "${KEYSTORE_DIR}":/usr/local/var/keri \
    -v "${KLI_CONFIG_DIR}:/config" \
    -v "${KLI_DATA_DIR}":/acdc-info \
    -e PYTHONWARNINGS="ignore::SyntaxWarning" \
    "${KLI1IMAGE}" "$@"
}

export -f klid

# Separate function enables different version of KERIpy to be used for some identifiers.
function kli2() {
  docker run -it --rm \
    --network vlei \
    -v "${KEYSTORE_DIR}":/usr/local/var/keri \
    -v "${KLI_CONFIG_DIR}:/config" \
    -v "${KLI_DATA_DIR}":/acdc-info \
    -e PYTHONWARNINGS="ignore::SyntaxWarning" \
    "${KLI2IMAGE}" "$@"
}

export -f kli2

# Runs the KLI command in a detached container which is expected to be used in conjunction with
# `docker wait` to wait for the container to finish before continuing with further steps.
function kli2d() {
  name=$1
  # must pull first arg off to use as container name
  shift 1
  # pass remaining args to docker run
  docker run -d \
    --network vlei \
    --name $name \
    -v "${KEYSTORE_DIR}":/usr/local/var/keri \
    -v "${KLI_CONFIG_DIR}:/config" \
    -v "${KLI_DATA_DIR}":/acdc-info \
    -e PYTHONWARNINGS="ignore::SyntaxWarning" \
    "${KLI2IMAGE}" "$@"
}

export -f kli2d

echo "Keystore directory is ${KEYSTORE_DIR}"
echo "Data directory is ${KLI_DATA_DIR}"
echo "Config directory is ${KLI_CONFIG_DIR}"