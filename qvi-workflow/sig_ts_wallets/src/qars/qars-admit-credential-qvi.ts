import {createTimestamp, parseAidInfo} from "../create-aid";
import {getOrCreateAID, getOrCreateClient} from "../keystore-creation";
import {resolveEnvironment, TestEnvironmentPreset} from "../resolve-env";
import {
    admitMultisig,
    getReceivedCredential,
    requireCredential,
    waitForCredential,
} from "../credentials";
import {
    assertExpectedCredential,
    assertIssuedCredentialConvergence,
    credentialSnapshot,
    type CredentialSnapshot,
} from '../credential-state.ts';
import {
    completeCoordinatedOperationsWithValidation,
} from '../coordinated-operation.ts';
import {
    isMainModule,
    parseNamedOrPositionalArguments,
    participantInvocationFromArguments,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {canonicalObserverSnapshots} from '../workflow-contracts.ts';

function admittedCredentialSnapshots(
    credentials: Array<
        Awaited<ReturnType<typeof getReceivedCredential>>
    >,
    memberPrefixes: string[],
    expected: {
        said: string;
        issuer: string;
        schema?: string;
        issuee: string;
    }
): CredentialSnapshot[] {
    const snapshots = credentials.map((credential, index) =>
        credentialSnapshot(
            requireCredential(
                credential,
                `QAR${index + 1} admitted credential ${expected.said}`
            ),
            memberPrefixes[index]
        )
    );
    const completeExpectation = {
        ...expected,
        schema: expected.schema ?? snapshots[0].schema,
    };
    snapshots.forEach((snapshot) =>
        assertExpectedCredential(snapshot, completeExpectation)
    );
    assertIssuedCredentialConvergence(
        snapshots,
        memberPrefixes,
        `Credential ${expected.said}`
    );
    return canonicalObserverSnapshots(snapshots);
}

/**
 * Uses QAR1, QAR2, and QAR3 to create a delegated multisig AID for the QVI delegated from the AID specified by delpre.
 * 
 * @param aidInfo A comma-separated list of AID information that is further separated by a pipe character for name, salt, and position
 * @param issuerPrefix identifier of the issuer AID who issued the credential to admit by the QARs for the QVI multisig
 * @param witnessIds list of witness IDs for the QVI multisig AID configuration
 * @param credSAID the SAID of the credential to admit
 * @param environment the runtime environment to use for resolving environment variables
 * @returns {Promise<{qviMsOobi: string}>} Object containing the delegatee QVI multisig AID OOBI
 */
export async function admitCredentialQvi(
    multisigName: string,
    aidInfo: string,
    issuerPrefix: string,
    credSAID: string,
    environment: TestEnvironmentPreset,
    expectedSchema?: string,
    expectedIssuee?: string
) {
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

    // Get the QVI multisig AID
    const groupAids = await Promise.all([
        QAR1Client.identifiers().get(multisigName),
        QAR2Client.identifiers().get(multisigName),
        QAR3Client.identifiers().get(multisigName),
    ]);
    const groupPrefixConverged = groupAids.every(
        (group) => group.prefix === groupAids[0].prefix
    );
    if (groupPrefixConverged === false) {
        throw new Error('QARs disagree on the QVI prefix');
    }
    const credentialExpectation = {
        said: credSAID,
        issuer: issuerPrefix,
        schema: expectedSchema,
        issuee: expectedIssuee ?? groupAids[0].prefix,
    };
    // Skip if a QVI AID has already been incepted.
    
    const initiallyObservedCredentials = await Promise.all([
        getReceivedCredential(QAR1Client, credSAID),
        getReceivedCredential(QAR2Client, credSAID),
        getReceivedCredential(QAR3Client, credSAID),
    ]);
    const observedCredentials = initiallyObservedCredentials;
    const everyQarHasCredential = observedCredentials.every(
        (credential) => credential !== undefined
    );
    const noQarHasCredential = observedCredentials.every(
        (credential) => credential === undefined
    );
    const credentialStateIsMixed =
        everyQarHasCredential === false &&
        noQarHasCredential === false;
    if (credentialStateIsMixed) {
        throw new Error(
            `Credential ${credSAID} is admitted on only a subset of QARs`
        );
    }

    if (noQarHasCredential) {
        const admitTime = createTimestamp();
        const admit1 = await admitMultisig(
            QAR1Client,
            QAR1Id,
            [QAR2Id, QAR3Id],
            groupAids[0],
            issuerPrefix,
            credSAID,
            admitTime,
            {isInitiator: true}
        );
        const admit2 = await admitMultisig(
            QAR2Client,
            QAR2Id,
            [QAR1Id, QAR3Id],
            groupAids[1],
            issuerPrefix,
            credSAID,
            admitTime,
            {coordinator: QAR1Id.prefix}
        );
        const admit3 = await admitMultisig(
            QAR3Client,
            QAR3Id,
            [QAR1Id, QAR2Id],
            groupAids[2],
            issuerPrefix,
            credSAID,
            admitTime,
            {coordinator: QAR1Id.prefix}
        );
        const completion =
            await completeCoordinatedOperationsWithValidation(
                [
                    {client: QAR1Client, result: admit1},
                    {client: QAR2Client, result: admit2},
                    {client: QAR3Client, result: admit3},
                ],
                async () => {
                    const admittedCredentials = await Promise.all([
                        waitForCredential(QAR1Client, credSAID),
                        waitForCredential(QAR2Client, credSAID),
                        waitForCredential(QAR3Client, credSAID),
                    ]);
                    return admittedCredentialSnapshots(
                        admittedCredentials,
                        memberPrefixes,
                        credentialExpectation
                    );
                }
            );
        return completion.validatedState;
    }

    return admittedCredentialSnapshots(
        observedCredentials,
        memberPrefixes,
        credentialExpectation
    );
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const parsed = parseNamedOrPositionalArguments(
            process.argv.slice(2),
            [
                'config',
                'group-name',
                'issuer-prefix',
                'credential-said',
                'expected-schema',
                'expected-issuee',
            ],
            [
                'environment',
                'group-name',
                'participant-source',
                'issuer-prefix',
                'credential-said',
            ]
        );
        requireNamedArguments(parsed, [
            'group-name',
            'issuer-prefix',
            'credential-said',
        ]);
        const invocation = participantInvocationFromArguments(parsed);
        const credentials = await admitCredentialQvi(
            parsed['group-name'],
            invocation.participantSource,
            parsed['issuer-prefix'],
            parsed['credential-said'],
            invocation.environment,
            parsed['expected-schema'],
            parsed['expected-issuee']
        );
        return {
            status: 'admitted',
            credentialSaid: parsed['credential-said'],
            observations: credentials,
        };
    });
}
