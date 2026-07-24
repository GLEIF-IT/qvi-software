import type {HabState, SignifyClient} from 'signify-ts';

import {assertExactObserverSet} from './observer-evidence.ts';

export interface GroupStateSnapshot {
    prefix: string;
    delegator: string;
    sequence: string;
    establishmentDigest: string;
    signingThreshold: string | string[];
    nextThreshold: string | string[];
    signingMembers: string[];
    rotationMembers: string[];
}

export interface GroupObservation {
    observerAid: string;
    group: HabState;
    snapshot: GroupStateSnapshot;
}

export interface ExpectedGroupState {
    prefix?: string;
    delegator?: string;
    sequence?: string;
    signingThreshold?: string | string[];
    nextThreshold?: string | string[];
}

function sorted(values: string[]): string[] {
    return [...values].sort();
}

function sameValues(left: string[], right: string[]): boolean {
    return JSON.stringify(sorted(left)) === JSON.stringify(sorted(right));
}

export async function readGroupObservation(
    client: SignifyClient,
    observerAid: string,
    groupName: string,
    expectedMembers: string[]
): Promise<GroupObservation> {
    const group = await client.identifiers().get(groupName);
    const members = await client.identifiers().members(groupName);
    const signingMembers = members.signing.map((record) => record.aid);
    const rotationMembers = members.rotation.map((record) => record.aid);
    const signingMembershipIsInvalid =
        sameValues(signingMembers, expectedMembers) === false;
    const rotationMembershipIsInvalid =
        sameValues(rotationMembers, expectedMembers) === false;
    if (signingMembershipIsInvalid || rotationMembershipIsInvalid) {
        throw new Error(
            `Group ${group.prefix} membership does not match configured member AIDs`
        );
    }

    return {
        observerAid,
        group,
        snapshot: {
            prefix: group.prefix,
            delegator: group.state.di,
            sequence: group.state.s,
            establishmentDigest: group.state.ee.d,
            signingThreshold: group.state.kt,
            nextThreshold: group.state.nt,
            signingMembers: sorted(signingMembers),
            rotationMembers: sorted(rotationMembers),
        },
    };
}

export function assertGroupStateConvergence(
    observations: GroupObservation[],
    expectedObserverAids: string[],
    expected: ExpectedGroupState = {}
): GroupStateSnapshot {
    const memberCountIsInvalid = observations.length !== 3;
    if (memberCountIsInvalid) {
        throw new Error(
            `Expected three group observations; received ${observations.length}`
        );
    }
    assertExactObserverSet(
        observations.map((observation) => observation.observerAid),
        expectedObserverAids,
        'Group-state convergence'
    );
    const baseline = observations[0].snapshot;
    const establishmentDigestIsMissing =
        typeof baseline.establishmentDigest !== 'string' ||
        baseline.establishmentDigest.length === 0;
    if (establishmentDigestIsMissing) {
        throw new Error(
            'QVI group state has no establishment event digest'
        );
    }
    const baselineJson = JSON.stringify(baseline);
    const stateConverged = observations.every(
        (observation) =>
            JSON.stringify(observation.snapshot) === baselineJson
    );
    if (stateConverged === false) {
        throw new Error(
            `QAR group state diverged: ${JSON.stringify(observations.map((item) => item.snapshot))}`
        );
    }

    const expectationChecks: Array<
        [string, unknown, unknown]
    > = [
        ['prefix', baseline.prefix, expected.prefix],
        ['delegator', baseline.delegator, expected.delegator],
        ['sequence', baseline.sequence, expected.sequence],
        [
            'signing threshold',
            baseline.signingThreshold,
            expected.signingThreshold,
        ],
        [
            'next threshold',
            baseline.nextThreshold,
            expected.nextThreshold,
        ],
    ];
    for (const [field, actual, wanted] of expectationChecks) {
        const expectationIsDefined = wanted !== undefined;
        const valueMatches =
            JSON.stringify(actual) === JSON.stringify(wanted);
        if (expectationIsDefined && valueMatches === false) {
            throw new Error(
                `Group ${field} ${JSON.stringify(actual)} does not match expected ${JSON.stringify(wanted)}`
            );
        }
    }
    return baseline;
}
