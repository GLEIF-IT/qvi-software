import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env.ts";
import {parseAidInfoSingleSig} from "../create-aid.ts";
import {getOrCreateClient} from "../keystore-creation.ts";
import {resolveOobi} from "../oobis.ts";
import {parseOobiInfoSingleSig} from "./oobis.ts";
import {getOrCreateContact} from "../agent-contacts.ts";

const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1];
const oobiArg = args[2];

const {vleiServerUrl} = resolveEnvironment(env);

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

async function resolveSchemaOobis(aidInfo: string, oobiStrArg: string, environment: TestEnvironmentPreset) {
    // get Clients
    const {QVI} = parseAidInfoSingleSig(aidInfo);
    const QVIClient = await getOrCreateClient(QVI.salt, environment, 1);

    // resolve OOBIs for all participants
    const {GAR, LAR, SALLY, DIRECT_SALLY} = parseOobiInfoSingleSig(oobiStrArg);

    // set up OOBIs now that the delegation is complete
    await Promise.all([
        resolveOobi(QVIClient, QVI_SCHEMA_URL),
        resolveOobi(QVIClient, LE_SCHEMA_URL),
        resolveOobi(QVIClient, ECR_AUTH_SCHEMA_URL),
        resolveOobi(QVIClient, OOR_AUTH_SCHEMA_URL),
        resolveOobi(QVIClient, ECR_SCHEMA_URL),
        resolveOobi(QVIClient, OOR_SCHEMA_URL),

        getOrCreateContact(QVIClient, GAR.position, GAR.oobi),
        getOrCreateContact(QVIClient, LAR.position, LAR.oobi),
        getOrCreateContact(QVIClient, SALLY.position, SALLY.oobi),
        getOrCreateContact(QVIClient, DIRECT_SALLY.position, DIRECT_SALLY.oobi),
    ])
}
await resolveSchemaOobis(aidInfoArg, oobiArg, env);
console.log("QVI resolved schema OOBIs")