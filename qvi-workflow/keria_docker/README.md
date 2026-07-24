# KLI, KERIA, SignifyTS, and Sally QVI workflow

This is a public, one-run-at-a-time interoperability demonstration for the
complete QVI story. Docker Compose runs:

- KERIpy witnesses and KLI jobs for the GARs and LARs;
- three KERIA agents and SignifyTS wallets for the QARs and Person;
- the vLEI schema server;
- direct-mode Sally; and
- a small webhook that records Sally callbacks.

The workflow favors visible commands, deterministic demo identities, and
console output that a developer can follow. It keeps the protocol checks that
distinguish working interoperability from a command that merely exited zero.

## Versions

- `weboftrust/keria:0.4.0`
- `signify-ts@0.4.0`
- `gleif/sally:1.0.2`
- `weboftrust/keri:1.1.32` and `gleif/keri:1.2.9` for the KLI lanes

The Signify image installs the locked Node dependencies with `npm ci`. A host
Node.js installation is not required for the Docker workflow.

## Public demo configuration

[`keria-signify-docker.env`](keria-signify-docker.env) contains the participant
names, salts, passcodes, schema identifiers, and other values used by the
demonstration. These are public test fixtures, not secrets.

To run with different identities, copy the file, edit the copy, and point the
workflow at it:

```bash
cp keria-signify-docker.env my-qvi-demo.env
QVI_WORKFLOW_ENV_FILE="$PWD/my-qvi-demo.env" ./vlei-workflow.sh
```

Fresh identities are recommended when presenting to an external staging,
production, or alternate Sally so an earlier run cannot conflict with the
history you are creating.

## Run the story

```bash
cd qvi-workflow/keria_docker
./vlei-workflow.sh
```

The script also works from another current directory because it resolves its
own location.

Each invocation first runs `docker compose down -v --remove-orphans`, replaces
`runtime/`, and starts the Compose stack. A normal exit tears down the stack
and removes `runtime/`. On failure, recent Compose and detached-job logs are
printed before cleanup.

Use `--keep-runtime` to leave the stack and ordinary `runtime/` directory in
place for inspection:

```bash
./vlei-workflow.sh --keep-runtime
docker compose \
  --env-file keria-signify-docker.env \
  -f docker-compose-keria_signify_qvi.yaml \
  ps
```

The next invocation clears the retained stack and runtime automatically.

### Options

```text
-t, --alternate       Present the LE credential to an alternate Sally
-s, --staging         Present the LE credential to GLEIF Staging Sally
-p, --production      Present the LE credential to GLEIF Production Sally
-a, --alias ALIAS     Alias for --alternate
-o, --oobi OOBI       OOBI URL for --alternate
    --timeout SECONDS Timeout for each bounded operation (default: 120)
    --keep-runtime    Preserve runtime/ and the Compose stack
    --pause           Pause at story checkpoints
-h, --help            Display help
```

## Story sequence

1. Sally starts its own Habery and identifier through `sally server start`.
2. GAR, LAR, QAR, and Person identifiers are created and exchange OOBIs.
3. The driver performs both directions of eight useful challenge
   relationships: GAR1-GAR2, LAR1-LAR2, the three QAR pairs, GAR1-QAR1,
   QAR1-LAR1, and QAR1-Person. All 16 response-and-verification commands must
   succeed.
4. The GARs create the GEDA. The three QARs create the delegated QVI and
   authorize its three KERIA agent endpoints.
5. The workflow issues and admits the QVI and LE credentials, then presents
   both to Sally.
6. The LE issues OOR-Auth; the QVI issues OOR to the Person. The Person admits
   and presents the active OOR.
7. The QVI revokes the OOR. All three QARs must observe status sequence `1`
   and the same TEL digest. Sally must log the rejected revoked credential and
   send the matching `rev` callback.
8. The LE issues ECR-Auth; the QVI issues ECR to the Person. The Person admits
   it, then all three QARs converge on the ECR revocation.

Sally 1.0.2 does not support the ECR reporting story, so this workflow does not
present ECR. It simply ends that branch after admission and converged
revocation. OOR-Auth and ECR-Auth remain active because the QVI did not issue
them.

Useful console milestones include the 16 successful challenge directions, the
delegated QVI prefix and canonical OOBI, credential SAIDs, Sally callback
messages, and common OOR/ECR revocation TEL digests.

## Code structure

The TypeScript is intentionally split by responsibility so it can double as a
readable SignifyTS example:

- wallet actions call SignifyTS and return what KERIA actually produced;
- `multisig-coordinator.ts` assigns member roles, sends member exchanges,
  correlates follower notifications, and completes member operations;
- `group-state.ts` and `credential-state.ts` observe wallet state without
  deciding what this demonstration expects; and
- the `qars-assert-*.ts` and `person-assert-*.ts` runners contain the
  demonstration's expectations.

The Bash story keeps those boundaries visible. It runs an action and then
runs the corresponding assertion as a separate command. Core wallet functions
therefore do not accept test-only arguments such as an expected schema,
issuee, issuer, threshold, or status.

## Runtime layout

With `--keep-runtime`, the generated files are deliberately easy to find:

```text
runtime/
├── acdc-info/
├── config/
├── jobs/
├── keystores/
├── logs/
├── qvi_data/
└── sally-callbacks.jsonl
```

The callback recorder accepts a JSON object at `POST /`, adds a receipt
timestamp, and appends it to `sally-callbacks.jsonl`. See
[`callback_recorder/README.md`](callback_recorder/README.md).

## Developer checks

```bash
cd ../sig_ts_wallets
npm ci
npm ls signify-ts@0.4.0 --depth=0
npm run typecheck
npm test

cd ../keria_docker
python3 -m unittest discover -s callback_recorder/tests -v
docker compose \
  --env-file keria-signify-docker.env \
  -f docker-compose-keria_signify_qvi.yaml \
  config --quiet
```
