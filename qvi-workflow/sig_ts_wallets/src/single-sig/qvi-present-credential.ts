import {TestEnvironmentPreset} from "../resolve-env.ts";
import {createTimestamp, parseAidInfo, parseAidInfoSingleSig} from "../create-aid.ts";
import {getOrCreateClient} from "../keystore-creation.ts";
import {getIssuedCredential, getReceivedCredBySchemaAndIssuer} from "../credentials.ts";
import {Serder} from "signify-ts";
import {waitOperation} from "../operations.ts";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]
const schemaSAID = args[2]
const issuerPrefix = args[3]
const issueePrefix = args[4]
const recipientPrefix = args[5]

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
    issueePrefix: string, recipientPrefix: string, environment: TestEnvironmentPreset): Promise<string> {
    // get QAR Clients
    const {QVI} = parseAidInfoSingleSig(aidInfo);
    const QVIClient = await getOrCreateClient(QVI.salt, environment, 1);

    // Check to see if the credential exists
    let receivedCred = await getReceivedCredBySchemaAndIssuer(
        QVIClient,
        schemaSAID,
        issuerPrefix
    )
    if (!receivedCred) {
        return "false-credential-not-found"
    }

    // grant credential
    const cred = await getIssuedCredential(
        QVIClient,
        issuerPrefix,
        issueePrefix,
        schemaSAID
    );

    const grantTime = createTimestamp();
    console.log(`[QVI] QVI IPEX Granting credential to ${recipientPrefix}...`);
    const [grant, gsigs, gend] = await QVIClient.ipex().grant({
        senderName: QVI.name,
        acdc: new Serder(receivedCred.sad),
        anc: new Serder(receivedCred.anc),
        iss: new Serder(receivedCred.iss),
        ancAttachment: receivedCred.ancAttachment,
        recipient: recipientPrefix,
        datetime: grantTime,
    });

    const op = await QVIClient
        .ipex()
        .submitGrant(QVI.name, grant, gsigs, gend, [
            recipientPrefix,
        ]);
    await waitOperation(QVIClient, op);

    return op.response;
}

const granted: string = await grantCredential(aidInfoArg, schemaSAID, issuerPrefix, issueePrefix, recipientPrefix, env);
console.log(granted);
