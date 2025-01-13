import { getOrCreateContact } from "./agent-contacts";
import { getOrCreateClients } from "./keystore-creation";
import { TestEnvironmentPreset } from "./resolve-env";
import { OobiInfo } from "./qvi-data";
import { parseAidInfo } from "./create-aid";
import { parseOobiInfo } from "./oobis";

// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';

// parse the OOBIs for the GEDA, GIDA, and Sally needed for initial setup
export function parseOobiInfo(oobiInfoArg: string) {
    const oobiInfos = oobiInfoArg.split(','); // expect format: "geda1|OOBI,geda2|OOBI,gida1|OOBI,gida2|OOBI,sally|OOBI"
    const oobiObjs: OobiInfo[] = oobiInfos.map((aidInfo) => {
        const [position, oobi] = aidInfo.split('|'); // expect format: "geda1|OOBI"
        return {position, oobi};
    });

    const GEDA1 = oobiObjs.find((oobiInfo) => oobiInfo.position === 'geda1') as OobiInfo;
    const GEDA2 = oobiObjs.find((oobiInfo) => oobiInfo.position === 'geda2') as OobiInfo;
    const GIDA1 = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gida1') as OobiInfo;
    const GIDA2 = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gida2') as OobiInfo;
    const SALLY = oobiObjs.find((oobiInfo) => oobiInfo.position === 'sally') as OobiInfo;
    return {GEDA1, GEDA2, GIDA1, GIDA2, SALLY};
}

// Resolve OOBIs between the QARs and the person and the GEDA, GIDA, and Sally based on script arguments
// aidInfoArg format: "qar1|Alice|salt1,qar2|Bob|salt2,qar3|Charlie|salt3,person|David|salt4"
// oobiStrArg format: "geda1|OOBI,geda2|OOBI,gida1|OOBI,gida2|OOBI,sally|OOBI"
async function resolveOobis(aidStrArg: string, oobiStrArg: string, environment: TestEnvironmentPreset) {
    // create SignifyTS Clients
    const {QAR1, QAR2, QAR3, PERSON} = parseAidInfo(aidStrArg);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
        personClient,
    ] = await getOrCreateClients(4, [QAR1.salt, QAR2.salt, QAR3.salt, PERSON.salt], environment);
    
    // resolve OOBIs for all participants
    const {GEDA1, GEDA2, GIDA1, GIDA2, SALLY} = parseOobiInfo(oobiStrArg);
    await Promise.all([
        getOrCreateContact(QAR1Client, GEDA1.position, GEDA1.oobi),
        getOrCreateContact(QAR1Client, GEDA2.position, GEDA2.oobi),
        getOrCreateContact(QAR1Client, GIDA1.position, GIDA1.oobi),
        getOrCreateContact(QAR1Client, GIDA2.position, GIDA2.oobi),

        getOrCreateContact(QAR2Client, GEDA1.position, GEDA1.oobi),
        getOrCreateContact(QAR2Client, GEDA2.position, GEDA2.oobi),
        getOrCreateContact(QAR2Client, GIDA1.position, GIDA1.oobi),
        getOrCreateContact(QAR2Client, GIDA2.position, GIDA2.oobi),

        getOrCreateContact(QAR3Client, GEDA1.position, GEDA1.oobi),
        getOrCreateContact(QAR3Client, GEDA2.position, GEDA2.oobi),
        getOrCreateContact(QAR3Client, GIDA1.position, GIDA1.oobi),
        getOrCreateContact(QAR3Client, GIDA2.position, GIDA2.oobi),

        getOrCreateContact(personClient, GIDA1.position, GIDA1.oobi),
        getOrCreateContact(personClient, GIDA2.position, GIDA2.oobi),
        getOrCreateContact(personClient, SALLY.position, SALLY.oobi),

    ])
}
await resolveOobis(args[1], args[2], env);