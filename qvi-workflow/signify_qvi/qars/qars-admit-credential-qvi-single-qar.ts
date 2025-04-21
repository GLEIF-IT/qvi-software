import {createTimestamp, parseAidInfo} from "../create-aid";
import {getOrCreateAID, getOrCreateClients} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {
    admitSinglesig,
    getReceivedCredential,
    waitForCredential
} from "../credentials";

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
    const {QAR1} = parseAidInfo(aidInfo);
    const [QAR1Client] = await getOrCreateClients(1, [QAR1.salt], environment);

    // get AIDs
    const aidConfigQARs = {
        toad: 1,
        wits: [WIL],
    };
    const [
            QAR1Id
    ] = await Promise.all([
        getOrCreateAID(QAR1Client, QAR1.name, aidConfigQARs)
    ]);

    let contacts = await QAR1Client.contacts().list();
    
    let credByQAR1 = await getReceivedCredential(QAR1Client, credSAID);
    if (!credByQAR1) {
        const admitTime = createTimestamp();
        await admitSinglesig(
            QAR1Client,
            QAR1Id.name,
            issuerPrefix,
        );
        credByQAR1 = await waitForCredential(QAR1Client, credSAID);
        console.log(`Credential ${credSAID} admitted by QAR1: ${credByQAR1}`);
    }
    
}
const admitResult: any = await admitCredentialQvi(multisigName, aidInfoArg, issuerPrefix, witnessIds, credSAID, env);

console.log(`credential ${credSAID} admitted`);
