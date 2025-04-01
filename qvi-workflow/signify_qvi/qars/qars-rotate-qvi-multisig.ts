import signify, {HabState, Serder, Siger, SignifyClient, KeyState} from "signify-ts";
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
    const [WAN, WIL, WES, WIT] = witnessIds; // QARs use WIL, Person uses WES

    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const [
        QAR1Client,
        QAR2Client,
        QAR3Client,
    ] = await getOrCreateClients(3, [QAR1.salt, QAR2.salt, QAR3.salt], environment);

    const qar1MSAID = await QAR1Client.identifiers().get(multisigName);

    // get AIDs
    const aidConfigQARs = {
        toad: 1,
        wits: [WIL],
    };
    let [
            QAR1Id,
            QAR2Id,
            QAR3Id,
    ] = await Promise.all([
        getOrCreateAID(QAR1Client, QAR1.name, aidConfigQARs),
        getOrCreateAID(QAR2Client, QAR2.name, aidConfigQARs),
        getOrCreateAID(QAR3Client, QAR3.name, aidConfigQARs),
    ]);

    // Rotate all single signature AIDs and refresh keystate
    const members = [
        {name: QAR1.name, client: QAR1Client, id: QAR1Id},
        {name: QAR2.name, client: QAR2Client, id: QAR2Id},
        {name: QAR3.name, client: QAR3Client, id: QAR3Id}
    ];
    const [aid1State, aid2State, aid3State] = await rotateMultisigMembersAndRefreshKeystate(members);

    // Recreate HabStates to include the updated key states post-rotation - essential to use latest key indicated by Keeper.kidx
    let [
            Q1,
            Q2,
            Q3,
    ] = await Promise.all([
        getOrCreateAID(QAR1Client, QAR1.name, aidConfigQARs),
        getOrCreateAID(QAR2Client, QAR2.name, aidConfigQARs),
        getOrCreateAID(QAR3Client, QAR3.name, aidConfigQARs),
    ]);

    QAR1Id = Q1;
    QAR2Id = Q2;
    QAR3Id = Q3;

    // get QAR keystates for inclusion in the multisig rotation event
    const states = [aid1State, aid2State, aid3State];
    const rstates = [...states];

    console.log("Creating multisig rotation operation...");
    const rotateOp = await QAR1Client.identifiers().rotate(
        multisigName, {states: states, rstates: rstates}
    );
    const body = rotateOp.serder;
    let sigs = rotateOp.sigs;

    // add signature attachments to the exn message
    const sigers: Siger[] = sigs.map((sig) => new signify.Siger({qb64: sig}));
    const ims = signify.d(signify.messagize(body, sigers));
    const atc = ims.substring(body.size); // extract just the attachments
    const embeds = {
        rot: [body, atc]
    };
    // signing member IDs (signing this rotation - must satisfy the current signing threshold and prior next)
    const smids = states.map((state: KeyState) => state['i']);
    const rmids = states.map((state: KeyState) => state['i']);
    const payload = { gid: body.pre, smids: smids, rmids: rmids};
    const recipients = [aid2State, aid3State].map((state: KeyState) => state['i']);

    console.log(`Sending multisig rotation exchange message to ${recipients}...`);
    await QAR1Client
        .exchanges()
        .send(
            QAR1.name,
            multisigName,
            QAR1Id,
            '/multisig/rot',
            payload,
            embeds,
            recipients
        );
    console.log("Multisig joining rotation as QARs...");
    // await new Promise(resolve => setTimeout(resolve, 3000));// wait for the operation to be processed


    console.log("Waiting to mark notifications for multisig rotation...");
    // join operation with other QARs
    // join with QAR2
    const qar2RotExnSAID = await waitAndMarkNotification(
            QAR2Client, '/multisig/rot');

    const qar2ExnReplayList = await QAR2Client
        .groups()
        .getRequest(qar2RotExnSAID);

    const qar2RotExn = qar2ExnReplayList[0].exn;
    const qar2RotSerd = new Serder(qar2RotExn.e.rot);

    const qar2RotRes = await QAR2Client.identifiers().rotate(
        multisigName, {states: states, rstates: rstates}
    );
    const qar2RotOp = await qar2RotRes.op();
    const qar2RotSerder = qar2RotRes.serder;
    const qar2RotSigs = qar2RotRes.sigs;
    const qar2Sigers = qar2RotSigs.map((sig) => new signify.Siger({qb64:sig}));
    const qar2ims = signify.d(signify.messagize(qar2RotSerder, qar2Sigers));
    const qar2atc = qar2ims.substring(qar2RotSerder.size);
    const qar2Embeds = {
        rot: [qar2RotSerder, qar2atc]
    }

    const qar2Recp = [aid1State, aid3State].map((state) => state["i"]);
    const qar2ExnResp = await QAR2Client.exchanges()
        .send(
            QAR2.name,
            multisigName,
            QAR2Id,
            '/multisig/rot',
            {gid: qar2RotSerder.pre, smids: smids, rmids: rmids},
            qar2Embeds,
            qar2Recp
        );
    console.log("QAR2 joined multisig rotation, waiting for QAR3 to join...");

    const qar2MSAID = await QAR2Client.identifiers().get(multisigName);
    const qar3RotExnSAID = await waitAndMarkNotification(
            QAR3Client, '/multisig/rot');

    const qar3ExnReplayList = await QAR3Client
        .groups()
        .getRequest(qar3RotExnSAID);

    const qar3RotExn = qar3ExnReplayList[0].exn;
    const qar3RotSer = new Serder(qar3RotExn.e.rot);

    const qar3RotRes = await QAR3Client.identifiers().rotate(
        multisigName, {states: states, rstates: rstates}
    );
    const qar3RotOp = await qar3RotRes.op();
    const qar3RotSerder = qar3RotRes.serder;
    const qar3RotSigs = qar3RotRes.sigs;
    const qar3Sigers = qar3RotSigs.map((sig) => new signify.Siger({qb64:sig}));
    const qar3ims = signify.d(signify.messagize(qar3RotSerder, qar3Sigers));
    const qar3atc = qar3ims.substring(qar3RotSerder.size);
    const qar3Embeds = {
        rot: [qar3RotSerder, qar3atc]
    }

    const qar3Recp = [aid1State, aid2State].map((state) => state["i"]);
    const qar3ExnResp = await QAR3Client.exchanges()
        .send(
            QAR3.name,
            multisigName,
            QAR3Id,
            '/multisig/rot',
            {gid: qar3RotSerder.pre, smids: smids, rmids: rmids},
            qar3Embeds,
            qar3Recp
        );
    console.log("QAR3 joined multisig rotation, waiting for GEDA to confirm rotation...");

    const qar3MSAID = await QAR3Client.identifiers().get(multisigName);

    // refresh each other's key state again
    const initialUpdates = await Promise.all([
        await QAR1Client.keyStates().query(QAR2Id.prefix),
        await QAR1Client.keyStates().query(QAR3Id.prefix),
        await QAR2Client.keyStates().query(QAR1Id.prefix),
        await QAR2Client.keyStates().query(QAR3Id.prefix),
        await QAR3Client.keyStates().query(QAR1Id.prefix),
        await QAR3Client.keyStates().query(QAR2Id.prefix),
    ]);
    const [aid2St, aid3St, aid1St] = await Promise.all([
        waitOperation(QAR1Client, initialUpdates[0]),
        waitOperation(QAR1Client, initialUpdates[1]),
        waitOperation(QAR2Client, initialUpdates[2]),
        waitOperation(QAR2Client, initialUpdates[3]),
        waitOperation(QAR3Client, initialUpdates[4]),
        waitOperation(QAR3Client, initialUpdates[5]),
    ]);
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

    // refresh key state
    let [aid1, aid2, aid3] = await Promise.all([
        QAR1Client.identifiers().get(qar1),
        QAR2Client.identifiers().get(qar2),
        QAR3Client.identifiers().get(qar3),
    ]);
    const initialUpdates = await Promise.all([
        await QAR1Client.keyStates().query(aid2.prefix),
        await QAR1Client.keyStates().query(aid3.prefix),
        await QAR2Client.keyStates().query(aid1.prefix),
        await QAR2Client.keyStates().query(aid3.prefix),
        await QAR3Client.keyStates().query(aid1.prefix),
        await QAR3Client.keyStates().query(aid2.prefix),
    ]);
    const [aid2St, aid3St, aid1St] = await Promise.all([
        waitOperation(QAR1Client, initialUpdates[0]),
        waitOperation(QAR1Client, initialUpdates[1]),
        waitOperation(QAR2Client, initialUpdates[2]),
        waitOperation(QAR2Client, initialUpdates[3]),
        waitOperation(QAR3Client, initialUpdates[4]),
        waitOperation(QAR3Client, initialUpdates[5]),
    ]);

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
    let [a1, a2, a3] = await Promise.all([
        QAR1Client.identifiers().get(qar1),
        QAR2Client.identifiers().get(qar2),
        QAR3Client.identifiers().get(qar3),
    ]);
    aid1 = a1;
    aid2 = a2;
    aid3 = a3;

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

const multisigOobiObj: any = await rotateMultisig(multisigName, aidInfoArg, witnessIds, env);
console.log("QVI delegated multisig rotated, waiting for GEDA to confirm rotation...");
