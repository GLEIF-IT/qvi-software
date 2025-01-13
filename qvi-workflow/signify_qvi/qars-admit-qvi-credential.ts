import fs from "fs";
import signify, { CreateIdentiferArgs, HabState } from "signify-ts";
import { createTimestamp, parseAidInfo } from "./create-aid";
import { getOrCreateAID, getOrCreateClients } from "./keystore-creation";
import { createAIDMultisig } from "./multisig-creation";
import { resolveEnvironment, TestEnvironmentPreset } from "./resolve-env";
import { admitMultisig, getReceivedCredential, waitForCredential } from "./credentials";
import { waitAndMarkNotification } from "./notifications";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]
const gedaPrefix = args[2]
const qviCredSAID = args[3]

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);
const QVI_MS_NAME='QVI';


/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param gedaPrefix identifier of the GEDA multisig AID who issued the QVI credential
 * @param witnessIds list of witness IDs for the QVI multisig AID configuration
 * @param qviCredSAID the SAID of the QVI credential issued by the GEDA
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function admitQviCredential(aidInfo: string, gedaPrefix: string, witnessIds: Array<string>, qviCredSAID: string, environment: TestEnvironmentPreset) {
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
    const qar1Ms = await QAR1Client.identifiers().get(QVI_MS_NAME);
    // Skip if a QVI AID has already been incepted.
    
    let qviCredbyQAR1 = await getReceivedCredential(QAR1Client, qviCredSAID);
    let qviCredbyQAR2 = await getReceivedCredential(QAR2Client, qviCredSAID);
    let qviCredbyQAR3 = await getReceivedCredential(QAR3Client, qviCredSAID);
    if (!(qviCredbyQAR1 && qviCredbyQAR2 && qviCredbyQAR3)) {
        const admitTime = createTimestamp();
        await admitMultisig(
            QAR1Client,
            QAR1Id,
            [QAR2Id, QAR3Id],
            qar1Ms,
            gedaPrefix,
            admitTime
        );
        await admitMultisig(
            QAR2Client,
            QAR2Id,
            [QAR1Id, QAR3Id],
            qar1Ms,
            gedaPrefix,
            admitTime
        );
        await admitMultisig(
            QAR3Client,
            QAR3Id,
            [QAR1Id, QAR2Id],
            qar1Ms,
            gedaPrefix,
            admitTime
        );
        await waitAndMarkNotification(QAR1Client, '/multisig/exn');
        await waitAndMarkNotification(QAR2Client, '/multisig/exn');
        await waitAndMarkNotification(QAR3Client, '/multisig/exn');
        await waitAndMarkNotification(QAR1Client, '/exn/ipex/admit');
        await waitAndMarkNotification(QAR2Client, '/exn/ipex/admit');
        await waitAndMarkNotification(QAR3Client, '/exn/ipex/admit');

        qviCredbyQAR1 = await waitForCredential(QAR1Client, qviCredSAID);
        qviCredbyQAR2 = await waitForCredential(QAR2Client, qviCredSAID);
        qviCredbyQAR3 = await waitForCredential(QAR3Client, qviCredSAID);
    }
    
}
const admitResult: any = await admitQviCredential(aidInfoArg, gedaPrefix, witnessIds, qviCredSAID, env);

console.log("QVI credential admitted");
