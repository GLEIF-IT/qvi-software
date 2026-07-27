#!/usr/bin/env bash

# Create the isolated Python and TypeScript environments used by this workflow.

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
VENV_DIR="${SCRIPT_DIR}/.venvs"
DEPENDENCY_DIR="${SCRIPT_DIR}/.deps"

PYTHON_VERSION=${PYTHON_VERSION:-3.12.6}
# GEDA remains on the GLEIF 1.1.x compatibility line in a maintained worktree.
GEDA_KERIPY_VERSION=1.1.42
GEDA_KERIPY_BRANCH=perf/configurable-command-tocks-1.1.42
GEDA_KERIPY_DIR=${GEDA_KERIPY_DIR:-/Users/kbull/enc/keri/worktrees/keripy/configurable-command-tocks-1.1.42}
# Every other local Python process uses the actively tuned 1.2.x source tree.
LOCAL_KERIPY_BRANCH=v1.2.14
LOCAL_KERIPY_DIR=${LOCAL_KERIPY_DIR:-/Users/kbull/enc/keri/core/python/keripy}
LOCAL_KERIA_COMMIT=86e21cbdf98dcc75817e16708879c3c5a9b41cb8
LOCAL_KERIA_DIR=${LOCAL_KERIA_DIR:-/Users/kbull/enc/keri/core/python/keria}
KERIA_VERSION=0.4.1
SALLY_VERSION=1.0.5
HIO_VERSION=0.6.19
LMDB_VERSION=1.6.2
VLEI_COMMIT=c12e208f566478e6a256b6af6ddb1990e66a6d91

# Require one host command before making any environment changes.
required_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf '%s is required to bootstrap the local workflow\n' "$1" >&2
        return 1
    }
}

# Locate the exact pyenv interpreter selected for this workflow.
python_for_version() {
    local pyenv_root

    pyenv_root=$(pyenv root)
    printf '%s/versions/%s/bin/python\n' "${pyenv_root}" "${PYTHON_VERSION}"
}

# Keep immutable external dependencies at their pinned commits under .deps.
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

# Create or refresh one workflow-owned virtual environment.
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

# Replace a released KERIpy dependency with the local performance branch.
install_local_keripy() {
    local venv_name=$1
    local venv_python="${VENV_DIR}/${venv_name}/bin/python"

    uv pip install \
        --python "${venv_python}" \
        --no-deps \
        --editable "${LOCAL_KERIPY_DIR}"
    # Install HIO last so every local runtime uses the requested scheduler.
    uv pip install \
        --python "${venv_python}" \
        "hio==${HIO_VERSION}" \
        "lmdb==${LMDB_VERSION}"
}

# Validate local sources and install every workflow dependency.
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
    if [[ ! -f "${LOCAL_KERIPY_DIR}/pyproject.toml" &&
          ! -f "${LOCAL_KERIPY_DIR}/setup.py" ]]; then
        printf 'Local KERIpy checkout not found at %s\n' \
            "${LOCAL_KERIPY_DIR}" >&2
        return 1
    fi
    if [[ ! -f "${GEDA_KERIPY_DIR}/setup.py" ]]; then
        printf 'GEDA KERIpy checkout not found at %s\n' \
            "${GEDA_KERIPY_DIR}" >&2
        return 1
    fi
    if [[ "$(git -C "${GEDA_KERIPY_DIR}" branch --show-current)" != \
          "${GEDA_KERIPY_BRANCH}" ]]; then
        printf 'GEDA KERIpy must be on branch %s: %s\n' \
            "${GEDA_KERIPY_BRANCH}" "${GEDA_KERIPY_DIR}" >&2
        return 1
    fi
    if [[ "$(git -C "${LOCAL_KERIPY_DIR}" branch --show-current)" != \
          "${LOCAL_KERIPY_BRANCH}" ]]; then
        printf 'Local KERIpy must be on branch %s: %s\n' \
            "${LOCAL_KERIPY_BRANCH}" "${LOCAL_KERIPY_DIR}" >&2
        return 1
    fi
    if [[ ! -f "${LOCAL_KERIA_DIR}/pyproject.toml" ]]; then
        printf 'Local KERIA checkout not found at %s\n' \
            "${LOCAL_KERIA_DIR}" >&2
        return 1
    fi
    if [[ "$(git -C "${LOCAL_KERIA_DIR}" rev-parse HEAD)" != \
          "${LOCAL_KERIA_COMMIT}" ]]; then
        printf 'Local KERIA must be based on commit %s: %s\n' \
            "${LOCAL_KERIA_COMMIT}" "${LOCAL_KERIA_DIR}" >&2
        return 1
    fi
    ensure_checkout \
        vlei git@github.com:WebOfTrust/vLEI.git "${VLEI_COMMIT}"

    ensure_venv geda-kli "${python_path}" \
        --editable "${GEDA_KERIPY_DIR}"
    uv pip install \
        --python "${VENV_DIR}/geda-kli/bin/python" \
        "hio==${HIO_VERSION}" \
        "lmdb==${LMDB_VERSION}"

    ensure_venv kli "${python_path}" \
        --editable "${LOCAL_KERIPY_DIR}"
    install_local_keripy kli

    ensure_venv keria "${python_path}" \
        --editable "${LOCAL_KERIA_DIR}"
    install_local_keripy keria

    ensure_venv witnesses "${python_path}" \
        --editable "${LOCAL_KERIPY_DIR}"
    install_local_keripy witnesses

    ensure_venv sally "${python_path}" \
        "sally==${SALLY_VERSION}"
    install_local_keripy sally

    ensure_venv vlei "${python_path}" \
        --editable "${DEPENDENCY_DIR}/vlei" \
        "keri==1.2.6" \
        "hio==${HIO_VERSION}" \
        "lmdb==${LMDB_VERSION}"

    npm --prefix "${SCRIPT_DIR}/../sig_ts_wallets" ci

    printf 'Local workflow dependencies are ready:\n'
    printf '  GEDA KLI:  %s (local KERIpy %s, version %s, at %s)\n' \
        "${VENV_DIR}/geda-kli" "${GEDA_KERIPY_BRANCH}" \
        "${GEDA_KERIPY_VERSION}" "${GEDA_KERIPY_DIR}"
    printf '  KLI:       %s (local KERIpy branch %s)\n' \
        "${VENV_DIR}/kli" "${LOCAL_KERIPY_BRANCH}"
    printf '  KERIA:     %s (local source at %s)\n' \
        "${VENV_DIR}/keria" "${LOCAL_KERIA_DIR}"
    printf '  witnesses: %s\n' "${VENV_DIR}/witnesses"
    printf '  Sally:     %s (PyPI version %s)\n' \
        "${VENV_DIR}/sally" "${SALLY_VERSION}"
    printf '  vLEI:      %s\n' "${VENV_DIR}/vlei"
}

main "$@"
