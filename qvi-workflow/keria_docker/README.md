# KERIA and KLI Docker workflow

This is the isolated, fail-closed regression harness for the complete local
QVI story. Compose runs the witnesses, schema server, KERIA agents, direct
Sally verifier, KLI jobs, SignifyTS jobs, and callback recorder. KLI represents the
GARs and LARs; KERIA with SignifyTS represents the three QARs and the Person.

The default workflow proves protocol convergence and exact evidence. It does
not infer success from a process exit alone, fixed sleeps, notification routes,
cached webhook state, or human-readable success messages. The full contract is
documented in [`HARDENED-PROOF.md`](HARDENED-PROOF.md).

## Requirements and pins

- Docker with the Compose plugin
- Bash 3.2 or later
- `weboftrust/keria:0.4.0`
- `signify-ts@0.4.0`
- `gleif/sally:1.0.2`

The Signify runner is built from `../sig_ts_wallets` with `npm ci`. Host
Node.js and a globally installed `tsx` are not required.

Sally owns its own bootstrap lifecycle. On a fresh volume,
`sally server start` creates its Habery and no-witness identifier from the
protected runtime salt and inception configuration; on restart, it reopens
that same identifier. The workflow accepts the verifier as ready only after
its blind `/oobi` endpoint returns a valid `KERI-AID` header, and it asserts
that the prefix does not change when Sally restarts with the final GEDA
authorization prefix.

## Run the complete local story

From this directory:

```bash
./vlei-workflow.sh
```

The script resolves its own directory, so it can also be invoked from another
working directory.

Every invocation starts with a new private runtime and unique Compose project.
On success or failure, the default cleanup removes that project's containers,
volumes, network, keystores, generated data, and secret inputs. Sanitized proof
artifacts remain under `proofs/<run-id>/`.

### Options

```text
-t, --alternate       Present the LE credential to an alternate Sally
-s, --staging         Present the LE credential to GLEIF Staging Sally
-p, --production      Present the LE credential to GLEIF Production Sally
-a, --alias ALIAS     Alias for --alternate
-o, --oobi OOBI       OOBI URL for --alternate
    --timeout SECONDS Timeout for each bounded operation (default: 120)
    --keep-runtime    Preserve the private runtime and Compose stack
    --pause           Pause at story checkpoints
-h, --help            Display help
```

Alternate, staging, and production modes are explicit external presentation
paths. They are not substitutes for the default local proof and are excluded
from automated acceptance.

`--timeout` applies a positive per-operation deadline to polling, KERIA
operations, HTTP evidence, and detached jobs. `--keep-runtime` prints the exact
scoped `docker compose down --volumes --remove-orphans` command needed for
teardown. A retained runtime contains protected participant configuration and
must be treated as sensitive until it is removed. There is no
`--keystore-dir`, `--environment`, `--clear`, or `--debug` mode.

## What the proof covers

- Eight intended challenge relationships produce exactly 16 verified
  directions.
- The three QARs agree on the delegated QVI's prefix, delegator, members,
  sequence, establishment digest, and current and next thresholds.
- All consumers resolve exactly three endpoint-qualified
  `/oobi/<qvi-prefix>/agent/<eid>` URLs, built only after all QARs agree on the
  three authorized group EIDs and their member-agent endpoint locations. The
  workflow neither strips their suffixes nor fabricates a broad group URL.
- Only the QVI-issued OOR and ECR leaves are revoked. LE-issued OOR-Auth and
  ECR-Auth credentials remain active.
- Active QVI, LE, and OOR presentations require exact structured Sally
  callbacks.
- The revoked OOR requires both Sally's exact rejection log and its exact
  structured `rev` callback.
- ECR issuance, Person admission, and one common revocation TEL digest are
  proved across the QARs. No ECR is presented to Sally, and no ECR callback may
  appear.

Challenge words, salts, passcodes, and participant seed material are never
printed or retained. See
[`proof_hook/README.md`](proof_hook/README.md)
for the callback and Sally evidence adapters.

## Developer checks

Install and test the shared Signify package with its locked dependencies:

```bash
cd ../sig_ts_wallets
npm ci
npm ls signify-ts@0.4.0 --depth=0
npm run typecheck
npm test
```

Run the callback-recorder tests from `keria_docker`:

```bash
python3 -m unittest discover -s proof_hook/tests -v
```
