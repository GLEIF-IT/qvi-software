#!/usr/bin/env bash

set -Eeuo pipefail

SALLY_KS_NAME="${SALLY_KS_NAME:?SALLY_KS_NAME is required}"
SALLY_ALIAS="${SALLY_ALIAS:?SALLY_ALIAS is required}"
SALLY_SALT="${SALLY_SALT:?SALLY_SALT is required}"
SALLY_PASSCODE="${SALLY_PASSCODE:?SALLY_PASSCODE is required}"
WEBHOOK_HOST="${WEBHOOK_HOST:?WEBHOOK_HOST is required}"
GEDA_PRE="${GEDA_PRE:?GEDA_PRE is required}"

# Sally owns its complete bootstrap lifecycle. On a new volume, server start
# creates the Habery and identifier from the public demo configuration. On
# restart, it reopens the same identifier.
exec sally server start \
    --direct \
    --http "${SALLY_PORT:-9823}" \
    --name "${SALLY_KS_NAME}" \
    --alias "${SALLY_ALIAS}" \
    --salt "${SALLY_SALT}" \
    --passcode "${SALLY_PASSCODE}" \
    --config-dir /sally/conf \
    --config-file direct-sally.json \
    --incept-file sally-incept-no-wits.json \
    --web-hook "${WEBHOOK_HOST}" \
    --auth "${GEDA_PRE}" \
    --loglevel INFO
