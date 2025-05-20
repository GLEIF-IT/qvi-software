import { HabState } from "signify-ts";
import { parseAidInfo } from "../create-aid";
import {getOrCreateClient} from "../keystore-creation";
import { TestEnvironmentPreset } from "../resolve-env";
import fs from 'fs';

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1]
const aidInfoArg = args[2]
const dataDir = args[3];


/**
 * Checks to see if the QVI multisig exists
 *
 * @param multisigName name of the multisig AID
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<string>} String true/false if QVI multisig AID exists or not
 */
async function checkQviMultisig(multisigName: string, aidInfo: string, environment: TestEnvironmentPreset): Promise<number> {
    // get Clients
    const {QAR1} = parseAidInfo(aidInfo);
    const QAR1Client = await getOrCreateClient(QAR1.salt, environment, 1);

    // Check to see if QVI multisig exists    
    let qar1Ms: HabState;
    try {
        qar1Ms = await QAR1Client.identifiers().get(multisigName);
    } catch (e: any) {
        return -1
    }
    return parseInt(qar1Ms.state.s)
}
const sequenceNo = await checkQviMultisig(multisigName, aidInfoArg, env);
const seqNoObj = {
    sequenceNo: sequenceNo,
}
console.log("Writing QVI multisig sequence number to file");
await fs.promises.writeFile(`${dataDir}/qvi-sequence-no.json`, JSON.stringify(seqNoObj))
console.log(sequenceNo);
