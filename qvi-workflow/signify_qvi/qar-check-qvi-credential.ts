import { HabState } from "signify-ts";
import { parseAidInfo } from "./create-aid";
import { getOrCreateClients } from "./keystore-creation";
import { TestEnvironmentPreset } from "./resolve-env";
import { getReceivedCredential } from "./credentials";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]
const qviCredSAID = args[2]

const QVI_MS_NAME='QVI';


/**
 * Checks to see if the QVI credential exists for the QAR
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI credential exists or not for the QAR
 */
async function checkQviCredential(aidInfo: string, qviCredSAID: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {QAR1} = parseAidInfo(aidInfo);
    const [QAR1Client] = await getOrCreateClients(1, [QAR1.salt], environment);

    // Check to see if QVI multisig exists    
    let qar1Ms: HabState;
    try {
        qar1Ms = await QAR1Client.identifiers().get(QVI_MS_NAME);
    } catch (e: any) {
        return "false-ms-not-found"
    }
    
    // Check to see if the QVI credential exists
    let qviCredential = await getReceivedCredential(
        QAR1Client,
        qviCredSAID
    )
    if (!qviCredential) {
        return "false-credential-not-found"
    }
    return "true"
}
const exists: string = await checkQviCredential(aidInfoArg, qviCredSAID, env);
console.log(exists);
