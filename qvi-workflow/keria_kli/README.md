# Local execution adapter

This directory contains the local runtime and command adapter used by
`../vlei-workflow.sh`. It is not a separate workflow story.

## Bootstrap

```bash
cd qvi-workflow/keria_kli
./bootstrap-local.sh
```

Bootstrap creates the pinned Python environments and installs the locked
SignifyTS dependencies. The host needs Node.js, npm, pyenv, uv, Git, curl, jq,
and the standard macOS command-line tools. Python 3.12.6 must be available
through pyenv.

The local toolchain uses:

- local KERIA main at `86e21cbd`;
- GLEIF KERIpy 1.1.42 for GEDA KLI wallets;
- the local KERIpy `v1.2.14` branch for KERIA, witnesses, Sally, and remaining
  KLI wallets;
- Sally 1.0.5, HIO 0.6.19, and SignifyTS 0.4.0.

The bootstrap expects the normal multi-repository workspace layout. Override
`KERI_WORKSPACE_DIR` or the individual source-directory variables for another
layout.

## Run

Run the canonical driver from its parent directory:

```bash
cd ..
./vlei-workflow.sh --backend local
```

Generated state lives under `runtime/` only when `--keep-artifacts` is used.
All local witnesses, KERIA agencies, KLI/Signify runners, Sally, and the
callback recorder stop on success, failure, or interruption.

`stop-local.sh` remains a recovery tool for an interrupted process whose shell
could not execute its cleanup trap.
