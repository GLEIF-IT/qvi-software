import signify, {
    assertMultisigRot,
    type HabState,
    type KeyState,
    type Siger,
    type SignifyClient,
} from 'signify-ts';
import {parseAidInfo} from "../create-aid";
import {sendExchangeToEachRecipient} from '../exchanges.ts';
import {getOrCreateAID, getOrCreateClient} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {
    notificationReference,
    waitForMatchingNotification,
} from '../notifications.ts';
import {
    waitKeyStateOperation,
    waitOperation,
    validateThreeMemberOperationNames,
} from '../operations.ts';
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';


/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 *
 * @param multisigName
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param witnessIds
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
export async function rotateMultisig(
    multisigName: string,
    aidInfo: string,
    environment: TestEnvironmentPreset
) {
    const {witnessIds} = resolveEnvironment(environment);
    const [, WIL] = witnessIds;

    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const QAR1Client = await getOrCreateClient(QAR1.salt, environment, 1);
    const QAR2Client = await getOrCreateClient(QAR2.salt, environment, 2);
    const QAR3Client = await getOrCreateClient(QAR3.salt, environment, 3);

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
    const qar1RotRes = await QAR1Client.identifiers().rotate(
        multisigName, {states: states, rstates: rstates}
    );
    const qar1RotOp = await qar1RotRes.op();
    const body = qar1RotRes.serder;
    let sigs = qar1RotRes.sigs;

    // add signature attachments to the exn message
    const sigers: Siger[] = sigs.map((sig) => new signify.Siger({qb64: sig}));
    const ims = signify.d(signify.messagize(body, sigers));
    const atc = ims.substring(body.size); // extract just the attachments
    const embeds = {
        rot: [body, atc]
    };
    // signing member IDs (signing this rotation - must satisfy the current signing threshold and prior next)
    const smids = states.map((state: KeyState) => state.i);
    const rmids = states.map((state: KeyState) => state.i);
    const payload = { gid: body.pre, smids: smids, rmids: rmids};
    const recipients = [aid2State, aid3State].map(
        (state: KeyState) => state.i
    );

    console.log(`Sending multisig rotation exchange message to ${recipients}...`);
    const qar1Receipts = await sendExchangeToEachRecipient(QAR1Client, {
        name: QAR1.name,
        topic: multisigName,
        sender: QAR1Id,
        route: '/multisig/rot',
        payload,
        embeds,
        recipients,
    });
    console.log("Multisig joining rotation as QARs...");
    // await new Promise(resolve => setTimeout(resolve, 3000));// wait for the operation to be processed


    console.log("Waiting for multisig rotation notifications...");
    // join operation with other QARs
    // join with QAR2
    const qar2RotationNotification =
        await waitForMatchingNotification(QAR2Client, {
            notificationRoute: '/multisig/rot',
            exchangeRoute: '/multisig/rot',
            sender: QAR1Id.prefix,
            recipient: QAR2Id.prefix,
            groupPrefix: body.pre,
        });

    const qar2ExnReplayList = await QAR2Client
        .groups()
        .getRequest(qar2RotationNotification.exchangeSaid);

    const qar2Request = assertMultisigRot(qar2ExnReplayList[0]);
    const replayedRotationMatches =
        qar2Request.exn.e.rot.d === body.said;
    if (replayedRotationMatches === false) {
        throw new Error(
            `QAR2 received rotation ${qar2Request.exn.e.rot.d}; expected ${body.said}`
        );
    }

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

    const qar2Recp = [aid1State, aid3State].map((state) => state.i);
    const qar2Receipts = await sendExchangeToEachRecipient(QAR2Client, {
        name: QAR2.name,
        topic: multisigName,
        sender: QAR2Id,
        route: '/multisig/rot',
        payload: {
            gid: qar2RotSerder.pre,
            smids,
            rmids,
        },
        embeds: qar2Embeds,
        recipients: qar2Recp,
    });
    console.log(
        "QAR2 joined multisig rotation; retaining its notice until completion"
    );

    const qar2MSAID = await QAR2Client.identifiers().get(multisigName);
    const qar3RotationNotification =
        await waitForMatchingNotification(QAR3Client, {
            notificationRoute: '/multisig/rot',
            exchangeRoute: '/multisig/rot',
            sender: QAR2Id.prefix,
            recipient: QAR3Id.prefix,
            groupPrefix: body.pre,
        });

    const qar3ExnReplayList = await QAR3Client
        .groups()
        .getRequest(qar3RotationNotification.exchangeSaid);

    const qar3Request = assertMultisigRot(qar3ExnReplayList[0]);
    const qar3ReplayedRotationMatches =
        qar3Request.exn.e.rot.d === body.said;
    if (qar3ReplayedRotationMatches === false) {
        throw new Error(
            `QAR3 received rotation ${qar3Request.exn.e.rot.d}; expected ${body.said}`
        );
    }

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

    const qar3Recp = [aid1State, aid2State].map((state) => state.i);
    const qar3Receipts = await sendExchangeToEachRecipient(QAR3Client, {
        name: QAR3.name,
        topic: multisigName,
        sender: QAR3Id,
        route: '/multisig/rot',
        payload: {
            gid: qar3RotSerder.pre,
            smids,
            rmids,
        },
        embeds: qar3Embeds,
        recipients: qar3Recp,
    });
    console.log(
        "QAR3 joined multisig rotation; retaining its notice until completion"
    );

    const qar3MSAID = await QAR3Client.identifiers().get(multisigName);
    const operationNames = validateThreeMemberOperationNames(
        [
            qar1RotOp.name,
            qar2RotOp.name,
            qar3RotOp.name,
        ],
        'Delegated rotation completion'
    );

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
    return {
        status: 'submitted' as const,
        groupName: multisigName,
        operationNames,
        notificationReferences: {
            qar2: notificationReference(
                qar2RotationNotification
            ),
            qar3: notificationReference(
                qar3RotationNotification
            ),
        },
        coordinationReceipts: [
            ...qar1Receipts.map((receipt) => ({
                sender: QAR1Id.prefix,
                ...receipt,
            })),
            ...qar2Receipts.map((receipt) => ({
                sender: QAR2Id.prefix,
                ...receipt,
            })),
            ...qar3Receipts.map((receipt) => ({
                sender: QAR3Id.prefix,
                ...receipt,
            })),
        ],
    };
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
        waitKeyStateOperation(QAR1Client, updates[0]),
        waitKeyStateOperation(QAR1Client, updates[1]),
        waitKeyStateOperation(QAR2Client, updates[2]),
        waitKeyStateOperation(QAR2Client, updates[3]),
        waitKeyStateOperation(QAR3Client, updates[4]),
        waitKeyStateOperation(QAR3Client, updates[5]),
    ]);
    return [aid1State, aid2State, aid3State] as const;
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            ['config', 'group-name'],
            ['environment', 'group-name', 'participant-source']
        );
        requireNamedArguments(parsed, ['group-name']);
        const invocation = participantInvocationFromArguments(parsed);
        return rotateMultisig(
            parsed['group-name'],
            invocation.participantSource,
            invocation.environment
        );
    });
}
