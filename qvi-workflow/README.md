# End-to-end vLEI QVI workflows

This directory contains five implementations of the QVI qualification story:

1. `kli_only/vlei-workflow.sh` uses local KERIpy keystores for every
   participant.
2. `kli_docker/vlei-workflow.sh` runs the KLI-only story with containerized
   witnesses and KERIpy jobs.
3. `keria_kli/vlei-workflow.sh` uses local KLI processes for the GAR and LAR
   participants and KERIA with SignifyTS for the QARs and Person.
4. `keria_docker/vlei-workflow.sh` runs the complete KLI/KERIA story in an
   isolated Compose project.
5. `single-sig/vlei-workflow.sh` is a focused compatibility workflow with
   single-signature GEDA, QVI, and LE identifiers.

The implementations are demonstrations with different dependency and proof
boundaries. The hardened regression harness is `keria_docker`; do not assume
that the other four workflows produce the same evidence.

Local reporting uses direct Sally only.

## Hardened Docker workflow

The default `keria_docker` workflow proves:

- the exact 16 challenge directions derived from eight intended trust
  relationships;
- convergence of the three-member delegated QVI and its thresholds, member
  sets, and establishment state;
- discovery and resolution of all three endpoint-qualified QVI agent OOBIs;
- exact identity and TEL convergence for the QVI-issued OOR and ECR leaves;
- active QVI, LE, and OOR callbacks from Sally;
- both Sally's rejection and its structured revocation report for the revoked
  OOR; and
- the absence of any ECR presentation or Sally callback.

The QVI revokes only credentials it issued. The LE-issued OOR-Auth and ECR-Auth
credentials remain active.

See
[`keria_docker/README.md`](keria_docker/README.md)
for usage and
[`keria_docker/HARDENED-PROOF.md`](keria_docker/HARDENED-PROOF.md)
for the evidence contract.

## Dependencies

The containerized workflows require Docker with the Compose plugin.
`keria_docker` builds its Signify runner with `npm ci`; it does not require a
host Node.js installation or a globally installed `tsx`.

The local `keria_kli` workflow requires Node.js and the dependencies installed
from `sig_ts_wallets/package-lock.json`. Its README describes how to expose the
project-local `tsx` executable without installing it globally.

Each workflow has additional version and service requirements in its own
README.
