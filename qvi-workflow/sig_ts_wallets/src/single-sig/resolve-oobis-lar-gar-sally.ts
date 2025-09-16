import {getOrCreateContact} from "../agent-contacts";
import {getOrCreateClient} from "../keystore-creation";
import {TestEnvironmentPreset} from "../resolve-env";
import {parseAidInfoSingleSig} from "../create-aid.ts";
import {parseOobiInfoSingleSig} from "./oobis.ts";

// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1];
const oobiArg = args[2];

// Resolve OOBIs between the QARs and the person and the GEDA, GIDA, and Sally based on script arguments
// aidInfoArg format: "qar|Alice|salt,person|David|salt"
// oobiStrArg format: "gar|OOBI,lar|OOBI,sally-indirect|OOBI"
async function resolveOobis(aidStrArg: string, oobiStrArg: string, environment: TestEnvironmentPreset) {
    // create SignifyTS Clients
    const {QAR, PERSON} = parseAidInfoSingleSig(aidStrArg);
    const QARClient = await getOrCreateClient(QAR.salt, environment, 1);
    const PersonClient = await getOrCreateClient(PERSON.salt, environment, 1);
    
    // resolve OOBIs for all participants
    const {GAR, LAR, SALLY} = parseOobiInfoSingleSig(oobiStrArg);
    await Promise.all([
        getOrCreateContact(QARClient, GAR.position, GAR.oobi),
        getOrCreateContact(QARClient, LAR.position, LAR.oobi),
        getOrCreateContact(QARClient, SALLY.position, SALLY.oobi),

        getOrCreateContact(PersonClient, LAR.position, LAR.oobi),
        getOrCreateContact(PersonClient, SALLY.position, SALLY.oobi)
    ])
}
await resolveOobis(aidInfoArg, oobiArg, env);