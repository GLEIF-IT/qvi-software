import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {readGroupObservation} from '../group-state.ts';
import {
    qviNextThreshold,
    qviSigningThreshold,
} from '../qvi-configuration.ts';
import {assertGroupStateConvergence} from '../workflow-assertions.ts';
import {loadQviMembers} from './qvi-context.ts';

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'group-name',
            'group-prefix',
            'delegator-prefix',
            'sequence',
        ]);
        requireNamedArguments(args, [
            'group-name',
            'group-prefix',
            'delegator-prefix',
            'sequence',
        ]);
        const config = participantConfigFromArguments(args);
        const members = await loadQviMembers(
            config,
            args['group-name']
        );
        const memberPrefixes = members.map(
            ({memberAid}) => memberAid.prefix
        );
        const observations = await Promise.all(
            members.map(({client, memberAid}) =>
                readGroupObservation(
                    client,
                    memberAid.prefix,
                    args['group-name']
                )
            )
        );
        const state = assertGroupStateConvergence(observations, {
            prefix: args['group-prefix'],
            delegator: args['delegator-prefix'],
            sequence: args.sequence,
            signingThreshold: qviSigningThreshold(),
            nextThreshold: qviNextThreshold(),
            members: memberPrefixes,
        });
        return {status: 'converged', state};
    });
}
