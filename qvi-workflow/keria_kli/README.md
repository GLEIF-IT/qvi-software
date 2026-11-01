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

- local KERIA `tocks-build-out` at base `86e21cbd`;
- GLEIF KERIpy 1.1.42 for GEDA KLI wallets;
- the local KERIpy `tocks-build-out` branch, targeting `v1.2.14`, for KERIA,
  witnesses, Sally, and remaining KLI wallets;
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

## Scheduler configuration

`config/tocks.json` is the local workflow's centralized scheduler
configuration. Runtime generation copies its direct KERIpy keys into KLI,
witness, and Sally configuration and copies the full structure, including
`tocks.signify`, into each KERIA Agency configuration. KERIA resolves the
process snapshot before it accepts requests and does not persist it in Agent
configuration.

KLI commands are separate processes. Because `kli init --config-file` imports
bootstrap data but does not retain that source path, runtime generation also
writes a scheduler-only config at each KLI wallet's normal persistent Configer
path. Every later command therefore resolves the same direct snapshot when it
reopens the Habery.

All local workflow cadences are `0.03125` seconds except the explicit
`tocks.signify.initer` value `0.0`. The workflow also sets
`KERIA_ESCROWER_TOCK=0.0`; its preflight check proves that this environment
value overrides the configured `0.03125` without losing explicit zero. Values
may be any finite non-negative number, including zero and values below
`1/32`; invalid values and unknown keys fail startup.

KERIpy's library defaults are `0.0` for historically doified loops, `0.25`
for `pollerIdle`, and independently `0.5` for `counselorEscrow`,
`registrarEscrow`, and `credentialerEscrow`. Signify scheduler defaults are
`0.0`. Direct settings use their matching `KERI_*_TOCK` environment variable;
Signify settings use the established `KERIA_*_TOCK` names documented by
KERIA.

The `pollerEvent`/`KERI_POLLER_EVENT_TOCK` and
`vdrEscrow`/`KERI_VDR_ESCROW_TOCK` aliases are accepted by the new KERIpy
release and its following release, then removed in the next release. Flat
KERIA scheduler keys remain accepted for one release before
`tocks.signify` becomes the only form. This workflow uses neither deprecated
form with the new runtime. Its isolated KERIpy 1.1.42 GEDA process still uses
those names as that legacy branch's canonical configuration interface.
