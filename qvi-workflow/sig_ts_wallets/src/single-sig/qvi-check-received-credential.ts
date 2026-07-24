import {
    isMainModule,
    parseNamedArguments,
    requireNamedArguments,
    runJsonCli,
    singleSigParticipantInvocationFromArguments,
} from '../cli.ts';
import {checkReceivedCredentialSingleSig} from "./qvi-operations-single-sig.ts";

export async function checkQviReceivedCredential(options: {
    participantSource: string;
    credentialSaid: string;
    environment: Parameters<
        typeof checkReceivedCredentialSingleSig
    >[2];
}) {
    return checkReceivedCredentialSingleSig(
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
                'credential-said',
            ]
        );
        requireNamedArguments(parsed, ['credential-said']);
        const invocation =
            singleSigParticipantInvocationFromArguments(parsed);
        return checkQviReceivedCredential({
            participantSource: invocation.participantSource,
            credentialSaid: parsed['credential-said'],
            environment: invocation.environment,
        });
    });
}
