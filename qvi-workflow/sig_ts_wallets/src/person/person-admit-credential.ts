import {parseAidInfo} from "../create-aid";
import {getOrCreateClient} from "../keystore-creation";
import {TestEnvironmentPreset} from "../resolve-env";
import {
    admitSinglesig,
    getReceivedCredential,
    waitForCredential
} from "../credentials";
import {waitAndRemoveNotification} from "../notifications";

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
    // Create SignifyTS Clients
    const QAR1Client = await getOrCreateClient(QAR1.salt, environment, 1);
    const QAR2Client = await getOrCreateClient(QAR2.salt, environment, 2);
    const QAR3Client = await getOrCreateClient(QAR3.salt, environment, 3);
    const PersonClient = await getOrCreateClient(PERSON.salt, environment, 1);

    const PersonId = await PersonClient.identifiers().get(PERSON.name);

    let cred = await getReceivedCredential(PersonClient, credSAID);
    const credentialIsMissing = cred === undefined;
    if (credentialIsMissing) {
        console.log(`Credential ${credSAID} not found for ${PersonId.name}, admitting...`);
        await admitSinglesig(
            PersonClient,
            PersonId.name,
            issuerPrefix,
        );

        await Promise.all([
            waitAndRemoveNotification(
                QAR1Client,
                '/exn/ipex/admit',
                {timeout: 30000}
            ),
            waitAndRemoveNotification(
                QAR2Client,
                '/exn/ipex/admit',
                {timeout: 30000}
            ),
            waitAndRemoveNotification(
                QAR3Client,
                '/exn/ipex/admit',
                {timeout: 30000}
            ),
        ]);

        cred = await waitForCredential(PersonClient, credSAID, 30);
    } else{
        console.log(`Credential ${credSAID} already admitted`);
    }
    return cred;
}
console.log(`Admitting credential with issuer ${issuerPrefixArg} of SAID ${credSAIDArg} `);
const admitResult: any = await admitCredential(aidInfoArg, issuerPrefixArg, credSAIDArg, env);
console.log(`Person admitted credential with SAID: ${credSAIDArg}`);
console.log("Credential admitted:", admitResult.sad.a);
