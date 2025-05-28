# KERIA and KLI in Docker vLEI Workflow

This vlei-workflow.sh uses Docker containers for both the KLI (KERIpy) setup of the GARs and LARs and the KERIA setup for the QARs and Person.

The `sig_ts_wallets` directory contains the SignifyTS code used to act like a wallet for the QARs and Person.

## Usage

```bash
cd qvi-workflow/keria_docker
./vlei-workflow.sh
```

## Requirements

- Docker installed and running
- Docker Compose
