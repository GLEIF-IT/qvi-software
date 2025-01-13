import { HabState } from "signify-ts";
import { parseAidInfo } from "./create-aid";
import { getOrCreateClients } from "./keystore-creation";
import { TestEnvironmentPreset } from "./resolve-env";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]

const QVI_MS_NAME='QVI';


/**
 * Checks to see if the QVI multisig exists
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI multisig AID exists or not
 */
async function checkQviMultisig(aidInfo: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {QAR1} = parseAidInfo(aidInfo);
    const [QAR1Client] = await getOrCreateClients(1, [QAR1.salt], environment);

    // Check to see if QVI multisig exists    
    let qar1Ms: HabState;
    try {
        qar1Ms = await QAR1Client.identifiers().get(QVI_MS_NAME);
    } catch (e: any) {
        return "false"
    }
    return "true"
}
const exists: string = await checkQviMultisig(aidInfoArg, env);
console.log(exists);
