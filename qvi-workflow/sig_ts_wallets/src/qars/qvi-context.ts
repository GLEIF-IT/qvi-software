import type {HabState, SignifyClient} from 'signify-ts';

export interface QviMember {
    client: SignifyClient;
    memberAid: HabState;
    groupAid: HabState;
}

/**
 * Load concrete member and group identifiers from connected wallets.
 */
export async function loadGroupMembers(
    clients: SignifyClient[],
    memberNames: string[],
    groupName: string
): Promise<QviMember[]> {
    if (clients.length !== memberNames.length) {
        throw new Error(
            'Group member clients and identifier names must have equal length'
        );
    }
    const memberAids = await Promise.all(
        memberNames.map((name, index) =>
            clients[index].identifiers().get(name)
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
