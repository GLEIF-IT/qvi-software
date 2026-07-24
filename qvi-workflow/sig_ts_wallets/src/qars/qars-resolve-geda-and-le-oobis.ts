import { getOrCreateContact } from "../agent-contacts";
import {getOrCreateClient} from "../keystore-creation";
import { TestEnvironmentPreset } from "../resolve-env";
import { parseAidInfo } from "../create-aid";
import { OobiInfo } from "../qvi-data";
import {
    isMainModule,
    parseNamedArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';

// parse the OOBIs for the GEDA and GIDA multisig AIDs needed for delegation and then LE credential issuance
export function parseOobiInfo(oobiInfo: string) {
    const oobiInfos = oobiInfo.split(','); // expect format: "gedaName|OOBI,leName|OOBI"
    const oobiObjs: OobiInfo[] = oobiInfos.map((oobiInfo) => {
        const [position, oobi] = oobiInfo.split('|'); // expect format: "gar1|OOBI"
        return {position, oobi};
    });

    const GEDA_NAME = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gedaName') as OobiInfo;
    const LE_NAME = oobiObjs.find((oobiInfo) => oobiInfo.position === 'leName') as OobiInfo;
    return {GEDA_NAME, LE_NAME};
}

/**
 * Resolves the GLEIF External Delegated AID (GEDA) and GLEIF Internal Delegated AID (GIDA - LE in this example) multisig OOBIs for the QAR participants
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param oobiInfo A comma-separated list of OOBIs for the GEDA and GIDA multisig AIDs
 * @param environment the runtime environment to use for resolving environment variables
 */
export async function resolveMultisigOobis(
    aidInfo: string,
    oobiInfo: string,
    environment: TestEnvironmentPreset
) {
    // create SignifyTS Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const QAR1Client = await getOrCreateClient(QAR1.salt, environment, 1);
    const QAR2Client = await getOrCreateClient(QAR2.salt, environment, 2);
    const QAR3Client = await getOrCreateClient(QAR3.salt, environment, 3);

    const {GEDA_NAME, LE_NAME} = parseOobiInfo(oobiInfo);
    await Promise.all([
        getOrCreateContact(QAR1Client, GEDA_NAME.position, GEDA_NAME.oobi),
        getOrCreateContact(QAR1Client, LE_NAME.position, LE_NAME.oobi),

        getOrCreateContact(QAR2Client, GEDA_NAME.position, GEDA_NAME.oobi),
        getOrCreateContact(QAR2Client, LE_NAME.position, LE_NAME.oobi),

        getOrCreateContact(QAR3Client, GEDA_NAME.position, GEDA_NAME.oobi),
        getOrCreateContact(QAR3Client, LE_NAME.position, LE_NAME.oobi),
    ]);
    return {status: 'resolved' as const, contactCount: 6};
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedArguments(
            process.argv.slice(2),
            ['config', 'environment', 'participant-source', 'oobis']
        );
        requireNamedArguments(parsed, ['oobis']);
        const invocation = participantInvocationFromArguments(parsed);
        return resolveMultisigOobis(
            invocation.participantSource,
            parsed.oobis,
            invocation.environment
        );
    });
}
