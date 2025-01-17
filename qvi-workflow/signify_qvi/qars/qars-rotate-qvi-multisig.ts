import signify, {HabState, Serder, Siger, SignifyClient, State} from "signify-ts";
import {parseAidInfo} from "../create-aid";
import {getOrCreateAID, getOrCreateClients} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {waitAndMarkNotification} from "../notifications.ts";
import {waitOperation} from "../operations.ts";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1];
const aidInfoArg = args[2];

// resolve witness IDs for QVI multisig AID configuration
const {witnessIds} = resolveEnvironment(env);


/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 *
 * @param multisigName
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param witnessIds
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
async function rotateMultisig(multisigName: string, aidInfo: string, witnessIds: Array<string>, environment: TestEnvironmentPreset) {
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

    // Rotate all single signature AIDs and refresh keystate
    const members = [
        {name: QAR1.name, client: QAR1Client, id: QAR1Id},
        {name: QAR2.name, client: QAR2Client, id: QAR2Id},
        {name: QAR3.name, client: QAR3Client, id: QAR3Id}
    ];
    const [aid1State, aid2State, aid3State] = await rotateMultisigMembersAndRefreshKeystate(members);

    const multisig = await QAR1Client.identifiers().get(multisigName);

    // get QAR keystates for inclusion in the multisig inception event
    const states = [aid1State, aid2State, aid3State];
    const rstates = [...states];

    const identifier = QAR1Client.identifiers();
    console.log("Creating multisig rotation operation...");
    const rotateOp = await identifier.rotate(
        multisigName, {states: states, rstates: states}
    );

    // add signature attachments to the exn message
    const {payload, rotationEmbeds} = createMultisigExnData(states, rotateOp.serder, rotateOp.sigs);
    const recipients = [aid2State, aid3State].map((state: State) => state['i']);

    console.log(`Sending multisig rotation exchange message to ${recipients}...`);
    await QAR1Client
        .exchanges()
        .send(
            QAR1.name,
            'multisig',
            QAR1Id,
            '/multisig/rot',
            payload,
            rotationEmbeds,
            recipients
        );

    console.log("Multisig joining rotation as QARs...");


    console.log("Waiting to mark notifications for multisig rotation...");
    // await waitAndMarkNotification(QAR2Client, '/multisig/rot');
    // await waitAndMarkNotification(QAR3Client, '/multisig/rot');
}

/**
 * Prepare each single-signature identifier participating in the multisignature identifier for the delegated rotation by
 * rotating each individual key and refreshing the keystate amongst all the participants.
 * @param members
 * @returns {Promise<[HabState, HabState, HabState]>} The updated key states for each member
 */
async function rotateMultisigMembersAndRefreshKeystate(members: {name: string, client: SignifyClient, id: HabState}[]) {
    const [
        {name: qar1, client: QAR1Client, id: QAR1Id},
        {name: qar2, client: QAR2Client, id: QAR2Id},
        {name: qar3, client: QAR3Client, id: QAR3Id}
    ] = members;
    // rotate single sig
    const [rotateResult1, rotateResult2, rotateResult3] = await Promise.all([
        QAR1Client.identifiers().rotate(qar1),
        QAR2Client.identifiers().rotate(qar2),
        QAR3Client.identifiers().rotate(qar3),
    ]);

    await Promise.all([
        waitOperation(QAR1Client, await rotateResult1.op()),
        waitOperation(QAR2Client, await rotateResult2.op()),
        waitOperation(QAR3Client, await rotateResult3.op()),
    ]);

    // refresh key state
    const [aid1, aid2, aid3] = await Promise.all([
        QAR1Client.identifiers().get(qar1),
        QAR2Client.identifiers().get(qar2),
        QAR3Client.identifiers().get(qar3),
    ]);

    const updates = await Promise.all([
        await QAR1Client.keyStates().query(aid2.prefix),
        await QAR1Client.keyStates().query(aid3.prefix),
        await QAR2Client.keyStates().query(aid1.prefix),
        await QAR2Client.keyStates().query(aid3.prefix),
        await QAR3Client.keyStates().query(aid1.prefix),
        await QAR3Client.keyStates().query(aid2.prefix),
    ]);

    const [aid2State, aid3State, aid1State] = await Promise.all([
        waitOperation(QAR1Client, updates[0]),
        waitOperation(QAR1Client, updates[1]),
        waitOperation(QAR2Client, updates[2]),
        waitOperation(QAR2Client, updates[3]),
        waitOperation(QAR3Client, updates[4]),
        waitOperation(QAR3Client, updates[5]),
    ]);
    return [aid1State.response, aid2State.response, aid3State.response];
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
    return {payload, rotationEmbeds};
}

const multisigOobiObj: any = await rotateMultisig(multisigName, aidInfoArg, witnessIds, env);
console.log("QVI delegated multisig rotated, waiting for GEDA to confirm rotation...");
