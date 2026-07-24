import {parseAidInfoSingleSig} from "../create-aid.ts";
import {getOrCreateClient} from "../keystore-creation.ts";
import {TestEnvironmentPreset} from "../resolve-env.ts";
import {waitOperation} from "../operations.ts";
import fs from "fs";
import {
    isMainModule,
    parseNamedArguments,
    requireNamedArguments,
    runJsonCli,
    singleSigParticipantInvocationFromArguments,
} from '../cli.ts';

/**
 * Both completes the delegation by refreshing keystate from the delegator to discover the approval
 * and adds the agent endpoint role to the delegate QVI AID.
 * Returns the agent OOBI of the delegate QVI AID.
 *
 * @param qviName
 * @param aidInfo
 * @param delegatorPrefix
 * @param icpOpName
 * @param environment
 */
export async function completeDelegation(
    qviName: string,
    aidInfo: string,
    delegatorPrefix: string,
    icpOpName: string,
    environment: TestEnvironmentPreset
) {
    // get Clients
    const {QVI} = parseAidInfoSingleSig(aidInfo);
    const QVIClient = await getOrCreateClient(QVI.salt, environment, 1);

    const keyStateOp = await QVIClient.keyStates().query(delegatorPrefix, '2'); // GAR icp is 0, registry is 1, so dip is 2
    await waitOperation(QVIClient, keyStateOp);

    // Client 2 check inception operation complete
    const icpOp = await QVIClient.operations().get(icpOpName);
    await waitOperation(QVIClient, icpOp);
    const qviAid = await QVIClient.identifiers().get(qviName);
    console.log('Delegation approved for aid:', qviAid.prefix);

    const agentPrefix = QVIClient.agent?.pre;
    const agentPrefixIsMissing =
        typeof agentPrefix !== 'string' || agentPrefix.length === 0;
    if (agentPrefixIsMissing) {
        throw new Error(
            `KERIA returned no agent AID while authorizing ${qviName}`
        );
    }
    const endRoleRes = await QVIClient
        .identifiers()
        .addEndRole(qviName, 'agent', agentPrefix);
    await waitOperation(QVIClient, await endRoleRes.op());
    const qviOobis = await QVIClient.oobis().get(qviName);
    const agentOobi = qviOobis.oobis[0];
    const agentOobiIsMissing =
        typeof agentOobi !== 'string' || agentOobi.length === 0;
    if (agentOobiIsMissing) {
        throw new Error(
            `KERIA returned no endpoint-qualified agent OOBI for ${qviName}`
        );
    }
    const expectedPath =
        `/oobi/${qviAid.prefix}/agent/${agentPrefix}`;
    const oobiPathMatches =
        new URL(agentOobi).pathname === expectedPath;
    if (oobiPathMatches === false) {
        throw new Error(
            `QVI agent OOBI path does not match ${expectedPath}`
        );
    }
    console.log(`Full Agent OOBI: ${agentOobi}`)

    console.log(`Agent OOBI for delegate ${qviName}: ${agentOobi}`);
    return agentOobi;

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
                'delegator-prefix',
                'inception-operation',
                'artifact-dir',
            ]
        );
        requireNamedArguments(parsed, [
            'qvi-name',
            'delegator-prefix',
            'inception-operation',
            'artifact-dir',
        ]);
        const invocation =
            singleSigParticipantInvocationFromArguments(parsed);
        const agentOobi = await completeDelegation(
            parsed['qvi-name'],
            invocation.participantSource,
            parsed['delegator-prefix'],
            parsed['inception-operation'],
            invocation.environment
        );
        const artifact = {qviAgentOobi: agentOobi};
        await fs.promises.writeFile(
            `${parsed['artifact-dir']}/qvi-agent-oobi.json`,
            JSON.stringify(artifact)
        );
        return artifact;
    });
}
