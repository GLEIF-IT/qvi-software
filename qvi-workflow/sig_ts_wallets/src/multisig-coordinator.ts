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
 * Starts the proposal, overlaps independent follower contributions, and waits
 * for every member's local operation to complete.
 */
export async function coordinateMultisigOperation(
    members: MultisigMember[],
    initiatorPrefix: string,
    runMember: RunMemberOperation
): Promise<void> {
    const contexts = memberContexts(members, initiatorPrefix);
    const initiator = contexts.find(({isInitiator}) => isInitiator);
    if (initiator === undefined) {
        throw new Error('Multisig initiator context is missing');
    }

    // Followers need the initiator's proposal, but they use separate KERIA
    // stores and do not depend on one another.
    const initiatorResult = await runMember(initiator);
    const followers = contexts.filter(
        (context) => context !== initiator
    );
    const followerResults = await Promise.all(
        followers.map((context) => runMember(context))
    );

    await completeMultisigOps([
        {client: initiator.client, result: initiatorResult},
        ...followers.map((context, index) => ({
            client: context.client,
            result: followerResults[index],
        })),
    ]);
}

export function operationFrom(
    operation: Operation,
    coordination: MatchedNotification[]
): MultisigResult {
    return {operation, coordination};
}
