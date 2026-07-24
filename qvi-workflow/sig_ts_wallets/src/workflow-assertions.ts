import {sortAids} from './canonical-order.ts';
import type {CredentialSnapshot} from './credential-state.ts';
import type {
    GroupObservation,
    GroupStateSnapshot,
} from './group-state.ts';
import {assertExactObserverSet} from './observer-evidence.ts';

export interface ExpectedCredential {
    said: string;
    issuer: string;
    schema: string;
    issuee: string;
    statusSequence: string;
}

export interface ExpectedGroupState {
    prefix: string;
    delegator: string;
    sequence: string;
    signingThreshold: string | string[];
    nextThreshold: string | string[];
    members: string[];
}

function sameValue(left: unknown, right: unknown): boolean {
    return JSON.stringify(left) === JSON.stringify(right);
}

export function assertGroupStateConvergence(
    observations: GroupObservation[],
    expected: ExpectedGroupState
): GroupStateSnapshot {
    assertExactObserverSet(
        observations.map(({observerAid}) => observerAid),
        expected.members,
        'QVI group-state convergence'
    );
    const baseline = observations[0]?.snapshot;
    if (baseline === undefined) {
        throw new Error('No QVI group observations were provided');
    }
    const allStatesMatch = observations.every(({snapshot}) =>
        sameValue(snapshot, baseline)
    );
    if (allStatesMatch === false) {
        throw new Error(
            `QAR group state diverged: ${JSON.stringify(observations.map(({snapshot}) => snapshot))}`
        );
    }
    const expectedMembers = sortAids(expected.members);
    const expectedState = {
        prefix: expected.prefix,
        delegator: expected.delegator,
        sequence: expected.sequence,
        signingThreshold: expected.signingThreshold,
        nextThreshold: expected.nextThreshold,
        signingMembers: expectedMembers,
        rotationMembers: expectedMembers,
    };
    const actualState = {
        prefix: baseline.prefix,
        delegator: baseline.delegator,
        sequence: baseline.sequence,
        signingThreshold: baseline.signingThreshold,
        nextThreshold: baseline.nextThreshold,
        signingMembers: baseline.signingMembers,
        rotationMembers: baseline.rotationMembers,
    };
    if (sameValue(actualState, expectedState) === false) {
        throw new Error(
            `QVI group state ${JSON.stringify(actualState)} does not match ${JSON.stringify(expectedState)}`
        );
    }
    if (baseline.establishmentDigest.length === 0) {
        throw new Error(
            'QVI group state has no establishment event digest'
        );
    }
    return baseline;
}

export function assertCredentialConvergence(
    snapshots: CredentialSnapshot[],
    expectedObservers: string[],
    expected: ExpectedCredential
): CredentialSnapshot {
    assertExactObserverSet(
        snapshots.map(({observerAid}) => observerAid),
        expectedObservers,
        'QVI credential convergence'
    );
    const baseline = snapshots[0];
    if (baseline === undefined) {
        throw new Error('No credential observations were provided');
    }
    const allSnapshotsMatch = snapshots.every((snapshot) =>
        sameValue(
            {...snapshot, observerAid: ''},
            {...baseline, observerAid: ''}
        )
    );
    if (allSnapshotsMatch === false) {
        throw new Error(
            `QAR credential state diverged: ${JSON.stringify(snapshots)}`
        );
    }
    const actual = {
        said: baseline.said,
        issuer: baseline.issuer,
        schema: baseline.schema,
        issuee: baseline.issuee,
        statusSequence: baseline.statusSequence,
    };
    if (sameValue(actual, expected) === false) {
        throw new Error(
            `Credential state ${JSON.stringify(actual)} does not match ${JSON.stringify(expected)}`
        );
    }
    return baseline;
}
