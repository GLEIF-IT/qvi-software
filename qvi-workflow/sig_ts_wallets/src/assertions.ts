import type {HabState, SignifyClient} from 'signify-ts';

import {
    credentialSnapshot,
    getCredential,
    type CredentialSnapshot,
} from './credential-state.ts';
import {
    readGroupObservation,
    type GroupStateSnapshot,
} from './group-state.ts';
import {
    assertCredentialConvergence,
    assertGroupStateConvergence,
    type ExpectedGroupState,
} from './workflow-assertions.ts';

export interface ExpectedCredentialState {
    credentialSaid: string;
    issuerPrefix: string;
    schema: string;
    issueePrefix: string;
    statusSequence: string;
}

export interface WalletObserver {
    client: SignifyClient;
    aid: HabState;
}

/** Assert exact QVI KEL, signing-roster, next-roster, and observer convergence. */
export async function assertGroupConvergence(
    observers: WalletObserver[],
    groupName: string,
    expected: ExpectedGroupState,
    eventSaid?: string
): Promise<GroupStateSnapshot> {
    const observations = await Promise.all(
        observers.map(({client, aid}) =>
            readGroupObservation(
                client,
                aid.prefix,
                groupName
            )
        )
    );
    const snapshot = assertGroupStateConvergence(
        observations,
        expected
    );
    if (
        eventSaid !== undefined &&
        snapshot.establishmentDigest !== eventSaid
    ) {
        throw new Error(
            `Group establishment digest ${snapshot.establishmentDigest} does not match ${eventSaid}`
        );
    }
    return snapshot;
}

/** Assert credential and TEL convergence across concrete wallet observers. */
export async function assertQviCredentialConvergence(
    observers: WalletObserver[],
    expected: ExpectedCredentialState
): Promise<CredentialSnapshot> {
    const snapshots = await Promise.all(
        observers.map(async ({client, aid}) => {
            return credentialSnapshot(
                await getCredential(client, expected.credentialSaid),
                aid.prefix
            );
        })
    );
    return assertCredentialConvergence(
        snapshots,
        snapshots.map(({observerAid}) => observerAid),
        {
            said: expected.credentialSaid,
            issuer: expected.issuerPrefix,
            schema: expected.schema,
            issuee: expected.issueePrefix,
            statusSequence: expected.statusSequence,
        }
    );
}

/** Assert the holder observes the expected credential and TEL state. */
export async function assertPersonCredentialState(
    observer: WalletObserver,
    expected: ExpectedCredentialState
): Promise<CredentialSnapshot> {
    const snapshot = credentialSnapshot(
        await getCredential(
            observer.client,
            expected.credentialSaid
        ),
        observer.aid.prefix
    );
    const actual = {
        credentialSaid: snapshot.said,
        issuerPrefix: snapshot.issuer,
        schema: snapshot.schema,
        issueePrefix: snapshot.issuee,
        statusSequence: snapshot.statusSequence,
    };
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        throw new Error(
            `Person credential state ${JSON.stringify(actual)} does not match ${JSON.stringify(expected)}`
        );
    }
    return snapshot;
}
