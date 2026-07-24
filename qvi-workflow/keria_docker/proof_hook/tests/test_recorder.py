from __future__ import annotations

import json
import os
import stat
import tempfile
import threading
import unittest
from datetime import datetime, timezone
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path

from proof_hook.recorder import (
    CallbackStore,
    InvalidCallback,
    handler_for,
    normalize_callback,
)


class NormalizeCallbackTests(unittest.TestCase):
    def setUp(self) -> None:
        self.received_at = datetime(2026, 7, 23, 17, 0, tzinfo=timezone.utc)

    def test_normalizes_valid_issuance(self) -> None:
        record = normalize_callback(
            {
                "action": "iss",
                "actor": "EIssuer",
                "data": {
                    "credential": "ECredential",
                    "schema": "ESchema",
                    "issuer": "EIssuer",
                    "recipient": "EHolder",
                },
            },
            received_at=self.received_at,
        )

        self.assertEqual(record["credential"], "ECredential")
        self.assertEqual(record["receivedAt"], "2026-07-23T17:00:00.000000Z")

    def test_rejects_revocation_without_timestamp(self) -> None:
        with self.assertRaisesRegex(
            InvalidCallback,
            "data.revocationTimestamp",
        ):
            normalize_callback(
                {
                    "action": "rev",
                    "actor": "EIssuer",
                    "data": {
                        "credential": "ECredential",
                        "schema": "ESchema",
                    },
                },
                received_at=self.received_at,
            )

    def test_rejects_unknown_action(self) -> None:
        with self.assertRaisesRegex(InvalidCallback, "unsupported"):
            normalize_callback(
                {
                    "action": "delete",
                    "actor": "EIssuer",
                    "data": {
                        "credential": "ECredential",
                        "schema": "ESchema",
                    },
                },
                received_at=self.received_at,
            )

    def test_drops_unrecognized_issuance_data(self) -> None:
        record = normalize_callback(
            {
                "action": "iss",
                "actor": "EIssuer",
                "data": {
                    "credential": "ECredential",
                    "schema": "ESchema",
                    "issuer": "EIssuer",
                    "recipient": "EHolder",
                    "passcode": "not-a-real-private-passcode",
                    "unknown": {"nested": "value"},
                },
            },
            received_at=self.received_at,
        )

        self.assertEqual(
            record["data"],
            {
                "credential": "ECredential",
                "schema": "ESchema",
                "issuer": "EIssuer",
                "recipient": "EHolder",
            },
        )

    def test_drops_unrecognized_revocation_data(self) -> None:
        record = normalize_callback(
            {
                "action": "rev",
                "actor": "EIssuer",
                "data": {
                    "credential": "ECredential",
                    "schema": "ESchema",
                    "revocationTimestamp": "2026-07-23T16:59:59Z",
                    "salt": "not-a-real-private-salt",
                    "unknown": "value",
                },
            },
            received_at=self.received_at,
        )

        self.assertEqual(
            record["data"],
            {
                "credential": "ECredential",
                "schema": "ESchema",
                "revocationTimestamp": "2026-07-23T16:59:59Z",
            },
        )


class CallbackStoreTests(unittest.TestCase):
    def test_appends_canonical_private_jsonl(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_path = Path(temporary_directory) / "callbacks.jsonl"
            store = CallbackStore(
                output_path,
                clock=lambda: datetime(
                    2026,
                    7,
                    23,
                    17,
                    0,
                    tzinfo=timezone.utc,
                ),
            )

            store.append(
                {
                    "action": "rev",
                    "actor": "EIssuer",
                    "data": {
                        "credential": "ECredential",
                        "schema": "ESchema",
                        "revocationTimestamp": "2026-07-23T16:59:59Z",
                        "passcode": "not-a-real-private-passcode",
                        "unknown": "value",
                    },
                }
            )

            lines = output_path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 1)
            persisted_record = json.loads(lines[0])
            self.assertEqual(persisted_record["action"], "rev")
            self.assertEqual(
                persisted_record["data"],
                {
                    "credential": "ECredential",
                    "schema": "ESchema",
                    "revocationTimestamp": "2026-07-23T16:59:59Z",
                },
            )
            self.assertNotIn(
                "not-a-real-private-passcode",
                lines[0],
            )
            permissions = stat.S_IMODE(output_path.stat().st_mode)
            self.assertEqual(permissions, 0o600)

    @unittest.skipUnless(hasattr(os, "O_NOFOLLOW"), "needs O_NOFOLLOW")
    def test_rejects_symlink_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            target_path = root / "outside.jsonl"
            target_path.write_text("unchanged\n", encoding="utf-8")
            output_path = root / "callbacks.jsonl"
            output_path.symlink_to(target_path)

            with self.assertRaises(OSError):
                CallbackStore(output_path)

            self.assertEqual(
                target_path.read_text(encoding="utf-8"),
                "unchanged\n",
            )


class RecorderHttpContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        output_path = Path(self.temporary_directory.name) / "callbacks.jsonl"
        store = CallbackStore(
            output_path,
            clock=lambda: datetime(
                2026,
                7,
                23,
                17,
                0,
                tzinfo=timezone.utc,
            ),
        )
        self.output_path = output_path
        self.server = ThreadingHTTPServer(
            ("127.0.0.1", 0),
            handler_for(store),
        )
        self.server_thread = threading.Thread(
            target=self.server.serve_forever,
            daemon=True,
        )
        self.server_thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.server_thread.join(timeout=2)
        self.temporary_directory.cleanup()

    def request(
        self,
        method: str,
        path: str,
        body: dict[str, object] | None = None,
    ) -> tuple[int, dict[str, object]]:
        connection = HTTPConnection(
            "127.0.0.1",
            self.server.server_address[1],
            timeout=2,
        )
        encoded_body = json.dumps(body) if body is not None else None
        headers = {"Content-Type": "application/json"} if body is not None else {}
        connection.request(method, path, body=encoded_body, headers=headers)
        response = connection.getresponse()
        response_body = json.loads(response.read())
        connection.close()
        return response.status, response_body

    def test_health_endpoint(self) -> None:
        status, body = self.request("GET", "/health")

        self.assertEqual(status, 200)
        self.assertEqual(body, {"status": "healthy"})

    def test_callback_is_flushed_before_acceptance(self) -> None:
        status, body = self.request(
            "POST",
            "/",
            {
                "action": "iss",
                "actor": "EIssuer",
                "data": {
                    "credential": "ECredential",
                    "schema": "ESchema",
                    "issuer": "EIssuer",
                    "recipient": "EHolder",
                },
            },
        )

        self.assertEqual(status, 202)
        self.assertTrue(body["accepted"])
        persisted_record = json.loads(self.output_path.read_text(encoding="utf-8"))
        self.assertEqual(persisted_record["credential"], "ECredential")

    def test_malformed_callback_is_not_recorded(self) -> None:
        status, _body = self.request(
            "POST",
            "/",
            {
                "action": "rev",
                "actor": "EIssuer",
                "data": {
                    "credential": "ECredential",
                    "schema": "ESchema",
                },
            },
        )

        self.assertEqual(status, 400)
        self.assertEqual(self.output_path.read_text(encoding="utf-8"), "")


if __name__ == "__main__":
    unittest.main()
