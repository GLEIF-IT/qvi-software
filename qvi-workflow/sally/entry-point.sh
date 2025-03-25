#!/usr/bin/env bash

SALLY="${SALLY:-sally}"
SALLY_SALT="${SALLY_SALT:-0AD45YWdzWSwNREuAoitH_CC}"
SALLY_PASSCODE="${SALLY_PASSCODE:-VVmRdBTe5YCyLMmYRqTAi}"
WEBHOOK_HOST="${WEBHOOK_HOST:-http://hook:9923}"
GEDA_PRE="${GEDA_PRE:-EMCRBKH4Kvj03xbEVzKmOIrg0sosqHUF9VG2vzT9ybzv}"

# Create Habery / keystore
kli init \
    --name "${SALLY}" \
    --salt "${SALLY_SALT}" \
    --passcode "${SALLY_PASSCODE}" \
    --config-dir /sally/conf \
    --config-file sally-habery.json

# Create sally identifier
kli incept \
    --name "${SALLY}" \
    --alias "${SALLY}" \
    --passcode "${SALLY_PASSCODE}" \
    --file "/sally/conf/sally-incept.json"

sally server start --name "${SALLY}" --alias "${SALLY}" \
  --passcode "${SALLY_PASSCODE}" \
  --config-dir /sally/conf \
  --config-file sally-habery.json \
  --web-hook "${WEBHOOK_HOST}" \
  --auth "${GEDA_PRE}" \
  --loglevel INFO