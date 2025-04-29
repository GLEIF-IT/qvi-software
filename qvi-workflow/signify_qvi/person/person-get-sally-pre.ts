import { getOrCreateContact } from "../agent-contacts";
import { getOrCreateClients } from "../keystore-creation";
import { AidInfo, OobiInfo } from "../qvi-data";
import { TestEnvironmentPreset } from "../resolve-env";

// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1];
const oobiArg = args[2];

export function parseAidInfo(aidInfoArg: string) {
    const aids = aidInfoArg.split(','); // expect format: "qar1|Alice|salt1,qar2|Bob|salt2,qar3|Charlie|salt3,person|David|salt4"
    const aidObjs: AidInfo[] = aids.map((aidInfo) => {
        const [position, name, salt] = aidInfo.split('|'); // expect format: "qar1|Alice|salt1"
        return {position, name, salt};
    });

    const PERSON = aidObjs.find((aid) => aid.position === 'person') as AidInfo;
    return {PERSON};
}

export function parseOobiInfo(oobiInfo: string) {
    const oobiInfos = oobiInfo.split(','); // expect format: "gedaName|OOBI,leName|OOBI"
    const oobiObjs: OobiInfo[] = oobiInfos.map((oobiInfo) => {
        const [position, oobi] = oobiInfo.split('|'); // expect format: "gar1|OOBI"
        return {position, oobi};
    });

    const SALLY = oobiObjs.find((oobiInfo) => oobiInfo.position === 'sally') as OobiInfo;
    return {SALLY};
}

async function getSallyPre(aidStrArg: string, oobiStrArg: string, environment: TestEnvironmentPreset) {
    // Get Client
    const {PERSON} = parseAidInfo(aidStrArg);
    const [
        personClient,
    ] = await getOrCreateClients(1, [PERSON.salt], environment);
    
    // resolve sally OOBIs 
    const {SALLY} = parseOobiInfo(oobiStrArg);
    const sallyPre = await getOrCreateContact(personClient, SALLY.position, SALLY.oobi);
    return sallyPre;
}
const sallyPre: string = await getSallyPre(aidInfoArg, oobiArg, env);
console.log(sallyPre);