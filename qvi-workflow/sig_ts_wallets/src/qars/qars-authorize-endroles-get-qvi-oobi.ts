import {
    assertQviEndRoles,
    observeQviEndpoints,
} from '../assertions.ts';
import type {GroupMember} from '../client.ts';
import {createTimestamp} from '../create-aid.ts';
import {authorizeEndRole} from '../multisig-creation.ts';
import {retry} from '../retry.ts';

export interface AuthorizeEndRoleOptions {
    members: GroupMember[];
    groupName: string;
}

/** Read the unique connected agent EIDs for concrete group members. */
function memberAgentEids(members: GroupMember[]): string[] {
    const eids = members.map(({client}) => client.agent?.pre);
    if (
        eids.some(
            (eid) => typeof eid !== 'string' || eid.length === 0
        )
    ) {
        throw new Error('A group member has no connected agent AID');
    }
    const values = eids as string[];
    if (new Set(values).size !== values.length) {
        throw new Error('Group member agent EIDs must be unique');
    }
    return values;
}

/**
 * Preserve the combined authorization behavior used by deferred workflows.
 *
 * The canonical workflow calls the focused authorization and assertion
 * functions directly.
 */
export async function authorizeAgentEndRoles(
    options: AuthorizeEndRoleOptions
) {
    const members = options.members;
    const initiator = members[0];
    if (initiator === undefined) {
        throw new Error('Endpoint authorization requires group members');
    }
    const qviPrefix = initiator.groupAid.prefix;
    if (
        members.some(
            ({groupAid}) => groupAid.prefix !== qviPrefix
        )
    ) {
        throw new Error('Group members disagree on the group prefix');
    }
    const clients = members.map(({client}) => client);
    const existing = await Promise.all(
        clients.map((client) =>
            client.oobis().endroles(qviPrefix, 'agent')
        )
    );
    if (existing.some((roles) => roles.length > 0)) {
        throw new Error(
            'QVI agent roles already exist; authorization is a one-shot phase'
        );
    }
    const expectedEids = memberAgentEids(members);
    const expectedEndpoints = await observeQviEndpoints(
        clients,
        options.groupName,
        expectedEids
    );
    const timestamp = createTimestamp();
    for (const eid of expectedEids) {
        await authorizeEndRole({
            members,
            initiatorPrefix: initiator.memberAid.prefix,
            eid,
            timestamp,
        });
    }
    return await retry(() =>
        assertQviEndRoles(
            clients,
            options.groupName,
            qviPrefix,
            expectedEndpoints
        )
    );
}
