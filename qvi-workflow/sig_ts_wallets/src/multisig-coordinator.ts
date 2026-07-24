import type {
    HabState,
    Operation,
    SignifyClient,
} from 'signify-ts';

import {
    completeMultisigOps,
    type MultisigResult,
} from './coordinated-operation.ts';
import type {MatchedNotification} from './notifications.ts';

export interface MultisigMember {
    client: SignifyClient;
    aid: HabState;
}

export interface MultisigMemberContext extends MultisigMember {
    otherMembers: HabState[];
    isInitiator: boolean;
    coordinatorPrefix: string;
}

export type RunMemberOperation = (
    context: MultisigMemberContext
) => Promise<MultisigResult>;

export interface MemberSubmission {
    memberPrefix: string;
    operation: Operation | string;
    notifications: MatchedNotification[];
}

/** Validate a concrete member set and its explicit operation initiator. */
function requireMembers(
    members: MultisigMember[],
    initiatorPrefix: string
): void {
    if (members.length === 0) {
        throw new Error('Multisig coordination requires at least one member');
    }
    const prefixes = members.map(({aid}) => aid.prefix);
    const prefixesAreUnique =
        new Set(prefixes).size === prefixes.length;
    if (prefixesAreUnique === false) {
        throw new Error('Multisig member prefixes must be unique');
    }
    if (prefixes.includes(initiatorPrefix) === false) {
        throw new Error(
            `Multisig initiator ${initiatorPrefix} is not a member`
        );
    }
}

/** Build member-local operation inputs around an explicit initiator. */
export function memberContexts(
    members: MultisigMember[],
    initiatorPrefix: string
): MultisigMemberContext[] {
    requireMembers(members, initiatorPrefix);
    return members.map((member) => ({
        ...member,
        otherMembers: members
            .filter((candidate) => candidate !== member)
            .map(({aid}) => aid),
        isInitiator: member.aid.prefix === initiatorPrefix,
        coordinatorPrefix: initiatorPrefix,
    }));
}

/**
 * Runs a member-scoped multisig action in protocol order and completes it.
 */
export async function coordinateMultisigOperation(
    members: MultisigMember[],
    initiatorPrefix: string,
    runMember: RunMemberOperation
): Promise<void> {
    const completedMembers: Array<{
        client: SignifyClient;
        result: MultisigResult;
    }> = [];

    for (const context of memberContexts(members, initiatorPrefix)) {
        const result = await runMember(context);
        completedMembers.push({client: context.client, result});
    }

    await completeMultisigOps(completedMembers);
}

export function operationFrom(
    operation: Operation,
    coordination: MatchedNotification[]
): MultisigResult {
    return {operation, coordination};
}
