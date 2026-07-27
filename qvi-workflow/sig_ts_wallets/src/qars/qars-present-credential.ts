import {createTimestamp} from '../create-aid.ts';
import type {GroupMember} from '../client.ts';
import {grantCredential} from '../ipex.ts';
import {getCredential} from '../credential-state.ts';

export interface PresentCredentialOptions {
    members: GroupMember[];
    initiatorPrefix: string;
    credentialSaid: string;
    recipientPrefix: string;
}

/** Present one credential from the final QVI roster. */
export async function presentCredential(
    options: PresentCredentialOptions
) {
    const members = options.members;
    const credentials = await Promise.all(
        members.map(({client}) =>
            getCredential(client, options.credentialSaid)
        )
    );
    await grantCredential({
        members,
        initiatorPrefix: options.initiatorPrefix,
        recipientPrefix: options.recipientPrefix,
        credentials,
        timestamp: createTimestamp(),
    });
    return {
        status: 'presented' as const,
        credentialSaid: options.credentialSaid,
        recipientPrefix: options.recipientPrefix,
    };
}
