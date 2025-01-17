# vLEI QVI Workflow End to End Script Demonstration

The demonstration scripts in this directory are an illustration of the steps in the QVI qualification dry run process. This includes presenting a credential to Sally at the end of the process and Sally calling a webhook. 

There are three demonstrations:
1. `qvi-workflow-kli.sh` - demonstrates the end-to-end workflow using keystores built by a local, non-containerized workflow using only the KLI (KERIpy).
2. `qvi-workflow-kli-docker.sh` - demonstrates end-to-end workflow using a containerized setup for witnesses and KERIpy keystore manipulation using only the KLI (KERIpy).
3. `qvi-workflow-keri_signify_qvi.sh` - demonstrates end-to-end workflow using KLI for the GAR parts and KERIA with SignifyTS for the QVI parts.
4. `qvi-workflow-keri_signify_qvi-docker.sh` (WIP) - demonstrates end-to-end workflow using a containerized setup for witnesses, KERIA, vLEI-server, and KERIpy keystore manipulation. Uses KLI for the GAR parts and KERIA with SignifyTS for the QVI parts via NodeJS scripts.

## Dependencies

- NodeJS - remember to do `npm install` in the `full` directory to install 
- [`tsx`](https://tsx.is/getting-started) - TypeScript Execute - for easily running Typescript files like a shell script.
  - This MUST be installed globally with `npm i -g tsx` in order to run properly.

## TODOs

- [ ] Add sample log output of the end-to-end scripts so people running the process can see what to expect.