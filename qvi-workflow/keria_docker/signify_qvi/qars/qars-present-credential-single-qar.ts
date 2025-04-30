import {TestEnvironmentPreset} from "../resolve-env.ts";
import {createTimestamp, parseAidInfo} from "../create-aid.ts";
import {getOrCreateClients} from "../keystore-creation.ts";
import {
    getIssuedCredential,
    getReceivedCredBySchemaAndIssuer,
    grantMultisig
} from "../credentials.ts";
import {Notification, waitAndMarkNotification} from "../notifications.ts";
import {Serder} from "signify-ts";
import {waitOperation} from "../operations.ts";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1]
const aidInfoArg = args[2]
const schemaSAID = args[3]
const issuerPrefix = args[4]
const issueePrefix = args[5]
const recipientPrefix = args[6]

/**
 * Grants a credential from the QVI multisig AID to a recipient
 *
 * @param multisigName name of the multisig AID
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param schemaSAID The schema SAID of the type of credential issuance to check for.
 * @param issuerPrefix identifier of the issuer AID who issued the credential
 * @param issueePrefix identifier of the original issuee of the credential being presented
 * @param recipientPrefix identifier of the recipient AID who will receive the credential presentation
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
export async function grantCredential(
    multisigName: string, aidInfo: string, schemaSAID: string, issuerPrefix: string,
    issueePrefix: string, recipientPrefix: string, environment: TestEnvironmentPreset): Promise<string> {
    // get QAR Clients
    const {QAR1} = parseAidInfo(aidInfo);
    const [QAR1Client] = await getOrCreateClients(1, [QAR1.salt], environment);

    // get QVI participant AIDs
    const QAR1Id = await QAR1Client.identifiers().get(QAR1.name);


    // Check to see if the credential exists
    let receivedCred = await getReceivedCredBySchemaAndIssuer(
        QAR1Client,
        schemaSAID,
        issuerPrefix
    )
    if (!receivedCred) {
        return "false-credential-not-found"
    }

    // grant credential
    const credbyQAR1 = await getIssuedCredential(
        QAR1Client,
        issuerPrefix,
        issueePrefix,
        schemaSAID
    );

    const grantTime = createTimestamp();
    console.log(`[QVI] IPEX Granting credential to ${recipientPrefix}...`);
    console.log(`[QVI] QAR1 IPEX Granting credential to ${recipientPrefix}...`);
    const [grant, gsigs, gend] = await QAR1Client.ipex().grant({
        senderName: QAR1.name,
        acdc: new Serder(receivedCred.sad),
        anc: new Serder(receivedCred.anc),
        iss: new Serder(receivedCred.iss),
        ancAttachment: receivedCred.ancAttachment,
        recipient: recipientPrefix,
        datetime: grantTime,
    });

    const op = await QAR1Client
        .ipex()
        .submitGrant(QAR1.name, grant, gsigs, gend, [
            recipientPrefix,
        ]);
    await waitOperation(QAR1Client, op);

    return op.response;
}

const granted: string = await grantCredential(multisigName, aidInfoArg, schemaSAID, issuerPrefix, issueePrefix, recipientPrefix, env);
console.log(granted);
