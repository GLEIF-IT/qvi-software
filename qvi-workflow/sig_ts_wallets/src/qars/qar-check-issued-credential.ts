import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {checkIssuedCredential} from "../qvi-operations.ts";
import type {TestEnvironmentPreset} from '../resolve-env.ts';

export interface CheckIssuedCredentialOptions {
    groupName: string;
    participantSource: string;
    issueePrefix: string;
    schemaSaid: string;
    environment: TestEnvironmentPreset;
}

export async function checkQarIssuedCredential(
    options: CheckIssuedCredentialOptions
) {
    return checkIssuedCredential(
        options.groupName,
        options.participantSource,
        options.schemaSaid,
        options.issueePrefix,
        options.environment
    );
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            [
                'config',
                'group-name',
                'issuee-prefix',
                'schema-said',
            ],
            [
                'environment',
                'group-name',
                'participant-source',
                'issuee-prefix',
                'schema-said',
            ]
        );
        requireNamedArguments(parsed, [
            'group-name',
            'issuee-prefix',
            'schema-said',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        return checkQarIssuedCredential({
            groupName: parsed['group-name'],
            participantSource: invocation.participantSource,
            issueePrefix: parsed['issuee-prefix'],
            schemaSaid: parsed['schema-said'],
            environment: invocation.environment,
        });
    });
}
