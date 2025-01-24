import {TestEnvironmentPreset} from "../resolve-env.ts";
import {parseAidInfo} from "../create-aid.ts";
import {getOrCreateClients} from "../keystore-creation.ts";
import {getReceivedCredBySchemaAndIssuer} from "../credentials.ts";

/*
Checks the specified multisig with the first QAR to see if a credential has been received
 */

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]
const schemaSAID = args[2]
const issuerPrefix = args[3]

/**
 * Checks to see if the Person has a credential
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param schemaSAID The schema SAID of the type of credential issuance to check for.
 * @param issuerPrefix identifier of the issuer AID who issued the credential
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
export async function checkReceivedCredentialPerson(aidInfo: string, schemaSAID: string, issuerPrefix: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {PERSON} = parseAidInfo(aidInfo);
    const [PersonClient] = await getOrCreateClients(1, [PERSON.salt], environment);

    // Check to see if the QVI credential exists
    let receivedCred = await getReceivedCredBySchemaAndIssuer(
        PersonClient,
        schemaSAID,
        issuerPrefix
    )
    if (!receivedCred) {
        return "false-credential-not-found"
    }
    return receivedCred.sad.d
}
const exists: string = await checkReceivedCredentialPerson(aidInfoArg, schemaSAID, issuerPrefix, env);
console.log(exists);
