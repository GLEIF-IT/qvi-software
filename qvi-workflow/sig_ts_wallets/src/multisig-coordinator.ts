import type {
    HabState,
    Operation,
    SignifyClient,
} from 'signify-ts';

import {
    completeMultisigOps,
    completeSavedMultisigOps,
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

export interface SavedMemberResult {
    memberPrefix: string;
    operationName: string;
    notificationIds: string[];
}

function requireMembers(
    members: MultisigMember[]
): [MultisigMember, MultisigMember, MultisigMember] {
    const hasThreeMembers = members.length === 3;
    if (hasThreeMembers === false) {
        throw new Error(
            `Multisig coordination requires three members; received ${members.length}`
        );
    }
    const prefixes = members.map(({aid}) => aid.prefix);
    const prefixesAreUnique = new Set(prefixes).size === 3;
    if (prefixesAreUnique === false) {
        throw new Error('Multisig member prefixes must be unique');
    }
    return [members[0], members[1], members[2]];
}

export function memberContexts(
    members: MultisigMember[]
): MultisigMemberContext[] {
    const [initiator] = requireMembers(members);
    return members.map((member, index) => ({
        ...member,
        otherMembers: members
            .filter((candidate) => candidate !== member)
            .map(({aid}) => aid),
        isInitiator: index === 0,
        coordinatorPrefix: initiator.aid.prefix,
    }));
}

/**
 * Runs a member-scoped multisig action in protocol order and completes it.
 */
export async function coordinateMultisigOperation(
    members: MultisigMember[],
    runMember: RunMemberOperation
): Promise<void> {
    const completedMembers: Array<{
        client: SignifyClient;
        result: MultisigResult;
    }> = [];

    for (const context of memberContexts(members)) {
        const result = await runMember(context);
        completedMembers.push({client: context.client, result});
    }

    await completeMultisigOps(completedMembers);
}

/**
 * Completes member results restored from the workflow persistence boundary.
 */
export async function completeSavedMemberResults(
    clientsByMemberPrefix: Map<string, SignifyClient>,
    savedMembers: SavedMemberResult[]
): Promise<void> {
    const members = savedMembers.map((member) => {
        const client = clientsByMemberPrefix.get(member.memberPrefix);
        if (client === undefined) {
            throw new Error(
                `No Signify client for multisig member ${member.memberPrefix}`
            );
        }
        return {
            client,
            result: {
                operationName: member.operationName,
                notificationIds: member.notificationIds,
            },
        };
    });
    await completeSavedMultisigOps(members);
}

export function operationFrom(
    operation: Operation,
    coordination: MatchedNotification[]
): MultisigResult {
    return {operation, coordination};
}
