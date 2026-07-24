#!/usr/bin/env bash

# Validate the terminal proof emitted after a delegated QVI rotation.
#
# This function intentionally returns only an exit status. Callers can assign
# that status to a named predicate without exposing or rewriting the artifact.
function qvi_rotation_completion_artifact_is_valid() {
    local artifact_path=$1
    local expected_qvi_prefix=$2

    jq -e \
        --arg qvi "${expected_qvi_prefix}" \
        '
          . as $completion |
          (.ok == true) and
          (.status == "refreshed") and
          (.groupState.prefix == $qvi) and
          (.groupState.sequence == "1") and
          (.groupState.observerCount == 3) and
          (.groupState.establishmentDigest |
            type == "string" and length > 0) and
          (.operationEvidence | length == 3) and
          ([.operationEvidence[].result.said] |
            unique == [$completion.groupState.establishmentDigest]) and
          all(
            .operationEvidence[];
            .done == true and
            .result.kind == "event" and
            (.result.said |
              type == "string" and length > 0) and
            .name == ("group." + .result.said) and
            .result.prefix == $qvi and
            .result.sequence == "1"
          )
        ' \
        "${artifact_path}" >/dev/null
}
