import {readFileSync} from 'node:fs';

import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {
    completePendingMultisigOperation,
    parsePendingMultisigOperation,
} from '../multisig-coordinator.ts';
import {refreshGedaMultisigstate} from '../qvi-operations.ts';
import {loadQviMembers} from './qvi-context.ts';

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'geda-prefix',
            'group-name',
            'operation-artifact',
        ]);
        requireNamedArguments(args, ['geda-prefix']);
        const config = participantConfigFromArguments(args);
        const invocation = participantInvocationFromArguments(args);
        const clients = await refreshGedaMultisigstate(
            invocation.participantSource,
            args['geda-prefix'],
            invocation.environment
        );
        if (args['operation-artifact'] !== undefined) {
            requireNamedArguments(args, ['group-name']);
            const artifact = JSON.parse(
                readFileSync(args['operation-artifact'], 'utf8')
            ) as Record<string, unknown>;
            const pending =
                parsePendingMultisigOperation(artifact.pending);
            const members = await loadQviMembers(
                config,
                args['group-name']
            );
            await completePendingMultisigOperation(
                new Map(
                    members.map(({client, memberAid}) => [
                        memberAid.prefix,
                        client,
                    ])
                ),
                pending
            );
        }
        return {
            status: 'refreshed',
            agents: [
                clients.QAR1Client.agent?.pre,
                clients.QAR2Client.agent?.pre,
                clients.QAR3Client.agent?.pre,
            ],
        };
    });
}
