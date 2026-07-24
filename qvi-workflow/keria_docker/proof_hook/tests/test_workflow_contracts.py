import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from proof_hook.workflow_contracts import (
    ContractError,
    RELATIONSHIPS,
    _read_jsonl,
    parse_json_stream,
    validate_challenge_manifest,
    validate_contact_binding,
)


def challenge_receipts():
    digest = "a" * 64
    records = []
    for relationship, participants in RELATIONSHIPS.items():
        for source, target in (
            participants,
            tuple(reversed(participants)),
        ):
            records.append(
                {
                    "type": "challenge",
                    "relationship": relationship,
                    "direction": f"{source}->{target}",
                    "challengerPrefix": f"E-{source}",
                    "responderPrefix": f"E-{target}",
                    "verifierType": "kli",
                    "challengeDigest": digest,
                    "verifiedAt": "2026-07-24T12:00:00Z",
                }
            )
    return records


class ContactBindingTests(unittest.TestCase):
    def test_parses_kli_concatenated_contact_documents(self):
        result = parse_json_stream(
            '{"alias":"GAR1","id":"EGar1"}\n'
            '{"alias":"GAR2","id":"EGar2"}\n'
        )
        self.assertEqual(
            result,
            [
                {"alias": "GAR1", "id": "EGar1"},
                {"alias": "GAR2", "id": "EGar2"},
            ],
        )

    def test_rejects_empty_or_malformed_json_streams(self):
        for stream in ("", '{"alias":"GAR1"}\nnot-json\n'):
            with self.subTest(stream=stream):
                with self.assertRaises(ContractError):
                    parse_json_stream(stream)

    def test_accepts_one_exact_nested_alias_binding(self):
        result = validate_contact_binding(
            [{"contacts": [{"alias": "QAR1", "id": "EQar1"}]}],
            "QAR1",
            "EQar1",
        )
        self.assertEqual(result["prefix"], "EQar1")

    def test_rejects_missing_ambiguous_and_wrong_bindings(self):
        fixtures = [
            [],
            [
                {"alias": "QAR1", "id": "EQar1"},
                {"alias": "QAR1", "id": "EOther"},
            ],
            [{"alias": "QAR1", "prefix": "EWrong"}],
        ]
        for fixture in fixtures:
            with self.subTest(fixture=fixture):
                with self.assertRaises(ContractError):
                    validate_contact_binding(
                        fixture, "QAR1", "EQar1"
                    )


class ChallengeManifestTests(unittest.TestCase):
    def test_accepts_exact_challenge_graph(self):
        result = validate_challenge_manifest(
            challenge_receipts()
        )
        self.assertEqual(result["relationshipCount"], 8)
        self.assertEqual(result["directionCount"], 16)

    def test_rejects_missing_duplicate_and_malformed_receipts(self):
        exact = challenge_receipts()
        fixtures = [
            exact[:-1],
            exact + [exact[0]],
            [{**exact[0], "challengeDigest": "not-a-digest"}]
            + exact[1:],
            [{**exact[0], "verifierType": "unknown"}]
            + exact[1:],
        ]
        for fixture in fixtures:
            with self.subTest(size=len(fixture)):
                with self.assertRaises(ContractError):
                    validate_challenge_manifest(fixture)

    def test_rejects_malformed_jsonl(self):
        with TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.jsonl"
            manifest.write_text(
                '{"type":"challenge"}\nnot-json\n',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                ContractError, "line 2 is invalid JSON"
            ):
                _read_jsonl(manifest)


if __name__ == "__main__":
    unittest.main()
