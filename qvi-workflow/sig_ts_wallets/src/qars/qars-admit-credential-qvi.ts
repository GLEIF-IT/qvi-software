import {createTimestamp} from '../create-aid.ts';
import type {GroupMember} from '../client.ts';
import {
    admitCredential,
    waitForCredential,
} from '../credentials.ts';
import {credentialSnapshot} from '../credential-state.ts';

/** Admit one credential through the final QVI roster. */
export async function admitCredentialQvi(
    members: GroupMember[],
    issuerPrefix: string,
    credentialSaid: string
) {
    const initiator = members[0];
    if (initiator === undefined) {
        throw new Error('Credential admission requires group members');
    }
    const timestamp = createTimestamp();
    await admitCredential({
        members,
        initiatorPrefix: initiator.memberAid.prefix,
        issuerPrefix,
        credentialSaid,
        timestamp,
    });
    return Promise.all(
        members.map(async ({client, memberAid}) =>
            credentialSnapshot(
                await waitForCredential(client, credentialSaid),
                memberAid.prefix
            )
        )
    );
}
