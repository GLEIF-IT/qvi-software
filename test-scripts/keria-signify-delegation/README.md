# KLI Delegator to KERIA Signify Delegate

This test proves:
- v1.2.13 KERIpy multisig delegator (2 of 2) delegator
- v0.4.0 KERIA multisig delegates (2 of 3), which also uses KERIpy 1.2.13

works for delegation.

## Running The Script

```bash
cd test-scripts/keria-signify-delegation
./version-compat.sh --clear
```

## What it does
It shows a 2-of-2 multisig KERIpy KLI GEDA delegator approving delegated inception for 
two KERIA-managed multisig delegates with both SignifyTS and SignifyPy:

- a 3-member SignifyTS QVI delegate
- a 3-member SignifyPy QVI delegate

The KLI and witness side is pinned by Docker to `weboftrust/keri:1.2.13`.
KERIA is pinned to `weboftrust/keria:0.4.0`. SignifyTS is installed from npm as
`signify-ts@0.4.0`. SignifyPy is installed from PyPI as `signifypy==0.4.2`.

Supported overrides:

- `KERI_IMAGE`, `KERI_IMAGE_TAG`
- `KERIA_IMAGE`, `KERIA_IMAGE_TAG`

The witness and KERIA config mounts are intentionally writable because KERI
Configer needs write access to load these configs in the container paths used by
the stock images.

Runtime state is isolated under this directory and ignored by git:

- `docker-keystores/`
- `events/`
- `qvi-data/`
- compose volumes owned by Docker Compose
