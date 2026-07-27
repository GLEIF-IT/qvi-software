# Fully local KERIA and KLI vLEI workflow

This workflow runs the complete GEDA → QVI → LE → OOR/ECR holder → Sally →
callback-recorder story directly on the host. It uses KLI for the GAR and LAR
participants, isolated KERIA agencies for the QARs and Person, and SignifyTS as
their wallet client.

All generated KERI state, service configuration, logs, results, and timings
live under `runtime/`. The workflow manages its own witnesses, vLEI schema
server, KERIA agencies, Sally, and callback recorder.

## Bootstrap

The bootstrap script creates pinned virtual environments and installs the
locked SignifyTS dependencies:

```bash
cd qvi-workflow/keria_kli
./bootstrap-local.sh
```

The local toolchain uses:

- local KERIA main at `86e21cbd` (package version 0.4.1);
- GLEIF KERIpy 1.1.42 for the GEDA KLI wallets;
- the local KERIpy `v1.2.14` branch for KERIA, witnesses, Sally, and the
  remaining KLI wallets;
- Sally 1.0.5 from PyPI;
- HIO 0.6.19;
- SignifyTS 0.4.0.

The `v1.2.14` branch currently reports package version 1.2.13. Bootstrap and
preflight therefore verify its source checkout, not that stale metadata value.
The bootstrap expects the standard multi-repository layout rooted four
directories above this workflow. Override `KERI_WORKSPACE_DIR` or the
individual `GEDA_KERIPY_DIR`, `LOCAL_KERIPY_DIR`, and `LOCAL_KERIA_DIR`
variables when the source checkouts use another layout.

The host needs Node.js, npm, pyenv, uv, Git, curl, jq, and standard macOS
command-line tools. Python 3.12.6 must be available through pyenv.

## Run the complete proof

```bash
./vlei-workflow.sh --timeout 8
```

The eight-second operation deadline intentionally exposes local paths that
miss the expected low-latency envelope. It is not increased merely to hide a
slow poll, replay, or escrow path.

The canonical run proves:

- all 16 directed challenge responses across eight relationships;
- delegated QVI inception and rotations through sequences 0–3, ending with
  QAR1, QAR2, and QAR4;
- issuance and admission of QVI, LE, OOR-Auth, ECR-Auth, OOR, and ECR
  credentials;
- active QVI, LE, and OOR presentations to Sally;
- converged QVI revocation of OOR and ECR; and
- Sally's rejected revoked-OOR presentation and `rev` callback.

Useful controls are `--timeout SECONDS`, `--stop-after PHASE`,
`--keep-runtime`, and `--pause`. Run `./vlei-workflow.sh --help` for the full
phase list and presentation modes.

Pressing Ctrl+C sends SIGINT through the managed process trees so HIO-based
services receive their normal `KeyboardInterrupt` cleanup. Normal completion
also removes the isolated runtime. To stop processes retained with
`--keep-runtime`, run:

```bash
./stop-local.sh
```
