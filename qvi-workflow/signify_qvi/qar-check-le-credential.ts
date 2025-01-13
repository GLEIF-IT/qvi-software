import { HabState } from "signify-ts";
import { parseAidInfo } from "./create-aid";
import { getOrCreateClients } from "./keystore-creation";
import { TestEnvironmentPreset } from "./resolve-env";
import { getIssuedCredential } from "./credentials";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]
const lePrefix = args[2]

const QVI_MS_NAME='QVI';
const LE_SCHEMA_SAID = 'ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY';


/**
 * Checks to see if the QVI credential exists for the QAR
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param lePrefix identifier prefix for the Legal Entity multisig AID who would be the recipient, or issuee, of the LE credential.
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
async function checkLeCredential(aidInfo: string, lePrefix: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {QAR1} = parseAidInfo(aidInfo);
    const [QAR1Client] = await getOrCreateClients(1, [QAR1.salt], environment);

    // Check to see if QVI multisig exists    
    const qar1Ms = await QAR1Client.identifiers().get(QVI_MS_NAME);
    
    // Check to see if the QVI credential exists
    const qviCredential = await getIssuedCredential(
        QAR1Client,
        qar1Ms.prefix,
        lePrefix,
        LE_SCHEMA_SAID
    )
    if (!qviCredential) {
        return "false-credential-not-found"
    }
    return "true"
}
const exists: string = await checkLeCredential(aidInfoArg, lePrefix, env);
console.log(exists);
