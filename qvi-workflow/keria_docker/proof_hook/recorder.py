#!/usr/bin/env python3
"""Record Sally callbacks as private, append-only JSON Lines.

The recorder deliberately persists only Sally's JSON body plus a local receipt
timestamp. HTTP signatures and other headers are transport details and may
contain data that does not belong in retained proof artifacts.
"""

from __future__ import annotations

import argparse
import json
import os
import threading
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

MAX_CALLBACK_BYTES = 1_048_576
SUPPORTED_ACTIONS = frozenset(("iss", "rev"))
DEFAULT_OUTPUT_PATH = Path(
    os.environ.get(
        "QVI_PROOF_CALLBACKS_PATH",
        "/proof/sally-callbacks.jsonl",
    )
)
DEFAULT_BIND = os.environ.get("QVI_PROOF_HOOK_BIND", "0.0.0.0")
DEFAULT_PORT = int(os.environ.get("QVI_PROOF_HOOK_PORT", "9923"))


class InvalidCallback(ValueError):
    """Raised when a request is not a valid Sally callback."""


def utc_now() -> datetime:
    """Return the current timezone-aware UTC time."""

    return datetime.now(timezone.utc)


def format_utc(timestamp: datetime) -> str:
    """Render a timezone-aware datetime as canonical RFC 3339 UTC."""

    if timestamp.tzinfo is None:
        raise ValueError("callback receipt timestamp must include a timezone")

    normalized = timestamp.astimezone(timezone.utc)
    return normalized.isoformat(timespec="microseconds").replace("+00:00", "Z")


def require_nonempty_string(
    value: object,
    *,
    field_name: str,
) -> str:
    """Return a validated non-empty string."""

    field_is_valid = isinstance(value, str) and bool(value.strip())
    if field_is_valid:
        return value

    raise InvalidCallback(f"{field_name} must be a non-empty string")


def normalize_callback(
    payload: object,
    *,
    received_at: datetime,
) -> dict[str, Any]:
    """Validate and normalize the callback fields needed by the proof harness."""

    payload_is_object = isinstance(payload, Mapping)
    if not payload_is_object:
        raise InvalidCallback("callback body must be a JSON object")

    action = require_nonempty_string(payload.get("action"), field_name="action")
    action_is_supported = action in SUPPORTED_ACTIONS
    if not action_is_supported:
        raise InvalidCallback(f"unsupported callback action: {action}")

    actor = require_nonempty_string(payload.get("actor"), field_name="actor")
    data = payload.get("data")
    data_is_object = isinstance(data, Mapping)
    if not data_is_object:
        raise InvalidCallback("data must be a JSON object")

    credential = require_nonempty_string(
        data.get("credential"),
        field_name="data.credential",
    )
    schema = require_nonempty_string(data.get("schema"), field_name="data.schema")

    if action == "iss":
        issuer = require_nonempty_string(
            data.get("issuer"),
            field_name="data.issuer",
        )
        recipient = require_nonempty_string(
            data.get("recipient"),
            field_name="data.recipient",
        )
        normalized_data = {
            "credential": credential,
            "schema": schema,
            "issuer": issuer,
            "recipient": recipient,
        }
    else:
        revocation_timestamp = require_nonempty_string(
            data.get("revocationTimestamp"),
            field_name="data.revocationTimestamp",
        )
        normalized_data = {
            "credential": credential,
            "schema": schema,
            "revocationTimestamp": revocation_timestamp,
        }

    return {
        "receivedAt": format_utc(received_at),
        "action": action,
        "actor": actor,
        "data": normalized_data,
        "credential": credential,
        "schema": schema,
    }


class CallbackStore:
    """Serialize valid callback records to one append-only file."""

    def __init__(
        self,
        output_path: Path,
        *,
        clock: Callable[[], datetime] = utc_now,
    ) -> None:
        self.output_path = output_path
        self.clock = clock
        self._write_lock = threading.Lock()
        self._prepare_output()

    def _prepare_output(self) -> None:
        self.output_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        open_flags = (
            os.O_APPEND
            | os.O_CREAT
            | os.O_WRONLY
            | getattr(os, "O_NOFOLLOW", 0)
        )
        file_descriptor = os.open(
            self.output_path,
            open_flags,
            0o600,
        )
        try:
            os.fchmod(file_descriptor, 0o600)
        finally:
            os.close(file_descriptor)

    def append(self, payload: object) -> dict[str, Any]:
        """Validate, append, flush, and return a callback record."""

        record = normalize_callback(payload, received_at=self.clock())
        encoded_record = (
            json.dumps(record, separators=(",", ":"), sort_keys=True) + "\n"
        ).encode("utf-8")

        with self._write_lock:
            open_flags = (
                os.O_APPEND | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0)
            )
            file_descriptor = os.open(
                self.output_path,
                open_flags,
            )
            with os.fdopen(file_descriptor, "ab") as output_file:
                output_file.write(encoded_record)
                output_file.flush()
                os.fsync(output_file.fileno())

        return record


def handler_for(store: CallbackStore) -> type[BaseHTTPRequestHandler]:
    """Create an HTTP handler bound to a callback store."""

    class CallbackHandler(BaseHTTPRequestHandler):
        server_version = "QVIProofHook/1.0"

        def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            path_is_health = self.path == "/health"
            if not path_is_health:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return

            self._send_json(HTTPStatus.OK, {"status": "healthy"})

        def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            path_is_callback = self.path == "/"
            if not path_is_callback:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return

            try:
                payload = self._read_json_body()
                record = store.append(payload)
            except (InvalidCallback, json.JSONDecodeError, UnicodeDecodeError) as error:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(error)})
                return

            self._send_json(
                HTTPStatus.ACCEPTED,
                {
                    "accepted": True,
                    "credential": record["credential"],
                    "receivedAt": record["receivedAt"],
                },
            )

        def _read_json_body(self) -> object:
            content_length_header = self.headers.get("Content-Length")
            content_length_is_present = content_length_header is not None
            if not content_length_is_present:
                raise InvalidCallback("Content-Length is required")

            try:
                content_length = int(content_length_header)
            except ValueError as error:
                raise InvalidCallback("Content-Length must be an integer") from error

            content_length_is_valid = 0 < content_length <= MAX_CALLBACK_BYTES
            if not content_length_is_valid:
                raise InvalidCallback(
                    f"callback body must be between 1 and {MAX_CALLBACK_BYTES} bytes"
                )

            raw_body = self.rfile.read(content_length)
            body_is_complete = len(raw_body) == content_length
            if not body_is_complete:
                raise InvalidCallback("callback body ended before Content-Length")

            return json.loads(raw_body.decode("utf-8"))

        def _send_json(self, status: HTTPStatus, body: Mapping[str, object]) -> None:
            encoded_body = (
                json.dumps(body, separators=(",", ":"), sort_keys=True)
            ).encode("utf-8")
            self.send_response(status.value)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded_body)))
            self.end_headers()
            self.wfile.write(encoded_body)

        def log_message(self, _format: str, *args: object) -> None:
            # Request bodies are intentionally absent from service logs.
            return

    return CallbackHandler


def build_argument_parser() -> argparse.ArgumentParser:
    """Build the recorder command-line parser without starting the service."""

    parser = argparse.ArgumentParser(
        description="Record Sally callbacks as timestamped JSON Lines.",
    )
    parser.add_argument("--output", default=DEFAULT_OUTPUT_PATH, type=Path)
    parser.add_argument("--bind", default=DEFAULT_BIND)
    parser.add_argument("--port", default=DEFAULT_PORT, type=int)
    return parser


def run_server(
    *,
    output_path: Path,
    bind: str,
    port: int,
) -> None:
    """Run the callback recorder until its process is stopped."""

    port_is_valid = 1 <= port <= 65535
    if not port_is_valid:
        raise ValueError("port must be between 1 and 65535")

    store = CallbackStore(output_path)
    server = ThreadingHTTPServer((bind, port), handler_for(store))
    print(
        json.dumps(
            {
                "event": "proof-hook-listening",
                "bind": bind,
                "port": port,
            },
            separators=(",", ":"),
            sort_keys=True,
        ),
        flush=True,
    )
    server.serve_forever()


def main(arguments: Sequence[str] | None = None) -> int:
    """Parse command-line arguments and run the recorder."""

    options = build_argument_parser().parse_args(arguments)
    run_server(
        output_path=options.output,
        bind=options.bind,
        port=options.port,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
