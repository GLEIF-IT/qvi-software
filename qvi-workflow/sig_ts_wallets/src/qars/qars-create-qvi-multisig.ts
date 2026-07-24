import fs from "fs";
import signify, { CreateIdentiferArgs } from "signify-ts";
import { parseAidInfo } from "../create-aid";
import {getOrCreateAID, getOrCreateClient} from "../keystore-creation";
import { createAIDMultisig } from "../multisig-creation";
import {notificationReference} from '../notifications.ts';
import { resolveEnvironment, TestEnvironmentPreset } from "../resolve-env";
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {
    qviNextThreshold,
    qviSigningThreshold,
} from '../qvi-configuration.ts';
import {
    assertExactDirectedFanout,
    canonicalReceipts,
    canonicalStrings,
} from '../workflow-contracts.ts';


/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 *
 * @param multisigName the name of the multisig to create
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param delpre The prefix of the delegator to use for the multisig AID
 * @param witnessIds the list of witness IDs to use for the multisig AID
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
export async function createQviMultisig(multisigName: string, aidInfo: string, delpre: string, environment: TestEnvironmentPreset) {
    const {witnessIds} = resolveEnvironment(environment);
    const [WAN, WIL, WES] = witnessIds; // QARs use WIL, Person uses WES

    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(aidInfo);
    const QAR1Client = await getOrCreateClient(QAR1.salt, environment, 1);
    const QAR2Client = await getOrCreateClient(QAR2.salt, environment, 2);
    const QAR3Client = await getOrCreateClient(QAR3.salt, environment, 3);
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
    const memberPrefixes = [
        QAR1Id.prefix,
        QAR2Id.prefix,
        QAR3Id.prefix,
    ];

    const rstates = [QAR1Id.state, QAR2Id.state, QAR3Id.state];
    const kargsMultisigAID: CreateIdentiferArgs = {
        delpre: delpre,
        algo: signify.Algos.group,
        isith: qviSigningThreshold(),
        nsith: qviNextThreshold(),
        toad: aidConfigQARs.toad,
        wits: aidConfigQARs.wits,
        states: [...rstates],
        rstates: rstates,
    };

    kargsMultisigAID.mhab = QAR1Id;
    const inception1 = await createAIDMultisig(
        QAR1Client,
        QAR1Id,
        [QAR2Id, QAR3Id],
        multisigName,
        kargsMultisigAID,
        {isInitiator: true}
    );
    kargsMultisigAID.mhab = QAR2Id;
    const inception2 = await createAIDMultisig(
        QAR2Client,
        QAR2Id,
        [QAR1Id, QAR3Id],
        multisigName,
        kargsMultisigAID,
        {coordinator: QAR1Id.prefix}
    );
    kargsMultisigAID.mhab = QAR3Id;
    const inception3 = await createAIDMultisig(
        QAR3Client,
        QAR3Id,
        [QAR1Id, QAR2Id],
        multisigName,
        kargsMultisigAID,
        {coordinator: QAR1Id.prefix}
    );

    const [qar1Ms, qar2Ms, qar3Ms] = await Promise.all([
        QAR1Client.identifiers().get(multisigName),
        QAR2Client.identifiers().get(multisigName),
        QAR3Client.identifiers().get(multisigName),
    ]);
    const groupPrefixConverged =
        qar2Ms.prefix === qar1Ms.prefix &&
        qar3Ms.prefix === qar1Ms.prefix;
    if (groupPrefixConverged === false) {
        throw new Error('QARs disagree on the delegated QVI prefix');
    }

    const inceptions = [
        {sender: QAR1Id.prefix, ...inception1},
        {sender: QAR2Id.prefix, ...inception2},
        {sender: QAR3Id.prefix, ...inception3},
    ];
    
    
    const operationNames = inceptions.map(
        (inception) => inception.operation.name
    );
    const coordinationReceipts = inceptions.flatMap(
        (inception) =>
            inception.wrapperReceipts.map((receipt) => ({
                sender: inception.sender,
                ...receipt,
            }))
    );
    const expectedOperationName = `group.${qar1Ms.prefix}`;
    const operationNamesAreExact =
        operationNames.length === 3 &&
        operationNames.every(
            (operationName) =>
                operationName === expectedOperationName
        );
    if (operationNamesAreExact === false) {
        throw new Error(
            'Delegated inception did not return one matching member operation per QAR'
        );
    }
    assertExactDirectedFanout(
        coordinationReceipts,
        memberPrefixes,
        'Delegated inception coordination',
        qar1Ms.prefix
    );

    return {
        msPrefix: qar1Ms.prefix,
        delegationAnchor: {
            i: qar1Ms.prefix,
            s: '0',
            d: qar1Ms.prefix,
        },
        operationNames: canonicalStrings(operationNames),
        coordinationNotifications: inceptions.map(
            (inception) => ({
                memberPrefix: inception.sender,
                notifications: inception.coordination.map(
                    notificationReference
                ),
            })
        ),
        coordinationReceipts:
            canonicalReceipts(coordinationReceipts),
    }
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            ['config', 'group-name', 'data-dir', 'delegator-prefix'],
            [
                'environment',
                'group-name',
                'data-dir',
                'participant-source',
                'delegator-prefix',
            ]
        );
        requireNamedArguments(parsed, [
            'group-name',
            'data-dir',
            'delegator-prefix',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        const multisig = await createQviMultisig(
            parsed['group-name'],
            invocation.participantSource,
            parsed['delegator-prefix'],
            invocation.environment
        );
        await fs.promises.writeFile(
            `${parsed['data-dir']}/qvi-multisig-info.json`,
            JSON.stringify(multisig)
        );
        return {
            status: 'inception-submitted',
            ...multisig,
        };
    });
}
