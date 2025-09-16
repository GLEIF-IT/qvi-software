#!/usr/bin/env bash

SALLY_KS_NAME="${SALLY_KS_NAME:-sally}"
SALLY_SALT="${SALLY_SALT:-0AD45YWdzWSwNREuAoitH_CC}"
SALLY_PASSCODE="${SALLY_PASSCODE:-VVmRdBTe5YCyLMmYRqTAi}"
WEBHOOK_HOST="${WEBHOOK_HOST:-http://hook:9923}"
GEDA_PRE="${GEDA_PRE}"

if [ -z "${GEDA_PRE}" ]; then
  echo "GEDA_PRE auth AID is not set. Exiting."
  exit 1
else
  echo "GEDA_PRE auth AID is set to: ${GEDA_PRE}"
fi

# Create Habery / keystore
kli init \
    --name "${SALLY_KS_NAME}" \
    --salt "${SALLY_SALT}" \
    --passcode "${SALLY_PASSCODE}" \
    --config-dir /sally/conf \
    --config-file sally.json

# Create sally identifier
kli incept \
    --name "${SALLY_KS_NAME}" \
    --alias "${SALLY_ALIAS}" \
    --passcode "${SALLY_PASSCODE}" \
    --config /sally/conf \
    --file "/sally/conf/sally-incept.json"

sally server start \
  --http "${SALLY_PORT:-9723}" \
  --name "${SALLY_KS_NAME}" \
  --alias "${SALLY_ALIAS}" \
  --passcode "${SALLY_PASSCODE}" \
  --config-dir /sally/conf \
  --config-file sally.json \
  --web-hook "${WEBHOOK_HOST}" \
  --auth "${GEDA_PRE}" \
  --loglevel INFO