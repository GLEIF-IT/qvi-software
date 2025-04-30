import {createTimestamp, parseAidInfo} from "../create-aid";
import {getOrCreateAID, getOrCreateClients} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {admitMultisig, getReceivedCredential, waitForCredential} from "../credentials";
import {waitAndMarkNotification} from "../notifications";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1]
const aidInfoArg = args[2]
const issuerPrefix = args[3]
const credSAID = args[4]

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);


/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param issuerPrefix identifier of the issuer AID who issued the credential to admit by the QARs for the QVI multisig
 * @param witnessIds list of witness IDs for the QVI multisig AID configuration
 * @param credSAID the SAID of the credential to admit
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function admitCredentialQvi(multisigName: string, aidInfo: string, issuerPrefix: string, witnessIds: Array<string>, credSAID: string, environment: TestEnvironmentPreset) {
    const [WAN, WIL, WES, WIT] = witnessIds; // QARs use WIL, Person uses WES

    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
    ] = await getOrCreateClients(3, [QAR1.salt, QAR2.salt, QAR3.salt], environment);

    // get AIDs
    const aidConfigQARs = {
        toad: 1,
        wits: [WIL],
    };
    const [
            QAR1Id,
            QAR2Id,
            QAR3Id,
    ] = await Promise.all([
        getOrCreateAID(QAR1Client, QAR1.name, aidConfigQARs),
        getOrCreateAID(QAR2Client, QAR2.name, aidConfigQARs),
        getOrCreateAID(QAR3Client, QAR3.name, aidConfigQARs),
    ]);

    // Get the QVI multisig AID
    const qar1Ms = await QAR1Client.identifiers().get(multisigName);
    // Skip if a QVI AID has already been incepted.
    
    let credByQAR1 = await getReceivedCredential(QAR1Client, credSAID);
    let credByQAR2 = await getReceivedCredential(QAR2Client, credSAID);
    let credByQAR3 = await getReceivedCredential(QAR3Client, credSAID);
    if (!(credByQAR1 && credByQAR2 && credByQAR3)) {
        const admitTime = createTimestamp();
        await admitMultisig(
            QAR1Client,
            QAR1Id,
            [QAR2Id, QAR3Id],
            qar1Ms,
            issuerPrefix,
            admitTime
        );
        await admitMultisig(
            QAR2Client,
            QAR2Id,
            [QAR1Id, QAR3Id],
            qar1Ms,
            issuerPrefix,
            admitTime
        );
        await admitMultisig(
            QAR3Client,
            QAR3Id,
            [QAR1Id, QAR2Id],
            qar1Ms,
            issuerPrefix,
            admitTime
        );
        try {
            await waitAndMarkNotification(QAR1Client, '/multisig/exn');
            console.log(`/multisig/exn notification marked for QAR1`);
        } catch (e) {
            // Handle the case where the notification was not received
            console.error(`Failed to mark notification for QAR1: ${e}`);
        }
        try {
            await waitAndMarkNotification(QAR2Client, '/multisig/exn');
            console.log(`/multisig/exn notification marked for QAR2`);
        }
        catch (e) {
            // Handle the case where the notification was not received
            console.error(`Failed to mark notification for QAR2: ${e}`);
        }
        try {
            await waitAndMarkNotification(QAR3Client, '/multisig/exn');
            console.log(`/multisig/exn notification marked for QAR3`);
        } catch (e) {
            // Handle the case where the notification was not received
            console.error(`Failed to mark notification for QAR3: ${e}`);
        }
        try {
            await waitAndMarkNotification(QAR1Client, '/exn/ipex/admit');
            console.log(`/exn/ipex/admit notification marked for QAR1`);
        } catch (e) {
            // Handle the case where the notification was not received
            console.error(`Failed to mark notification for QAR1: ${e}`);
        }
        try {
            await waitAndMarkNotification(QAR2Client, '/exn/ipex/admit');
            console.log(`/exn/ipex/admit notification marked for QAR2`);
        } catch (e) {
            // Handle the case where the notification was not received
            console.error(`Failed to mark notification for QAR2: ${e}`);
        }
        try {
            await waitAndMarkNotification(QAR3Client, '/exn/ipex/admit');
            console.log(`/exn/ipex/admit notification marked for QAR3`);
        } catch (e) {
            // Handle the case where the notification was not received
            console.error(`Failed to mark notification for QAR3: ${e}`);
        }

        credByQAR1 = await waitForCredential(QAR1Client, credSAID);
        credByQAR2 = await waitForCredential(QAR2Client, credSAID);
        credByQAR3 = await waitForCredential(QAR3Client, credSAID);
    }
    
}
const admitResult: any = await admitCredentialQvi(multisigName, aidInfoArg, issuerPrefix, witnessIds, credSAID, env);

console.log(`credential ${credSAID} admitted`);
