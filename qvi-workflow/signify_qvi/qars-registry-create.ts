import fs from "fs";
import signify, { CreateIdentiferArgs, HabState, randomNonce } from "signify-ts";
import { parseAidInfo } from "./create-aid";
import { getOrCreateAID, getOrCreateClients } from "./keystore-creation";
import { createAIDMultisig } from "./multisig-creation";
import { resolveEnvironment, TestEnvironmentPreset } from "./resolve-env";
import { createRegistryMultisig } from "./credentials";
import { waitOperation } from "./operations";
import { waitAndMarkNotification } from "./notifications";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const dataDir = args[1];
const aidInfoArg = args[2]

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);
const QVI_MS_NAME='QVI';
const QVI_REGISTRY_NAME='QVI-REGISTRY'


/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param witnessIds list of witness IDs for the QVI multisig AID configuration
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{registryRegk: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function createQviRegistry(aidInfo: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
    ] = await getOrCreateClients(3, [QAR1.salt, QAR2.salt, QAR3.salt], environment);

    // get AIDs
    const kargsAID = {
        toad: witnessIds.length,
        wits: witnessIds,
    };
    const [
            QAR1Id,
            QAR2Id,
            QAR3Id,
    ] = await Promise.all([
        getOrCreateAID(QAR1Client, QAR1.name, kargsAID),
        getOrCreateAID(QAR2Client, QAR2.name, kargsAID),
        getOrCreateAID(QAR3Client, QAR3.name, kargsAID),
    ]);

    // Get the QVI multisig AID
    const qviAID = await QAR1Client.identifiers().get(QVI_MS_NAME);
    // Skip if a QVI AID has already been incepted.
    
    let [qviRegistrybyQAR1, qviRegistrybyQAR2, qviRegistrybyQAR3] =
        await Promise.all([
            QAR1Client.registries().list(QVI_MS_NAME),
            QAR2Client.registries().list(QVI_MS_NAME),
            QAR3Client.registries().list(QVI_MS_NAME),
        ]);
    if (qviRegistrybyQAR1.length != 0 &&
        qviRegistrybyQAR2.length != 0 &&
        qviRegistrybyQAR3.length != 0
    ) {
        console.log("QVI registry already exists: ", qviRegistrybyQAR1[0].regk);
        return {registryRegk: qviRegistrybyQAR1[0].regk}
    } else {
        
        const nonce = randomNonce();
        const registryOp1 = await createRegistryMultisig(
            QAR1Client,
            QAR1Id,
            [QAR2Id, QAR3Id],
            qviAID,
            QVI_REGISTRY_NAME,
            nonce,
            true
        );
        const registryOp2 = await createRegistryMultisig(
            QAR2Client,
            QAR2Id,
            [QAR1Id, QAR3Id],
            qviAID,
            QVI_REGISTRY_NAME,
            nonce
        );
        const registryOp3 = await createRegistryMultisig(
            QAR3Client,
            QAR3Id,
            [QAR1Id, QAR2Id],
            qviAID,
            QVI_REGISTRY_NAME,
            nonce
        );

        await Promise.all([
            waitOperation(QAR1Client, registryOp1),
            waitOperation(QAR2Client, registryOp2),
            waitOperation(QAR3Client, registryOp3),
        ]);

        await waitAndMarkNotification(QAR1Client, '/multisig/vcp');
        await new Promise(r => setTimeout(r, 5000)); // wait five seconds for the registry to be witnessed;

        [qviRegistrybyQAR1, qviRegistrybyQAR2, qviRegistrybyQAR3] =
            await Promise.all([
                QAR1Client.registries().list(qviAID.name),
                QAR2Client.registries().list(qviAID.name),
                QAR3Client.registries().list(qviAID.name),
            ]);
        console.log("QVI registry created: ", qviRegistrybyQAR1[0].regk);
        return {registryRegk: qviRegistrybyQAR1[0].regk}
    }
}
const registryInfo: any = await createQviRegistry(aidInfoArg, witnessIds, env);
await fs.writeFile(`${dataDir}/qvi-registry-info.json`, JSON.stringify(registryInfo), (err) => {
    if (err) {
        console.log(`error writing client info to file: ${err}`);        
        return
    }
});
