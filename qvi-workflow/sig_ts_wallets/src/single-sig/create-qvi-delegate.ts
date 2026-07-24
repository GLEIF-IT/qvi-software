import {parseAidInfoSingleSig} from "../create-aid";
import {getOrCreateClient} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {parseOobiInfoSingleSig} from "./oobis.ts";
import {resolveOobi} from "../oobis.ts";
import fs from "fs";
import {
    isMainModule,
    parseNamedArguments,
    requireNamedArguments,
    runJsonCli,
    singleSigParticipantInvocationFromArguments,
} from '../cli.ts';

/**
 * Create a delegated AID for the QVI delegated from the AID specified by delpre.
 *
 * @param qviName
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param witnessIds
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
export async function createQviDelegate(
    qviName: string,
    aidInfo: string,
    oobiInfo: string,
    delegatorPrefix: string,
    environment: TestEnvironmentPreset
) {
    const {witnessIds} = resolveEnvironment(environment);
    const [, WIL] = witnessIds;

    // get Clients
    const {QVI} = parseAidInfoSingleSig(aidInfo);
    const QVIClient = await getOrCreateClient(QVI.salt, environment, 1);

    // get OOBI info
    const {GAR} = parseOobiInfoSingleSig(oobiInfo);
    await resolveOobi(QVIClient, GAR.oobi, GAR.position)

    // create delegate
    const delegateConfig = {
        toad: 1,
        wits: [WIL],
        delpre: delegatorPrefix
    };
    const qviIcpRes = await QVIClient.identifiers().create(qviName, delegateConfig);
    const op = await qviIcpRes.op();
    const delegatePre = op.name.split('.')[1];

    console.log(`Delegate ${delegatePre} waiting for approval...`)
    return {delegatePre, icpOpName: op.name}
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedArguments(
            process.argv.slice(2),
            [
                'config',
                'environment',
                'participant-source',
                'qvi-name',
                'oobis',
                'delegator-prefix',
                'artifact-dir',
            ]
        );
        requireNamedArguments(parsed, [
            'qvi-name',
            'oobis',
            'delegator-prefix',
            'artifact-dir',
        ]);
        const invocation =
            singleSigParticipantInvocationFromArguments(parsed);
        const {delegatePre, icpOpName} = await createQviDelegate(
            parsed['qvi-name'],
            invocation.participantSource,
            parsed.oobis,
            parsed['delegator-prefix'],
            invocation.environment
        );
        const artifact = {qviPre: delegatePre, icpOpName};
        await fs.promises.writeFile(
            `${parsed['artifact-dir']}/qvi-delegate-info.json`,
            JSON.stringify(artifact)
        );
        return artifact;
    });
}
