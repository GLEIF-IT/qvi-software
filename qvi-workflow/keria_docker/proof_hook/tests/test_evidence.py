from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from proof_hook.evidence import (
    EvidenceError,
    assert_no_callback,
    parse_sally_102_rejection,
    validate_active_presentation,
    validate_revoked_oor,
)

FIXTURES = Path(__file__).parent / "fixtures"
SUBMISSION_TIME = datetime(2026, 7, 23, 17, 0, tzinfo=timezone.utc)


class ActivePresentationEvidenceTests(unittest.TestCase):
    def test_requires_exact_current_presentation(self) -> None:
        evidence = validate_active_presentation(
            FIXTURES / "callbacks.jsonl",
            submitted_after=SUBMISSION_TIME,
            credential_said="EQviCredential",
            schema="EQviSchema",
            holder="EQviHolder",
            issuer="EQviIssuer",
        )

        self.assertEqual(evidence["action"], "iss")
        self.assertEqual(evidence["credential"], "EQviCredential")

    def test_rejects_wrong_holder(self) -> None:
        with self.assertRaisesRegex(EvidenceError, "data.recipient mismatch"):
            validate_active_presentation(
                FIXTURES / "callbacks.jsonl",
                submitted_after=SUBMISSION_TIME,
                credential_said="EQviCredential",
                schema="EQviSchema",
                holder="EWrongHolder",
                issuer="EQviIssuer",
            )

    def test_rejects_stale_callback(self) -> None:
        after_callback = datetime(
            2026,
            7,
            23,
            17,
            0,
            1,
            tzinfo=timezone.utc,
        )
        with self.assertRaisesRegex(EvidenceError, "found 0"):
            validate_active_presentation(
                FIXTURES / "callbacks.jsonl",
                submitted_after=after_callback,
                credential_said="EQviCredential",
                schema="EQviSchema",
                holder="EQviHolder",
                issuer="EQviIssuer",
            )

    def test_rejects_duplicate_callback(self) -> None:
        callback_line = (FIXTURES / "callbacks.jsonl").read_text(
            encoding="utf-8"
        ).splitlines()[0]
        with tempfile.TemporaryDirectory() as temporary_directory:
            callback_path = Path(temporary_directory) / "callbacks.jsonl"
            callback_path.write_text(
                f"{callback_line}\n{callback_line}\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(EvidenceError, "found 2"):
                validate_active_presentation(
                    callback_path,
                    submitted_after=SUBMISSION_TIME,
                    credential_said="EQviCredential",
                    schema="EQviSchema",
                    holder="EQviHolder",
                    issuer="EQviIssuer",
                )


class RevokedOorEvidenceTests(unittest.TestCase):
    def test_requires_callback_and_sally_102_rejection(self) -> None:
        evidence = validate_revoked_oor(
            FIXTURES / "callbacks.jsonl",
            FIXTURES / "sally-1.0.2-revoked.log",
            submitted_after=datetime(
                2026,
                7,
                23,
                17,
                0,
                2,
                tzinfo=timezone.utc,
            ),
            credential_said="EOorCredential",
            schema="EOorSchema",
            issuer="ELegalEntity",
            revocation_timestamp="2026-07-23T17:00:03.000000+00:00",
        )

        self.assertEqual(evidence["action"], "rev")
        self.assertEqual(evidence["sallyVersion"], "1.0.2")

    def test_rejects_wrong_revocation_timestamp(self) -> None:
        with self.assertRaisesRegex(
            EvidenceError,
            "data.revocationTimestamp mismatch",
        ):
            validate_revoked_oor(
                FIXTURES / "callbacks.jsonl",
                FIXTURES / "sally-1.0.2-revoked.log",
                submitted_after=datetime(
                    2026,
                    7,
                    23,
                    17,
                    0,
                    2,
                    tzinfo=timezone.utc,
                ),
                credential_said="EOorCredential",
                schema="EOorSchema",
                issuer="ELegalEntity",
                revocation_timestamp="2026-07-23T17:00:09Z",
            )

    def test_rejects_rejection_without_timestamp(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            log_path = Path(temporary_directory) / "sally.log"
            log_path.write_text(
                "revoked credential EOorCredential being presented\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(EvidenceError, "no RFC 3339 timestamp"):
                parse_sally_102_rejection(
                    log_path,
                    submitted_after=SUBMISSION_TIME,
                    credential_said="EOorCredential",
                )

    def test_rejects_report_without_rejection(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            log_path = Path(temporary_directory) / "sally.log"
            log_path.write_text(
                "2026-07-23T17:00:05Z no revoked credential rejection\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(
                EvidenceError,
                "expected exactly one current Sally 1.0.2",
            ):
                validate_revoked_oor(
                    FIXTURES / "callbacks.jsonl",
                    log_path,
                    submitted_after=datetime(
                        2026,
                        7,
                        23,
                        17,
                        0,
                        2,
                        tzinfo=timezone.utc,
                    ),
                    credential_said="EOorCredential",
                    schema="EOorSchema",
                    issuer="ELegalEntity",
                    revocation_timestamp="2026-07-23T17:00:03.000000+00:00",
                )

    def test_rejects_rejection_without_report(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            callback_path = Path(temporary_directory) / "callbacks.jsonl"
            callback_path.write_text("", encoding="utf-8")

            with self.assertRaisesRegex(
                EvidenceError,
                "expected exactly one current callback",
            ):
                validate_revoked_oor(
                    callback_path,
                    FIXTURES / "sally-1.0.2-revoked.log",
                    submitted_after=datetime(
                        2026,
                        7,
                        23,
                        17,
                        0,
                        2,
                        tzinfo=timezone.utc,
                    ),
                    credential_said="EOorCredential",
                    schema="EOorSchema",
                    issuer="ELegalEntity",
                    revocation_timestamp="2026-07-23T17:00:03.000000+00:00",
                )

    def test_rejects_stale_revocation_callback(self) -> None:
        with self.assertRaisesRegex(
            EvidenceError,
            "expected exactly one current callback",
        ):
            validate_revoked_oor(
                FIXTURES / "callbacks.jsonl",
                FIXTURES / "sally-1.0.2-revoked.log",
                submitted_after=datetime(
                    2026,
                    7,
                    23,
                    17,
                    0,
                    5,
                    tzinfo=timezone.utc,
                ),
                credential_said="EOorCredential",
                schema="EOorSchema",
                issuer="ELegalEntity",
                revocation_timestamp="2026-07-23T17:00:03.000000+00:00",
            )

    def test_rejects_wrong_revoked_credential_said(self) -> None:
        with self.assertRaisesRegex(
            EvidenceError,
            "expected exactly one current callback",
        ):
            validate_revoked_oor(
                FIXTURES / "callbacks.jsonl",
                FIXTURES / "sally-1.0.2-revoked.log",
                submitted_after=datetime(
                    2026,
                    7,
                    23,
                    17,
                    0,
                    2,
                    tzinfo=timezone.utc,
                ),
                credential_said="EWrongOorCredential",
                schema="EOorSchema",
                issuer="ELegalEntity",
                revocation_timestamp="2026-07-23T17:00:03.000000+00:00",
            )


class NoEcrCallbackTests(unittest.TestCase):
    def test_accepts_absent_ecr_callback(self) -> None:
        evidence = assert_no_callback(
            FIXTURES / "callbacks.jsonl",
            submitted_after=SUBMISSION_TIME,
            schema="EEcrSchema",
            credential_said="EEcrCredential",
        )

        self.assertEqual(evidence["action"], "none")

    def test_rejects_ecr_schema_even_with_wrong_said(self) -> None:
        callback = (
            '{"action":"rev","actor":"EIssuer","credential":"EOther",'
            '"data":{"credential":"EOther","revocationTimestamp":'
            '"2026-07-23T17:00:03Z","schema":"EEcrSchema"},'
            '"receivedAt":"2026-07-23T17:00:04Z","schema":"EEcrSchema"}\n'
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            callback_path = Path(temporary_directory) / "callbacks.jsonl"
            callback_path.write_text(callback, encoding="utf-8")

            with self.assertRaisesRegex(EvidenceError, "found 1"):
                assert_no_callback(
                    callback_path,
                    submitted_after=SUBMISSION_TIME,
                    schema="EEcrSchema",
                    credential_said="EEcrCredential",
                )


if __name__ == "__main__":
    unittest.main()
