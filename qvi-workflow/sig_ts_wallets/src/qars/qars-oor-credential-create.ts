import fs from "fs";
import {CredentialData, CredentialSubject} from "signify-ts";
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

const OOR_SCHEMA_SAID = 'EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy';

export interface CreateOorCredentialOptions {
    groupName: string;
    dataDir: string;
    participantSource: string;
    issueePrefix: string;
    environment: TestEnvironmentPreset;
}

export interface OorCredentialArtifact {
    oorCredSAID: string;
    oorCredIssuer: string;
    oorCredIssuee: string;
}

export interface CreateOorCredentialResult {
    artifact: OorCredentialArtifact;
    registryId: string;
    telDigest: string;
}

/**
 * Uses QAR1, QAR2, and QAR3 to issue the OOR credential to the person AID.
 */
export async function createOorCredential(
    options: CreateOorCredentialOptions
): Promise<CreateOorCredentialResult> {
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

    // Reuse an existing OOR credential only while all three QARs observe the
    // same active issuance event.
    let oorCredByQAR1 = await getIssuedCredential(
        QAR1Client,
        qviAID.prefix,
        issueePrefix,
        OOR_SCHEMA_SAID
    );
    let oorCredbyQAR2 = await getIssuedCredential(
        QAR2Client,
        qviAID.prefix,
        issueePrefix,
        OOR_SCHEMA_SAID
    );
    let oorCredbyQAR3 = await getIssuedCredential(
        QAR3Client,
        qviAID.prefix,
        issueePrefix,
        OOR_SCHEMA_SAID
    );

    
    const existingCredentials = [
        oorCredByQAR1,
        oorCredbyQAR2,
        oorCredbyQAR3,
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
                        `QAR${index + 1} OOR credential`
                    ),
                    memberPrefixes[index]
                )
        );
        assertIssuedCredentialConvergence(
            snapshots,
            memberPrefixes,
            'OOR credential'
        );
        console.log("OOR credential already exists");
        return {
            artifact: {
                oorCredSAID: snapshots[0].said,
                oorCredIssuer: snapshots[0].issuer,
                oorCredIssuee: snapshots[0].issuee,
            },
            registryId: snapshots[0].registry,
            telDigest: snapshots[0].currentTelDigest,
        };
    }

    const onlySomeQarsHaveCredential = noQarHasCredential === false;
    if (onlySomeQarsHaveCredential) {
        throw new Error(
            'OOR credential exists on only a subset of QARs'
        );
    }
    console.log("OOR Credential does not exist, creating and granting");

    const registries = await QAR1Client.registries().list(groupName);
    const registryCountIsInvalid = registries.length !== 1;
    if (registryCountIsInvalid) {
        throw new Error(
            `Expected one QVI registry; found ${registries.length}`
        );
    }
    const qviRegistry = registries[0];

    const oorData = JSON.parse(
        await fs.promises.readFile(
            `${dataDir}/temp-data/oor-data.json`,
            'utf-8'
        )
    );
    const oorAuthEdge = JSON.parse(
        await fs.promises.readFile(
            `${dataDir}/temp-data/oor-auth-edge.json`,
            'utf-8'
        )
    );
    const oorRules = JSON.parse(
        await fs.promises.readFile(
            `${dataDir}/rules/oor-rules.json`,
            'utf-8'
        )
    );

    const kargsSub: CredentialSubject = {
        i: issueePrefix,
        dt: createTimestamp(),
        ...oorData,
    };
    const kargsIss: CredentialData = {
        i: qviAID.prefix,
        ri: qviRegistry.regk,
        s: OOR_SCHEMA_SAID,
        a: kargsSub,
        e: oorAuthEdge,
        r: oorRules,
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

    oorCredByQAR1 = await getIssuedCredential(
        QAR1Client,
        qviAID.prefix,
        issueePrefix,
        OOR_SCHEMA_SAID
    );
    oorCredbyQAR2 = await getIssuedCredential(
        QAR2Client,
        qviAID.prefix,
        issueePrefix,
        OOR_SCHEMA_SAID
    );
    oorCredbyQAR3 = await getIssuedCredential(
        QAR3Client,
        qviAID.prefix,
        issueePrefix,
        OOR_SCHEMA_SAID
    );
    const issuedCredentials = [
        requireCredential(oorCredByQAR1, 'QAR1 OOR credential'),
        requireCredential(oorCredbyQAR2, 'QAR2 OOR credential'),
        requireCredential(oorCredbyQAR3, 'QAR3 OOR credential'),
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
        'OOR credential'
    );

    const grantTime = createTimestamp();
    console.log("IPEX Granting OOR credential to Person...");
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
            oorCredSAID: issuedSnapshots[0].said,
            oorCredIssuer: issuedSnapshots[0].issuer,
            oorCredIssuee: issuedSnapshots[0].issuee,
        },
        registryId: issuedSnapshots[0].registry,
        telDigest: issuedSnapshots[0].currentTelDigest,
    };
}

function parseOorCredentialArguments(
    argv: string[]
): CreateOorCredentialOptions & {artifactDir: string} {
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
        const options = parseOorCredentialArguments(
            process.argv.slice(2)
        );
        const result = await createOorCredential(options);
        await fs.promises.writeFile(
            `${options.artifactDir}/oor-cred-info.json`,
            JSON.stringify(result.artifact)
        );
        return {
            status: 'converged',
            credential: result.artifact,
            credentialSaid: result.artifact.oorCredSAID,
            registryId: result.registryId,
            telDigest: result.telDigest,
        };
    });
}
