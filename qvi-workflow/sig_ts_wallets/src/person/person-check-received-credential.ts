import {TestEnvironmentPreset} from "../resolve-env.ts";
import {parseAidInfo} from "../create-aid.ts";
import {getOrCreateClient} from "../keystore-creation.ts";
import {getReceivedCredBySchemaAndIssuer} from "../credential-mutations.ts";
import {
    isMainModule,
    parseNamedArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';

/**
 * Checks to see if the Person has a credential
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param schemaSAID The schema SAID of the type of credential issuance to check for.
 * @param issuerPrefix identifier of the issuer AID who issued the credential
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
export async function checkReceivedCredentialPerson(aidInfo: string, schemaSAID: string, issuerPrefix: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {PERSON} = parseAidInfo(aidInfo);
    const PersonClient = await getOrCreateClient(PERSON.salt, environment, 1);

    // Check to see if the QVI credential exists
    const receivedCred = await getReceivedCredBySchemaAndIssuer(
        PersonClient,
        schemaSAID,
        issuerPrefix
    );
    const credentialIsMissing = receivedCred === undefined;
    if (credentialIsMissing) {
        return {found: false as const};
    }
    return {
        found: true as const,
        credentialSaid: receivedCred.sad.d,
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedArguments(
            process.argv.slice(2),
            [
                'config',
                'environment',
                'participant-source',
                'schema-said',
                'issuer-prefix',
            ]
        );
        requireNamedArguments(parsed, [
            'schema-said',
            'issuer-prefix',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        return checkReceivedCredentialPerson(
            invocation.participantSource,
            parsed['schema-said'],
            parsed['issuer-prefix'],
            invocation.environment
        );
    });
}
