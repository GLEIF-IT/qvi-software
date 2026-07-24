import fs from "fs";
import {CredentialData, CredentialSubject, Salter} from "signify-ts";
import {createTimestamp, parseAidInfo} from "../create-aid";
import {getOrCreateAID, getOrCreateClient} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {
    completeMultisigIpex,
    getIssuedCredential,
    grantMultisig,
    issueCredentialMultisig,
    requireCredential,
} from "../credentials";
import {
    assertIssuedCredentialConvergence,
    credentialSnapshot,
    type CredentialSnapshot,
} from '../credential-state.ts';
import {
    type OperationEvidence,
} from '../operations.ts';
import {
    completeCoordinatedOperations,
} from '../coordinated-operation.ts';
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {
    assertIssuanceContract,
    canonicalObserverSnapshots,
    canonicalOperationEvidence,
} from '../workflow-contracts.ts';

const ECR_SCHEMA_SAID = 'EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw';

export interface CreateEcrCredentialOptions {
    groupName: string;
    dataDir: string;
    participantSource: string;
    issueePrefix: string;
    environment: TestEnvironmentPreset;
}

export interface EcrCredentialArtifact {
    ecrCredSAID: string;
    ecrCredIssuer: string;
    ecrCredIssuee: string;
}

export interface GrantCoordinationReceipt {
    sender: string;
    recipient: string;
    exnSaid: string;
    innerExchangeSaid: string;
}

export interface CreateEcrCredentialResult {
    artifact: EcrCredentialArtifact;
    observations: CredentialSnapshot[];
    operationEvidence: OperationEvidence[];
    issuanceReceipts: GrantCoordinationReceipt[];
    coordinationReceipts: GrantCoordinationReceipt[];
}

/**
 * Uses QAR1, QAR2, and QAR3 to issue the ECR credential to the person AID.
 */
export async function createEcrCredential(
    options: CreateEcrCredentialOptions
): Promise<CreateEcrCredentialResult> {
    const {
        groupName,
        dataDir,
        participantSource,
        issueePrefix,
        environment,
    } = options;
    const {witnessIds} = resolveEnvironment(environment);
    const [, WIL] = witnessIds;

    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(participantSource);
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

    const qviAids = await Promise.all([
        QAR1Client.identifiers().get(groupName),
        QAR2Client.identifiers().get(groupName),
        QAR3Client.identifiers().get(groupName),
    ]);
    const qviAID = qviAids[0];
    const qviPrefixConverged = qviAids.every(
        (group) => group.prefix === qviAID.prefix
    );
    if (qviPrefixConverged === false) {
        throw new Error('QARs disagree on the QVI prefix');
    }

    // Reuse an existing ECR credential only while all three QARs observe the
    // same active issuance event.
    let ecrCredByQAR1 = await getIssuedCredential(
        QAR1Client,
        qviAID.prefix,
        issueePrefix,
        ECR_SCHEMA_SAID
    );
    let ecrCredbyQAR2 = await getIssuedCredential(
        QAR2Client,
        qviAID.prefix,
        issueePrefix,
        ECR_SCHEMA_SAID
    );
    let ecrCredbyQAR3 = await getIssuedCredential(
        QAR3Client,
        qviAID.prefix,
        issueePrefix,
        ECR_SCHEMA_SAID
    );

    
    const existingCredentials = [
        ecrCredByQAR1,
        ecrCredbyQAR2,
        ecrCredbyQAR3,
    ];
    const everyQarHasCredential = existingCredentials.every(
        (credential) => credential !== undefined
    );
    const noQarHasCredential = existingCredentials.every(
        (credential) => credential === undefined
    );
    if (everyQarHasCredential) {
        const snapshots = existingCredentials.map(
            (credential, index) =>
                credentialSnapshot(
                    requireCredential(
                        credential,
                        `QAR${index + 1} ECR credential`
                    ),
                    memberPrefixes[index]
                )
        );
        assertIssuedCredentialConvergence(
            snapshots,
            memberPrefixes,
            'ECR credential'
        );
        console.log("ECR credential already exists");
        const result: CreateEcrCredentialResult = {
            artifact: {
                ecrCredSAID: snapshots[0].said,
                ecrCredIssuer: snapshots[0].issuer,
                ecrCredIssuee: snapshots[0].issuee,
            },
            observations:
                canonicalObserverSnapshots(snapshots),
            operationEvidence: [],
            issuanceReceipts: [],
            coordinationReceipts: [],
        };
        assertIssuanceContract(
            result,
            memberPrefixes,
            {
                issuer: qviAID.prefix,
                schema: ECR_SCHEMA_SAID,
                issuee: issueePrefix,
            },
            'ECR credential'
        );
        return result;
    }

    const onlySomeQarsHaveCredential = noQarHasCredential === false;
    if (onlySomeQarsHaveCredential) {
        throw new Error(
            'ECR credential exists on only a subset of QARs'
        );
    }
    console.log("ECR Credential does not exist, creating and granting");

    const registries = await QAR1Client.registries().list(groupName);
    const registryCountIsInvalid = registries.length !== 1;
    if (registryCountIsInvalid) {
        throw new Error(
            `Expected one QVI registry; found ${registries.length}`
        );
    }
    const qviRegistry = registries[0];

    const ecrData = JSON.parse(
        await fs.promises.readFile(
            `${dataDir}/temp-data/ecr-data.json`,
            'utf-8'
        )
    );
    const ecrAuthEdge = JSON.parse(
        await fs.promises.readFile(
            `${dataDir}/temp-data/ecr-auth-edge.json`,
            'utf-8'
        )
    );
    const ecrRules = JSON.parse(
        await fs.promises.readFile(
            `${dataDir}/rules/ecr-rules.json`,
            'utf-8'
        )
    );

    const kargsSub: CredentialSubject = {
        i: issueePrefix,
        dt: createTimestamp(),
        u: new Salter({}).qb64,
        ...ecrData,
    };
    const kargsIss: CredentialData = {
        u: new Salter({}).qb64,
        i: qviAID.prefix,
        ri: qviRegistry.regk,
        s: ECR_SCHEMA_SAID,
        a: kargsSub,
        e: ecrAuthEdge,
        r: ecrRules,
    };
    const IssOp1 = await issueCredentialMultisig(
        QAR1Client,
        QAR1Id,
        [QAR2Id, QAR3Id],
        qviAID.name,
        kargsIss,
        {isInitiator: true}
    );
    const IssOp2 = await issueCredentialMultisig(
        QAR2Client,
        QAR2Id,
        [QAR1Id, QAR3Id],
        qviAID.name,
        kargsIss,
        {coordinator: QAR1Id.prefix}
    );
    const IssOp3 = await issueCredentialMultisig(
        QAR3Client,
        QAR3Id,
        [QAR1Id, QAR2Id],
        qviAID.name,
        kargsIss,
        {coordinator: QAR1Id.prefix}
    );

    const operationEvidence = await completeCoordinatedOperations([
        {client: QAR1Client, result: IssOp1},
        {client: QAR2Client, result: IssOp2},
        {client: QAR3Client, result: IssOp3},
    ]);

    ecrCredByQAR1 = await getIssuedCredential(
        QAR1Client,
        qviAID.prefix,
        issueePrefix,
        ECR_SCHEMA_SAID
    );
    ecrCredbyQAR2 = await getIssuedCredential(
        QAR2Client,
        qviAID.prefix,
        issueePrefix,
        ECR_SCHEMA_SAID
    );
    ecrCredbyQAR3 = await getIssuedCredential(
        QAR3Client,
        qviAID.prefix,
        issueePrefix,
        ECR_SCHEMA_SAID
    );

    const issuedCredentials = [
        requireCredential(ecrCredByQAR1, 'QAR1 ECR credential'),
        requireCredential(ecrCredbyQAR2, 'QAR2 ECR credential'),
        requireCredential(ecrCredbyQAR3, 'QAR3 ECR credential'),
    ];
    const issuedSnapshots = issuedCredentials.map(
        (credential, index) =>
            credentialSnapshot(
                credential,
                memberPrefixes[index]
            )
    );
    assertIssuedCredentialConvergence(
        issuedSnapshots,
        memberPrefixes,
        'ECR credential'
    );

    const grantTime = createTimestamp();
    console.log("IPEX Granting ECR credential to Person...");
    const grant1 = await grantMultisig(
        QAR1Client,
        QAR1Id,
        [QAR2Id, QAR3Id],
        qviAids[0],
        issueePrefix,
        issuedCredentials[0],
        grantTime,
        {isInitiator: true}
    );
    const grant2 = await grantMultisig(
        QAR2Client,
        QAR2Id,
        [QAR1Id, QAR3Id],
        qviAids[1],
        issueePrefix,
        issuedCredentials[1],
        grantTime,
        {coordinator: QAR1Id.prefix}
    );
    const grant3 = await grantMultisig(
        QAR3Client,
        QAR3Id,
        [QAR1Id, QAR2Id],
        qviAids[2],
        issueePrefix,
        issuedCredentials[2],
        grantTime,
        {coordinator: QAR1Id.prefix}
    );
    await Promise.all([
        completeMultisigIpex(QAR1Client, grant1),
        completeMultisigIpex(QAR2Client, grant2),
        completeMultisigIpex(QAR3Client, grant3),
    ]);

    const result: CreateEcrCredentialResult = {
        artifact: {
            ecrCredSAID: issuedSnapshots[0].said,
            ecrCredIssuer: issuedSnapshots[0].issuer,
            ecrCredIssuee: issuedSnapshots[0].issuee,
        },
        observations: canonicalObserverSnapshots(issuedSnapshots),
        operationEvidence:
            canonicalOperationEvidence(operationEvidence),
        issuanceReceipts: [
            ...IssOp1.wrapperReceipts.map((receipt) => ({
                sender: QAR1Id.prefix,
                ...receipt,
                innerExchangeSaid: issuedSnapshots[0].currentTelDigest,
            })),
            ...IssOp2.wrapperReceipts.map((receipt) => ({
                sender: QAR2Id.prefix,
                ...receipt,
                innerExchangeSaid: issuedSnapshots[1].currentTelDigest,
            })),
            ...IssOp3.wrapperReceipts.map((receipt) => ({
                sender: QAR3Id.prefix,
                ...receipt,
                innerExchangeSaid: issuedSnapshots[2].currentTelDigest,
            })),
        ].sort((left, right) =>
            `${left.sender}\u0000${left.recipient}`.localeCompare(
                `${right.sender}\u0000${right.recipient}`
            )
        ),
        coordinationReceipts: [
            ...grant1.wrapperReceipts.map((receipt) => ({
                sender: QAR1Id.prefix,
                ...receipt,
                innerExchangeSaid: grant1.innerExchangeSaid,
            })),
            ...grant2.wrapperReceipts.map((receipt) => ({
                sender: QAR2Id.prefix,
                ...receipt,
                innerExchangeSaid: grant2.innerExchangeSaid,
            })),
            ...grant3.wrapperReceipts.map((receipt) => ({
                sender: QAR3Id.prefix,
                ...receipt,
                innerExchangeSaid: grant3.innerExchangeSaid,
            })),
        ].sort((left, right) =>
            `${left.sender}\u0000${left.recipient}`.localeCompare(
                `${right.sender}\u0000${right.recipient}`
            )
        ),
    };
    assertIssuanceContract(
        result,
        memberPrefixes,
        {
            issuer: qviAID.prefix,
            schema: ECR_SCHEMA_SAID,
            issuee: issueePrefix,
        },
        'ECR credential'
    );
    return result;
}

function parseEcrCredentialArguments(
    argv: string[]
): CreateEcrCredentialOptions & {artifactDir: string} {
    const parsed = parseNamedOrPositionalArguments(
        argv,
        [
            'config',
            'group-name',
            'data-dir',
            'issuee-prefix',
            'artifact-dir',
        ],
        [
            'environment',
            'group-name',
            'data-dir',
            'participant-source',
            'issuee-prefix',
            'artifact-dir',
        ]
    );
    requireNamedArguments(parsed, [
        'group-name',
        'data-dir',
        'issuee-prefix',
        'artifact-dir',
    ]);
    const invocation = participantInvocationFromArguments(parsed);
    return {
        groupName: parsed['group-name'],
        dataDir: parsed['data-dir'],
        participantSource: invocation.participantSource,
        issueePrefix: parsed['issuee-prefix'],
        artifactDir: parsed['artifact-dir'],
        environment: invocation.environment,
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const options = parseEcrCredentialArguments(
            process.argv.slice(2)
        );
        const result = await createEcrCredential(options);
        await fs.promises.writeFile(
            `${options.artifactDir}/ecr-cred-info.json`,
            JSON.stringify(result.artifact)
        );
        return {
            status: 'converged',
            credential: result.artifact,
            observations: result.observations,
            operationEvidence: result.operationEvidence,
            issuanceReceipts: result.issuanceReceipts,
            coordinationReceipts: result.coordinationReceipts,
        };
    });
}
