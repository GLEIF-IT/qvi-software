#!/usr/bin/env bash
# checkpointing.sh - Save/restore checkpoint artifacts for fast reruns.

# Return success when checkpoint metadata, keystore archive, and witness archive exist.
function checkpoint_exists() {
  [[ -f "${CHECKPOINT_META_FILE}" && -f "${CHECKPOINT_KEYSTORE_ARCHIVE}" && -f "${CHECKPOINT_WITNESS_ARCHIVE}" ]]
}

# Remove checkpoint artifacts so next run must rebuild from scratch.
function clear_checkpoint_artifacts() {
  rm -f "${CHECKPOINT_META_FILE}" "${CHECKPOINT_KEYSTORE_ARCHIVE}" "${CHECKPOINT_WITNESS_ARCHIVE}" >/dev/null 2>&1 || true
}

# Clear runtime state (containers, compose stack, keystores, event artifacts).
function clear_runtime_state() {
  remove_if_exists gar1 gar2 qvi1 qvi2
  docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" down -v >/dev/null 2>&1 || true
  find "${KEYSTORE_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + >/dev/null 2>&1 || true
  find "${EVENTS_DIR}" -maxdepth 1 -type f ! -name '.gitignore' ! -name '.gitkeep' -delete >/dev/null 2>&1 || true
}

# Resolve the docker volume name backing witness `/usr/local/var/keri`.
function resolve_witness_volume_name() {
  local witness_container # container ID for the witness-demo compose service
  local witness_volume # docker volume mounted as witness persistent state

  witness_container=$(docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" ps -q witness-demo 2>/dev/null || true)
  if [[ -n "${witness_container}" ]]; then
    witness_volume=$(docker inspect \
      --format '{{range .Mounts}}{{if and (eq .Destination "/usr/local/var/keri") (eq .Type "volume")}}{{.Name}}{{end}}{{end}}' \
      "${witness_container}" 2>/dev/null || true)
  fi

  if [[ -z "${witness_volume}" ]]; then
    # Fallback to the compose default `<project>_<volume>` naming pattern.
    witness_volume="delegation-compat_wit-vol"
  fi

  echo "${witness_volume}"
}

# Archive witness state volume into CHECKPOINT_WITNESS_ARCHIVE.
function snapshot_witness_volume() {
  local witness_volume=$1 # source docker volume containing witness state
  local archive_name # witness archive basename written under checkpoints dir

  [[ -n "${witness_volume}" ]] || return 1
  archive_name=$(basename "${CHECKPOINT_WITNESS_ARCHIVE}")

  docker run --rm \
    --entrypoint /bin/sh \
    -v "${witness_volume}:/from:ro" \
    -v "${CHECKPOINTS_DIR}:/checkpoint" \
    "${KLI_QVI_IMAGE}" \
    -c "tar czf /checkpoint/${archive_name} -C /from ." >/dev/null 2>&1
}

# Restore witness state volume from CHECKPOINT_WITNESS_ARCHIVE and restart witness.
function restore_witness_volume_from_checkpoint() {
  local witness_volume=$1 # target docker volume used by witness-demo
  local archive_name # witness archive basename read from checkpoints dir

  [[ -n "${witness_volume}" ]] || return 1
  [[ -f "${CHECKPOINT_WITNESS_ARCHIVE}" ]] || return 1
  archive_name=$(basename "${CHECKPOINT_WITNESS_ARCHIVE}")

  docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" stop witness-demo >/dev/null 2>&1 || true
  docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" rm -f witness-demo >/dev/null 2>&1 || true

  docker volume rm -f "${witness_volume}" >/dev/null 2>&1 || true
  docker volume create "${witness_volume}" >/dev/null 2>&1 || return 1

  docker run --rm \
    --entrypoint /bin/sh \
    -v "${witness_volume}:/to" \
    -v "${CHECKPOINTS_DIR}:/checkpoint:ro" \
    "${KLI_QVI_IMAGE}" \
    -c "tar xzf /checkpoint/${archive_name} -C /to" >/dev/null 2>&1 || return 1

  docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" up -d --wait witness-demo >/dev/null 2>&1 || return 1
  return 0
}

# Save keystore + witness archives and metadata that lets us validate/restore quickly.
function save_checkpoint() {
  local witness_volume # docker volume holding witness state
  local gar1_seq # GAR1 participant sequence captured at checkpoint time
  local gar2_seq # GAR2 participant sequence captured at checkpoint time
  local qar1_seq # QAR1 participant sequence captured at checkpoint time
  local qar2_seq # QAR2 participant sequence captured at checkpoint time
  local geda_seq # GEDA multisig sequence captured at checkpoint time
  local qvi_seq # QVI multisig sequence captured at checkpoint time

  mkdir -p "${CHECKPOINTS_DIR}"
  witness_volume=$(resolve_witness_volume_name)

  tar czf "${CHECKPOINT_KEYSTORE_ARCHIVE}" -C "${KEYSTORE_DIR}" . >/dev/null 2>&1 || \
    fail "Failed to create checkpoint archive"

  snapshot_witness_volume "${witness_volume}" || fail "Failed to create witness checkpoint archive"

  gar1_seq=$(aid_seq kli_gleif "${GAR1}" "${GAR1}" "${GAR1_PASSCODE}" || true)
  gar2_seq=$(aid_seq kli_gleif "${GAR2}" "${GAR2}" "${GAR2_PASSCODE}" || true)
  qar1_seq=$(aid_seq kli_qvi "${QAR1}" "${QAR1}" "${QAR1_PASSCODE}" || true)
  qar2_seq=$(aid_seq kli_qvi "${QAR2}" "${QAR2}" "${QAR2_PASSCODE}" || true)
  geda_seq=$(aid_seq kli_gleif "${GAR1}" "${GEDA_NAME}" "${GAR1_PASSCODE}" || true)
  qvi_seq=$(aid_seq kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}" || true)

  jq -n \
    --argjson version "${CHECKPOINT_VERSION}" \
    --arg gleif_image "${KLI_GLEIF_IMAGE}" \
    --arg qvi_image "${KLI_QVI_IMAGE}" \
    --arg keystore_archive "$(basename "${CHECKPOINT_KEYSTORE_ARCHIVE}")" \
    --arg witness_archive "$(basename "${CHECKPOINT_WITNESS_ARCHIVE}")" \
    --arg witness_volume "${witness_volume}" \
    --arg gar1_pre "${GAR1_PRE}" \
    --arg gar2_pre "${GAR2_PRE}" \
    --arg qar1_pre "${QAR1_PRE}" \
    --arg qar2_pre "${QAR2_PRE}" \
    --arg geda_pre "${GEDA_PRE}" \
    --arg qvi_pre "${QVI_PRE}" \
    --arg gar1_seq "${gar1_seq}" \
    --arg gar2_seq "${gar2_seq}" \
    --arg qar1_seq "${qar1_seq}" \
    --arg qar2_seq "${qar2_seq}" \
    --arg geda_seq "${geda_seq}" \
    --arg qvi_seq "${qvi_seq}" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      version: $version,
      created_at: $created_at,
      images: { gleif: $gleif_image, qvi: $qvi_image },
      checkpoint_components: {
        keystore: { archive: $keystore_archive },
        witness: {
          archive: $witness_archive,
          compose_service: "witness-demo",
          volume: $witness_volume
        }
      },
      prefixes: {
        gar1: $gar1_pre,
        gar2: $gar2_pre,
        qar1: $qar1_pre,
        qar2: $qar2_pre,
        geda: $geda_pre,
        qvi: $qvi_pre
      },
      sequences: {
        gar1: $gar1_seq,
        gar2: $gar2_seq,
        qar1: $qar1_seq,
        qar2: $qar2_seq,
        geda: $geda_seq,
        qvi: $qvi_seq
      }
    }' > "${CHECKPOINT_META_FILE}" || fail "Failed to write checkpoint metadata"

  log "Saved checkpoint at ${CHECKPOINTS_DIR}"
}

# Validate metadata structure and expected KERI image/version tuple.
function validate_checkpoint_metadata() {
  checkpoint_exists || return 1

  jq -e \
    --argjson version "${CHECKPOINT_VERSION}" \
    --arg gleif_image "${KLI_GLEIF_IMAGE}" \
    --arg qvi_image "${KLI_QVI_IMAGE}" \
    '.version == $version
     and .images.gleif == $gleif_image
     and .images.qvi == $qvi_image
     and (.checkpoint_components.witness.archive | length > 0)
     and (.checkpoint_components.witness.volume | length > 0)
     and (.prefixes.geda | length > 0)
     and (.prefixes.qvi | length > 0)
     and (.sequences.gar1 | test("^[0-9]+$"))
     and (.sequences.gar2 | test("^[0-9]+$"))
     and (.sequences.qar1 | test("^[0-9]+$"))
     and (.sequences.qar2 | test("^[0-9]+$"))
     and (.sequences.geda | test("^[0-9]+$"))
     and (.sequences.qvi | test("^[0-9]+$"))' \
    "${CHECKPOINT_META_FILE}" >/dev/null 2>&1
}

# Validate that restored keystores still contain expected group prefixes.
function validate_restored_state() {
  local expected_geda # expected GEDA group prefix from checkpoint metadata
  local expected_qvi # expected QVI group prefix from checkpoint metadata
  local expected_gar1_seq # expected GAR1 sequence from checkpoint metadata
  local expected_gar2_seq # expected GAR2 sequence from checkpoint metadata
  local expected_qar1_seq # expected QAR1 sequence from checkpoint metadata
  local expected_qar2_seq # expected QAR2 sequence from checkpoint metadata
  local expected_geda_seq # expected GEDA multisig sequence from checkpoint metadata
  local expected_qvi_seq # expected QVI multisig sequence from checkpoint metadata
  local actual_gar1_seq # observed GAR1 sequence after restore
  local actual_gar2_seq # observed GAR2 sequence after restore
  local actual_qar1_seq # observed QAR1 sequence after restore
  local actual_qar2_seq # observed QAR2 sequence after restore
  local actual_geda_seq # observed GEDA multisig sequence after restore
  local actual_qvi_seq # observed QVI multisig sequence after restore
  local qvi_status # status text used for delegated relation verification

  expected_geda=$(jq -r '.prefixes.geda' "${CHECKPOINT_META_FILE}")
  expected_qvi=$(jq -r '.prefixes.qvi' "${CHECKPOINT_META_FILE}")
  expected_gar1_seq=$(jq -r '.sequences.gar1' "${CHECKPOINT_META_FILE}")
  expected_gar2_seq=$(jq -r '.sequences.gar2' "${CHECKPOINT_META_FILE}")
  expected_qar1_seq=$(jq -r '.sequences.qar1' "${CHECKPOINT_META_FILE}")
  expected_qar2_seq=$(jq -r '.sequences.qar2' "${CHECKPOINT_META_FILE}")
  expected_geda_seq=$(jq -r '.sequences.geda' "${CHECKPOINT_META_FILE}")
  expected_qvi_seq=$(jq -r '.sequences.qvi' "${CHECKPOINT_META_FILE}")

  refresh_known_prefixes_from_keystore
  [[ "${GEDA_PRE}" == "${expected_geda}" ]] || return 1
  [[ "${QVI_PRE}" == "${expected_qvi}" ]] || return 1

  actual_gar1_seq=$(aid_seq kli_gleif "${GAR1}" "${GAR1}" "${GAR1_PASSCODE}" || true)
  actual_gar2_seq=$(aid_seq kli_gleif "${GAR2}" "${GAR2}" "${GAR2_PASSCODE}" || true)
  actual_qar1_seq=$(aid_seq kli_qvi "${QAR1}" "${QAR1}" "${QAR1_PASSCODE}" || true)
  actual_qar2_seq=$(aid_seq kli_qvi "${QAR2}" "${QAR2}" "${QAR2_PASSCODE}" || true)
  actual_geda_seq=$(aid_seq kli_gleif "${GAR1}" "${GEDA_NAME}" "${GAR1_PASSCODE}" || true)
  actual_qvi_seq=$(aid_seq kli_qvi "${QAR1}" "${QVI_NAME}" "${QAR1_PASSCODE}" || true)

  [[ "${actual_gar1_seq}" == "${expected_gar1_seq}" ]] || return 1
  [[ "${actual_gar2_seq}" == "${expected_gar2_seq}" ]] || return 1
  [[ "${actual_qar1_seq}" == "${expected_qar1_seq}" ]] || return 1
  [[ "${actual_qar2_seq}" == "${expected_qar2_seq}" ]] || return 1
  [[ "${actual_geda_seq}" == "${expected_geda_seq}" ]] || return 1
  [[ "${actual_qvi_seq}" == "${expected_qvi_seq}" ]] || return 1

  qvi_status=$(kli_qvi status --name "${QAR1}" --alias "${QVI_NAME}" --passcode "${QAR1_PASSCODE}" 2>/dev/null || true)
  [[ -n "${qvi_status}" ]] || return 1
  echo "${qvi_status}" | grep -q "${GEDA_PRE}" || return 1
  return 0
}

# Restore checkpoint if available and valid; return non-zero when restore cannot be trusted.
function restore_checkpoint_if_available() {
  local witness_volume # target witness volume where checkpoint state is restored

  checkpoint_exists || return 1
  validate_checkpoint_metadata || return 1

  log "Restoring keystores + witness state from checkpoint"
  find "${KEYSTORE_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} + >/dev/null 2>&1 || true
  tar xzf "${CHECKPOINT_KEYSTORE_ARCHIVE}" -C "${KEYSTORE_DIR}" >/dev/null 2>&1 || return 1

  witness_volume=$(resolve_witness_volume_name)
  restore_witness_volume_from_checkpoint "${witness_volume}" || return 1

  validate_restored_state || return 1
  return 0
}
