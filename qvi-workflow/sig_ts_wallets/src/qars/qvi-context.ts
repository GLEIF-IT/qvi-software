import type {HabState, SignifyClient} from 'signify-ts';

import type {ParticipantConfig} from '../cli.ts';
import {getOrCreateClient} from '../keystore-creation.ts';

export interface QviMemberContext {
    client: SignifyClient;
    memberAid: HabState;
    groupAid: HabState;
}

export async function loadQviMembers(
    config: ParticipantConfig,
    groupName: string
): Promise<QviMemberContext[]> {
    const participants = [
        config.participants.qar1,
        config.participants.qar2,
        config.participants.qar3,
    ];
    const clients = await Promise.all(
        participants.map((participant) =>
            getOrCreateClient(
                participant.salt,
                config.environment,
                participant.keriaHost
            )
        )
    );
    const memberAids = await Promise.all(
        participants.map((participant, index) =>
            clients[index].identifiers().get(participant.name)
        )
    );
    const groupAids = await Promise.all(
        clients.map((client) =>
            client.identifiers().get(groupName)
        )
    );
    return clients.map((client, index) => ({
        client,
        memberAid: memberAids[index],
        groupAid: groupAids[index],
    }));
}
