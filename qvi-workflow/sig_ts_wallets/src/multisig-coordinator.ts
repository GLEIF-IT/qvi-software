import type {
    HabState,
    Operation,
    SignifyClient,
} from 'signify-ts';

import {
    consumeNotifications,
    type NotificationWriter,
} from './notifications.ts';
import {
    waitOperation,
    type OperationClient,
} from './operations.ts';

export interface MultisigMember<
    Client extends OperationClient & NotificationWriter = SignifyClient,
> {
    client: Client;
    aid: HabState;
}

export interface MultisigMemberContext<
    Client extends OperationClient & NotificationWriter = SignifyClient,
> extends MultisigMember<Client> {
    otherMembers: HabState[];
    isInitiator: boolean;
    initiatorPrefix: string;
}

export interface MultisigResult {
    operation: Operation | string;
    notificationIds: string[];
}

export type RunMemberOperation<
    Client extends OperationClient & NotificationWriter = SignifyClient,
> = (
    context: MultisigMemberContext<Client>
) => Promise<MultisigResult>;

export interface MemberSubmission {
    memberPrefix: string;
    operation: Operation | string;
    notificationIds: string[];
}

/** Validate a concrete member set and its explicit operation initiator. */
function requireMembers<
    Client extends OperationClient & NotificationWriter,
>(
    members: MultisigMember<Client>[],
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
export function memberContexts<
    Client extends OperationClient & NotificationWriter,
>(
    members: MultisigMember<Client>[],
    initiatorPrefix: string
): MultisigMemberContext<Client>[] {
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
    client: OperationClient & NotificationWriter;
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
export async function coordinateMultisigOperation<
    Client extends OperationClient & NotificationWriter,
>(
    members: MultisigMember<Client>[],
    initiatorPrefix: string,
    runMember: RunMemberOperation<Client>
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
