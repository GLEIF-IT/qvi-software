import {TestEnvironmentPreset} from "../resolve-env.ts";
import {createTimestamp, parseAidInfo} from "../create-aid.ts";
import {getOrCreateClients} from "../keystore-creation.ts";
import {getReceivedCredBySchemaAndIssuer} from "../credentials.ts";
import {Serder} from "signify-ts";
import {waitOperation} from "../operations.ts";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]
const schemaSAID = args[2]
const issuerPrefix = args[3]
const recipientPrefix = args[4]

/**
 * Grants a credential from the Person AID to a recipient
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param schemaSAID The schema SAID of the type of credential issuance to check for.
 * @param issuerPrefix identifier of the issuer AID who issued the credential
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
export async function grantCredential(aidInfo: string, schemaSAID: string, issuerPrefix: string, recipientPrefix: string, environment: TestEnvironmentPreset) {
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

    const PersonAID = await PersonClient.identifiers().get(PERSON.name);

    // grant credential
    const dt = createTimestamp();
    const [grant, gsigs, gend] = await PersonClient.ipex().grant({
        senderName: PERSON.name,
        acdc: new Serder(receivedCred.sad),
        anc: new Serder(receivedCred.anc),
        iss: new Serder(receivedCred.iss),
        ancAttachment: receivedCred.ancAttachment,
        recipient: recipientPrefix,
        datetime: dt,
    });

    const op = await PersonClient
        .ipex()
        .submitGrant(PERSON.name, grant, gsigs, gend, [
            recipientPrefix,
        ]);
    await waitOperation(PersonClient, op);

    return op.response;
}
const granted: string = await grantCredential(aidInfoArg, schemaSAID, issuerPrefix, recipientPrefix, env);
console.log(granted);
