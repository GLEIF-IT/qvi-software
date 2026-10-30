# Docker execution adapter

This directory contains the Docker Compose runtime and command adapter used by
`../vlei-workflow.sh`. It is not a separate workflow story.

Compose runs one witness-demo service, four QAR KERIA agencies, the Person
agency, persistent KLI and Signify command runners, the vLEI schema server,
direct-mode Sally, and the callback recorder. One witness process hosts every
witness required by the shared story.

## Versions and fixtures

- `weboftrust/keria:0.4.0`
- `signify-ts@0.4.0`
- `gleif/sally:1.0.5`
- `weboftrust/keri:1.1.32` for KLI
- `gleif/keri:1.2.9` for witnesses

`keria-signify-docker.env` contains deterministic public demonstration
identities, passcodes, schemas, and runtime values. They are fixtures, not
production secrets.

## Run

```bash
cd qvi-workflow
./vlei-workflow.sh
```

Docker is the default backend. Each fresh run removes the previous disposable
Compose state and recreates `keria_docker/runtime/`. Containers always stop at
exit.

With `--keep-artifacts`, the visible runtime directory and named KLI state
volume survive teardown for inspection or a later external LE presentation:

```bash
./vlei-workflow.sh --keep-artifacts
./present-external-le.sh \
  --backend docker \
  --artifacts "$PWD/keria_docker/runtime" \
  --alias external-sally \
  --oobi 'https://example.test/oobi/...'
```

The next canonical run removes the old retained volumes before creating clean
state.

## Runtime layout

```text
runtime/
├── acdc-info/
├── backend.json
├── config/
├── logs/
├── qvi_data/
├── le-issuance.json
├── oor-issuance.json
└── sally-callbacks.jsonl
```

KLI LMDB stays in the named Docker volume
`qvi-workflow-keria-docker_kli-vol`, avoiding macOS VirtioFS for database
files. Job stdout and stderr are retained as ordinary files under `logs/`.

Validate the adapter with:

```bash
docker compose \
  --project-name qvi-workflow-keria-docker \
  --project-directory . \
  --env-file keria-signify-docker.env \
  -f docker-compose-keria_signify_qvi.yaml \
  config --quiet
```
