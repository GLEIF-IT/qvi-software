import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {
    credentialSnapshot,
    getCredential,
} from '../credential-state.ts';
import {assertCredentialConvergence} from '../workflow-assertions.ts';
import {loadQviMembers} from './qvi-context.ts';

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'group-name',
            'credential-said',
            'issuer-prefix',
            'schema',
            'issuee-prefix',
            'status-sequence',
        ]);
        requireNamedArguments(args, [
            'group-name',
            'credential-said',
            'issuer-prefix',
            'schema',
            'issuee-prefix',
            'status-sequence',
        ]);
        const config = participantConfigFromArguments(args);
        const members = await loadQviMembers(
            config,
            args['group-name']
        );
        const snapshots = await Promise.all(
            members.map(async ({client, memberAid}) =>
                credentialSnapshot(
                    await getCredential(
                        client,
                        args['credential-said']
                    ),
                    memberAid.prefix
                )
            )
        );
        const state = assertCredentialConvergence(
            snapshots,
            members.map(({memberAid}) => memberAid.prefix),
            {
                said: args['credential-said'],
                issuer: args['issuer-prefix'],
                schema: args.schema,
                issuee: args['issuee-prefix'],
                statusSequence: args['status-sequence'],
            }
        );
        return {status: 'converged', state};
    });
}
