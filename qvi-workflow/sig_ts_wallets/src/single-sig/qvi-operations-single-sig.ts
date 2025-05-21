import {parseAidInfoSingleSig} from "../create-aid.ts";
import {getOrCreateClient} from "../keystore-creation.ts";
import {TestEnvironmentPreset} from "../resolve-env.ts";
import {getReceivedCredential} from "../credentials.ts";

/**
 * Checks to see if the QVI credential exists for the QAR
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param credSAID The SAID of the credential issuance to check for.
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
export async function checkReceivedCredentialSingleSig(aidInfo: string, credSAID: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {QVI} = parseAidInfoSingleSig(aidInfo);
    // Create SignifyTS Clients
    const QVIClient = await getOrCreateClient(QVI.salt, environment, 1);

    // Check to see if the QVI credential exists
    let receivedCred = await getReceivedCredential(
        QVIClient,
        credSAID
    )
    if (!receivedCred) {
        return "false-credential-not-found"
    }
    return "true"
}