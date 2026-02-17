# Delegation Compatibility Test (KLI + Docker)

This test validates multisig delegation compatibility between:

- GLEIF side: `gleif/keri:1.1.42`
- QVI side: `gleif/keri:1.2.11`
- Witnesses: `gleif/keri:1.2.11`

Scope is intentionally narrow: only delegated multisig inception for QVI from GLEIF's GEDA.
No KERIA, no SignifyTS, no credential issuance.

## Files

- `run-delegation-test.sh` - main test runner
- `kli-commands.sh` - versioned KLI wrappers for GLEIF and QVI
- `docker-compose-delegation-compat.yaml` - witness stack

## Usage

```bash
cd test-scripts/delegation-compat
./run-delegation-test.sh
```

Optional:

```bash
./run-delegation-test.sh /tmp/delegation-keystores --keep-artifacts --verbose
```

Flags:

- `--keep-artifacts` keep containers, volumes, and keystore files for inspection
- `--verbose` print detached container logs for multisig/delegation sub-steps

## Expected Result

On success, output ends with:

```text
PASS: QVI multisig delegation from GLEIF succeeded (1.2.11 <- 1.1.42)
```
