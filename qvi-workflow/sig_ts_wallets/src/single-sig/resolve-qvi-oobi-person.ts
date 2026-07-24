import {parseAidInfoSingleSig} from "../create-aid.ts";
import {TestEnvironmentPreset} from "../resolve-env.ts";
import {getOrCreateClient} from "../keystore-creation.ts";
import {getOrCreateContact} from "../agent-contacts.ts";
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    requireNamedArguments,
    runJsonCli,
    singleSigParticipantInvocationFromArguments,
} from '../cli.ts';

/**
 * Resolves the QVI Multisig OOBI for the Person in preparation for receiving the ECR and OOR credentials
 * @param qviName
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param qviOobi The QVI multisig OOBI
 * @param environment the runtime environment to use for resolving environment variables
 */
export async function resolveQviOobi(
    qviName: string,
    aidInfo: string,
    qviOobi: string,
    environment: TestEnvironmentPreset
) {
    // create SignifyTS Clients
    const {PERSON} = parseAidInfoSingleSig(aidInfo);
    // Create SignifyTS Clients
    const personClient = await getOrCreateClient(PERSON.salt, environment, 1);
    await getOrCreateContact(personClient, qviName, qviOobi);
    return {status: 'resolved' as const, qviName};
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            ['config', 'qvi-name', 'qvi-oobi'],
            [
                'environment',
                'qvi-name',
                'participant-source',
                'qvi-oobi',
            ]
        );
        requireNamedArguments(parsed, ['qvi-name', 'qvi-oobi']);
        const invocation =
            singleSigParticipantInvocationFromArguments(parsed);
        return resolveQviOobi(
            parsed['qvi-name'],
            invocation.participantSource,
            parsed['qvi-oobi'],
            invocation.environment
        );
    });
}
