#!/usr/bin/env bash
# Suggested witness entrypoint script when running without TLS.
#
# This script uses the best practice of sending the sigterm to the witness process rather than waiting for the shell process to exit
# upon receiving a SIGTERM signal. This ensures that the witness process is gracefully shut down.
# Because PID 1 in this container is the shell process running this script, not the witness process, then forwarding is needed for graceful, rapid shutdown.
# Thus, to forward the SIGTERM signal to the witness process, we need to trap the signal and send it to the witness process.
# Forwarding the SIGTERM shuts the container down quickly rather than waiting for the shell process to exit, which takes 10 seconds, by default, in Docker.
#
# Note: This scripts hows how to run witnesses without TLS. For TLS, see the witness-tls-entrypoint.sh script.

mkdir -p /witness/keri/cf  # Create the directory for the witness configuration files

PID=
function shutdown_handler() {
  echo "Received SIGTERM, gracefully shutting down witness $NAME"
  kill -s SIGTERM $PID
}
trap shutdown_handler SIGTERM

if [ -z "$PASSCODE" ]; then
    echo "PASSCODE environment variable not set, cannot start"
    exit 1
fi
if [ -z "$NAME" ]; then
    echo "NAME environment variable not set, cannot start"
    exit 1
fi
if [ -z "$SALT" ]; then
    echo "SALT environment variable not set, cannot start"
    exit 1
fi
if [ -z "$CONFIG_DIR" ]; then
    echo "CONFIG_DIR environment variable not set, cannot start"
    exit 1
fi
if [ -z "$CONFIG_FILE" ]; then
    echo "CONFIG_FILE environment variable not set, cannot start"
    exit 1
fi

function init_witness() {
  echo "INITIALIZING witness keystore for name=$NAME and alias=$NAME"
  # Witness Keystore Initialization
  kli init --passcode "$PASSCODE" \
      --name "$NAME" \
      --salt "$SALT" \
      --config-dir "$CONFIG_DIR" \
      --config-file "$CONFIG_FILE"
}

function start_witness() {
  echo "STARTING witness $NAME on TCP port ${TCP_PORT:-5632} and HTTP port ${HTTP_PORT:-5642}"
  # Witness Start without TLS
  kli witness start \
        --passcode "$PASSCODE" \
        --name "$NAME" \
        --alias "$NAME" \
        -T "${TCP_PORT:-5632}" \
        -H "${HTTP_PORT:-5642}" \
        --config-dir "$CONFIG_DIR" \
        --config-file "$CONFIG_FILE" &
  PID=$!
  wait $PID
}

# Check if the witness exists. If the output contains "Public Keys" then the witness has been initialized.
kli status --name "$NAME" --alias "$NAME" --passcode "$PASSCODE" | grep -q 'Public Keys'
exists=$?
if [ $exists -ne 0 ]; then
  init_witness
  start_witness
else
  start_witness
fi




