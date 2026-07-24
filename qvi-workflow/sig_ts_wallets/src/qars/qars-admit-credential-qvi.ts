import {createTimestamp} from '../create-aid.ts';
import {
    admitMultisig,
    waitForCredential,
} from '../credentials.ts';
import {credentialSnapshot} from '../credential-state.ts';
import {coordinateMultisigOperation} from '../multisig-coordinator.ts';
import type {QviMember} from './qvi-context.ts';

/** Admit one credential through the final QVI roster. */
export async function admitCredentialQvi(
    members: QviMember[],
    issuerPrefix: string,
    credentialSaid: string
) {
    const timestamp = createTimestamp();
    await coordinateMultisigOperation(
        members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        (context) => {
            const member = members.find(
                ({memberAid}) =>
                    memberAid.prefix === context.aid.prefix
            );
            if (member === undefined) {
                throw new Error(
                    `Missing QVI member ${context.aid.prefix}`
                );
            }
            return admitMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                member.groupAid,
                issuerPrefix,
                credentialSaid,
                timestamp,
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            );
        }
    );
    return Promise.all(
        members.map(async ({client, memberAid}) =>
            credentialSnapshot(
                await waitForCredential(client, credentialSaid),
                memberAid.prefix
            )
        )
    );
}
