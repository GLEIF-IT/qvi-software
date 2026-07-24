import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env.ts";
import {parseAidInfoSingleSig} from "../create-aid.ts";
import {getOrCreateClient} from "../keystore-creation.ts";
import {resolveOobi} from "../oobis.ts";
import {parseOobiInfoSingleSig} from "./oobis.ts";
import {getOrCreateContact} from "../agent-contacts.ts";
import {
    isMainModule,
    parseNamedArguments,
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

export async function resolveSchemaOobis(
    aidInfo: string,
    oobiStrArg: string,
    environment: TestEnvironmentPreset
) {
    const {vleiServerUrl} = resolveEnvironment(environment);
    const schemaOobis = [
        QVI_SCHEMA,
        LE_SCHEMA,
        ECR_AUTH_SCHEMA,
        OOR_AUTH_SCHEMA,
        ECR_SCHEMA,
        OOR_SCHEMA,
    ].map((schemaSaid) => `${vleiServerUrl}/oobi/${schemaSaid}`);

    // get Clients
    const {QVI} = parseAidInfoSingleSig(aidInfo);
    const QVIClient = await getOrCreateClient(QVI.salt, environment, 1);

    // resolve OOBIs for all participants
    const {GAR, LAR, SALLY} = parseOobiInfoSingleSig(oobiStrArg);

    // set up OOBIs now that the delegation is complete
    await Promise.all([
        ...schemaOobis.map((oobi) => resolveOobi(QVIClient, oobi)),

        getOrCreateContact(QVIClient, GAR.position, GAR.oobi),
        getOrCreateContact(QVIClient, LAR.position, LAR.oobi),
        getOrCreateContact(QVIClient, SALLY.position, SALLY.oobi)
    ]);
    return {
        status: 'resolved' as const,
        schemaCount: schemaOobis.length,
        contactCount: 3,
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedArguments(
            process.argv.slice(2),
            ['config', 'environment', 'participant-source', 'oobis']
        );
        requireNamedArguments(parsed, ['oobis']);
        const invocation =
            singleSigParticipantInvocationFromArguments(parsed);
        return resolveSchemaOobis(
            invocation.participantSource,
            parsed.oobis,
            invocation.environment
        );
    });
}
