# KERIA and KLI in Docker vLEI Workflow

This vlei-workflow.sh uses Docker containers for both the KLI (KERIpy) setup of the GARs and LARs and the KERIA setup for the QARs and Person.

The `sig_ts_wallets` directory contains the SignifyTS code used to act like a wallet for the QARs and Person.

## Story proof

The workflow performs mutual 128-bit challenge responses for GAR1-GAR2,
LAR1-LAR2, all three QAR pairs, GAR1-QAR1, QAR1-LAR1, and QAR1-Person. These
eight trust relationships produce exactly 16 directed responses.

Only credentials issued by the QVI are revoked here: the OOR and ECR leaves.
The LE-issued OOR-Auth and ECR-Auth credentials are outside the QVI's
revocation authority. The Person presents the active OOR once; after the QARs
revoke it, the QVI presents it so direct Sally receives the current KEL/TEL.
Success requires Sally's explicit revoked-credential rejection and its OOR
revocation report action.

Sally 1.0.2 does not support ECR reporting, so no active or revoked ECR is
presented to Sally. The ECR story ends after issuance, Person admission, and
revocation status `1` convergence on all three QARs.

## Usage

```bash
cd qvi-workflow/keria_docker
./vlei-workflow.sh
```

## Requirements

- Docker installed and running
- Docker Compose
