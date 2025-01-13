import { getOrCreateContact } from "./agent-contacts";
import { getOrCreateClients } from "./keystore-creation";
import { TestEnvironmentPreset } from "./resolve-env";
import { parseAidInfo } from "./create-aid";
import { OobiInfo } from "./qvi-data";

// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1];
const oobiInfoArg = args[2];

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
 * Resolves the GLEIF External Delegated AID (GEDA) and GLEIF Internal Delegated AID (GIDA - LE in this example) multisig OOBIs for the QAR participants
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param oobiInfo A comma-separated list of OOBIs for the GEDA and GIDA multisig AIDs
 * @param environment the runtime environment to use for resolving environment variables
 */
async function resolveMultisigOobis(aidInfo: string, oobiInfo: string, environment: TestEnvironmentPreset) {
    // create SignifyTS Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
    ] = await getOrCreateClients(3, [QAR1.salt, QAR2.salt, QAR3.salt], environment);

    const {GEDA_MS, GIDA_MS} = parseOobiInfo(oobiInfo);
    await Promise.all([
        getOrCreateContact(QAR1Client, GEDA_MS.position, GEDA_MS.oobi),
        getOrCreateContact(QAR1Client, GIDA_MS.position, GIDA_MS.oobi),

        getOrCreateContact(QAR2Client, GEDA_MS.position, GEDA_MS.oobi),
        getOrCreateContact(QAR2Client, GIDA_MS.position, GIDA_MS.oobi),

        getOrCreateContact(QAR3Client, GEDA_MS.position, GEDA_MS.oobi),
        getOrCreateContact(QAR3Client, GIDA_MS.position, GIDA_MS.oobi),
    ])
    console.log('Resolved multisig OOBIs');
}
await resolveMultisigOobis(aidInfoArg, oobiInfoArg, env);