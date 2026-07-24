import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
} from '../cli.ts';
import {createTimestamp} from '../create-aid.ts';
import {
    admitMultisig,
    waitForCredential,
} from '../credentials.ts';
import {credentialSnapshot} from '../credential-state.ts';
import {coordinateMultisigOperation} from '../multisig-coordinator.ts';
import {loadQviMembers} from './qvi-context.ts';

export async function admitCredentialQvi(
    config: ParticipantConfig,
    groupName: string,
    issuerPrefix: string,
    credentialSaid: string
) {
    const members = await loadQviMembers(config, groupName);
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

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'group-name',
            'issuer-prefix',
            'credential-said',
        ]);
        requireNamedArguments(args, [
            'group-name',
            'issuer-prefix',
            'credential-said',
        ]);
        const snapshots = await admitCredentialQvi(
            participantConfigFromArguments(args),
            args['group-name'],
            args['issuer-prefix'],
            args['credential-said']
        );
        return {
            status: 'admitted',
            credentialSaid: args['credential-said'],
            observations: snapshots,
        };
    });
}
