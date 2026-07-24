# Single Signature Workflow

This uses single signature GEDA, QVI, and LE identifiers, simplifying the workflow, to focus on testing of delegation, credential issuance, presentation, and revocation.

## Required or supported versions

- Docker with the Compose plugin
- `weboftrust/keria:0.4.0`
- `signify-ts@0.4.0`

The shared Signify runner installs its exact dependencies from
`sig_ts_wallets/package-lock.json` with `npm ci`.

This simplified workflow is a compatibility story with one delegated QVI
instead of the three-member QVI used by `keria_docker`. Its delegated QVI OOBI
remains endpoint-qualified; the runner does not strip the `/agent/{eid}` path.

The workflow uses direct-mode Sally. Sally owns its keystore bootstrap and
identifier inception through `sally server start`.
