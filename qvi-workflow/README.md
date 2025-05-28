# vLEI QVI Workflow End to End Script Demonstration

The demonstration scripts in this directory are an illustration of the steps in the QVI qualification dry run process. This includes presenting a credential to Sally at the end of the process and Sally calling a webhook. 

There are three demonstrations:
1. `kli_only/vlei-workflow.sh` 
   - demonstrates the end-to-end workflow using keystores built by a local, non-containerized workflow using only the KLI (KERIpy).
2. `kli_docker/vlei-workflow.sh` 
   - demonstrates end-to-end workflow using a containerized setup for witnesses and KERIpy keystore manipulation using only the KLI (KERIpy).
3. `keria_kli/vlei-workflow.sh` 
   - demonstrates end-to-end workflow using KLI for the GAR parts and KERIA with SignifyTS for the QVI parts.
4. `keria_docker/vlei-workflow.sh` 
   - demonstrates end-to-end workflow using a containerized setup for witnesses, KERIA, vLEI-server, and KERIpy keystore manipulation. Uses KLI for the GAR parts and KERIA with SignifyTS for the QVI parts via NodeJS scripts.

## Dependencies

### For kli_only and keria_kli

- NodeJS - remember to do `npm install` in the `sig_ts_wallets` directory to install 
- [`tsx`](https://tsx.is/getting-started) - TypeScript Execute - for easily running Typescript files like a shell script.
  - This MUST be installed globally with `npm i -g tsx` in order to run properly.

### For kli_docker and keria_docker

- Docker - make sure you have Docker installed and running on your machine.

## TODOs

- [ ] Add multisig revoke to the script and present a revoked credential to Sally. See signify-ts/examples/integration-tests/multisig.test.ts

# Setup instructions 

## Debugging friendly setup (running everything locally)

These instructions show you how to run the end-to-end script demonstrations locally on your machine. This is useful for debugging using IDEs and log messages and understanding the process.

TBD. See the `kli_only` and `keria_kli` workflow scripts for examples of how to run the process locally.

## Integration-friendly setup (running everything in containers)

These instructions show you how to run the end-to-end script demonstrations using Docker containers. This is useful for integration testing and running the process in a more production-like environment.

TBD.See the `kli_docker` and `keria_docker` workflow scripts for examples of how to run the process in containers.
