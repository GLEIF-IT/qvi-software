import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
} from '../cli.ts';
import {createTimestamp} from '../create-aid.ts';
import {grantMultisig} from '../credentials.ts';
import {getCredential} from '../credential-state.ts';
import {coordinateMultisigOperation} from '../multisig-coordinator.ts';
import {loadQviMembers} from './qvi-context.ts';

export interface PresentCredentialOptions {
    config: ParticipantConfig;
    groupName: string;
    credentialSaid: string;
    recipientPrefix: string;
}

export async function presentCredential(
    options: PresentCredentialOptions
) {
    const members = await loadQviMembers(
        options.config,
        options.groupName
    );
    const credentials = await Promise.all(
        members.map(({client}) =>
            getCredential(client, options.credentialSaid)
        )
    );
    const timestamp = createTimestamp();
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
                options.recipientPrefix,
                credentials[memberIndex],
                timestamp,
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            );
        }
    );
    return {
        status: 'presented' as const,
        credentialSaid: options.credentialSaid,
        recipientPrefix: options.recipientPrefix,
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'group-name',
            'credential-said',
            'recipient-prefix',
        ]);
        requireNamedArguments(args, [
            'group-name',
            'credential-said',
            'recipient-prefix',
        ]);
        return presentCredential({
            config: participantConfigFromArguments(args),
            groupName: args['group-name'],
            credentialSaid: args['credential-said'],
            recipientPrefix: args['recipient-prefix'],
        });
    });
}
