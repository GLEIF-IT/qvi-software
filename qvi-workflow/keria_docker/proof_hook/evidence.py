#!/usr/bin/env python3
"""Validate exact, current Sally evidence for the QVI workflow."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence, TypeVar

SALLY_102_REVOKED_PATTERN = re.compile(
    r"\brevoked credential (?P<said>[A-Za-z0-9_-]+) being presented\b"
)
RFC3339_PATTERN = re.compile(
    r"(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
    r"(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))"
)
EvidenceRecord = TypeVar("EvidenceRecord")


class EvidenceError(RuntimeError):
    """Raised when retained evidence does not prove the expected outcome."""


def parse_timestamp(value: object, *, field_name: str) -> datetime:
    """Parse a timezone-aware RFC 3339 timestamp."""

    value_is_string = isinstance(value, str) and bool(value.strip())
    if not value_is_string:
        raise EvidenceError(f"{field_name} must be a non-empty RFC 3339 timestamp")

    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        timestamp = datetime.fromisoformat(normalized)
    except ValueError as error:
        raise EvidenceError(f"{field_name} is not a valid RFC 3339 timestamp") from error

    timezone_is_present = timestamp.tzinfo is not None
    if not timezone_is_present:
        raise EvidenceError(f"{field_name} must include a timezone")

    return timestamp.astimezone(timezone.utc)


def read_callback_records(callback_path: Path) -> list[dict[str, Any]]:
    """Read JSONL records without silently skipping malformed evidence."""

    path_exists = callback_path.is_file()
    if not path_exists:
        raise EvidenceError(f"callback evidence file does not exist: {callback_path}")

    records: list[dict[str, Any]] = []
    with callback_path.open("r", encoding="utf-8") as callback_file:
        for line_number, line in enumerate(callback_file, start=1):
            line_has_content = bool(line.strip())
            if not line_has_content:
                continue

            try:
                record = json.loads(line)
            except json.JSONDecodeError as error:
                raise EvidenceError(
                    f"callback evidence line {line_number} is not valid JSON"
                ) from error

            record_is_object = isinstance(record, dict)
            if not record_is_object:
                raise EvidenceError(
                    f"callback evidence line {line_number} must be a JSON object"
                )

            parse_timestamp(
                record.get("receivedAt"),
                field_name=f"line {line_number} receivedAt",
            )
            records.append(record)

    return records


def records_after(
    records: Iterable[Mapping[str, Any]],
    *,
    submitted_after: datetime,
) -> list[Mapping[str, Any]]:
    """Return only records strictly newer than the submission boundary."""

    current_records: list[Mapping[str, Any]] = []
    for record in records:
        received_at = parse_timestamp(
            record.get("receivedAt"),
            field_name="receivedAt",
        )
        record_is_current = received_at > submitted_after
        if record_is_current:
            current_records.append(record)
    return current_records


def credential_records(
    records: Iterable[Mapping[str, Any]],
    *,
    credential_said: str,
) -> list[Mapping[str, Any]]:
    """Find all callback records for one exact credential SAID."""

    return [
        record
        for record in records
        if record.get("credential") == credential_said
        or (
            isinstance(record.get("data"), Mapping)
            and record["data"].get("credential") == credential_said
        )
    ]


def require_one_record(
    records: Sequence[EvidenceRecord],
    *,
    description: str,
) -> EvidenceRecord:
    """Reject missing and duplicate evidence."""

    record_count = len(records)
    count_is_one = record_count == 1
    if not count_is_one:
        raise EvidenceError(
            f"expected exactly one {description}; found {record_count}"
        )
    return records[0]


def require_mapping(value: object, *, field_name: str) -> Mapping[str, Any]:
    """Narrow an object to a mapping or reject the evidence."""

    value_is_mapping = isinstance(value, Mapping)
    if not value_is_mapping:
        raise EvidenceError(f"{field_name} must be a JSON object")
    return value


def require_exact(
    actual: object,
    expected: str,
    *,
    field_name: str,
) -> None:
    """Require exact field equality and provide a useful diagnostic."""

    values_match = actual == expected
    if not values_match:
        raise EvidenceError(
            f"{field_name} mismatch: expected {expected!r}, found {actual!r}"
        )


def validate_active_presentation(
    callback_path: Path,
    *,
    submitted_after: datetime,
    credential_said: str,
    schema: str,
    holder: str,
    issuer: str,
) -> dict[str, Any]:
    """Require one exact, post-submission issuance callback."""

    records = read_callback_records(callback_path)
    current_records = records_after(records, submitted_after=submitted_after)
    matching_credential = credential_records(
        current_records,
        credential_said=credential_said,
    )
    record = require_one_record(
        matching_credential,
        description=f"current callback for credential {credential_said}",
    )
    data = require_mapping(record.get("data"), field_name="data")

    require_exact(record.get("action"), "iss", field_name="action")
    require_exact(record.get("actor"), issuer, field_name="actor")
    require_exact(data.get("credential"), credential_said, field_name="data.credential")
    require_exact(data.get("schema"), schema, field_name="data.schema")
    require_exact(data.get("recipient"), holder, field_name="data.recipient")
    require_exact(data.get("issuer"), issuer, field_name="data.issuer")

    return {
        "action": "iss",
        "credential": credential_said,
        "schema": schema,
        "holder": holder,
        "issuer": issuer,
        "receivedAt": record["receivedAt"],
    }


@dataclass(frozen=True)
class Sally102Rejection:
    """Sally 1.0.2's exact revoked-presentation rejection evidence."""

    credential: str
    rejected_at: str
    line_number: int


def parse_sally_102_rejection(
    log_path: Path,
    *,
    submitted_after: datetime,
    credential_said: str,
) -> Sally102Rejection:
    """Require one current Sally 1.0.2 rejection for the exact credential."""

    path_exists = log_path.is_file()
    if not path_exists:
        raise EvidenceError(f"Sally log evidence file does not exist: {log_path}")

    matching_rejections: list[Sally102Rejection] = []
    with log_path.open("r", encoding="utf-8") as log_file:
        for line_number, line in enumerate(log_file, start=1):
            rejection_match = SALLY_102_REVOKED_PATTERN.search(line)
            line_is_rejection = rejection_match is not None
            if not line_is_rejection:
                continue

            rejected_said = rejection_match.group("said")
            said_matches = rejected_said == credential_said
            if not said_matches:
                continue

            timestamp_match = RFC3339_PATTERN.search(line)
            timestamp_is_present = timestamp_match is not None
            if not timestamp_is_present:
                raise EvidenceError(
                    "Sally 1.0.2 rejection line for the expected credential "
                    f"has no RFC 3339 timestamp at line {line_number}"
                )

            rejected_at_text = timestamp_match.group("timestamp")
            rejected_at = parse_timestamp(
                rejected_at_text,
                field_name=f"Sally log line {line_number} timestamp",
            )
            rejection_is_current = rejected_at > submitted_after
            if rejection_is_current:
                matching_rejections.append(
                    Sally102Rejection(
                        credential=credential_said,
                        rejected_at=rejected_at_text,
                        line_number=line_number,
                    )
                )

    rejection = require_one_record(
        matching_rejections,
        description=(
            "current Sally 1.0.2 revoked-presentation rejection for "
            f"{credential_said}"
        ),
    )
    return rejection


def validate_revoked_oor(
    callback_path: Path,
    log_path: Path,
    *,
    submitted_after: datetime,
    credential_said: str,
    schema: str,
    issuer: str,
    revocation_timestamp: str,
) -> dict[str, Any]:
    """Require exact Sally rejection and structured OOR revocation reporting."""

    records = read_callback_records(callback_path)
    current_records = records_after(records, submitted_after=submitted_after)
    matching_credential = credential_records(
        current_records,
        credential_said=credential_said,
    )
    record = require_one_record(
        matching_credential,
        description=f"current callback for revoked credential {credential_said}",
    )
    data = require_mapping(record.get("data"), field_name="data")

    require_exact(record.get("action"), "rev", field_name="action")
    require_exact(record.get("actor"), issuer, field_name="actor")
    require_exact(data.get("credential"), credential_said, field_name="data.credential")
    require_exact(data.get("schema"), schema, field_name="data.schema")
    require_exact(
        data.get("revocationTimestamp"),
        revocation_timestamp,
        field_name="data.revocationTimestamp",
    )

    rejection = parse_sally_102_rejection(
        log_path,
        submitted_after=submitted_after,
        credential_said=credential_said,
    )
    return {
        "action": "rev",
        "credential": credential_said,
        "schema": schema,
        "issuer": issuer,
        "revocationTimestamp": revocation_timestamp,
        "receivedAt": record["receivedAt"],
        "rejectedAt": rejection.rejected_at,
        "sallyVersion": "1.0.2",
    }


def assert_no_callback(
    callback_path: Path,
    *,
    submitted_after: datetime,
    schema: str,
    credential_said: str | None,
) -> dict[str, Any]:
    """Require that no current callback identifies the excluded credential."""

    records = read_callback_records(callback_path)
    current_records = records_after(records, submitted_after=submitted_after)
    forbidden_records: list[Mapping[str, Any]] = []
    for record in current_records:
        data = require_mapping(record.get("data"), field_name="data")
        schema_matches = data.get("schema") == schema
        credential_matches = (
            credential_said is not None
            and data.get("credential") == credential_said
        )
        callback_is_forbidden = schema_matches or credential_matches
        if callback_is_forbidden:
            forbidden_records.append(record)

    forbidden_count = len(forbidden_records)
    no_forbidden_callbacks = forbidden_count == 0
    if not no_forbidden_callbacks:
        raise EvidenceError(
            "expected no current callback for excluded schema or credential; "
            f"found {forbidden_count}"
        )

    return {
        "action": "none",
        "schema": schema,
        "credential": credential_said,
        "after": submitted_after.isoformat().replace("+00:00", "Z"),
    }


def add_common_callback_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--callbacks", required=True, type=Path)
    parser.add_argument("--after", required=True)
    parser.add_argument("--said", required=True)
    parser.add_argument("--schema", required=True)


def build_argument_parser() -> argparse.ArgumentParser:
    """Build the validation CLI parser without reading evidence."""

    parser = argparse.ArgumentParser(
        description="Validate exact Sally callback and rejection evidence.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    active_parser = subparsers.add_parser("active")
    add_common_callback_arguments(active_parser)
    active_parser.add_argument("--holder", required=True)
    active_parser.add_argument("--issuer", required=True)

    revoked_parser = subparsers.add_parser("revoked-oor")
    add_common_callback_arguments(revoked_parser)
    revoked_parser.add_argument("--logs", required=True, type=Path)
    revoked_parser.add_argument("--issuer", required=True)
    revoked_parser.add_argument("--revoked-at", required=True)

    none_parser = subparsers.add_parser("no-callback")
    none_parser.add_argument("--callbacks", required=True, type=Path)
    none_parser.add_argument("--after", required=True)
    none_parser.add_argument("--schema", required=True)
    none_parser.add_argument("--said")
    return parser


def execute_command(options: argparse.Namespace) -> dict[str, Any]:
    """Execute one parsed evidence command."""

    submitted_after = parse_timestamp(options.after, field_name="after")
    if options.command == "active":
        return validate_active_presentation(
            options.callbacks,
            submitted_after=submitted_after,
            credential_said=options.said,
            schema=options.schema,
            holder=options.holder,
            issuer=options.issuer,
        )
    if options.command == "revoked-oor":
        return validate_revoked_oor(
            options.callbacks,
            options.logs,
            submitted_after=submitted_after,
            credential_said=options.said,
            schema=options.schema,
            issuer=options.issuer,
            revocation_timestamp=options.revoked_at,
        )
    if options.command == "no-callback":
        return assert_no_callback(
            options.callbacks,
            submitted_after=submitted_after,
            schema=options.schema,
            credential_said=options.said,
        )

    raise EvidenceError(f"unsupported evidence command: {options.command}")


def main(arguments: Sequence[str] | None = None) -> int:
    """Run one validation command and emit one machine-readable result."""

    parser = build_argument_parser()
    options = parser.parse_args(arguments)
    try:
        result = execute_command(options)
    except EvidenceError as error:
        print(
            json.dumps(
                {"error": str(error), "ok": False},
                separators=(",", ":"),
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 1

    print(
        json.dumps(
            {"evidence": result, "ok": True},
            separators=(",", ":"),
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
