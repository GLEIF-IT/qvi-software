import {getOrCreateContact} from "../agent-contacts";
import {getOrCreateClient} from "../keystore-creation";
import {TestEnvironmentPreset} from "../resolve-env";
import {parseAidInfo} from "../create-aid";
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';

/**
 * Resolves an OOBI for the QVI Multisig participants.
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param alias
 * @param oobi The QVI multisig OOBI
 * @param environment the runtime environment to use for resolving environment variables
 */
export async function resolveQVIOobi(aidInfo: string, alias: string, oobi: string, environment: TestEnvironmentPreset) {
    // create SignifyTS Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const QAR1Client = await getOrCreateClient(QAR1.salt, environment, 1);
    const QAR2Client = await getOrCreateClient(QAR2.salt, environment, 2);
    const QAR3Client = await getOrCreateClient(QAR3.salt, environment, 3);

    await getOrCreateContact(QAR1Client, alias, oobi);
    await getOrCreateContact(QAR2Client, alias, oobi);
    await getOrCreateContact(QAR3Client, alias, oobi);
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            ['config', 'alias', 'oobi'],
            ['environment', 'participant-source', 'alias', 'oobi']
        );
        requireNamedArguments(parsed, ['alias', 'oobi']);
        const invocation = participantInvocationFromArguments(parsed);
        await resolveQVIOobi(
            invocation.participantSource,
            parsed.alias,
            parsed.oobi,
            invocation.environment
        );
        return {
            status: 'resolved',
            alias: parsed.alias,
            oobi: parsed.oobi,
        };
    });
}
