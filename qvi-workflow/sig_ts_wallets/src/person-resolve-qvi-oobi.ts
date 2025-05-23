import { getOrCreateContact } from "./agent-contacts";
import {getOrCreateClient} from "./keystore-creation";
import { TestEnvironmentPreset } from "./resolve-env";
import { parseAidInfo } from "./create-aid";
import { OobiInfo } from "./qvi-data";

// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1];
const aidInfoArg = args[2];
const qviOobiArg = args[3];

/**
 * Resolves the QVI Multisig OOBI for the Person in preparation for receiving the ECR and OOR credentials
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param qviOobi The QVI multisig OOBI
 * @param environment the runtime environment to use for resolving environment variables
 */
async function resolveQVIOobi(multisigName: string, aidInfo: string, qviOobi: string, environment: TestEnvironmentPreset) {
    // create SignifyTS Clients
    const {PERSON} = parseAidInfo(aidInfo);
    // Create SignifyTS Clients
    const personClient = await getOrCreateClient(PERSON.salt, environment, 1);
    await getOrCreateContact(personClient, multisigName, qviOobi);
}
await resolveQVIOobi(multisigName, aidInfoArg, qviOobiArg, env);
console.log('Person resolved QVI OOBI ' + qviOobiArg);