# Sally proof hook

This directory contains the workflow-owned replacement for Sally's in-memory
demo webhook and the Sally 1.0.2-specific evidence adapter. The recorder writes
each valid Sally callback as one JSON object per line with a UTC `receivedAt`
timestamp. It does not write HTTP headers or unredacted request bodies to its
logs.

## Recorder contract

The recorder accepts Sally 1.0.2 `iss` and `rev` callback shapes. Its HTTP
contract is deliberately small:

- `GET /health` returns `200` with `{"status":"healthy"}`.
- `POST /` accepts one Sally callback and returns `202` only after the record is
  flushed to disk.
- Any other route returns `404`; malformed or unsupported callbacks return
  `400` and are not recorded.

By default, JSONL is appended to `/proof/sally-callbacks.jsonl`. Compose mounts
the run's sanitized, retained proof directory at `/proof`. The path can be
changed with `QVI_PROOF_CALLBACKS_PATH` or `--output`; the named command
argument takes precedence. Bind address and port similarly use
`QVI_PROOF_HOOK_BIND`/`--bind` and `QVI_PROOF_HOOK_PORT`/`--port`. The service
must run with a UID and GID that can write the mounted proof directory.

```sh
python3 recorder.py \
  --output /private-run/proof/sally-callbacks.jsonl \
  --bind 0.0.0.0 \
  --port 9923
```

Only `receivedAt`, `action`, `actor`, the Sally `data` object, and duplicated
top-level `credential` and `schema` lookup keys are retained. Neither HTTP
headers nor request bodies are written to service logs. The JSONL file is
created with mode `0600`.

## Evidence CLI contract

The evidence CLI validates the exact callback associated with one workflow
action. The `--after` boundary must be captured immediately before submitting
the presentation. The active check is used independently for QVI, LE, and OOR
presentations:

```sh
python3 evidence.py active \
  --callbacks /private-run/proof/sally-callbacks.jsonl \
  --after 2026-01-01T00:00:00Z \
  --said ECredential \
  --schema ESchema \
  --holder EHolder \
  --issuer EIssuer
```

For a revoked OOR, `revoked-oor` requires both the exact structured `rev`
callback and Sally 1.0.2's timestamped rejection log for that credential:

```sh
python3 evidence.py revoked-oor \
  --callbacks /private-run/proof/sally-callbacks.jsonl \
  --logs /private-run/logs/direct-sally.log \
  --after 2026-01-01T00:00:00Z \
  --said EOorCredential \
  --schema EOorSchema \
  --issuer EQviIssuer \
  --revoked-at 2026-01-01T00:00:01.123456+00:00
```

`no-callback` fails if a post-boundary callback contains either the excluded
ECR schema or its credential SAID:

```sh
python3 evidence.py no-callback \
  --callbacks /private-run/proof/sally-callbacks.jsonl \
  --after 2026-01-01T00:00:00Z \
  --schema EEcrSchema \
  --said EEcrCredential
```

The workflow evaluates `no-callback` through a bounded post-ECR quiet interval;
one instantaneous empty read is not proof of continued absence.

Successful commands print exactly one JSON object with `ok: true` and a
sanitized `evidence` object. Evidence mismatch, absence, duplication, or
malformed input prints one `ok: false` JSON object to standard error and exits
nonzero. Argument errors also exit nonzero before reading evidence.

The revoked-credential log grammar is intentionally isolated to Sally 1.0.2.
Fixture tests protect that version-specific adapter from silently accepting a
different message.

Run the standard-library test suite with:

```sh
python3 -m unittest discover -s proof_hook/tests -v
```
