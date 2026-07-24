#!/usr/bin/env bash

set -Eeuo pipefail

SALLY_NAME="${SALLY_KS_NAME:-direct-sally}"
SALLY_ALIAS="${SALLY_ALIAS:-direct-sally}"
SALLY_SALT="${SALLY_SALT:-0ABVqAtad0CBkhDhCEPd514T}"
SALLY_PASSCODE="${SALLY_PASSCODE:-4TBjjhmKu9oeDp49J7Xdy}"
SALLY_WEBHOOK="${WEBHOOK_HOST:-http://hook:9923}"
SALLY_AUTHORITY="${GEDA_PRE:-}"
SALLY_PORT="${SALLY_PORT:-9823}"

authority_is_configured=false
if [[ -n "${SALLY_AUTHORITY}" ]]; then
  authority_is_configured=true
fi

if [[ "${authority_is_configured}" != true ]]; then
  echo "GEDA_PRE auth AID is not set. Exiting." >&2
  exit 1
fi

exec sally server start \
  --name "${SALLY_NAME}" \
  --alias "${SALLY_ALIAS}" \
  --salt "${SALLY_SALT}" \
  --passcode "${SALLY_PASSCODE}" \
  --config-dir /sally/conf \
  --config-file direct-sally.json \
  --incept-file /sally/conf/sally-incept-no-wits.json \
  --web-hook "${SALLY_WEBHOOK}" \
  --auth "${SALLY_AUTHORITY}" \
  --loglevel INFO \
  --http "${SALLY_PORT}" \
  --direct
