import fs from "fs";
import signify, {CreateIdentiferArgs, HabState, Serder, Siger, State} from "signify-ts";
import { parseAidInfo } from "../create-aid";
import { getOrCreateAID, getOrCreateClients } from "../keystore-creation";
import { createAIDMultisig } from "../multisig-creation";
import { resolveEnvironment, TestEnvironmentPreset } from "../resolve-env";
import {waitAndMarkNotification} from "../notifications.ts";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1];
const dataDir = args[2];
const aidInfoArg = args[3];
const delegationPrefix = args[4];

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);


/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 *
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param delpre The prefix of the delegator to use for the multisig AID
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function rotateMultisig(multisigName: string, aidInfo: string, delpre: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
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

    // Create a multisig AID for the QVI.
    // Skip if a QVI AID has already been incepted.

    const multisig = await QAR1Client.identifiers().get(multisigName);

    // get QAR keystates for inclusion in the multisig inception event
    const rstates = [QAR1Id.state, QAR2Id.state, QAR3Id.state];
    const states = rstates;

    const rotateOp = await QAR1Client.identifiers().rotate(
        multisigName, {states: states}
    );

    // add signature attachments to the exn message

    const {payload, rotationEmbeds, recipients} = createMultisigExnData(states, rotateOp.serder, rotateOp.sigs);

    await QAR1Client
        .exchanges()
        .send(
            QAR1.name,
            multisigName,
            QAR1Id,
            '/multisig/rotate',
            payload,
            rotationEmbeds,
            recipients
        );

    await Promise.all([
        waitAndMarkNotification(QAR1Client, '/multisig/rot'),
        waitAndMarkNotification(QAR2Client, '/multisig/rot'),
        waitAndMarkNotification(QAR3Client, '/multisig/rot'),
    ]);
}

/**
 * Prepares rotation payload, signature embeds, and a recipient list based on the rotation serder and key states.
 * Used in the exchange message ('exn') sent to multisig participants to perform the multisig rotation.
 * @param keyStates
 * @param rotation
 * @param sigs
 */
function createMultisigExnData(keyStates: State[], rotation: Serder, sigs: string[]) {
    // add signature attachments to the exn message
    const sigers: Siger[] = sigs.map(
        (sig) => new signify.Siger({qb64: sig})
    );
    const sigMessageStream = signify.d(signify.messagize(rotation, sigers));
    const attachmentStream = sigMessageStream.substring(rotation.size); // extract just the attachments
    const rotationEmbeds = {
        rot: [rotation, attachmentStream]
    };
    // signing member IDs (signing this rotation - must satisfy the current signing threshold and prior next)
    const smids = keyStates.map((state: State) => state['i']);
    // rotation member IDs (members that can sign the next rotation)
    const rmids = keyStates.map((state: State) => state['i']);
    const recipients = keyStates.map((state: State) => state['i']);
    const payload = { gid: rotation.pre, smids, rmids};
    return {payload, rotationEmbeds, recipients};
}

const multisigOobiObj: any = await rotateMultisig(multisigName, aidInfoArg, delegationPrefix, witnessIds, env);
console.log("QVI delegated multisig rotated, waiting for GEDA to confirm rotation...");
