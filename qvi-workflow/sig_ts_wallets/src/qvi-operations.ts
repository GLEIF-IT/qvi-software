import {getOrCreateClients} from "./keystore-creation.ts";
import {parseAidInfo} from "./create-aid.ts";
import {TestEnvironmentPreset} from "./resolve-env.ts";
import {getIssuedCredential, getReceivedCredential} from "./credentials.ts";
import {waitOperation} from "./operations.ts";

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
    return issuedCred.sad.d
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

/**
 * As the QVI multisig the participating QARs must refresh the keystate of the GEDA multisig in order to
 * respond to the anchoring of the delegation approval seal in the GEDA's key event log (KEL). This
 * enables the pending QVI delegated multisig inception operation to complete.
 */
export async function refreshGedaMultisigstate(aidInfoArg: string, gedaPrefix: string, environment: TestEnvironmentPreset) {
    const {QAR1, QAR2, QAR3, PERSON} = parseAidInfo(aidInfoArg);

        // create SignifyTS Clients
        const [
            QAR1Client,
            QAR2Client,
            QAR3Client,
            personClient,
        ] = await getOrCreateClients(4, [QAR1.salt, QAR2.salt, QAR3.salt, PERSON.salt], environment);


    // QARs query the GEDA's key state
    const queryOp1 = await QAR1Client.keyStates().query(gedaPrefix);
    const queryOp2 = await QAR2Client.keyStates().query(gedaPrefix);
    const queryOp3 = await QAR3Client.keyStates().query(gedaPrefix);

    let res;
    try {
        res = await waitOperation(QAR1Client, queryOp1);
    } catch (e) {
        console.error("Error refreshing GEDA multisig keystate", e);
        console.error("Response: ", res);
        throw e;
    }
    try {
        res = await waitOperation(QAR2Client, queryOp2);
    } catch (e) {
        console.error("Error refreshing GEDA multisig keystate", e);
        console.error("Response: ", res);
        throw e;
    }
    try {
        res = await waitOperation(QAR3Client, queryOp3);
    } catch (e) {
        console.error("Error refreshing GEDA multisig keystate", e);
        console.error("Response: ", res);
        throw e;
    }
    console.log('QARs have refreshed the GEDA multisig keystate');
    return {QAR1Client, QAR2Client, QAR3Client}
}