# Delegation Compatibility Test (KLI + Docker)

This test validates multisig delegation compatibility between:

- GLEIF side: `gleif/keri:1.1.42`
- QVI side: `gleif/keri:1.2.11`
- Witnesses: `gleif/keri:1.2.11`

Scope includes delegated multisig inception and two delegated multisig rotation approval workflows for QVI from GLEIF's GEDA:

- delegate `multisig rotate + multisig join` + delegator `kli delegate confirm`
- delegate `multisig rotate + multisig join` + delegator `kli multisig interact` with delegated rotation seal data (`i/s/d`)

After each delegated rotation approval, both multisig identifiers (`qvi` and `geda`) run a multisig interaction event with arbitrary `a` data to confirm they continue to function correctly.

No KERIA, no SignifyTS, no credential issuance.

## Files

- `run-delegation-test.sh` - main test runner
- `kli-commands.sh` - versioned KLI wrappers for GLEIF and QVI
- `docker-compose-delegation-compat.yaml` - witness stack
- `events/` - runtime event artifacts (delegated rotation anchor seal JSON)

## Usage

```bash
cd test-scripts/delegation-compat
./run-delegation-test.sh
```

Optional:

```bash
./run-delegation-test.sh /tmp/delegation-keystores --keep-artifacts --verbose
```

Rotate/join isolation mode:

```bash
./run-delegation-test.sh --rotate-join-only --log-level debug
```

Flags:

- `--keep-artifacts` keep containers, volumes, and keystore files for inspection
- `--verbose` compatibility alias for `--log-level debug`
- `--log-level <quiet|normal|debug|trace>` controls container log detail
- `--rotate-join-only` runs only delegated `multisig rotate + multisig join` after common setup
- `--clear` ignore/remove saved checkpoint and rebuild common setup from scratch

Checkpoint behavior:

- After common setup (GEDA + delegated QVI multisig), the script saves a checkpoint in `checkpoints/`
- The checkpoint now includes both:
  - keystore state (`keystores.tar.gz`)
  - witness volume state (`witness-volume.tar.gz`)
- On later runs, if checkpoint files + metadata are valid, both keystore and witness state are restored together
- Use `--clear` to force a fresh setup and checkpoint rewrite

Script layout:

- `run-delegation-test.sh`: delegation workflows and test orchestration
- `lib/context-setup.sh`: dependencies, runtime folders, stack bootstrap
- `lib/keri-setup.sh`: AID/OOBI setup and common baseline construction
- `lib/container-processes.sh`: detached container waits, timeout handling, join orchestration
- `lib/checkpointing.sh`: checkpoint save/restore/validation
- `lib/logging.sh`: log levels, diagnostics, trace log streaming

## Expected Result

On success, output ends with:

```text
PASS: QVI delegated multisig rotation approval succeeded with delegate confirm and multisig interact (1.2.11 <- 1.1.42)
```
