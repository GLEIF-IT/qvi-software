#!/usr/bin/env bash
# logging.sh - Log levels, trace log streaming, and diagnostics output.

# Print a standard prefixed info log line.
function log() {
  echo "[delegation-compat] $*"
}

# Print a prefixed error line and stop execution.
function fail() {
  echo "[delegation-compat] ERROR: $*" >&2
  exit 1
}

# Convert a symbolic log level to a numeric rank for comparisons.
function level_rank() {
  local level=$1 # symbolic level (quiet|normal|debug|trace)
  case "${level}" in
    quiet) echo 0 ;;
    normal) echo 1 ;;
    debug) echo 2 ;;
    trace) echo 3 ;;
    *) echo 1 ;;
  esac
}

# Return success when current LOG_LEVEL is >= requested level.
function should_log() {
  local want=$1 # minimum level required for this output
  [[ $(level_rank "${LOG_LEVEL}") -ge $(level_rank "${want}") ]]
}

# Stop all active trace-tail subprocesses started by start_trace_logs.
function stop_trace_logs() {
  local pid # PID for each background docker logs tail
  for pid in "${TRACE_LOG_PIDS[@]:-}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
  TRACE_LOG_PIDS=()
}

# Start background docker log tails for each named container in trace mode.
function start_trace_logs() {
  should_log trace || return 0
  local c # container name to tail
  for c in "$@"; do
    docker logs -f "${c}" 2>&1 | sed "s/^/[trace:${c}] /" &
    TRACE_LOG_PIDS+=("$!")
  done
}

# Print complete logs for one or more containers.
function dump_container_logs() {
  local c # container name whose logs are being printed
  for c in "$@"; do
    echo "----- logs: ${c} -----"
    docker logs "${c}" || true
  done
}

# Print compact container state and timing details for failures/timeouts.
function print_container_diagnostics() {
  local c=$1 # container name to inspect
  local state # docker state string (running|exited|missing)
  local exit_code # container exit code if available

  state=$(docker inspect --format '{{.State.Status}}' "${c}" 2>/dev/null || echo "missing")
  exit_code=$(docker inspect --format '{{.State.ExitCode}}' "${c}" 2>/dev/null || echo "n/a")

  echo "----- diagnostics: ${c} -----"
  echo "state=${state}"
  echo "exit_code=${exit_code}"
  docker inspect --format 'started={{.State.StartedAt}} finished={{.State.FinishedAt}} running={{.State.Running}}' "${c}" 2>/dev/null || true
}

# Persist status snapshots used for rotate/join isolation debugging.
function write_isolation_debug_snapshots() {
  local stamp # timestamp suffix to keep snapshot filenames unique
  local status_out # destination file for concise status output
  local verbose_out # destination file for verbose status output

  stamp=$(date +%Y%m%d-%H%M%S)
  status_out="${EVENTS_DIR}/debug-qvi-status-${stamp}.txt"
  verbose_out="${EVENTS_DIR}/debug-qvi-status-verbose-${stamp}.txt"

  {
    echo "=== qvi status from ${QAR1} ==="
    kli_qvi status --name "${QAR1}" --alias "${QVI_NAME}" --passcode "${QAR1_PASSCODE}" || true
    echo
    echo "=== qvi status from ${QAR2} ==="
    kli_qvi status --name "${QAR2}" --alias "${QVI_NAME}" --passcode "${QAR2_PASSCODE}" || true
  } > "${status_out}" 2>&1 || true

  kli_qvi status --name "${QAR1}" --alias "${QVI_NAME}" --passcode "${QAR1_PASSCODE}" --verbose > "${verbose_out}" 2>&1 || true
  log "Wrote debug snapshots to ${status_out} and ${verbose_out}"
}
