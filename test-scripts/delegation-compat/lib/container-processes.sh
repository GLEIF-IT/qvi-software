#!/usr/bin/env bash
# container-processes.sh - Container lifecycle, join orchestration, and wait semantics.

# Remove one or more containers when they exist.
function remove_if_exists() {
  local c # container name to remove if present
  for c in "$@"; do
    docker rm -f "${c}" >/dev/null 2>&1 || true
  done
}

# Wait for containers and collect diagnostics/logs on timeout/failure.
function wait_and_collect() {
  local failed=0 # set to 1 when any container fails or times out
  local timed_out=0 # set to 1 when timeout condition is hit
  local timeout_container="" # first container that timed out
  local failed_container="" # first container with non-zero exit code
  local wait_timeout=${WAIT_TIMEOUT_SECONDS:-15} # per-container max wait in seconds
  local c # container currently being awaited

  start_trace_logs "$@"
  for c in "$@"; do
    local exit_code # docker wait result (container exit code or timeout sentinel)

    # timeout returns 124; we preserve that code as an explicit timeout sentinel.
    exit_code=$(timeout "${wait_timeout}s" docker wait "${c}" 2>/dev/null || echo "124")
    if [[ "${exit_code}" == "124" ]]; then
      timed_out=1
      failed=1
      timeout_container="${c}"
      break
    fi

    if [[ "${exit_code}" != "0" ]]; then
      failed=1
      failed_container="${c}"
      break
    fi
  done
  stop_trace_logs

  if [[ ${failed} -ne 0 ]]; then
    for c in "$@"; do
      print_container_diagnostics "${c}"
    done
  fi

  for c in "$@"; do
    if should_log debug || [[ ${failed} -ne 0 ]]; then
      dump_container_logs "${c}"
    fi
    docker rm -f "${c}" >/dev/null 2>&1 || true
  done

  if ${ROTATE_JOIN_ONLY} && [[ ${failed} -ne 0 ]]; then
    write_isolation_debug_snapshots
  fi

  if [[ ${timed_out} -ne 0 ]]; then
    fail "One or more delegated workflow containers timed out after ${wait_timeout}s (first timeout: ${timeout_container})"
  fi

  [[ ${failed} -eq 0 ]] || fail "One or more delegated workflow containers failed (first failure: ${failed_container})"
}

# Assert that a detached container is still alive before dependent steps.
function ensure_container_running() {
  local c=$1 # container expected to remain running
  local state # live state from docker inspect

  sleep 1
  state=$(docker inspect --format '{{.State.Status}}' "${c}" 2>/dev/null || echo "missing")
  if [[ "${state}" != "running" ]]; then
    dump_container_logs "${c}"
    fail "Container ${c} exited before join step (state: ${state})"
  fi
}

# Return success when a named container is currently running.
function container_is_running() {
  local c=$1 # container name to inspect
  local state # inspect status for the container

  state=$(docker inspect --format '{{.State.Status}}' "${c}" 2>/dev/null || echo "missing")
  [[ "${state}" == "running" ]]
}

# Retry join while the proposer container is still running.
function complete_join_while_proposer_running() {
  local cmd=$1 # command wrapper to run (kli_gleif | kli_qvi)
  local name=$2 # participant keystore name
  local group=$3 # multisig alias/group name
  local passcode=$4 # participant passcode
  local proposer_container=$5 # proposer container that must stay alive
  local max_attempts=${6:-2} # retry bound for transient join failures
  local attempt # current retry attempt counter
  local rc # join command exit code

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if ! container_is_running "${proposer_container}"; then
      return
    fi

    rc=0
    join_group_auto_with_cleanup "${cmd}" "${name}" "${group}" "${passcode}" || rc=$?
    if [[ ${rc} -eq 124 || ${rc} -eq 255 ]]; then
      sleep 1
      continue
    fi
    [[ ${rc} -eq 0 ]] || fail "Join command failed with exit code ${rc}"
  done

  if container_is_running "${proposer_container}"; then
    dump_container_logs "${proposer_container}"
    fail "Join attempts exhausted while ${proposer_container} is still running"
  fi
}

# Run multisig join in background, enforce timeout, and keep temporary logs.
function join_group_auto_with_cleanup() {
  local cmd=$1 # command wrapper to run (kli_gleif | kli_qvi)
  local name=$2 # participant keystore name
  local group=$3 # multisig alias/group name
  local passcode=$4 # participant passcode
  local join_pid # PID of the background join subprocess
  local elapsed=0 # elapsed seconds while waiting for join completion
  local max_wait=15 # maximum seconds to wait before timeout
  local join_log # temp file storing join stdout/stderr
  local rc # join exit code

  join_log=$(mktemp "${EVENTS_DIR}/join-${name}-${group}.XXXXXX")

  # Launch join in a background subshell so the caller can continue coordinating
  # other containers. `yes Y` automatically answers any confirmation prompts.
  (
    # Keep this subshell tolerant of broken pipe behavior from the yes|join pipeline.
    set +o pipefail
    yes Y | \
      ${cmd} multisig join --name "${name}" --group "${group}" --passcode "${passcode}" --auto >"${join_log}" 2>&1
  ) &
  join_pid=$!

  # `kill -0` checks process liveness without sending a terminating signal.
  while kill -0 "${join_pid}" >/dev/null 2>&1; do
    if [[ ${elapsed} -ge ${max_wait} ]]; then
      kill "${join_pid}" >/dev/null 2>&1 || true
      wait "${join_pid}" >/dev/null 2>&1 || true
      rm -f "${join_log}" >/dev/null 2>&1 || true
      # 124 is the timeout sentinel, matching GNU timeout conventions.
      return 124
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  rc=0
  wait "${join_pid}" || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    echo "----- join logs (${name}/${group}) -----"
    cat "${join_log}" || true
    if grep -q "mdb_txn_begin: Resource temporarily unavailable" "${join_log}"; then
      rm -f "${join_log}" >/dev/null 2>&1 || true
      # 255 marks transient LMDB lock contention; caller may retry.
      return 255
    fi
  fi

  rm -f "${join_log}" >/dev/null 2>&1 || true
  return "${rc}"
}
