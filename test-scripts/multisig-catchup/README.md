# Multisig Joiner Export/Ingest Harness

This directory contains a KERIpy KLI compatibility harness for late multisig
joiners that need historical registry TEL and ACDC material.

It lives under `test-scripts/` because it is a regression and stress harness,
not the full QVI qualification workflow. It uses the QVI credential schema, but
does not run Sally, SignifyTS, KERIA, or the `qvi-workflow/` scripts.

## Prerequisites

- A KERIpy branch whose globally installed `kli` includes `kli import --cesr-in`.
- `jq` on `PATH`.
- `kli witness demo` running in another terminal.
- A vLEI schema server running from the vLEI repo root:

```bash
vLEI-server -s ./schema/acdc -c ./samples/acdc/ -o ./samples/oobis/
```

## Usage

From the qvi-software repository root:

```bash
test-scripts/multisig-catchup/run-multisig-catchup.sh --keep-artifacts
```

Stress mode:

```bash
test-scripts/multisig-catchup/run-multisig-catchup.sh --stress-chain --keep-artifacts
```

You can also run from inside this directory:

```bash
./run-multisig-catchup.sh --keep-artifacts
```

Set `AUTO=1`, `CI=1`, or `NONINTERACTIVE=1` to skip the readiness prompt.

## Scenarios

Default mode creates an m1/m2 multisig group, registry `r1`, and one QVI-schema
ACDC. Member m3 joins later, proves it cannot initially see `r1` or the prior
credential, ingests m1's CESR export with `kli import --cesr-in`, renames the
imported registry, verifies visibility, and leads a revocation.

On success, default mode completes the m3 post-ingest visibility and revocation
checks and ends with:

```text
=== SCRIPT COMPLETE ===
```

Stress mode runs A-F membership churn. New joiners ingest current material,
operate on prior registries and credentials, create new registries and
credentials, and continue after original members have been removed. A successful
stress run ends with:

```text
=== STRESS CHAIN SCRIPT COMPLETE ===
```

It should not continue into the default m3 post-ingest checks.

## State And Cleanup

The runner writes generated JSON configs and CESR bundles into a temporary
artifact directory. It creates script-owned KLI stores under
`~/.keri/{ks,db,reg,cf}/base-*` and removes those stores during cleanup.

Use `--keep-artifacts` to preserve logs, generated configs, and CESR bundles for
debugging. Keystore cleanup still targets only this script's `base-*` stores.
