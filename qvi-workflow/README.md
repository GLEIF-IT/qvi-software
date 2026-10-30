# QVI interoperability workflow

`vlei-workflow.sh` is the one supported KLI/KERIA/SignifyTS workflow driver.
Docker is the portable default; the local backend is the fast development and
acceptance path.

```bash
cd qvi-workflow
./vlei-workflow.sh
./vlei-workflow.sh --backend local
```

Both backends run the same protocol phases and assertions. The adapters own
only dependency validation, service lifecycle, KLI and Signify command
execution, and backend logs.

## Scenarios

The default `canonical` scenario proves:

- four bidirectional challenge relationships: GAR1-GAR2, QAR1-QAR2,
  GAR1-QAR1, and QAR1-LAR1;
- delegated QVI inception followed by one same-roster multisig key rotation,
  including a key rotation by QAR1, QAR2, and QAR3;
- QVI and LE issuance, admission, and Sally presentation;
- OOR authorization, issuance, admission, and active Sally reporting; and
- OOR revocation, holder convergence, rejected revoked presentation, and the
  revocation callback.

The ordinary rotation leaves the QVI at sequence 1 with QAR1, QAR2, and QAR3.
It is the required rotation proof, not preparation for a membership change.

Two focused regression scenarios reuse the shared setup:

```bash
./vlei-workflow.sh --backend local --scenario ecr-regression
./vlei-workflow.sh --backend local --scenario qar-replacement-regression
```

`ecr-regression` proves ECR authorization, issuance, admission, revocation, and
TEL convergence. `qar-replacement-regression` carries the more expensive
QAR3-to-QAR4 replacement through sequences 2 and 3. QAR3 remains endpoint
authorized and resolvable after replacement but no longer signs.

## Options and artifacts

```text
--backend docker|local
--scenario canonical|ecr-regression|qar-replacement-regression
--timeout SECONDS
--stop-after setup|delegation|qvi-credential|le-credential|le-presentation|leaf-lifecycle
--keep-artifacts
--pause
```

Services and jobs always stop. `--keep-artifacts` preserves runtime state,
domain result JSON, callbacks, and per-job logs. Without it, the backend
removes the disposable runtime and state.

To present an already-issued LE credential to an external Sally, first keep a
canonical run and then use the standalone utility:

```bash
./vlei-workflow.sh --backend local --keep-artifacts
./present-external-le.sh \
  --backend local \
  --artifacts "$PWD/keria_kli/runtime" \
  --alias external-sally \
  --oobi 'https://example.test/oobi/...'
```

The utility starts only the retained run's required KLI/witness services and
always stops them. It has no staging, production, or baked-in remote target.

## Implementation shape

- `vlei-workflow.sh` owns phase order and fixed actor-disjoint waves.
- `backends/` contains the local and Docker execution adapters.
- `lib/jobs.sh` owns named jobs, common deadlines, fail-fast cancellation,
  process-tree termination, and log replay.
- `sig_ts_wallets/src/notifications.ts` owns exact notification correlation.
- `multisig-coordinator.ts` owns initiator-first member execution and serial
  notification consumption.
- `multisig.ts` owns group inception, rotation, and join events.
- `credential-mutations.ts` owns registry and TEL state mutations.
- `ipex.ts` owns grants and admissions.

The older `kli_only`, `kli_docker`, and `single-sig` examples are independent
historical demonstrations. They are not alternate backends for this driver.

## Checks

```bash
cd sig_ts_wallets
npm run typecheck
npm test

cd ..
bash -n \
  vlei-workflow.sh present-external-le.sh lib/jobs.sh \
  backends/local.sh backends/docker.sh \
  keria_kli/lib/workflow-runtime.sh keria_docker/lib/workflow-runtime.sh
```
