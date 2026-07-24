import {
    assertCredentialConvergence,
    assertExpectedCredential,
    type CredentialSnapshot,
} from './credential-state.ts';
import type {
    OperationEvidence,
    OperationResultIdentity,
} from './operations.ts';
import {assertExactObserverSet} from './observer-evidence.ts';

export interface CoordinationReceipt {
    sender: string;
    recipient: string;
    exnSaid: string;
    innerExchangeSaid: string;
}

function compareStrings(left: string, right: string): number {
    return left.localeCompare(right);
}

function requireNonempty(value: string, description: string): void {
    const valueIsMissing =
        typeof value !== 'string' || value.length === 0;
    if (valueIsMissing) {
        throw new Error(`${description} is missing`);
    }
}

export function canonicalStrings(values: readonly string[]): string[] {
    return [...values].sort(compareStrings);
}

export function canonicalObserverSnapshots(
    snapshots: CredentialSnapshot[]
): CredentialSnapshot[] {
    return [...snapshots].sort((left, right) =>
        compareStrings(left.observerAid, right.observerAid)
    );
}

export function canonicalOperationEvidence(
    evidence: OperationEvidence[]
): OperationEvidence[] {
    return [...evidence].sort((left, right) =>
        compareStrings(left.name, right.name)
    );
}

export function canonicalReceipts<T extends CoordinationReceipt>(
    receipts: T[]
): T[] {
    return [...receipts].sort((left, right) =>
        compareStrings(
            `${left.sender}\u0000${left.recipient}\u0000${left.exnSaid}`,
            `${right.sender}\u0000${right.recipient}\u0000${right.exnSaid}`
        )
    );
}

export function assertExactDirectedFanout(
    receipts: CoordinationReceipt[],
    expectedMembers: string[],
    description: string,
    expectedInnerExchangeSaid?: string
): void {
    assertExactObserverSet(
        expectedMembers,
        expectedMembers,
        `${description} members`
    );
    const expectedPairs = expectedMembers.flatMap((sender) =>
        expectedMembers
            .filter((recipient) => recipient !== sender)
            .map((recipient) => `${sender}\u0000${recipient}`)
    );
    const observedPairs = receipts.map(
        ({sender, recipient}) => `${sender}\u0000${recipient}`
    );
    const pairSetIsExact =
        receipts.length === expectedPairs.length &&
        new Set(observedPairs).size === observedPairs.length &&
        JSON.stringify(canonicalStrings(observedPairs)) ===
            JSON.stringify(canonicalStrings(expectedPairs));
    if (pairSetIsExact === false) {
        throw new Error(
            `${description} does not contain the exact directed member fan-out`
        );
    }

    for (const receipt of receipts) {
        requireNonempty(receipt.exnSaid, `${description} EXN SAID`);
        requireNonempty(
            receipt.innerExchangeSaid,
            `${description} inner EXN SAID`
        );
        const innerSaidMatches =
            expectedInnerExchangeSaid === undefined ||
            receipt.innerExchangeSaid === expectedInnerExchangeSaid;
        if (innerSaidMatches === false) {
            throw new Error(
                `${description} receipt from ${receipt.sender} to ${receipt.recipient} references ${receipt.innerExchangeSaid}; expected ${expectedInnerExchangeSaid}`
            );
        }
    }
}

export function assertRepeatedDirectedFanout(
    receipts: CoordinationReceipt[],
    expectedMembers: string[],
    repetitionsPerDirection: number,
    description: string
): void {
    assertExactObserverSet(
        expectedMembers,
        expectedMembers,
        `${description} members`
    );
    const expectedPairs = expectedMembers.flatMap((sender) =>
        expectedMembers
            .filter((recipient) => recipient !== sender)
            .flatMap((recipient) =>
                Array.from(
                    {length: repetitionsPerDirection},
                    () => `${sender}\u0000${recipient}`
                )
            )
    );
    const observedPairs = receipts.map(
        ({sender, recipient}) => `${sender}\u0000${recipient}`
    );
    const pairMultisetIsExact =
        JSON.stringify(canonicalStrings(observedPairs)) ===
        JSON.stringify(canonicalStrings(expectedPairs));
    if (pairMultisetIsExact === false) {
        throw new Error(
            `${description} does not contain ${repetitionsPerDirection} copies of every directed member fan-out`
        );
    }
    for (const receipt of receipts) {
        requireNonempty(receipt.exnSaid, `${description} EXN SAID`);
        requireNonempty(
            receipt.innerExchangeSaid,
            `${description} inner EXN SAID`
        );
    }
}

export interface ExpectedOperationIdentity {
    name: string;
    result: Partial<OperationResultIdentity>;
}

export function assertTerminalOperationEvidence(
    evidence: OperationEvidence[],
    expected: ExpectedOperationIdentity[],
    description: string
): void {
    const actualCanonical = canonicalOperationEvidence(evidence);
    const expectedCanonical = [...expected].sort((left, right) =>
        compareStrings(left.name, right.name)
    );
    const countsMatch =
        actualCanonical.length === expectedCanonical.length;
    if (countsMatch === false) {
        throw new Error(
            `${description} expected ${expectedCanonical.length} terminal operations; received ${actualCanonical.length}`
        );
    }

    for (let index = 0; index < expectedCanonical.length; index++) {
        const actual = actualCanonical[index];
        const wanted = expectedCanonical[index];
        const nameMatches = actual.name === wanted.name;
        if (nameMatches === false) {
            throw new Error(
                `${description} operation ${actual.name} does not match expected ${wanted.name}`
            );
        }
        for (const [field, expectedValue] of Object.entries(
            wanted.result
        )) {
            const actualValue =
                actual.result[
                    field as keyof OperationResultIdentity
                ];
            const fieldMatches = actualValue === expectedValue;
            if (fieldMatches === false) {
                throw new Error(
                    `${description} operation ${actual.name} has ${field} ${String(actualValue)}; expected ${String(expectedValue)}`
                );
            }
        }
    }
}

export function assertCommonInnerExchangeSaid(
    receipts: CoordinationReceipt[],
    description: string
): string {
    const innerSaids = new Set(
        receipts.map(({innerExchangeSaid}) => innerExchangeSaid)
    );
    const commonSaidExists =
        innerSaids.size === 1 &&
        receipts.length > 0 &&
        receipts[0].innerExchangeSaid.length > 0;
    if (commonSaidExists === false) {
        throw new Error(
            `${description} does not reference one common inner EXN SAID`
        );
    }
    return receipts[0].innerExchangeSaid;
}

export interface IssuanceContract {
    observations: CredentialSnapshot[];
    operationEvidence: OperationEvidence[];
    issuanceReceipts: CoordinationReceipt[];
    coordinationReceipts: CoordinationReceipt[];
}

export function assertIssuanceContract(
    result: IssuanceContract,
    expectedMembers: string[],
    expected: {
        issuer: string;
        schema: string;
        issuee: string;
    },
    description: string
): void {
    assertExactObserverSet(
        result.observations.map(({observerAid}) => observerAid),
        expectedMembers,
        `${description} observations`
    );
    const baseline = result.observations[0];
    const observationsAreExact = result.observations.every(
        (snapshot) =>
            snapshot.said === baseline.said &&
            snapshot.issuer === expected.issuer &&
            snapshot.schema === expected.schema &&
            snapshot.issuee === expected.issuee &&
            snapshot.registry === baseline.registry &&
            snapshot.statusSequence === '0' &&
            snapshot.priorTelDigest === null &&
            snapshot.currentTelDigest === baseline.currentTelDigest
    );
    if (observationsAreExact === false) {
        throw new Error(
            `${description} credential identity or TEL state diverged`
        );
    }
    requireNonempty(baseline.said, `${description} credential SAID`);
    requireNonempty(
        baseline.registry,
        `${description} registry identifier`
    );
    requireNonempty(
        baseline.currentTelDigest,
        `${description} TEL digest`
    );

    const resultIsIdempotent =
        result.operationEvidence.length === 0 &&
        result.issuanceReceipts.length === 0 &&
        result.coordinationReceipts.length === 0;
    if (resultIsIdempotent) {
        return;
    }

    assertTerminalOperationEvidence(
        result.operationEvidence,
        Array.from({length: 3}, () => ({
            name: `credential.${baseline.said}`,
            result: {
                kind: 'credential',
                said: baseline.said,
                prefix: expected.issuer,
                schema: expected.schema,
            },
        })),
        `${description} issuance`
    );
    assertExactDirectedFanout(
        result.issuanceReceipts,
        expectedMembers,
        `${description} issuance coordination`,
        baseline.currentTelDigest
    );
    const ipexSaid = assertCommonInnerExchangeSaid(
        result.coordinationReceipts,
        `${description} IPEX coordination`
    );
    assertExactDirectedFanout(
        result.coordinationReceipts,
        expectedMembers,
        `${description} IPEX coordination`,
        ipexSaid
    );
}

export interface RevocationContract {
    status: 'already-revoked' | 'revoked';
    credentialSaid: string;
    qviPrefix: string;
    operationNames: string[];
    operationEvidence: OperationEvidence[];
    before: CredentialSnapshot[];
    after: CredentialSnapshot[];
    revocationTelDigest: string;
    revocationTimestamp: string;
    coordinationReceipts: CoordinationReceipt[];
}

function assertCredentialSnapshotsMatch(
    snapshots: CredentialSnapshot[],
    expectedMembers: string[],
    expected: {
        said: string;
        issuer: string;
        schema: string;
        issuee: string;
    }
): void {
    snapshots.forEach((snapshot) =>
        assertExpectedCredential(snapshot, expected)
    );
    assertCredentialConvergence(snapshots, expectedMembers);
}

export function assertRevocationContract(
    result: RevocationContract,
    expectedMembers: string[],
    expected: {
        said: string;
        issuer: string;
        schema: string;
        issuee: string;
    }
): void {
    const resultIdentityMatches =
        result.credentialSaid === expected.said &&
        result.qviPrefix === expected.issuer;
    if (resultIdentityMatches === false) {
        throw new Error(
            'Revocation result does not identify the expected credential and QVI'
        );
    }
    requireNonempty(
        result.revocationTimestamp,
        'Revocation timestamp'
    );
    requireNonempty(
        result.revocationTelDigest,
        'Revocation TEL digest'
    );
    assertCredentialSnapshotsMatch(
        result.before,
        expectedMembers,
        expected
    );
    assertCredentialSnapshotsMatch(
        result.after,
        expectedMembers,
        expected
    );

    const alreadyRevoked = result.status === 'already-revoked';
    if (alreadyRevoked) {
        const stateIsUnchanged =
            JSON.stringify(result.after) ===
            JSON.stringify(result.before);
        const stateIsRevoked = result.after.every(
            (snapshot) =>
                snapshot.statusSequence === '1' &&
                snapshot.currentTelDigest ===
                    result.revocationTelDigest
        );
        const noOperationWasSubmitted =
            result.operationNames.length === 0 &&
            result.operationEvidence.length === 0 &&
            result.coordinationReceipts.length === 0;
        if (
            stateIsUnchanged === false ||
            stateIsRevoked === false ||
            noOperationWasSubmitted === false
        ) {
            throw new Error(
                'Already-revoked result is not an unchanged converged TEL state'
            );
        }
        return;
    }

    const issuedDigest = result.before[0].currentTelDigest;
    const issuedStateIsExact = result.before.every(
        (snapshot) =>
            snapshot.statusSequence === '0' &&
            snapshot.priorTelDigest === null &&
            snapshot.currentTelDigest === issuedDigest
    );
    const revokedStateIsExact = result.after.every(
        (snapshot) =>
            snapshot.statusSequence === '1' &&
            snapshot.priorTelDigest === issuedDigest &&
            snapshot.currentTelDigest ===
                result.revocationTelDigest
    );
    if (issuedStateIsExact === false || revokedStateIsExact === false) {
        throw new Error(
            'Revocation before and after snapshots do not form one linked TEL transition'
        );
    }

    const operationNamesMatch =
        JSON.stringify(canonicalStrings(result.operationNames)) ===
        JSON.stringify(
            canonicalStrings(
                result.operationEvidence.map(({name}) => name)
            )
        );
    const terminalEventSaids = new Set(
        result.operationEvidence.map(({result: identity}) =>
            identity.said
        )
    );
    const terminalSequences = new Set(
        result.operationEvidence.map(({result: identity}) =>
            identity.sequence
        )
    );
    const operationEvidenceIsExact =
        result.operationEvidence.length === 3 &&
        operationNamesMatch &&
        terminalEventSaids.size === 1 &&
        terminalSequences.size === 1 &&
        result.operationEvidence.every(
            ({name, done, result: identity}) =>
                done === true &&
                identity.kind === 'event' &&
                typeof identity.said === 'string' &&
                identity.said.length > 0 &&
                name === `group.${identity.said}` &&
                identity.prefix === expected.issuer &&
                typeof identity.sequence === 'string' &&
                identity.sequence.length > 0
        );
    if (operationEvidenceIsExact === false) {
        throw new Error(
            'Revocation did not retain three matching terminal group operations'
        );
    }
    assertExactDirectedFanout(
        result.coordinationReceipts,
        expectedMembers,
        'Revocation coordination',
        result.revocationTelDigest
    );
}
