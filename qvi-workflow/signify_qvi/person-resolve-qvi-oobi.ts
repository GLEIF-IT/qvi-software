import { getOrCreateContact } from "./agent-contacts";
import { getOrCreateClients } from "./keystore-creation";
import { TestEnvironmentPreset } from "./resolve-env";
import { parseAidInfo } from "./create-aid";
import { OobiInfo } from "./qvi-data";

// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1];
const qviOobiArg = args[2];

const QVI_MS_NAME='QVI';

// parse the OOBIs for the GEDA and GIDA multisig AIDs needed for delegation and then LE credential issuance
export function parseOobiInfo(oobiInfo: string) {
    const oobiInfos = oobiInfo.split(','); // expect format: "gedaMS|OOBI,gidaMS|OOBI"
    const oobiObjs: OobiInfo[] = oobiInfos.map((oobiInfo) => {
        const [position, oobi] = oobiInfo.split('|'); // expect format: "geda1|OOBI"
        return {position, oobi};
    });

    const GEDA_MS = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gedaMS') as OobiInfo;
    const GIDA_MS = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gidaMS') as OobiInfo;
    return {GEDA_MS, GIDA_MS};
}

/**
 * Resolves the QVI Multisig OOBI for the Person in preparation for receiving the ECR and OOR credentials
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param qviOobi The QVI multisig OOBI
 * @param environment the runtime environment to use for resolving environment variables
 */
async function resolveQVIOobi(aidInfo: string, qviOobi: string, environment: TestEnvironmentPreset) {
    // create SignifyTS Clients
    const {PERSON} = parseAidInfo(aidInfo);
    const [PERSONClient] = await getOrCreateClients(1, [PERSON.salt], environment);
    await getOrCreateContact(PERSONClient, QVI_MS_NAME, qviOobi);
}
await resolveQVIOobi(aidInfoArg, qviOobiArg, env);
console.log('Person resolved QVI OOBI ' + qviOobiArg);