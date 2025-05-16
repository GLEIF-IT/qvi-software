import {createTimestamp, parseAidInfo} from "../create-aid";
import {getOrCreateAID, getOrCreateClients} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {
    admitMultisig,
    admitSinglesig,
    getReceivedCredential,
    waitForCredential
} from "../credentials";
import {waitAndMarkNotification} from "../notifications";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]
const issuerPrefixArg = args[2]
const credSAIDArg = args[3]

/**
 * Admits a credential for the person AID
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param issuerPrefix identifier of the issuer AID who issued the credential to admit by the QARs for the QVI multisig
 * @param credSAID the SAID of the credential to admit
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function admitCredential(aidInfo: string, issuerPrefix: string, credSAID: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {QAR1, QAR2, QAR3, PERSON} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
        PersonClient
    ] = await getOrCreateClients(4, [QAR1.salt, QAR2.salt, QAR3.salt, PERSON.salt], environment);

    const PersonId = await PersonClient.identifiers().get(PERSON.name);

    let cred = await getReceivedCredential(PersonClient, credSAID);
    if (!(cred)) {
        console.log(`Credential ${credSAID} not found for ${PersonId.name}, admitting...`);
        const admitTime = createTimestamp();
        try {
            await admitSinglesig(
                PersonClient,
                PersonId.name,
                issuerPrefix,
            );
        } catch (e) {
            console.log(`Person had error admitting credential: ${e}`);
        }

        try {
            await waitAndMarkNotification(QAR1Client, '/exn/ipex/admit');
        } catch (e) {
            console.log(`QAR1 did not have a notification to mark: ${e}`);
        }
        try {
            await waitAndMarkNotification(QAR2Client, '/exn/ipex/admit');
        } catch (e) {
            console.log(`QAR2 did not have a notification to mark: ${e}`);
        }
        try {
            await waitAndMarkNotification(QAR3Client, '/exn/ipex/admit');
        } catch (e) {
            console.log(`QAR3 did not have a notification to mark: ${e}`);
        }

        try {
            const credByPerson = await waitForCredential(PersonClient, credSAID, 20);
            cred = credByPerson;
        } catch (e) {
            console.log(`Error waiting for credential: ${e}`);
            cred = await getReceivedCredential(PersonClient, credSAID);
        }
    } else{
        console.log(`Credential ${credSAID} already admitted`);
    }
    return cred;
}
console.log(`Admitting credential with issuer ${issuerPrefixArg} of SAID ${credSAIDArg} `);
const admitResult: any = await admitCredential(aidInfoArg, issuerPrefixArg, credSAIDArg, env);
console.log(`Person admitted credential with SAID: ${credSAIDArg}`);
console.log("Credential admitted:", admitResult.sad.a);
