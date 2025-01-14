import {getOrCreateClients} from "./keystore-creation.ts";
import {parseAidInfo} from "./create-aid.ts";
import {TestEnvironmentPreset} from "./resolve-env.ts";
import {getIssuedCredential, getReceivedCredential} from "./credentials.ts";

/**
 * Checks to see if the QVI credential exists for the QAR
 *
 * @param multisigName name of the multisig identity to use to check for credentials
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param schemaSAID the SAID of the ACDC credential schema to use to filter the credential search
 * @param issueePrefix identifier prefix for the Legal Entity multisig AID who would be the recipient, or issuee, of the LE credential.
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
export async function checkIssuedCredential(multisigName: string, aidInfo: string, schemaSAID: string, issueePrefix: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {QAR1} = parseAidInfo(aidInfo);
    const [QAR1Client] = await getOrCreateClients(1, [QAR1.salt], environment);

    // Check to see if QVI multisig exists
    const multisig = await QAR1Client.identifiers().get(multisigName);

    // Check to see if the QVI credential exists
    const issuedCred = await getIssuedCredential(
        QAR1Client,
        multisig.prefix,
        issueePrefix,
        schemaSAID
    )
    if (!issuedCred) {
        return "false-credential-not-found"
    }
    return "true"
}

/**
 * Checks to see if the QVI credential exists for the QAR
 *
 * @param multisigName name of the multisig identity to use to check for credentials
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param credSAID The SAID of the credential issuance to check for.
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
export async function checkReceivedCredential(multisigName: string, aidInfo: string, credSAID: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {QAR1} = parseAidInfo(aidInfo);
    const [QAR1Client] = await getOrCreateClients(1, [QAR1.salt], environment);

    // Check to see if QVI multisig exists
    let multisig = await QAR1Client.identifiers().get(multisigName);

    // Check to see if the QVI credential exists
    let receivedCred = await getReceivedCredential(
        QAR1Client,
        credSAID
    )
    if (!receivedCred) {
        return "false-credential-not-found"
    }
    return "true"
}