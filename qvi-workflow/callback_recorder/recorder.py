#!/usr/bin/env python3
"""Receive Sally callbacks and append them to a local JSON Lines file."""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


CALLBACKS_PATH = Path(
    os.environ.get("QVI_CALLBACKS_PATH", "/runtime/sally-callbacks.jsonl")
)
PORT = int(os.environ.get("QVI_CALLBACK_PORT", "9923"))


def record_callback(payload: object, callbacks_path: Path) -> dict[str, object]:
    if not isinstance(payload, dict):
        raise ValueError("callback body must be a JSON object")

    record = {
        "receivedAt": datetime.now(timezone.utc).isoformat(),
        **payload,
    }
    callbacks_path.parent.mkdir(parents=True, exist_ok=True)
    with callbacks_path.open("a", encoding="utf-8") as callback_file:
        callback_file.write(
            json.dumps(record, separators=(",", ":"), sort_keys=True)
        )
        callback_file.write("\n")
    return record


class CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - stdlib HTTP API
        if self.path != "/health":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        self.send_response(HTTPStatus.OK)
        self.end_headers()

    def do_POST(self) -> None:  # noqa: N802 - stdlib HTTP API
        if self.path != "/":
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(
                self.rfile.read(content_length).decode("utf-8")
            )
            record_callback(payload, CALLBACKS_PATH)
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.send_error(HTTPStatus.BAD_REQUEST, str(error))
            return

        self.send_response(HTTPStatus.ACCEPTED)
        self.end_headers()

    def log_message(self, format_string: str, *args: object) -> None:
        print(format_string % args, flush=True)


def main() -> None:
    print(
        f"Recording Sally callbacks in {CALLBACKS_PATH} on port {PORT}",
        flush=True,
    )
    ThreadingHTTPServer(("0.0.0.0", PORT), CallbackHandler).serve_forever()


if __name__ == "__main__":
    main()
