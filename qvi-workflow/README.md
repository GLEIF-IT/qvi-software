# End-to-end vLEI QVI workflows

This directory contains five implementations of the QVI qualification story:

1. `kli_only/vlei-workflow.sh` uses local KERIpy keystores for every
   participant.
2. `kli_docker/vlei-workflow.sh` runs the KLI-only story with containerized
   witnesses and KERIpy jobs.
3. `keria_kli/vlei-workflow.sh` uses local KLI processes for the GAR and LAR
   participants and KERIA with SignifyTS for the QARs and Person.
4. `keria_docker/vlei-workflow.sh` runs the complete KLI/KERIA story in Docker
   Compose.
5. `single-sig/vlei-workflow.sh` is a focused compatibility workflow with
   single-signature GEDA, QVI, and LE identifiers.

These are public interoperability demonstrations. They intentionally expose
the commands and deterministic fixture data so developers can understand how
KLI, KERIA, SignifyTS, and Sally fit together.

Local reporting uses direct Sally only.

## Docker QVI story

The `keria_docker` workflow demonstrates:

- 16 successful directed challenge responses across eight useful
  relationships;
- convergence of the three-member delegated QVI, its thresholds, member sets,
  establishment state, endpoint roles, and canonical multisig OOBI;
- issuance, admission, and Sally presentation of the QVI, LE, and active OOR
  credentials;
- common three-QAR TEL state after the QVI revokes its OOR and ECR leaves; and
- Sally's revoked-OOR rejection and revocation callback.

The QVI revokes only credentials it issued. The LE-issued OOR-Auth and
ECR-Auth credentials remain active. Sally 1.0.2 does not support ECR
reporting, so the ECR branch ends after Person admission and converged
revocation.

See [`keria_docker/README.md`](keria_docker/README.md) for the tutorial,
configuration, runtime layout, and commands.

## Dependencies

The containerized workflows require Docker with the Compose plugin.
`keria_docker` builds its Signify runner with `npm ci`; it does not require a
host Node.js installation or a globally installed `tsx`.

The local `keria_kli` workflow requires Node.js and the dependencies installed
from `sig_ts_wallets/package-lock.json`. Its README describes how to use the
project-local `tsx` executable.

Each workflow has additional version and service requirements in its own
README.
