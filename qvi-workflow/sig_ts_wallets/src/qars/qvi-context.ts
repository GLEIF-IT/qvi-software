import type {HabState, SignifyClient} from 'signify-ts';

import {
    connectClient,
    type Participant,
    type WorkflowConfig,
} from '../client.ts';

export interface QviMemberContext {
    client: SignifyClient;
    memberAid: HabState;
    groupAid: HabState;
}

/**
 * Load the group and member identifiers for already-connected clients.
 */
async function loadMembers(
    clients: SignifyClient[],
    participants: Participant[],
    groupName: string
): Promise<QviMemberContext[]> {
    const memberAids = await Promise.all(
        participants.map((participant, index) =>
            clients[index].identifiers().get(participant.name)
        )
    );
    const groupAids = await Promise.all(
        clients.map((client) => client.identifiers().get(groupName))
    );
    return clients.map((client, index) => ({
        client,
        memberAid: memberAids[index],
        groupAid: groupAids[index],
    }));
}

/**
 * Load the final QVI roster from the generated workflow config.
 */
export async function loadQviMembers(
    config: WorkflowConfig,
    groupName: string
): Promise<QviMemberContext[]> {
    const participants = config.qvi.finalMembers.map(
        (role) => config.participants[role]
    );
    const clients = await Promise.all(participants.map(connectClient));
    return loadMembers(clients, participants, groupName);
}
