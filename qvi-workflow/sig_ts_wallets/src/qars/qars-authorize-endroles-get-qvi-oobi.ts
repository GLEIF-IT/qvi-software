import { SignifyClient } from "signify-ts";
import { createTimestamp, parseAidInfo } from "../create-aid";
import { getOrCreateAID, getOrCreateClients } from "../keystore-creation";
import { addEndRoleMultisig } from "../multisig-creation";
import { waitAndMarkNotification } from "../notifications";
import { waitOperation } from "../operations";
import { resolveEnvironment, TestEnvironmentPreset } from "../resolve-env";
import fs from 'fs';

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1]
const dataDir = args[2];
const aidInfoArg = args[3]

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);

/**
 * Authorizes the 'agent' role to each of the three agents used by each of the three SignifyTS participants in the QVI Multisig AID.
 * 
 * @param aidInfo Comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param witnessIds the set of witnesses to use for the QVI multisig AID configuration
 * @param environment runtime environment to use for resolving environment variables
 * @returns the three QAR SignifyClient instances
 */
async function authorizeAgentEndRoleForQVI(multisigName: string, aidInfo: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
    const [WAN, WIL, WES, WIT] = witnessIds; // QARs use WIL, Person uses WES

    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
    ] = await getOrCreateClients(3, [QAR1.salt, QAR2.salt, QAR3.salt], environment);

    // get AIDs
    const aidConfigQARs = {
        toad: 1,
        wits: [WIL],
    };
    const [
            QAR1Id,
            QAR2Id,
            QAR3Id,
    ] = await Promise.all([
        getOrCreateAID(QAR1Client, QAR1.name, aidConfigQARs),
        getOrCreateAID(QAR2Client, QAR2.name, aidConfigQARs),
        getOrCreateAID(QAR3Client, QAR3.name, aidConfigQARs),
    ]);

    const qviMultisigAid = await QAR1Client.identifiers().get(multisigName);

    // Skip if they have already been authorized.
    let [oobiQVIbyQAR1, oobiQVIbyQAR2, oobiQVIbyQAR3] = await Promise.all([
        QAR1Client.oobis().get(multisigName, 'agent'),
        QAR2Client.oobis().get(multisigName, 'agent'),
        QAR3Client.oobis().get(multisigName, 'agent'),
    ]);
    if (
        oobiQVIbyQAR1.oobis.length == 0 ||
        oobiQVIbyQAR2.oobis.length == 0 ||
        oobiQVIbyQAR3.oobis.length == 0
    ) {
        const timestamp = createTimestamp();
        const opList1 = await addEndRoleMultisig(
            QAR1Client,
            multisigName,
            QAR1Id,
            [QAR2Id, QAR3Id],
            qviMultisigAid,
            timestamp,
            true
        );
        const opList2 = await addEndRoleMultisig(
            QAR2Client,
            multisigName,
            QAR2Id,
            [QAR1Id, QAR3Id],
            qviMultisigAid,
            timestamp
        );
        const opList3 = await addEndRoleMultisig(
            QAR3Client,
            multisigName,
            QAR3Id,
            [QAR1Id, QAR2Id],
            qviMultisigAid,
            timestamp
        );

        await Promise.all(opList1.map((op) => waitOperation(QAR1Client, op)));
        await Promise.all(opList2.map((op) => waitOperation(QAR2Client, op)));
        await Promise.all(opList3.map((op) => waitOperation(QAR3Client, op)));

        await waitAndMarkNotification(QAR1Client, '/multisig/rpy');
        // await waitAndMarkNotification(QAR2Client, '/multisig/rpy');
        // await waitAndMarkNotification(QAR3Client, '/multisig/rpy');
        // need it for client 3?

        [oobiQVIbyQAR1, oobiQVIbyQAR2, oobiQVIbyQAR3] = await Promise.all([
            QAR1Client.oobis().get(multisigName, 'agent'),
            QAR2Client.oobis().get(multisigName, 'agent'),
            QAR3Client.oobis().get(multisigName, 'agent'),
        ]);

        const oobiData = await getQVIMultisigOobi(QAR1Client);
        await fs.promises.writeFile(`${dataDir}/qvi-oobi.json`, JSON.stringify(oobiData));
        console.log('QVI multisig oobi has been authorized and generated');
    }
    else {
        const oobiData = await getQVIMultisigOobi(QAR1Client);
        await fs.promises.writeFile(`${dataDir}/qvi-oobi.json`, JSON.stringify(oobiData));
        console.log("QVI multisig oobi has already been authorized and generated");
    }
}

/**
 * Writes the agent OOBI to the file qvi-oobi.json.
 * The agent OOBI strips off the final AID prefix that is specific to the participant so that messages sent to this OOBI
 * are sent to all multisig participants rather t han the participant identified by the last AID prefix on the agent OOBI.
 * @param QAR1Client SignifyClient for QAR1
 * @param QAR2Client SignifyClient for QAR2
 * @param QAR3Client SignifyClient for QAR3
 * @returns 
 */
async function getQVIMultisigOobi(QAR1Client: SignifyClient) {
    const msOobiResp = await QAR1Client.oobis().get(multisigName, 'agent')
    const oobi=msOobiResp.oobis[0].split('/agent/')[0];
    return {oobi: oobi}
}
await authorizeAgentEndRoleForQVI(multisigName, aidInfoArg, witnessIds, env);


