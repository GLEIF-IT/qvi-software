#!/usr/bin/env bash

SALLY="${SALLY:-sally}"
SALLY_PASSCODE="${SALLY_PASSCODE:-VVmRdBTe5YCyLMmYRqTAi}"
SALLY_SALT="${SALLY_SALT:-0AD45YWdzWSwNREuAoitH_CC}"
WEBHOOK_HOST="${WEBHOOK_HOST:-http://hook:9923}"
GEDA_PRE="${GEDA_PRE:-EMCRBKH4Kvj03xbEVzKmOIrg0sosqHUF9VG2vzT9ybzv}"

kli init \
    --name "${SALLY}" \
    --salt "${SALLY_SALT}" \
    --passcode "${SALLY_PASSCODE}" \
    --config-dir "/sally/scripts" \
    --config-file "sally.json" 
kli incept \
    --name "${SALLY}" \
    --alias "${SALLY}" \
    --passcode "${SALLY_PASSCODE}" \
    --file "/sally/sally-incept-config.json" 

sally server start --name ${SALLY} --alias ${SALLY} --passcode ${SALLY_PASSCODE} --config-dir scripts --config-file sally.json --web-hook ${WEBHOOK_HOST} --auth ${GEDA_PRE} -l