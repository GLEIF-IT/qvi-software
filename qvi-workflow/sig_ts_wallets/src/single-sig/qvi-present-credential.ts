import {TestEnvironmentPreset} from "../resolve-env.ts";
import {createTimestamp, parseAidInfoSingleSig} from "../create-aid.ts";
import {getOrCreateClient} from "../keystore-creation.ts";
import {getReceivedCredBySchemaAndIssuer} from "../credential-mutations.ts";
import {Serder} from "signify-ts";
import {
    requireOperationResponse,
    waitOperation,
} from "../operations.ts";
import {
    isMainModule,
    parseNamedArguments,
    requireNamedArguments,
    runJsonCli,
    singleSigParticipantInvocationFromArguments,
} from '../cli.ts';

/**
 * Grants a credential from the QVI multisig AID to a recipient
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param schemaSAID The schema SAID of the type of credential issuance to check for.
 * @param issuerPrefix identifier of the issuer AID who issued the credential
 * @param issueePrefix identifier of the original issuee of the credential being presented
 * @param recipientPrefix identifier of the recipient AID who will receive the credential presentation
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
export async function grantCredential(
    aidInfo: string, schemaSAID: string, issuerPrefix: string,
    issueePrefix: string, recipientPrefix: string, environment: TestEnvironmentPreset) {
    // get QAR Clients
    const {QVI} = parseAidInfoSingleSig(aidInfo);
    const QVIClient = await getOrCreateClient(QVI.salt, environment, 1);

    // Check to see if the credential exists
    const receivedCred = await getReceivedCredBySchemaAndIssuer(
        QVIClient,
        schemaSAID,
        issuerPrefix
    )
    const credentialIsMissing = receivedCred === undefined;
    if (credentialIsMissing) {
        throw new Error(
            `Credential from issuer ${issuerPrefix} with schema ${schemaSAID} was not found`
        );
    }

    const grantTime = createTimestamp();
    console.log(`[QVI] QVI IPEX Granting credential to ${recipientPrefix}...`);
    const [grant, gsigs, gend] = await QVIClient.ipex().grant({
        senderName: QVI.name,
        acdc: new Serder(receivedCred.sad),
        anc: new Serder(receivedCred.anc),
        iss: new Serder(receivedCred.iss),
        ancAttachment: receivedCred.ancatc,
        recipient: recipientPrefix,
        datetime: grantTime,
    });

    const op = await QVIClient
        .ipex()
        .submitGrant(QVI.name, grant, gsigs, gend, [
            recipientPrefix,
        ]);
    const completed = await waitOperation(QVIClient, op);
    const response = requireOperationResponse(
        completed,
        (value): value is {said: string} =>
            typeof value === 'object' &&
            value !== null &&
            typeof (value as {said?: unknown}).said === 'string',
        'QVI IPEX grant'
    );

    return {
        status: 'granted' as const,
        credentialSaid: receivedCred.sad.d,
        exchangeSaid: response.said,
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
                'issuee-prefix',
                'recipient-prefix',
            ]
        );
        requireNamedArguments(parsed, [
            'schema-said',
            'issuer-prefix',
            'issuee-prefix',
            'recipient-prefix',
        ]);
        const invocation =
            singleSigParticipantInvocationFromArguments(parsed);
        return grantCredential(
            invocation.participantSource,
            parsed['schema-said'],
            parsed['issuer-prefix'],
            parsed['issuee-prefix'],
            parsed['recipient-prefix'],
            invocation.environment
        );
    });
}
