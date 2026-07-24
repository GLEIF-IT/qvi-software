import fs from "fs";
import {CredentialData, CredentialSubject} from "signify-ts";
import {createTimestamp, parseAidInfo} from "../create-aid";
import {getOrCreateClient} from "../keystore-creation";
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
} from '../credential-state.ts';
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

const LE_SCHEMA_SAID = 'ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY';

export interface CreateLeCredentialOptions {
    groupName: string;
    dataDir: string;
    participantSource: string;
    issueePrefix: string;
    environment: TestEnvironmentPreset;
}

export interface LeCredentialArtifact {
    leCredSAID: string;
    leCredIssuer: string;
    leCredIssuee: string;
}

export interface CreateLeCredentialResult {
    artifact: LeCredentialArtifact;
    registryId: string;
    telDigest: string;
}

/**
 * Uses all three QARs to issue and grant the Legal Entity credential.
 */
export async function createLeCredential(
    options: CreateLeCredentialOptions
): Promise<CreateLeCredentialResult> {
    const {
        groupName,
        dataDir,
        participantSource,
        issueePrefix,
        environment,
    } = options;

    // Resolve the environment inside the domain action so importing this
    // module never depends on process arguments or runtime configuration.
    resolveEnvironment(environment);

    // get Clients
    const {QAR1, QAR2, QAR3} = parseAidInfo(participantSource);
    const QAR1Client = await getOrCreateClient(QAR1.salt, environment, 1);
    const QAR2Client = await getOrCreateClient(QAR2.salt, environment, 2);
    const QAR3Client = await getOrCreateClient(QAR3.salt, environment, 3);

    // get QVI participant AIDs
    const QAR1Id = await QAR1Client.identifiers().get(QAR1.name);
    const QAR2Id = await QAR2Client.identifiers().get(QAR2.name);
    const QAR3Id = await QAR3Client.identifiers().get(QAR3.name);
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

    // Reuse an existing LE credential only while all three QARs observe the
    // same active issuance event.
    let leCredbyQAR1 = await getIssuedCredential(
        QAR1Client,
        qviAID.prefix,
        issueePrefix,
        LE_SCHEMA_SAID
    );
    let leCredbyQAR2 = await getIssuedCredential(
        QAR2Client,
        qviAID.prefix,
        issueePrefix,
        LE_SCHEMA_SAID
    );
    let leCredbyQAR3 = await getIssuedCredential(
        QAR3Client,
        qviAID.prefix,
        issueePrefix,
        LE_SCHEMA_SAID
    );

    
    const existingCredentials = [
        leCredbyQAR1,
        leCredbyQAR2,
        leCredbyQAR3,
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
                        `QAR${index + 1} LE credential`
                    ),
                    memberPrefixes[index]
                )
        );
        assertIssuedCredentialConvergence(
            snapshots,
            memberPrefixes,
            'LE credential'
        );
        console.log("LE credential already exists");
        return {
            artifact: {
                leCredSAID: snapshots[0].said,
                leCredIssuer: snapshots[0].issuer,
                leCredIssuee: snapshots[0].issuee,
            },
            registryId: snapshots[0].registry,
            telDigest: snapshots[0].currentTelDigest,
        };
    }

    const onlySomeQarsHaveCredential = noQarHasCredential === false;
    if (onlySomeQarsHaveCredential) {
        throw new Error(
            'LE credential exists on only a subset of QARs'
        );
    }
    console.log("LE Credential does not exist, creating and granting");

    const registries = await QAR1Client.registries().list(groupName);
    const registryCountIsInvalid = registries.length !== 1;
    if (registryCountIsInvalid) {
        throw new Error(
            `Expected one QVI registry; found ${registries.length}`
        );
    }
    const qviRegistry = registries[0];

    const leData = JSON.parse(
        await fs.promises.readFile(
            `${dataDir}/temp-data/legal-entity-data.json`,
            'utf-8'
        )
    );
    const leCredentialEdge = JSON.parse(
        await fs.promises.readFile(
            `${dataDir}/temp-data/qvi-edge.json`,
            'utf-8'
        )
    );
    const leRules = JSON.parse(
        await fs.promises.readFile(
            `${dataDir}/rules/rules.json`,
            'utf-8'
        )
    );

    const kargsSub: CredentialSubject = {
        i: issueePrefix,
        dt: createTimestamp(),
        ...leData,
    };
    const kargsIss: CredentialData = {
        i: qviAID.prefix,
        ri: qviRegistry.regk,
        s: LE_SCHEMA_SAID,
        a: kargsSub,
        e: leCredentialEdge,
        r: leRules,
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

    await completeCoordinatedOperations([
        {client: QAR1Client, result: IssOp1},
        {client: QAR2Client, result: IssOp2},
        {client: QAR3Client, result: IssOp3},
    ]);

    leCredbyQAR1 = await getIssuedCredential(
        QAR1Client,
        qviAID.prefix,
        issueePrefix,
        LE_SCHEMA_SAID
    );
    leCredbyQAR2 = await getIssuedCredential(
        QAR2Client,
        qviAID.prefix,
        issueePrefix,
        LE_SCHEMA_SAID
    );
    leCredbyQAR3 = await getIssuedCredential(
        QAR3Client,
        qviAID.prefix,
        issueePrefix,
        LE_SCHEMA_SAID
    );
    const issuedCredentials = [
        requireCredential(leCredbyQAR1, 'QAR1 LE credential'),
        requireCredential(leCredbyQAR2, 'QAR2 LE credential'),
        requireCredential(leCredbyQAR3, 'QAR3 LE credential'),
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
        'LE credential'
    );

    const grantTime = createTimestamp();
    console.log("IPEX Granting LE credential to GIDA (LE)...");
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

    return {
        artifact: {
            leCredSAID: issuedSnapshots[0].said,
            leCredIssuer: issuedSnapshots[0].issuer,
            leCredIssuee: issuedSnapshots[0].issuee,
        },
        registryId: issuedSnapshots[0].registry,
        telDigest: issuedSnapshots[0].currentTelDigest,
    };
}

function parseLeCredentialArguments(
    argv: string[]
): CreateLeCredentialOptions & {artifactDir: string} {
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
        const options = parseLeCredentialArguments(
            process.argv.slice(2)
        );
        const result = await createLeCredential(options);
        await fs.promises.writeFile(
            `${options.artifactDir}/le-cred-info.json`,
            JSON.stringify(result.artifact)
        );
        return {
            status: 'converged',
            credential: result.artifact,
            credentialSaid: result.artifact.leCredSAID,
            registryId: result.registryId,
            telDigest: result.telDigest,
        };
    });
}
