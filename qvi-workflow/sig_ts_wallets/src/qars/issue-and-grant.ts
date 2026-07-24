import type {
    CredentialData,
    CredentialResult,
} from 'signify-ts';

import {createTimestamp} from '../create-aid.ts';
import {
    getIssuedCredential,
    grantMultisig,
    issueCredentialMultisig,
    requireCredential,
} from '../credentials.ts';
import {
    credentialSnapshot,
    type CredentialSnapshot,
} from '../credential-state.ts';
import {coordinateMultisigOperation} from '../multisig-coordinator.ts';
import type {QviMember} from './qvi-context.ts';

export interface IssueAndGrantOptions {
    members: QviMember[];
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
    const schema = options.credentialData.s;
    if (typeof schema !== 'string' || schema.length === 0) {
        throw new Error(
            'Credential issuance requires a schema SAID'
        );
    }
    const members = options.members;
    await coordinateMultisigOperation(
        members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        (context) =>
            issueCredentialMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                options.groupName,
                options.credentialData,
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            )
    );

    const credentials = await Promise.all(
        members.map(async ({client, groupAid}, index) =>
            requireCredential(
                await getIssuedCredential(
                    client,
                    groupAid.prefix,
                    options.issueePrefix,
                    schema
                ),
                `QAR${index + 1} issued credential`
            )
        )
    );
    const grantTimestamp = createTimestamp();
    await coordinateMultisigOperation(
        members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        (context) => {
            const memberIndex = members.findIndex(
                ({memberAid}) =>
                    memberAid.prefix === context.aid.prefix
            );
            if (memberIndex < 0) {
                throw new Error(
                    `Missing QVI member ${context.aid.prefix}`
                );
            }
            return grantMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                members[memberIndex].groupAid,
                options.issueePrefix,
                credentials[memberIndex],
                grantTimestamp,
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            );
        }
    );
    return credentials.map((credential, index) => ({
        credential,
        snapshot: credentialSnapshot(
            credential,
            members[index].memberAid.prefix
        ),
    }));
}
