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

- KERIA 0.4.0;
- KERIpy 1.2.12 for KERIA and witnesses;
- HIO 0.6.14;
- KERIpy 1.1.32 for the current GAR/LAR KLI compatibility lane; and
- SignifyTS 0.4.0.

The host needs Node.js, npm, pyenv, uv, Git, curl, jq, and standard macOS
command-line tools. Python 3.12.6 must be available through pyenv.

## Run the complete proof

```bash
./vlei-workflow.sh --timeout 45
```

The 45-second operation deadline is a temporary reliability ceiling for the
working baseline, not an accepted performance target. The default remains 30
seconds while the local workflow is optimized toward a sub-180-second total.

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
