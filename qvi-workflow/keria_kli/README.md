# KERIA and KLI in local command line vLEI Workflow

This vlei-workflow.sh uses the local command line environment for both the KLI (KERIpy) setup of the GARs and LARs and KERIA setup for the QARs and Person.

The `sig_ts_wallets` directory contains the SignifyTS code used to act like a wallet for the QARs and Person.

## Usage

```bash
cd qvi-workflow/keria_kli
./vlei-workflow.sh
```

## Requirements

- NodeJS - remember to do `npm install` in the `sig_ts_wallets` directory to install 
- [`tsx`](https://tsx.is/getting-started) - TypeScript Execute - for easily running Typescript files like a shell script.
  - This MUST be installed globally with `npm i -g tsx` in order to run properly.
- KERIpy installed globally - version weboftrust/keripy:1.1.32
    - then run `kli witness demo` in one terminal
- The Sally presentation handler program installed globally - version GLEIF-IT/sally:1.0.0
    - The script will run the `sally server start` command automatically at the appropriate time. 
- The vLEI-server schema server from the vLEI repo running in another terminal:
    - `vLEI-server -s ./schema/acdc -c ./samples/acdc/ -o ./samples/oobis/`
- The KERIA command installed globally and running in another terminal - version gleif/keria:0.3.0
    - `keria start --config-dir scripts --config-file keria --loglevel INFO`
