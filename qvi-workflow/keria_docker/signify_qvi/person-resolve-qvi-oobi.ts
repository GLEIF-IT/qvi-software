import { getOrCreateContact } from "./agent-contacts";
import { getOrCreateClients } from "./keystore-creation";
import { TestEnvironmentPreset } from "./resolve-env";
import { parseAidInfo } from "./create-aid";
import { OobiInfo } from "./qvi-data";

// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1];
const aidInfoArg = args[2];
const qviOobiArg = args[3];

// parse the OOBIs for the GEDA and GIDA multisig AIDs needed for delegation and then LE credential issuance
export function parseOobiInfo(oobiInfo: string) {
    const oobiInfos = oobiInfo.split(','); // expect format: "gedaName|OOBI,leName|OOBI"
    const oobiObjs: OobiInfo[] = oobiInfos.map((oobiInfo) => {
        const [position, oobi] = oobiInfo.split('|'); // expect format: "gar1|OOBI"
        return {position, oobi};
    });

    const GEDA_NAME = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gedaName') as OobiInfo;
    const LE_NAME = oobiObjs.find((oobiInfo) => oobiInfo.position === 'leName') as OobiInfo;
    return {GEDA_NAME, LE_NAME};
}

/**
 * Resolves the QVI Multisig OOBI for the Person in preparation for receiving the ECR and OOR credentials
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param qviOobi The QVI multisig OOBI
 * @param environment the runtime environment to use for resolving environment variables
 */
async function resolveQVIOobi(multisigName: string, aidInfo: string, qviOobi: string, environment: TestEnvironmentPreset) {
    // create SignifyTS Clients
    const {PERSON} = parseAidInfo(aidInfo);
    const [PERSONClient] = await getOrCreateClients(1, [PERSON.salt], environment);
    await getOrCreateContact(PERSONClient, multisigName, qviOobi);
}
await resolveQVIOobi(multisigName, aidInfoArg, qviOobiArg, env);
console.log('Person resolved QVI OOBI ' + qviOobiArg);