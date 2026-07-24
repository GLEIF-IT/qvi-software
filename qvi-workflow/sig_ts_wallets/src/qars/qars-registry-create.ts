import fs from "fs";
import {randomNonce} from "signify-ts";
import {parseAidInfo} from "../create-aid";
import {getOrCreateAID, getOrCreateClient} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {createRegistryMultisig} from "../credentials";
import {
    completeCoordinatedOperations,
} from '../coordinated-operation.ts';
import {retry} from '../retry.ts';
import {
    assertGroupStateConvergence,
    readGroupObservation,
} from '../group-state.ts';
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
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param witnessIds list of witness IDs for the QVI multisig AID configuration
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{registryRegk: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
export async function createQviRegistry(multisigName: string, registryName: string, aidInfo: string, environment: TestEnvironmentPreset) {
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

    // Get the QVI multisig AID
    const clients = [QAR1Client, QAR2Client, QAR3Client];
    const memberPrefixes = [
        QAR1Id.prefix,
        QAR2Id.prefix,
        QAR3Id.prefix,
    ];
    const groupObservations = await Promise.all(
        clients.map((client, index) =>
            readGroupObservation(
                client,
                memberPrefixes[index],
                multisigName,
                memberPrefixes
            )
        )
    );
    assertGroupStateConvergence(
        groupObservations,
        memberPrefixes
    );
    const [qviAID1, qviAID2, qviAID3] =
        groupObservations.map((observation) => observation.group);
    let [qviRegistrybyQAR1, qviRegistrybyQAR2, qviRegistrybyQAR3] =
        await Promise.all([
            QAR1Client.registries().list(multisigName),
            QAR2Client.registries().list(multisigName),
            QAR3Client.registries().list(multisigName),
        ]);
    const registryLists = [
        qviRegistrybyQAR1,
        qviRegistrybyQAR2,
        qviRegistrybyQAR3,
    ];
    const everyQarHasOneRegistry = registryLists.every(
        (registries) => registries.length === 1
    );
    const noQarHasRegistry = registryLists.every(
        (registries) => registries.length === 0
    );
    if (everyQarHasOneRegistry) {
        const regk = registryLists[0][0].regk;
        const registryPrefixConverged = registryLists.every(
            (registries) => registries[0].regk === regk
        );
        if (registryPrefixConverged === false) {
            throw new Error('QARs disagree on the existing registry prefix');
        }
        return {
            registryRegk: regk,
        };
    }
    if (noQarHasRegistry === false) {
        throw new Error(
            'QVI registry state is missing, multiple, or present on only a subset of QARs'
        );
    }

    const nonce = randomNonce();
    const registryOp1 = await createRegistryMultisig(
        QAR1Client,
        QAR1Id,
        [QAR2Id, QAR3Id],
        qviAID1,
        registryName,
        nonce,
        {isInitiator: true}
    );
    const registryOp2 = await createRegistryMultisig(
        QAR2Client,
        QAR2Id,
        [QAR1Id, QAR3Id],
        qviAID2,
        registryName,
        nonce,
        {coordinator: QAR1Id.prefix}
    );
    const registryOp3 = await createRegistryMultisig(
        QAR3Client,
        QAR3Id,
        [QAR1Id, QAR2Id],
        qviAID3,
        registryName,
        nonce,
        {coordinator: QAR1Id.prefix}
    );

    await completeCoordinatedOperations([
        {client: QAR1Client, result: registryOp1},
        {client: QAR2Client, result: registryOp2},
        {client: QAR3Client, result: registryOp3},
    ]);

    [qviRegistrybyQAR1, qviRegistrybyQAR2, qviRegistrybyQAR3] =
        await retry(async () => {
            const registries = await Promise.all([
                QAR1Client.registries().list(qviAID1.name),
                QAR2Client.registries().list(qviAID2.name),
                QAR3Client.registries().list(qviAID3.name),
            ]);
            const allMembersObserveRegistry = registries.every(
                (memberRegistries) => memberRegistries.length === 1
            );
            const registryPrefixConverged =
                allMembersObserveRegistry &&
                registries.every(
                    (memberRegistries) =>
                        memberRegistries[0].regk ===
                        registries[0][0].regk
                );
            if (registryPrefixConverged === false) {
                throw new Error(
                    'QVI registry has not converged on all three QARs'
                );
            }
            return registries;
        });
    const registryRegk = qviRegistrybyQAR1[0].regk;
    return {registryRegk};
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            ['config', 'group-name', 'registry-name', 'data-dir'],
            [
                'environment',
                'group-name',
                'registry-name',
                'data-dir',
                'participant-source',
            ]
        );
        requireNamedArguments(parsed, [
            'group-name',
            'registry-name',
            'data-dir',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        const registryInfo = await createQviRegistry(
            parsed['group-name'],
            parsed['registry-name'],
            invocation.participantSource,
            invocation.environment
        );
        await fs.promises.writeFile(
            `${parsed['data-dir']}/qvi-registry-info.json`,
            JSON.stringify({
                registryRegk: registryInfo.registryRegk,
            })
        );
        return {
            status: 'created',
            ...registryInfo,
        };
    });
}
