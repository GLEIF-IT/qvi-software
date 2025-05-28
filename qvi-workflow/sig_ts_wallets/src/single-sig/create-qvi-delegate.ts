import {parseAidInfoSingleSig} from "../create-aid";
import {getOrCreateClient} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {parseOobiInfoSingleSig} from "./oobis.ts";
import {resolveOobi} from "../oobis.ts";
import fs from "fs";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const qviName = args[1];
const aidInfoArg = args[2];
const oobiInfoArg = args[3];
const delegatorPrefix = args[4];
const dataDir = args[5];

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);

/**
 * Create a delegated AID for the QVI delegated from the AID specified by delpre.
 *
 * @param qviName
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param witnessIds
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function createQviDelegate(qviName: string, aidInfo: string, oobiInfo: string, delegatorPrefix: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
    const [WAN, WIL, WES, WIT] = witnessIds; // QARs use WIL, Person uses WES

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


const {delegatePre, icpOpName} = await createQviDelegate(qviName, aidInfoArg, oobiInfoArg, delegatorPrefix, witnessIds, env);
console.log("Writing QVI delegate prefix and op name to file...");
await fs.promises.writeFile(`${dataDir}/qvi-delegate-info.json`, JSON.stringify({qviPre: delegatePre, icpOpName}));
