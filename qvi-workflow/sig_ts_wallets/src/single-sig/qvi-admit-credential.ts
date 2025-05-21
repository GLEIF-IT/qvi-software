import {parseAidInfoSingleSig} from "../create-aid";
import {getOrCreateClient} from "../keystore-creation";
import {TestEnvironmentPreset} from "../resolve-env";
import {admitSinglesig, getReceivedCredential, waitForCredential} from "../credentials";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]
const issuerPrefix = args[2]
const credSAID = args[3]

/**
 * Admits a credential using the QVI AID
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param issuerPrefix identifier of the issuer AID who issued the credential to admit by the QARs for the QVI multisig
 * @param credSAID the SAID of the credential to admit
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function admitCredentialQvi(aidInfo: string, issuerPrefix: string, credSAID: string, environment: TestEnvironmentPreset) {
    const {QVI} = parseAidInfoSingleSig(aidInfo);
    const QVIClient = await getOrCreateClient(QVI.salt, environment, 1);
    const QVIId = await QVIClient.identifiers().get(QVI.name);
    
    let cred = await getReceivedCredential(QVIClient, credSAID);
    if (!cred) {
        await admitSinglesig(
            QVIClient,
            QVIId.name,
            issuerPrefix,
        );
        cred = await waitForCredential(QVIClient, credSAID);
        console.log(`Credential ${credSAID} admitted by QVI: `, cred.sad.a);
    }
}
const admitResult: any = await admitCredentialQvi(aidInfoArg, issuerPrefix, credSAID, env);

console.log(`Credential ${credSAID} admitted`);
