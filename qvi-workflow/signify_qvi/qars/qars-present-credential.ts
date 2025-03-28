import {TestEnvironmentPreset} from "../resolve-env.ts";
import {createTimestamp, parseAidInfo} from "../create-aid.ts";
import {getOrCreateClients} from "../keystore-creation.ts";
import {
    getIssuedCredential,
    getReceivedCredBySchemaAndIssuer,
    grantMultisig
} from "../credentials.ts";
import {Notification, waitAndMarkNotification} from "../notifications.ts";

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
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
    ] = await getOrCreateClients(3, [QAR1.salt, QAR2.salt, QAR3.salt], environment);

    // get QVI participant AIDs
    const QAR1Id = await QAR1Client.identifiers().get(QAR1.name);
    const QAR2Id = await QAR2Client.identifiers().get(QAR2.name);
    const QAR3Id = await QAR3Client.identifiers().get(QAR3.name);

    // get multisig
    const qviAID = await QAR1Client.identifiers().get(multisigName);

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
    const credbyQAR2 = await getIssuedCredential(
        QAR2Client,
        issuerPrefix,
        issueePrefix,
        schemaSAID
    );
    const credbyQAR3 = await getIssuedCredential(
        QAR3Client,
        issuerPrefix,
        issueePrefix,
        schemaSAID
    );

    const grantTime = createTimestamp();
    console.log(`[QVI] IPEX Granting credential to ${recipientPrefix}...`);
    console.log(`[QVI] QAR1 IPEX Granting credential to ${recipientPrefix}...`);
    await grantMultisig(
        QAR1Client,
        QAR1Id,
        [QAR2Id, QAR3Id],
        qviAID,
        recipientPrefix,
        credbyQAR1,
        grantTime,
        true
    );
    console.log(`[QVI] QAR2 IPEX Granting credential to ${recipientPrefix}...`);
    await grantMultisig(
        QAR2Client,
        QAR2Id,
        [QAR1Id, QAR3Id],
        qviAID,
        recipientPrefix,
        credbyQAR2,
        grantTime
    );
    console.log(`[QVI] QAR3 IPEX Granting credential to ${recipientPrefix}...`);
    await grantMultisig(
        QAR3Client,
        QAR3Id,
        [QAR1Id, QAR2Id],
        qviAID,
        recipientPrefix,
        credbyQAR3,
        grantTime
    );
    console.log(`[QVI] IPEX Granting credential to ${recipientPrefix}...done`);

    console.log(`[QVI] marking IPEX Grant notifications read for all QARs...`);
    try {
        await waitAndMarkNotification(QAR1Client, '/exn/ipex/grant');
    } catch (e) {
        console.log(`QAR1 did not have an /exn/ipex/grant notification to mark: ${e}`);
    }
    try {
        await waitAndMarkNotification(QAR2Client, '/exn/ipex/grant');
    } catch (e) {
        console.log(`QAR2 did not have an /exn/ipex/grant notification to mark: ${e}`);
    }
    try {
        await waitAndMarkNotification(QAR3Client, '/exn/ipex/grant');
    } catch (e) {
        console.log(`QAR3 did not have an /exn/ipex/grant notification to mark: ${e}`);
    }

    return "true";
}

const granted: string = await grantCredential(multisigName, aidInfoArg, schemaSAID, issuerPrefix, issueePrefix, recipientPrefix, env);
console.log(granted);
