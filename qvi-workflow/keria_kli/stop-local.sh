#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORKFLOW_ENV_FILE="${SCRIPT_DIR}/local-workflow.env"

set -a
# shellcheck source=./local-workflow.env
source "${WORKFLOW_ENV_FILE}"
set +a

# shellcheck source=./lib/workflow-runtime.sh
source "${SCRIPT_DIR}/lib/workflow-runtime.sh"

stop_retained_local_processes
printf 'Stopped retained local workflow processes from %s/runtime/pids\n' \
    "${SCRIPT_DIR}"
