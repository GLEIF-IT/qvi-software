#!/usr/bin/env bash

SALLY="${SALLY:-sally}"
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
    --name "${SALLY}" \
    --salt "${SALLY_SALT}" \
    --passcode "${SALLY_PASSCODE}" \
    --config-dir /sally/conf \
    --config-file sally.json

# Create sally identifier
kli incept \
    --name "${SALLY}" \
    --alias "${SALLY}" \
    --passcode "${SALLY_PASSCODE}" \
    --config /sally/conf \
    --file "/sally/conf/sally-incept.json"

sally server start --name "${SALLY}" --alias "${SALLY}" \
  --passcode "${SALLY_PASSCODE}" \
  --config-dir /sally/conf \
  --config-file sally.json \
  --web-hook "${WEBHOOK_HOST}" \
  --auth "${GEDA_PRE}" \
  --loglevel INFO