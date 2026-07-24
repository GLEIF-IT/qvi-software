# KERIA and KLI in local command line vLEI Workflow

This vlei-workflow.sh uses the local command line environment for both the KLI (KERIpy) setup of the GARs and LARs and KERIA setup for the QARs and Person.

The `sig_ts_wallets` directory contains the SignifyTS code used to act like a wallet for the QARs and Person.

## Usage

```bash
cd qvi-workflow/keria_kli
./vlei-workflow.sh
```

## Requirements

- Node.js
- The locked `sig_ts_wallets` dependencies, including
  `signify-ts@0.4.0` and the project-local `tsx` executable:

  ```bash
  cd ../sig_ts_wallets
  npm ci
  export PATH="$PWD/node_modules/.bin:$PATH"
  cd ../keria_kli
  ```

  A global `tsx` installation is not required.
- KERIpy installed globally - version weboftrust/keripy:1.1.32
    - then run `kli witness demo` in one terminal
- The Sally presentation handler program installed globally - version GLEIF-IT/sally:1.0.0
    - The script runs direct `sally server start` automatically. Sally owns
      keystore initialization and no-witness identifier inception.
- The vLEI-server schema server from the vLEI repo running in another terminal:
    - `vLEI-server -s ./schema/acdc -c ./samples/acdc/ -o ./samples/oobis/`
- The KERIA 0.4.0 command installed globally and running in another terminal
    - `keria start --config-dir scripts --config-file keria --loglevel INFO`

The workflow keeps Signify participant material in the mode-`0600`
`qvi_data/participants.json` file and resolves all three endpoint-qualified
QVI agent OOBIs produced by the shared Signify runner.

This local hybrid workflow does not produce the hardened proof manifest
described by `keria_docker/HARDENED-PROOF.md`.
