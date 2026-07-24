import {getOrCreateContact} from "../agent-contacts";
import {getOrCreateAID, getOrCreateClient} from "../keystore-creation";
import {resolveOobi} from "../oobis";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import fs from 'fs';
import {parseAidInfoSingleSig} from "../create-aid.ts";
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    requireNamedArguments,
    runJsonCli,
    singleSigParticipantInvocationFromArguments,
} from '../cli.ts';

// Credential schema IDs and URLs to resolve from the credential schema caching server (vLEI server)
const QVI_SCHEMA="EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao"
const LE_SCHEMA="ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY"
const ECR_AUTH_SCHEMA="EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g"
const OOR_AUTH_SCHEMA="EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E"
const ECR_SCHEMA="EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw"
const OOR_SCHEMA="EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy"

// Create AIDs for the QARs and the person based on the command line arguments
// aidInfoArg format: "qar|Alice|salt,person|David|salt"
export async function setupQviAndPerson(
    aidInfoArg: string,
    environment: TestEnvironmentPreset
) {
    const {witnessIds, vleiServerUrl} =
        resolveEnvironment(environment);
    const schemaOobis = [
        QVI_SCHEMA,
        LE_SCHEMA,
        ECR_AUTH_SCHEMA,
        OOR_AUTH_SCHEMA,
        ECR_SCHEMA,
        OOR_SCHEMA,
    ].map((schemaSaid) => `${vleiServerUrl}/oobi/${schemaSaid}`);
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
        ...schemaOobis.map((oobi) => resolveOobi(QARClient, oobi)),
        ...schemaOobis.map((oobi) => resolveOobi(personClient, oobi)),
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

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            ['config', 'artifact-dir'],
            ['environment', 'artifact-dir', 'participant-source']
        );
        requireNamedArguments(parsed, ['artifact-dir']);
        const invocation =
            singleSigParticipantInvocationFromArguments(parsed);
        const participants = await setupQviAndPerson(
            invocation.participantSource,
            invocation.environment
        );
        await fs.promises.writeFile(
            `${parsed['artifact-dir']}/qar-and-person-info.json`,
            JSON.stringify(participants)
        );
        return {
            status: 'ready',
            participants,
        };
    });
}
