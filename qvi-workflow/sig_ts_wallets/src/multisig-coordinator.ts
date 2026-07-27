import type {
    HabState,
    Operation,
    SignifyClient,
} from 'signify-ts';

import {consumeNotifications} from './notifications.ts';
import {waitOperation} from './operations.ts';

export interface MultisigMember {
    client: SignifyClient;
    aid: HabState;
}

export interface MultisigMemberContext extends MultisigMember {
    otherMembers: HabState[];
    isInitiator: boolean;
    initiatorPrefix: string;
}

export interface MultisigResult {
    operation: Operation | string;
    notificationIds: string[];
}

export type RunMemberOperation = (
    context: MultisigMemberContext
) => Promise<MultisigResult>;

export interface MemberSubmission {
    memberPrefix: string;
    operation: Operation | string;
    notificationIds: string[];
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
        initiatorPrefix,
    }));
}

interface CompletedMember {
    client: SignifyClient;
    result: MultisigResult;
}

/**
 * Wait for the shared success barrier, then consume each member's local
 * notification records in deterministic member order.
 */
export async function completeMultisigOperations(
    members: CompletedMember[]
): Promise<void> {
    await Promise.all(
        members.map(({client, result}) =>
            waitOperation(client, result.operation)
        )
    );

    for (const {client, result} of members) {
        if (result.notificationIds.length > 0) {
            await consumeNotifications(client, result.notificationIds);
        }
    }
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

    await completeMultisigOperations([
        {client: initiator.client, result: initiatorResult},
        ...followers.map((context, index) => ({
            client: context.client,
            result: followerResults[index],
        })),
    ]);
}
