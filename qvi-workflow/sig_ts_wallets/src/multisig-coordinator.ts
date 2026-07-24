import type {
    HabState,
    Operation,
    SignifyClient,
} from 'signify-ts';

import {
    completeCoordinatedOperations,
    completePersistedCoordinatedOperations,
    type CoordinatedOperation,
} from './coordinated-operation.ts';
import {notificationReference} from './notifications.ts';

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
) => Promise<CoordinatedOperation>;

export interface PendingMultisigMember {
    memberPrefix: string;
    operationName: string;
    notificationIds: string[];
}

export interface PendingMultisigOperation {
    route: string;
    groupPrefix: string;
    members: PendingMultisigMember[];
}

function nonemptyString(
    value: unknown,
    description: string
): string {
    const valueIsValid =
        typeof value === 'string' && value.length > 0;
    if (valueIsValid === false) {
        throw new Error(`${description} must be a nonempty string`);
    }
    return value;
}

function stringArray(
    value: unknown,
    description: string
): string[] {
    if (Array.isArray(value) === false) {
        throw new Error(`${description} must be an array`);
    }
    return value.map((item, index) =>
        nonemptyString(item, `${description}[${index}]`)
    );
}

function record(value: unknown, description: string) {
    const valueIsRecord =
        typeof value === 'object' &&
        value !== null &&
        Array.isArray(value) === false;
    if (valueIsRecord === false) {
        throw new Error(`${description} must be an object`);
    }
    return value as Record<string, unknown>;
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
        result: CoordinatedOperation;
    }> = [];

    for (const context of memberContexts(members)) {
        const result = await runMember(context);
        completedMembers.push({client: context.client, result});
    }

    await completeCoordinatedOperations(completedMembers);
}

/**
 * Runs an operation that cannot complete until an external delegator anchors
 * it and returns the small handle needed to resume afterward.
 */
export async function submitPendingMultisigOperation(
    route: string,
    groupPrefix: string,
    members: MultisigMember[],
    runMember: RunMemberOperation
): Promise<PendingMultisigOperation> {
    const pendingMembers: PendingMultisigMember[] = [];

    for (const context of memberContexts(members)) {
        const result = await runMember(context);
        const operationName =
            typeof result.operation === 'string'
                ? result.operation
                : result.operation.name;
        pendingMembers.push({
            memberPrefix: context.aid.prefix,
            operationName,
            notificationIds: result.coordination.flatMap(
                (notification) =>
                    notificationReference(notification).notificationIds
            ),
        });
    }

    return {route, groupPrefix, members: pendingMembers};
}

export function parsePendingMultisigOperation(
    value: unknown
): PendingMultisigOperation {
    const pending = record(value, 'Pending multisig operation');
    const rawMembers = pending.members;
    if (Array.isArray(rawMembers) === false) {
        throw new Error(
            'Pending multisig operation members must be an array'
        );
    }
    const members = rawMembers.map((rawMember, index) => {
        const member = record(
            rawMember,
            `Pending multisig member ${index}`
        );
        return {
            memberPrefix: nonemptyString(
                member.memberPrefix,
                `Pending multisig member ${index} prefix`
            ),
            operationName: nonemptyString(
                member.operationName,
                `Pending multisig member ${index} operation`
            ),
            notificationIds: stringArray(
                member.notificationIds,
                `Pending multisig member ${index} notifications`
            ),
        };
    });
    const memberPrefixes = members.map(({memberPrefix}) => memberPrefix);
    const hasThreeUniqueMembers =
        members.length === 3 &&
        new Set(memberPrefixes).size === 3;
    if (hasThreeUniqueMembers === false) {
        throw new Error(
            'Pending multisig operation requires three unique members'
        );
    }
    return {
        route: nonemptyString(
            pending.route,
            'Pending multisig operation route'
        ),
        groupPrefix: nonemptyString(
            pending.groupPrefix,
            'Pending multisig operation group prefix'
        ),
        members,
    };
}

export async function completePendingMultisigOperation(
    clientsByMemberPrefix: Map<string, SignifyClient>,
    pending: PendingMultisigOperation
): Promise<void> {
    const members = pending.members.map((member) => {
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
    await completePersistedCoordinatedOperations(members);
}

export function operationFrom(
    operation: Operation,
    coordination: CoordinatedOperation['coordination']
): CoordinatedOperation {
    return {operation, coordination};
}
