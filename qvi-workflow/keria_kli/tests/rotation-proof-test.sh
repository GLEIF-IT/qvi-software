#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
)
source "${SCRIPT_DIR}/../lib/rotation-proof.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TEST_DIR}"' EXIT

VALID_ARTIFACT="${TEST_DIR}/valid.json"

printf '%s\n' \
  '{
    "ok": true,
    "status": "refreshed",
    "groupState": {
      "prefix": "EQvi",
      "sequence": "1",
      "establishmentDigest": "ERotation",
      "observerCount": 3
    },
    "operationEvidence": [
      {
        "name": "group.ERotation",
        "done": true,
        "result": {
          "kind": "event",
          "said": "ERotation",
          "prefix": "EQvi",
          "sequence": "1"
        }
      },
      {
        "name": "group.ERotation",
        "done": true,
        "result": {
          "kind": "event",
          "said": "ERotation",
          "prefix": "EQvi",
          "sequence": "1"
        }
      },
      {
        "name": "group.ERotation",
        "done": true,
        "result": {
          "kind": "event",
          "said": "ERotation",
          "prefix": "EQvi",
          "sequence": "1"
        }
      }
    ]
  }' > "${VALID_ARTIFACT}"

valid_artifact_status=0
qvi_rotation_completion_artifact_is_valid \
  "${VALID_ARTIFACT}" \
  "EQvi" ||
  valid_artifact_status=$?
valid_artifact_was_accepted=false
if [[ ${valid_artifact_status} -eq 0 ]]; then
  valid_artifact_was_accepted=true
fi
if [[ "${valid_artifact_was_accepted}" == false ]]; then
  printf 'Expected valid rotation proof to be accepted\n' >&2
  exit 1
fi

function require_invalid_artifact() {
  local description=$1
  local jq_mutation=$2
  local invalid_artifact="${TEST_DIR}/${description}.json"
  local validation_status=0
  local artifact_was_rejected=false

  jq "${jq_mutation}" "${VALID_ARTIFACT}" > "${invalid_artifact}"
  qvi_rotation_completion_artifact_is_valid \
    "${invalid_artifact}" \
    "EQvi" ||
    validation_status=$?
  if [[ ${validation_status} -ne 0 ]]; then
    artifact_was_rejected=true
  fi
  if [[ "${artifact_was_rejected}" == false ]]; then
    printf 'Expected %s rotation proof to be rejected\n' \
      "${description}" >&2
    exit 1
  fi
}

require_invalid_artifact \
  "wrong-prefix" \
  '.operationEvidence[1].result.prefix = "EOther"'
require_invalid_artifact \
  "wrong-sequence" \
  '.operationEvidence[1].result.sequence = "2"'
require_invalid_artifact \
  "non-event" \
  '.operationEvidence[1].result.kind = "object"'
require_invalid_artifact \
  "missing-said" \
  'del(.operationEvidence[1].result.said)'
require_invalid_artifact \
  "divergent-said" \
  '.operationEvidence[1].result.said = "EOther"'
require_invalid_artifact \
  "divergent-group-digest" \
  '.groupState.establishmentDigest = "EOther"'

printf 'rotation-proof-test: PASS\n'
