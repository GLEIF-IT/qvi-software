#!/usr/bin/env bash
# context-setup.sh - Environment/bootstrap setup outside KERI identity logic.

# Validate external command dependencies required by the test runner.
function check_dependencies() {
  command -v docker >/dev/null 2>&1 || fail "docker is required"
  command -v jq >/dev/null 2>&1 || fail "jq is required"
  command -v timeout >/dev/null 2>&1 || fail "timeout is required"
}

# Prepare runtime event artifact folder and clear prior JSON artifacts.
function prepare_events_dir() {
  mkdir -p "${EVENTS_DIR}"
  rm -f "${EVENTS_DIR}"/*.json >/dev/null 2>&1 || true
}

# Start docker network and witness compose stack needed for test workflows.
function start_stack() {
  docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1 || docker network create "${NETWORK_NAME}" >/dev/null
  docker compose -f "${COMPOSE_FILE}" --project-directory "${SCRIPT_DIR}" up -d --wait witness-demo >/dev/null
}
