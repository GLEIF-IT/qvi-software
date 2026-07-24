import {
    isMainModule,
    parseNamedArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {checkReceivedCredential} from "../qvi-operations.ts";
import type {TestEnvironmentPreset} from '../resolve-env.ts';

export async function checkQarReceivedCredential(options: {
    groupName: string;
    participantSource: string;
    credentialSaid: string;
    environment: TestEnvironmentPreset;
}) {
    return checkReceivedCredential(
        options.groupName,
        options.participantSource,
        options.credentialSaid,
        options.environment
    );
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedArguments(
            process.argv.slice(2),
            [
                'config',
                'environment',
                'participant-source',
                'group-name',
                'credential-said',
            ]
        );
        requireNamedArguments(parsed, [
            'group-name',
            'credential-said',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        return checkQarReceivedCredential({
            groupName: parsed['group-name'],
            participantSource: invocation.participantSource,
            credentialSaid: parsed['credential-said'],
            environment: invocation.environment,
        });
    });
}
