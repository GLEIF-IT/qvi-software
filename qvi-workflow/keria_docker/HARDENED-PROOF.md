# Hardened QVI workflow proof contract

This document defines what a successful default `keria_docker` run proves.
The workflow is a fail-closed regression harness: a command completing, a
notification having the expected route, or a webhook endpoint returning `200`
is not sufficient evidence.

## Protocol and client versions

The hardened KERIA lanes use:

- `weboftrust/keria:0.4.0`;
- `signify-ts@0.4.0`; and
- `gleif/sally:1.0.2`.

The KERI, vLEI, credential-schema, delegation, threshold, and Sally pins remain
unchanged by this hardening work. The proof records the resolved KERIA image
identity and SignifyTS version so a retained result can be tied to the software
that produced it.

## Sally bootstrap

The workflow has one local reporting verifier: no-witness direct Sally. Sally
owns initialization and inception through `sally server start --salt
--incept-file`; the driver does not compose `kli init` and `kli incept`.

The verifier's blind `/oobi` response is the bootstrap proof. It must complete
within the configured deadline and include a valid `KERI-AID` header. After the
GEDA prefix becomes known, the workflow recreates Sally with that authorization
and requires the same AID from `/oobi`. A healthy process, a log message, or
KLI status alone is not bootstrap evidence.

## Challenge graph

The workflow stores the intended trust graph as eight undirected
relationships:

| Relationship | Participants |
| --- | --- |
| GAR peer review | GAR1 and GAR2 |
| LAR peer review | LAR1 and LAR2 |
| QAR peer review 1 | QAR1 and QAR2 |
| QAR peer review 2 | QAR1 and QAR3 |
| QAR peer review 3 | QAR2 and QAR3 |
| GLEIF-to-QVI handoff | GAR1 and QAR1 |
| QVI-to-LE handoff | QAR1 and LAR1 |
| QVI-to-holder handoff | QAR1 and Person |

Each relationship produces one verified exchange in each direction, for
exactly these 16 directions:

```text
gar1->gar2       gar2->gar1
lar1->lar2       lar2->lar1
qar1->qar2       qar2->qar1
qar1->qar3       qar3->qar1
qar2->qar3       qar3->qar2
gar1->qar1       qar1->gar1
qar1->lar1       lar1->qar1
qar1->person     person->qar1
```

Challenge words exist only for their exchange. They are never printed or
retained. A receipt is written only after verification succeeds and contains
the relationship, direction, participant prefixes, verifier type, SHA-256
challenge digest, verification time, and the response EXN SAID when KERIA
exposes it. Success requires the exact unique set above; a counter cannot prove
that set.

## QVI multisig OOBI

The workflow requires every QAR to report:

- the same three authorized group agent EIDs; and
- the same endpoint location for each signing member's agent.

Those observations prove that all three expected agent endpoint roles exist.
KERIA supplies an endpoint-qualified OOBI:

```text
/oobi/<qvi-prefix>/agent/<qar-agent-eid>
```

Any OOBI that KERIA enumerates must match the authorized endpoint evidence.
The workflow strips `/agent/<eid>` from one such URL to produce the canonical
multisig OOBI:

```text
/oobi/<qvi-prefix>
```

The OOBI artifact contains that one URL plus the three `{eid, url}` endpoint
records used to validate its origin. The workflow rejects missing, duplicate,
extra, divergent, or mismatched endpoint evidence. Each external KLI and
Signify consumer resolves the canonical multisig OOBI once.

Subsequent multisig coordination must reach both non-initiators. Multisig EXNs
are recipient-bound: the sender creates one EXN for each unique recipient and
sends that event only to that recipient.

## Group and credential state

Each QAR reads its own QVI state. The three observations must agree on the QVI
prefix, delegator, signing and rotation member sets, sequence number,
establishment-event digest, current threshold, and next threshold. Each QAR's
own group-state snapshot is used when constructing that member's seals.

Credential selection starts with the exact SAID recorded by the workflow.
Fallback selection is allowed only when exactly one active credential matches
the expected issuer, schema, and issuee. Missing, ambiguous, historical,
revoked, or cross-QAR-divergent results fail.

Before revoking either leaf, every QAR must observe the same credential and
registry and the workflow must prove:

- the QVI is the issuer;
- the schema is the expected OOR or ECR leaf schema;
- the Person is the issuee; and
- all three observations are issued at TEL sequence `0`, or all three are
  already revoked at TEL sequence `1`.

A missing or mixed state fails before revocation. A new revocation uses one
timestamp for all QARs. Completion requires sequence `1` and one common
revocation TEL digest across all three observations.

The QVI revokes only the OOR and ECR leaves that it issued. The OOR-Auth and
ECR-Auth credentials are issued by the LE and remain active because their
issuer is outside this workflow's revocation scope.

## Sally reporting evidence

The workflow-owned recorder stores callbacks as timestamped JSONL. Active QVI,
LE, and OOR presentations are each matched after their own submission boundary
using the exact action, credential SAID, schema, holder, and issuer.

The revoked OOR proof requires both:

1. Sally 1.0.2's timestamped rejection log naming the exact revoked
   credential; and
2. a post-submission structured `rev` callback naming that credential, its OOR
   schema, its QVI issuer, and its revocation timestamp.

Either half without the other fails. Stale callbacks, the wrong SAID, and a
holder-only `200` response are not evidence.

Sally 1.0.2 does not support ECR reporting. The ECR story ends after issuance,
Person admission, and three-QAR revocation convergence. The workflow never
presents an ECR and requires a callback-free post-ECR observation interval.

The recorder and Sally 1.0.2 log adapter are described in
[`proof_hook/README.md`](proof_hook/README.md).

## Runtime isolation and retained proof

Argument validation completes before Docker activity. Every run then creates:

- a unique Compose project and Compose-managed network;
- a private mode-`0700` runtime directory with an ownership sentinel;
- writable configuration copies, keystores, generated credential data,
  participant configuration, and secret material scoped to that run; and
- a separate sanitized proof directory.

The workflow never accepts a caller-owned keystore directory and never removes
a path without validating its canonical location and ownership sentinel.
Salts, passcodes, seed material, challenge words, and unredacted participant
configuration are excluded from retained output.

The default cleanup removes the scoped containers, volumes, network, and
private runtime while preserving the sanitized proof directory. On failure,
the proof directory also receives redacted Compose status, service logs, job
logs, and the partial manifest. `--keep-runtime` preserves both the private
runtime and Compose stack and prints the exact teardown command. That retained
runtime still contains protected participant configuration and must be treated
as sensitive until it is removed.

The JSONL manifest and summary identify the dependencies and record detached
KLI jobs, challenge receipts, common QVI state, credential/TEL convergence,
Sally callbacks, and the final status and duration.

## JSON ownership

Validation stays with the component that understands the data:

- SignifyTS runners validate KERIA, multisig, credential, operation, and TEL
  contracts before returning `{ok:true}`.
- The workflow-contract Python adapter validates KLI contact JSON and aggregate
  challenge-manifest evidence.
- Bash checks command status and orchestrates the story.
- `jq` in the Bash driver only extracts scalar fields, constructs JSON,
  projects or tags proof records, normalizes one JSON result, and formats JSON
  for display.

Collections are canonicalized by their TypeScript or Python producer before
Bash receives them. Domain predicates, comparisons, filtering, deduplication,
and sorting do not belong in the driver's `jq` programs. The focused
`tests/jq-serialization-policy-test.sh` guard makes that boundary executable.
