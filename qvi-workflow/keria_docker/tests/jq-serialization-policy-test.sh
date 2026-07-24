#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
DRIVER="${SCRIPT_DIR}/../vlei-workflow.sh"

removed_validators=(
    qvi_inception_submission_is_exact
    qvi_endrole_operation_names_are_exact
    qvi_registry_operation_names_are_exact
    qvi_revocation_result_is_exact
    load_qvi_leaf_credential_said
)

for validator in "${removed_validators[@]}"; do
    validator_is_present=false
    grep -q "${validator}" "${DRIVER}" &&
        validator_is_present=true
    if [[ "${validator_is_present}" == true ]]; then
        printf 'Removed Bash validator returned: %s\n' \
            "${validator}" >&2
        exit 1
    fi
done

forbidden_jq_fragments=(
    'jq -e'
    'select('
    'all('
    'any('
    '| unique'
    'capture('
    'test('
    '| sort'
)

for fragment in "${forbidden_jq_fragments[@]}"; do
    fragment_is_present=false
    grep -Fq "${fragment}" "${DRIVER}" &&
        fragment_is_present=true
    if [[ "${fragment_is_present}" == true ]]; then
        printf 'Forbidden jq predicate returned: %s\n' \
            "${fragment}" >&2
        exit 1
    fi
done

cat_jq_pipeline_is_present=false
grep -Eq 'cat .*\|[[:space:]]*jq' "${DRIVER}" &&
    cat_jq_pipeline_is_present=true
if [[ "${cat_jq_pipeline_is_present}" == true ]]; then
    printf 'Use jq directly for display; cat-to-jq is forbidden\n' >&2
    exit 1
fi

printf 'jq serialization-only policy passed\n'
