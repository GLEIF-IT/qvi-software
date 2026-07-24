import type {HabState, SignifyClient} from 'signify-ts';

import {sortAids} from './canonical-order.ts';

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

export async function readGroupObservation(
    client: SignifyClient,
    observerAid: string,
    groupName: string
): Promise<GroupObservation> {
    const group = await client.identifiers().get(groupName);
    const members = await client.identifiers().members(groupName);
    const signingMembers = members.signing.map((record) => record.aid);
    const rotationMembers = members.rotation.map((record) => record.aid);
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
            signingMembers: sortAids(signingMembers),
            rotationMembers: sortAids(rotationMembers),
        },
    };
}
