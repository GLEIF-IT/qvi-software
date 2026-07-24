import type {CredentialResult, SignifyClient} from 'signify-ts';

import {assertExactObserverSet} from './observer-evidence.ts';

export interface CredentialSnapshot {
    observerAid: string;
    said: string;
    issuer: string;
    schema: string;
    issuee: string;
    registry: string;
    statusSequence: string;
    priorTelDigest: string | null;
    currentTelDigest: string;
}

export interface ExpectedCredential {
    said?: string;
    issuer: string;
    schema: string;
    issuee: string;
}

type CredentialSad = CredentialResult['sad'];
type CredentialStateSnapshot = Omit<
    CredentialSnapshot,
    'observerAid'
>;
type EdgeAttributes = {
    i?: string;
    [key: string]: unknown;
};

function hasEdgeAttributes(
    sad: CredentialSad
): sad is CredentialSad & {a: EdgeAttributes} {
    return 'a' in sad && sad.a !== undefined;
}

function requireNonemptyString(
    value: unknown,
    fieldName: string
): string {
    const fieldIsInvalid = typeof value !== 'string' || value.length === 0;
    if (fieldIsInvalid) {
        throw new Error(`Credential ${fieldName} is missing`);
    }
    return value;
}

function credentialStateSnapshot(
    credential: CredentialResult
): CredentialStateSnapshot {
    const sad = credential.sad;
    const credentialHasEdgeAttributes = hasEdgeAttributes(sad);
    if (credentialHasEdgeAttributes === false) {
        const credentialIsAggregate = 'A' in sad;
        const reason = credentialIsAggregate
            ? 'uses aggregate attributes'
            : 'has no edge attributes';
        throw new Error(
            `Credential ${sad.d} ${reason}, which this workflow does not support`
        );
    }

    const attributes = sad.a;
    return {
        said: requireNonemptyString(sad.d, 'SAID'),
        issuer: requireNonemptyString(sad.i, 'issuer'),
        schema: requireNonemptyString(sad.s, 'schema'),
        issuee: requireNonemptyString(attributes.i, 'issuee'),
        registry: requireNonemptyString(
            credential.status.ri,
            'registry identifier'
        ),
        statusSequence: requireNonemptyString(
            credential.status.s,
            'status sequence'
        ),
        priorTelDigest:
            credential.status.s === '0'
                ? null
                : requireNonemptyString(
                      credential.iss.d,
                      'issuance TEL digest'
                  ),
        currentTelDigest: requireNonemptyString(
            credential.status.d,
            'current TEL digest'
        ),
    };
}

export function credentialSnapshot(
    credential: CredentialResult,
    observerAid: string
): CredentialSnapshot {
    return {
        observerAid: requireNonemptyString(
            observerAid,
            'observer AID'
        ),
        ...credentialStateSnapshot(credential),
    };
}

export function assertExpectedCredential(
    snapshot: CredentialStateSnapshot,
    expected: ExpectedCredential
): void {
    const identityChecks: Array<[string, string, string]> = [
        ['issuer', snapshot.issuer, expected.issuer],
        ['schema', snapshot.schema, expected.schema],
        ['issuee', snapshot.issuee, expected.issuee],
    ];
    if (expected.said !== undefined) {
        identityChecks.push(['SAID', snapshot.said, expected.said]);
    }

    for (const [field, actual, wanted] of identityChecks) {
        const fieldMatches = actual === wanted;
        if (fieldMatches === false) {
            throw new Error(
                `Credential ${snapshot.said} has ${field} ${actual}; expected ${wanted}`
            );
        }
    }
}

export function assertCredentialConvergence(
    snapshots: CredentialSnapshot[],
    expectedObserverAids: string[]
): void {
    const expectedMemberCount = 3;
    const memberCountIsInvalid =
        snapshots.length !== expectedMemberCount;
    if (memberCountIsInvalid) {
        throw new Error(
            `Expected ${expectedMemberCount} credential snapshots; received ${snapshots.length}`
        );
    }
    assertExactObserverSet(
        snapshots.map((snapshot) => snapshot.observerAid),
        expectedObserverAids,
        'Credential convergence'
    );

    const baseline = snapshots[0];
    const identityIsConsistent = snapshots.every(
        (snapshot) =>
            snapshot.said === baseline.said &&
            snapshot.issuer === baseline.issuer &&
            snapshot.schema === baseline.schema &&
            snapshot.issuee === baseline.issuee &&
            snapshot.registry === baseline.registry
    );
    if (identityIsConsistent === false) {
        throw new Error(
            `QAR credential identity diverged: ${JSON.stringify(snapshots)}`
        );
    }

    const statusIsConsistent = snapshots.every(
        (snapshot) =>
            snapshot.statusSequence === baseline.statusSequence &&
            snapshot.currentTelDigest === baseline.currentTelDigest
    );
    if (statusIsConsistent === false) {
        throw new Error(
            `QAR credential TEL state diverged: ${JSON.stringify(snapshots)}`
        );
    }
}

export function assertIssuedCredentialConvergence(
    snapshots: CredentialSnapshot[],
    expectedObserverAids: string[],
    credentialDescription: string
): void {
    assertCredentialConvergence(snapshots, expectedObserverAids);

    const credentialIsActiveOnEveryObserver = snapshots.every(
        (snapshot) => snapshot.statusSequence === '0'
    );
    if (credentialIsActiveOnEveryObserver === false) {
        throw new Error(
            `${credentialDescription} must be active at TEL sequence 0 on every QAR`
        );
    }
}

export async function selectCredential(
    client: SignifyClient,
    expected: ExpectedCredential
): Promise<CredentialResult> {
    if (expected.said !== undefined) {
        const credential = await client.credentials().get(expected.said);
        const snapshot = credentialStateSnapshot(credential);
        assertExpectedCredential(snapshot, expected);
        return credential;
    }

    const credentials = await client.credentials().list({
        filter: {
            '-i': expected.issuer,
            '-s': expected.schema,
            '-a-i': expected.issuee,
        },
    });
    const activeCredentials = credentials.filter(
        (credential) => credential.status.s === '0'
    );
    const activeCredentialCountIsInvalid =
        activeCredentials.length !== 1;
    if (activeCredentialCountIsInvalid) {
        throw new Error(
            `Expected exactly one active credential for issuer ${expected.issuer}, schema ${expected.schema}, issuee ${expected.issuee}; found ${activeCredentials.length}`
        );
    }

    return activeCredentials[0];
}
