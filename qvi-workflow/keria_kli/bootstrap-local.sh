#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
VENV_DIR="${SCRIPT_DIR}/.venvs"
DEPENDENCY_DIR="${SCRIPT_DIR}/.deps"

PYTHON_VERSION=${PYTHON_VERSION:-3.12.6}
KLI_VERSION=1.1.32
KERIA_VERSION=0.4.0
WITNESS_KERI_VERSION=1.2.12
HIO_VERSION=0.6.14
LMDB_VERSION=1.6.2
SALLY_COMMIT=33fe75ab5fa2fa06e12a289f858cca02ae683df7
VLEI_COMMIT=c12e208f566478e6a256b6af6ddb1990e66a6d91

required_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf '%s is required to bootstrap the local workflow\n' "$1" >&2
        return 1
    }
}

python_for_version() {
    local pyenv_root

    pyenv_root=$(pyenv root)
    printf '%s/versions/%s/bin/python\n' "${pyenv_root}" "${PYTHON_VERSION}"
}

ensure_checkout() {
    local name=$1
    local url=$2
    local commit=$3
    local checkout_dir="${DEPENDENCY_DIR}/${name}"

    if [[ ! -d "${checkout_dir}/.git" ]]; then
        git clone --filter=blob:none --no-checkout "${url}" "${checkout_dir}"
    else
        git -C "${checkout_dir}" remote set-url origin "${url}"
    fi

    git -C "${checkout_dir}" fetch --depth 1 origin "${commit}"
    git -C "${checkout_dir}" checkout --detach "${commit}"
}

ensure_venv() {
    local name=$1
    local python_path=$2
    shift 2
    local venv_path="${VENV_DIR}/${name}"

    if [[ ! -x "${venv_path}/bin/python" ]]; then
        uv venv --python "${python_path}" "${venv_path}"
    fi
    uv pip install --python "${venv_path}/bin/python" "$@"
}

main() {
    required_command git
    required_command npm
    required_command pyenv
    required_command uv

    local python_path
    python_path=$(python_for_version)
    if [[ ! -x "${python_path}" ]]; then
        printf 'pyenv Python %s is not installed at %s\n' \
            "${PYTHON_VERSION}" "${python_path}" >&2
        return 1
    fi

    mkdir -p "${VENV_DIR}" "${DEPENDENCY_DIR}"
    ensure_checkout \
        sally git@github.com:GLEIF-IT/sally.git "${SALLY_COMMIT}"
    ensure_checkout \
        vlei git@github.com:WebOfTrust/vLEI.git "${VLEI_COMMIT}"

    ensure_venv kli "${python_path}" \
        "keri==${KLI_VERSION}" \
        "hio==${HIO_VERSION}" \
        "lmdb==${LMDB_VERSION}"
    ensure_venv keria "${python_path}" \
        "keria==${KERIA_VERSION}" \
        "hio==${HIO_VERSION}" \
        "lmdb==${LMDB_VERSION}"
    ensure_venv witnesses "${python_path}" \
        "keri==${WITNESS_KERI_VERSION}" \
        "hio==${HIO_VERSION}" \
        "lmdb==${LMDB_VERSION}"
    ensure_venv sally "${python_path}" \
        --editable "${DEPENDENCY_DIR}/sally" \
        "hio==${HIO_VERSION}" \
        "lmdb==${LMDB_VERSION}"
    ensure_venv vlei "${python_path}" \
        --editable "${DEPENDENCY_DIR}/vlei" \
        "keri==1.2.6" \
        "hio==${HIO_VERSION}" \
        "lmdb==${LMDB_VERSION}"

    npm --prefix "${SCRIPT_DIR}/../sig_ts_wallets" ci

    printf 'Local workflow dependencies are ready:\n'
    printf '  KLI:       %s\n' "${VENV_DIR}/kli"
    printf '  KERIA:     %s\n' "${VENV_DIR}/keria"
    printf '  witnesses: %s\n' "${VENV_DIR}/witnesses"
    printf '  Sally:     %s\n' "${VENV_DIR}/sally"
    printf '  vLEI:      %s\n' "${VENV_DIR}/vlei"
}

main "$@"
