# KLI Delegator to KERIA Signify Delegates

This regression proves that a KERIpy KLI 2-of-2 GEDA delegator can approve
delegated inception for two KERIA-managed QVI groups:

- a three-member weighted 2-of-3 SignifyPy delegate
- a three-member weighted 2-of-3 SignifyTS delegate

It verifies that every member observes the same delegated identifier prefix,
GEDA delegator, inception sequence, and `["1/2", "1/2", "1/2"]` current and
next thresholds. It does not test completing an operation with one member
offline.

## Run

```bash
cd test-scripts/keria-signify-delegation
./version-compat.sh
```

Every invocation removes prior containers, volumes, and generated state before
starting. Preserve the completed stack and artifacts for inspection with:

```bash
./version-compat.sh --keep-artifacts
```

The default version matrix is:

- `weboftrust/keri:1.2.13`
- `weboftrust/keria:0.4.0`
- `signify-ts@0.4.0`
- `signifypy==0.4.2`

The KERI and KERIA image names and tags can be overridden with `KERI_IMAGE`,
`KERI_IMAGE_TAG`, `KERIA_IMAGE`, and `KERIA_IMAGE_TAG`.

Generated state is isolated in the ignored `docker-keystores/`, `events/`, and
`qvi-data/` directories. Witness and KERIA config mounts remain writable
because KERI Configer requires write access at the stock image paths.
