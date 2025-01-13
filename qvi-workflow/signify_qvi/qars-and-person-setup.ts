import { getOrCreateContact } from "./agent-contacts";
import { getOrCreateAID, getOrCreateClients} from "./keystore-creation";
import { resolveOobi } from "./oobis";
import { resolveEnvironment, TestEnvironmentPreset } from "./resolve-env";
import { parseAidInfo } from "./create-aid";
import fs from 'fs';

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
// aidInfoArg format: "qar1|Alice|salt1,qar2|Bob|salt2,qar3|Charlie|salt3,person|David|salt4"
async function setupQVIAndPerson(aidInfoArg: string, environment: TestEnvironmentPreset) {
    const {QAR1, QAR2, QAR3, PERSON} = parseAidInfo(aidInfoArg);

    // create SignifyTS Clients
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
        personClient,
    ] = await getOrCreateClients(4, [QAR1.salt, QAR2.salt, QAR3.salt, PERSON.salt], environment);
    console.log("QARs and Person SignifyClients created")

    const kargsAID = {
        toad: witnessIds.length,
        wits: witnessIds,
    };

    // Create AIDs
    const [
        QAR1Id,
        QAR2Id,
        QAR3Id,
        personId,
    ] = await Promise.all([
        getOrCreateAID(QAR1Client, QAR1.name, kargsAID),
        getOrCreateAID(QAR2Client, QAR2.name, kargsAID),
        getOrCreateAID(QAR3Client, QAR3.name, kargsAID),
        getOrCreateAID(personClient, PERSON.name, kargsAID),
    ]);
    console.log("QARs and Person AIDs created")
    
    // Get Witness and Agent OOBIs
    const WitnessRole = 'witness';
    const [
        QAR1WitnessOobiResp,
        QAR2WitnessOobiResp,
        QAR3WitnessOobiResp,
        personWitnessOobiResp,
    ] = await Promise.all([
        QAR1Client.oobis().get(QAR1.name, WitnessRole),
        QAR2Client.oobis().get(QAR2.name, WitnessRole),
        QAR3Client.oobis().get(QAR3.name, WitnessRole),
        personClient.oobis().get(PERSON.name, WitnessRole),
    ]);
    const AgentRole = 'agent';
    const [
        QAR1AgentOobiResp,
        QAR2AgentOobiResp,
        QAR3AgentOobiResp,
        personAgentOobiResp,
    ] = await Promise.all([
        QAR1Client.oobis().get(QAR1.name, AgentRole),
        QAR2Client.oobis().get(QAR2.name, AgentRole),
        QAR3Client.oobis().get(QAR3.name, AgentRole),
        personClient.oobis().get(PERSON.name, AgentRole),
    ]);
    console.log("QAR and Person witness and agent OOBIs created.");

    // TODO perform challenge phrase exchange between QARs and between QARs and person

    // Perform all OOBI introductions between QAR participants and the person
    console.log("QAR and Person resolving OOBIs...")
    await Promise.all([
        getOrCreateContact(QAR1Client, QAR2.name, QAR2AgentOobiResp.oobis[0]),
        getOrCreateContact(QAR1Client, QAR3.name, QAR3AgentOobiResp.oobis[0]),
        getOrCreateContact(QAR1Client, PERSON.name, personAgentOobiResp.oobis[0]),

        getOrCreateContact(QAR2Client, QAR1.name, QAR1AgentOobiResp.oobis[0]),
        getOrCreateContact(QAR2Client, QAR3.name, QAR3AgentOobiResp.oobis[0]),
        getOrCreateContact(QAR2Client, PERSON.name, personAgentOobiResp.oobis[0]),

        getOrCreateContact(QAR3Client, QAR1.name, QAR1AgentOobiResp.oobis[0]),
        getOrCreateContact(QAR3Client, QAR2.name, QAR2AgentOobiResp.oobis[0]),
        getOrCreateContact(QAR3Client, PERSON.name, personAgentOobiResp.oobis[0]),

        getOrCreateContact(personClient, QAR1.name, QAR1AgentOobiResp.oobis[0]),
        getOrCreateContact(personClient, QAR2.name, QAR2AgentOobiResp.oobis[0]),
        getOrCreateContact(personClient, QAR3.name, QAR3AgentOobiResp.oobis[0]),
    ]);

    // resolve credential OOBIs
    console.log("QAR and Person resolving credential OOBIs...")
    await Promise.all([
        resolveOobi(QAR1Client, QVI_SCHEMA_URL),
        resolveOobi(QAR2Client, QVI_SCHEMA_URL),
        resolveOobi(QAR3Client, QVI_SCHEMA_URL),
        resolveOobi(QAR1Client, LE_SCHEMA_URL),
        resolveOobi(QAR2Client, LE_SCHEMA_URL),
        resolveOobi(QAR3Client, LE_SCHEMA_URL),
        resolveOobi(QAR1Client, ECR_AUTH_SCHEMA_URL),
        resolveOobi(QAR2Client, ECR_AUTH_SCHEMA_URL),
        resolveOobi(QAR3Client, ECR_AUTH_SCHEMA_URL),
        resolveOobi(QAR1Client, OOR_AUTH_SCHEMA_URL),
        resolveOobi(QAR2Client, OOR_AUTH_SCHEMA_URL),
        resolveOobi(QAR3Client, OOR_AUTH_SCHEMA_URL),
        resolveOobi(QAR1Client, ECR_SCHEMA_URL),
        resolveOobi(QAR2Client, ECR_SCHEMA_URL),
        resolveOobi(QAR3Client, ECR_SCHEMA_URL),
        resolveOobi(QAR1Client, OOR_SCHEMA_URL),
        resolveOobi(QAR2Client, OOR_SCHEMA_URL),
        resolveOobi(QAR3Client, OOR_SCHEMA_URL),
        resolveOobi(personClient, ECR_SCHEMA_URL),
        resolveOobi(personClient, OOR_SCHEMA_URL),
    ])

    return {
        QAR1: {
            aid: QAR1Id.prefix,
            agentOobi: QAR1AgentOobiResp.oobis[0],
            witnessOobi: QAR1WitnessOobiResp.oobis[0]
        },
        QAR2: {
            aid: QAR2Id.prefix,
            agentOobi: QAR2AgentOobiResp.oobis[0],
            witnessOobi: QAR2WitnessOobiResp.oobis[0]
        },
        QAR3: {
            aid: QAR3Id.prefix,
            agentOobi: QAR3AgentOobiResp.oobis[0],
            witnessOobi: QAR3WitnessOobiResp.oobis[0]
        },
        PERSON: {
            aid: personId.prefix,
            agentOobi: personAgentOobiResp.oobis[0],
            witnessOobi: personWitnessOobiResp.oobis[0]
        }
    }
}
const clientInfo: any = await setupQVIAndPerson(aidInfoArg, env);
await fs.writeFile(`${dataDir}/qars-and-person-info.json`, JSON.stringify(clientInfo), (err) => {
    if (err) {
        console.log(`error writing client info to file: ${err}`);        
        return
    }
});
