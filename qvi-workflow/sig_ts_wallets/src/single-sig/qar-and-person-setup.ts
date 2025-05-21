import {getOrCreateContact} from "../agent-contacts";
import {getOrCreateAID, getOrCreateClient} from "../keystore-creation";
import {resolveOobi} from "../oobis";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import fs from 'fs';
import {parseAidInfoSingleSig} from "../create-aid.ts";

/**
 * Expects the following arguments, in order:
 * 1. env: The runtime environment to use for resolving environment variables
 * 2. aidInfoArg: A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * 3. dataDir: The path prefix to the directory where the client info file will be written
 */
// Pull in arguments from the command line and configuration
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const dataDir = args[1];
const aidInfoArg = args[2];

const {witnessIds, vleiServerUrl} = resolveEnvironment(env);

// Credential schema IDs and URLs to resolve from the credential schema caching server (vLEI server)
const QVI_SCHEMA="EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao"
const LE_SCHEMA="ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY"
const ECR_AUTH_SCHEMA="EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g"
const OOR_AUTH_SCHEMA="EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E"
const ECR_SCHEMA="EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw"
const OOR_SCHEMA="EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy"

const QVI_SCHEMA_URL=`${vleiServerUrl}/oobi/${QVI_SCHEMA}`;
const LE_SCHEMA_URL=`${vleiServerUrl}/oobi/${LE_SCHEMA}`;
const ECR_AUTH_SCHEMA_URL=`${vleiServerUrl}/oobi/${ECR_AUTH_SCHEMA}`;
const OOR_AUTH_SCHEMA_URL=`${vleiServerUrl}/oobi/${OOR_AUTH_SCHEMA}`;
const ECR_SCHEMA_URL=`${vleiServerUrl}/oobi/${ECR_SCHEMA}`;
const OOR_SCHEMA_URL=`${vleiServerUrl}/oobi/${OOR_SCHEMA}`;

// Create AIDs for the QARs and the person based on the command line arguments
// aidInfoArg format: "qar|Alice|salt,person|David|salt"
async function setupQVIAndPerson(aidInfoArg: string, environment: TestEnvironmentPreset) {
    const {QAR, PERSON} = parseAidInfoSingleSig(aidInfoArg);
    const [_WAN, WIL, WES] = witnessIds; // QARs use WIL, Person uses WES

    // Create SignifyTS Clients
    const QARClient = await getOrCreateClient(QAR.salt, environment, 1);
    const personClient = await getOrCreateClient(PERSON.salt, environment, 1);

    // Create QAR AIDs
    const QARId = await getOrCreateAID(QARClient, QAR.name, { toad: 1, wits: [WIL]});

    // Create Person AID
    const personId = await getOrCreateAID(personClient, PERSON.name, { toad: 1, wits: [WES]});

    // Get Witness and Agent OOBIs
    const WitnessRole = 'witness';
    const [
        QARWitnessOobiResp,
        personWitnessOobiResp,
    ] = await Promise.all([
        QARClient.oobis().get(QAR.name, WitnessRole),
        personClient.oobis().get(PERSON.name, WitnessRole),
    ]);
    const AgentRole = 'agent';
    const [
        QARAgentOobiResp,
        personAgentOobiResp,
    ] = await Promise.all([
        QARClient.oobis().get(QAR.name, AgentRole),
        personClient.oobis().get(PERSON.name, AgentRole),
    ]);

    // Perform all OOBI introductions between QAR participants and the person
    console.log("QARs and Person resolving each other's agent OOBIs...")
    console.log(`QAR Resolving Person OOBI: ${personAgentOobiResp.oobis[0]}`)
    console.log(`Person Resolving QAR OOBI: ${QARAgentOobiResp.oobis[0]}`)
    await Promise.all([
        getOrCreateContact(QARClient, PERSON.name, personAgentOobiResp.oobis[0]),
        getOrCreateContact(personClient, QAR.name, QARAgentOobiResp.oobis[0]),
    ]);

    // resolve credential OOBIs
    console.log("QAR and Person resolving credential OOBIs...")
    await Promise.all([
        resolveOobi(QARClient, QVI_SCHEMA_URL),
        resolveOobi(QARClient, LE_SCHEMA_URL),
        resolveOobi(QARClient, ECR_AUTH_SCHEMA_URL),
        resolveOobi(QARClient, OOR_AUTH_SCHEMA_URL),
        resolveOobi(QARClient, ECR_SCHEMA_URL),
        resolveOobi(QARClient, OOR_SCHEMA_URL),

        resolveOobi(personClient, QVI_SCHEMA_URL),
        resolveOobi(personClient, LE_SCHEMA_URL),
        resolveOobi(personClient, ECR_AUTH_SCHEMA_URL),
        resolveOobi(personClient, OOR_AUTH_SCHEMA_URL),
        resolveOobi(personClient, ECR_SCHEMA_URL),
        resolveOobi(personClient, OOR_SCHEMA_URL),
    ])

    return {
        QAR: {
            aid: QARId.prefix,
            agentOobi: QARAgentOobiResp.oobis[0],
            witnessOobi: QARWitnessOobiResp.oobis[0]
        },
        PERSON: {
            aid: personId.prefix,
            agentOobi: personAgentOobiResp.oobis[0],
            witnessOobi: personWitnessOobiResp.oobis[0]
        }
    }
}
const clientInfo: any = await setupQVIAndPerson(aidInfoArg, env);
console.log("Writing QAR and Person data to file...");
await fs.promises.writeFile(`${dataDir}/qar-and-person-info.json`, JSON.stringify(clientInfo));
