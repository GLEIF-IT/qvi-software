import type {
    CredentialData,
    CredentialResult,
} from 'signify-ts';

import type {GroupMember} from '../client.ts';
import {createTimestamp} from '../create-aid.ts';
import {
    grantCredential,
    issueCredential,
} from '../credentials.ts';
import {
    credentialSnapshot,
    type CredentialSnapshot,
} from '../credential-state.ts';

export interface IssueAndGrantOptions {
    members: GroupMember[];
    groupName: string;
    issueePrefix: string;
    credentialData: CredentialData;
}

export interface IssuedCredential {
    credential: CredentialResult;
    snapshot: CredentialSnapshot;
}

/** Issue and grant one credential through the final QVI roster. */
export async function issueAndGrantCredential(
    options: IssueAndGrantOptions
): Promise<IssuedCredential[]> {
    const members = options.members;
    const initiator = members[0];
    if (initiator === undefined) {
        throw new Error('Credential issuance requires group members');
    }
    const credentials = await issueCredential({
        members,
        initiatorPrefix: initiator.memberAid.prefix,
        groupName: options.groupName,
        issueePrefix: options.issueePrefix,
        credentialData: options.credentialData,
    });
    await grantCredential({
        members,
        initiatorPrefix: initiator.memberAid.prefix,
        recipientPrefix: options.issueePrefix,
        credentials,
        timestamp: createTimestamp(),
    });
    return credentials.map((credential, index) => ({
        credential,
        snapshot: credentialSnapshot(
            credential,
            members[index].memberAid.prefix
        ),
    }));
}
