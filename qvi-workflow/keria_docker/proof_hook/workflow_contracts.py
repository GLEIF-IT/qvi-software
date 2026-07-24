"""Validation adapters for workflow evidence not produced by SignifyTS."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


RELATIONSHIPS = {
    "GAR1-GAR2": ("gar1", "gar2"),
    "LAR1-LAR2": ("lar1", "lar2"),
    "QAR1-QAR2": ("qar1", "qar2"),
    "QAR1-QAR3": ("qar1", "qar3"),
    "QAR2-QAR3": ("qar2", "qar3"),
    "GAR1-QAR1": ("gar1", "qar1"),
    "QAR1-LAR1": ("qar1", "lar1"),
    "QAR1-Person": ("qar1", "person"),
}
CHALLENGE_DIGEST = re.compile(r"^[0-9a-f]{64}$")


class ContractError(ValueError):
    """Raised when workflow evidence violates its declared contract."""


def _records(value: Any) -> Iterable[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _records(child)
    elif isinstance(value, list):
        for child in value:
            yield from _records(child)


def validate_contact_binding(
    contacts: Any,
    alias: str,
    expected_prefix: str,
) -> dict[str, Any]:
    prefixes = {
        prefix
        for record in _records(contacts)
        if record.get("alias") == alias
        for prefix in (record.get("id") or record.get("prefix"),)
        if isinstance(prefix, str) and prefix
    }
    binding_is_exact = prefixes == {expected_prefix}
    if not binding_is_exact:
        raise ContractError(
            f"contact {alias!r} must bind only to {expected_prefix!r}; "
            f"observed {sorted(prefixes)!r}"
        )
    return {
        "ok": True,
        "alias": alias,
        "prefix": expected_prefix,
    }


def _expected_directions() -> set[tuple[str, str]]:
    return {
        (relationship, f"{source}->{target}")
        for relationship, participants in RELATIONSHIPS.items()
        for source, target in (
            participants,
            tuple(reversed(participants)),
        )
    }


def _require_string(
    record: dict[str, Any],
    field: str,
    description: str,
) -> str:
    value = record.get(field)
    if not isinstance(value, str) or not value:
        raise ContractError(f"{description} has no valid {field}")
    return value


def validate_challenge_manifest(
    records: list[dict[str, Any]],
) -> dict[str, Any]:
    receipts = [
        record for record in records
        if record.get("type") == "challenge"
    ]
    actual_directions: list[tuple[str, str]] = []
    for receipt in receipts:
        relationship = _require_string(
            receipt, "relationship", "challenge receipt"
        )
        direction = _require_string(
            receipt, "direction", "challenge receipt"
        )
        _require_string(
            receipt, "challengerPrefix", "challenge receipt"
        )
        _require_string(
            receipt, "responderPrefix", "challenge receipt"
        )
        verifier_type = _require_string(
            receipt, "verifierType", "challenge receipt"
        )
        if verifier_type not in {"kli", "keria"}:
            raise ContractError(
                f"challenge receipt has invalid verifierType "
                f"{verifier_type!r}"
            )
        digest = _require_string(
            receipt, "challengeDigest", "challenge receipt"
        )
        if CHALLENGE_DIGEST.fullmatch(digest) is None:
            raise ContractError(
                "challenge receipt has an invalid SHA-256 digest"
            )
        verified_at = _require_string(
            receipt, "verifiedAt", "challenge receipt"
        )
        try:
            datetime.fromisoformat(
                verified_at.replace("Z", "+00:00")
            )
        except ValueError as error:
            raise ContractError(
                "challenge receipt has an invalid verification timestamp"
            ) from error
        response_said = receipt.get("responseExnSaid")
        response_said_is_invalid = (
            response_said is not None
            and (
                not isinstance(response_said, str)
                or not response_said
            )
        )
        if response_said_is_invalid:
            raise ContractError(
                "challenge receipt has an invalid response EXN SAID"
            )
        actual_directions.append((relationship, direction))

    expected = _expected_directions()
    actual = set(actual_directions)
    directions_are_exact = (
        len(actual_directions) == len(expected)
        and len(actual) == len(actual_directions)
        and actual == expected
    )
    if not directions_are_exact:
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        raise ContractError(
            "challenge manifest must contain the exact 16 directions; "
            f"missing={missing!r}, unexpected={unexpected!r}"
        )

    canonical_directions = [
        {
            "relationship": relationship,
            "direction": direction,
        }
        for relationship, direction in sorted(actual)
    ]
    return {
        "ok": True,
        "relationshipCount": len(RELATIONSHIPS),
        "directionCount": len(actual_directions),
        "directions": canonical_directions,
    }


def parse_json_stream(text: str) -> list[Any]:
    """Decode the whitespace-delimited JSON documents emitted by KLI."""
    decoder = json.JSONDecoder()
    documents: list[Any] = []
    offset = 0
    while offset < len(text):
        while offset < len(text) and text[offset].isspace():
            offset += 1
        if offset == len(text):
            break
        try:
            document, offset = decoder.raw_decode(text, offset)
        except json.JSONDecodeError as error:
            raise ContractError(
                f"stdin is not a valid JSON stream: {error.msg}"
            ) from error
        documents.append(document)

    if not documents:
        raise ContractError("stdin contains no JSON documents")
    return documents


def _read_json_stream_stdin() -> list[Any]:
    return parse_json_stream(sys.stdin.read())


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise ContractError(
            f"unable to read proof manifest {path}: {error}"
        ) from error
    for line_number, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise ContractError(
                f"proof manifest line {line_number} is invalid JSON"
            ) from error
        if not isinstance(record, dict):
            raise ContractError(
                f"proof manifest line {line_number} is not an object"
            )
        records.append(record)
    return records


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    contact = subparsers.add_parser("contact-binding")
    contact.add_argument("--alias", required=True)
    contact.add_argument("--expected-prefix", required=True)

    challenge = subparsers.add_parser("challenge-manifest")
    challenge.add_argument("--manifest", required=True, type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "contact-binding":
            result = validate_contact_binding(
                _read_json_stream_stdin(),
                args.alias,
                args.expected_prefix,
            )
        else:
            result = validate_challenge_manifest(
                _read_jsonl(args.manifest)
            )
    except ContractError as error:
        print(
            json.dumps({"ok": False, "error": str(error)}),
            file=sys.stderr,
        )
        return 1

    print(json.dumps(result, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
