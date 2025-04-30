import { getOrCreateContact } from "../agent-contacts";
import { getOrCreateClients } from "../keystore-creation";
import { TestEnvironmentPreset } from "../resolve-env";
import { OobiInfo } from "../qvi-data";
import { parseAidInfo } from "../create-aid";

// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';

// parse the OOBIs for the GEDA, GIDA, and Sally needed for initial setup
export function parseOobiInfo(oobiInfoArg: string) {
    const oobiInfos = oobiInfoArg.split(','); // expect format: "gar1|OOBI,gar2|OOBI,lar1|OOBI,lar1|OOBI,sally|OOBI"
    const oobiObjs: OobiInfo[] = oobiInfos.map((aidInfo) => {
        const [position, oobi] = aidInfo.split('|'); // expect format: "gar1|OOBI"
        return {position, oobi};
    });

    const GAR1 = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gar1') as OobiInfo;
    const GAR2 = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gar2') as OobiInfo;
    const LAR1 = oobiObjs.find((oobiInfo) => oobiInfo.position === 'lar1') as OobiInfo;
    const LAR2 = oobiObjs.find((oobiInfo) => oobiInfo.position === 'lar2') as OobiInfo;
    const SALLY = oobiObjs.find((oobiInfo) => oobiInfo.position === 'sally') as OobiInfo;
    return {GAR1: GAR1, GAR2: GAR2, LAR1: LAR1, LAR2: LAR2, SALLY};
}

// Resolve OOBIs between the QARs and the person and the GEDA, GIDA, and Sally based on script arguments
// aidInfoArg format: "qar1|Alice|salt1,qar2|Bob|salt2,qar3|Charlie|salt3,person|David|salt4"
// oobiStrArg format: "gar1|OOBI,gar2|OOBI,lar1|OOBI,lar2|OOBI,sally|OOBI"
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
    const {GAR1, GAR2, LAR1, LAR2, SALLY} = parseOobiInfo(oobiStrArg);
    await Promise.all([
        getOrCreateContact(QAR1Client, GAR1.position, GAR1.oobi),
        getOrCreateContact(QAR1Client, GAR2.position, GAR2.oobi),
        getOrCreateContact(QAR1Client, LAR1.position, LAR1.oobi),
        getOrCreateContact(QAR1Client, LAR2.position, LAR2.oobi),
        getOrCreateContact(QAR1Client, SALLY.position, SALLY.oobi),

        getOrCreateContact(QAR2Client, GAR1.position, GAR1.oobi),
        getOrCreateContact(QAR2Client, GAR2.position, GAR2.oobi),
        getOrCreateContact(QAR2Client, LAR1.position, LAR1.oobi),
        getOrCreateContact(QAR2Client, LAR2.position, LAR2.oobi),
        getOrCreateContact(QAR2Client, SALLY.position, SALLY.oobi),

        getOrCreateContact(QAR3Client, GAR1.position, GAR1.oobi),
        getOrCreateContact(QAR3Client, GAR2.position, GAR2.oobi),
        getOrCreateContact(QAR3Client, LAR1.position, LAR1.oobi),
        getOrCreateContact(QAR3Client, LAR2.position, LAR2.oobi),
        getOrCreateContact(QAR3Client, SALLY.position, SALLY.oobi),

        getOrCreateContact(personClient, LAR1.position, LAR1.oobi),
        getOrCreateContact(personClient, LAR2.position, LAR2.oobi),
        getOrCreateContact(personClient, SALLY.position, SALLY.oobi),
    ])
}
await resolveOobis(args[1], args[2], env);