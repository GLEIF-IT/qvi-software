import type {CredentialResult, SignifyClient} from 'signify-ts';

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

export interface CredentialObservation {
    sad: {
        [key: string]: unknown;
        d: string;
        i: string;
        s: string;
        a?: unknown;
        A?: unknown;
    };
    iss: {d: string};
    status: {
        ri: string;
        s: string;
        d: string;
    };
}

type CredentialSad = CredentialObservation['sad'];
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
    credential: CredentialObservation
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
    credential: CredentialObservation,
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

export async function getCredential(
    client: SignifyClient,
    credentialSaid: string
): Promise<CredentialResult> {
    return client.credentials().get(credentialSaid);
}
