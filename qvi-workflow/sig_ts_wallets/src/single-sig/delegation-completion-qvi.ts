import {parseAidInfoSingleSig} from "../create-aid.ts";
import {getOrCreateClient} from "../keystore-creation.ts";
import {TestEnvironmentPreset} from "../resolve-env.ts";
import {waitOperation} from "../operations.ts";
import fs from "fs";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const qviName = args[1];
const aidInfoArg = args[2];
const delegatorPrefix = args[3];
const icpOpName = args[4];
const dataDir = args[5];

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
async function completeDelegation(qviName: string, aidInfo: string, delegatorPrefix: string, icpOpName: string, environment: TestEnvironmentPreset) {
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

    const endRoleRes = await QVIClient
        .identifiers()
        .addEndRole(qviName, 'agent', QVIClient!.agent!.pre);
    await waitOperation(QVIClient, await endRoleRes.op());
    const qviOobis = await QVIClient.oobis().get(qviName);
    console.log(`Full Agent OOBI: ${qviOobis.oobis[0]}`)
    const agentOobi = qviOobis.oobis[0].split('/agent/')[0];

    console.log(`Agent OOBI for delegate ${qviName}: ${agentOobi}`);
    return agentOobi;

}
const agentOobi = await completeDelegation(qviName, aidInfoArg, delegatorPrefix, icpOpName, env);
console.log("Delegation check complete, writing agent OOBI to file...");
await fs.promises.writeFile(`${dataDir}/qvi-agent-oobi.json`, JSON.stringify({qviAgentOobi: agentOobi}));