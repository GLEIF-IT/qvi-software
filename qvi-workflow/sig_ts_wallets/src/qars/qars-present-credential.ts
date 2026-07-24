import {
    assertCredentialConvergence,
    assertExpectedCredential,
    credentialSnapshot,
    selectCredential,
} from '../credential-state.ts';
import {
    isMainModule,
    parseNamedArguments,
    readParticipantConfig,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {createTimestamp} from '../create-aid.ts';
import {
    completeMultisigIpex,
    grantMultisig,
} from '../credentials.ts';
import {getOrCreateClient} from '../keystore-creation.ts';
import {
    assertGroupStateConvergence,
    readGroupObservation,
} from '../group-state.ts';

export interface PresentCredentialOptions {
    configPath: string;
    groupName: string;
    credentialSaid: string;
    expectedIssuer: string;
    expectedSchema: string;
    expectedIssuee: string;
    recipientPrefix: string;
    expectedStatus: 'active' | 'revoked';
}

export async function presentCredential(
    options: PresentCredentialOptions
) {
    const config = readParticipantConfig(options.configPath);
    const participants = [
        config.participants.qar1,
        config.participants.qar2,
        config.participants.qar3,
    ];
    const clients = await Promise.all(
        participants.map((participant) =>
            getOrCreateClient(
                participant.salt,
                config.environment,
                participant.keriaHost
            )
        )
    );
    const memberAids = await Promise.all(
        participants.map((participant, index) =>
            clients[index]
                .identifiers()
                .get(participant.name)
        )
    );
    const memberPrefixes = memberAids.map(
        (member) => member.prefix
    );
    const groupObservations = await Promise.all(
        clients.map((client, index) =>
            readGroupObservation(
                client,
                memberPrefixes[index],
                options.groupName,
                memberPrefixes
            )
        )
    );
    assertGroupStateConvergence(
        groupObservations,
        memberPrefixes
    );
    const groupAids = groupObservations.map(
        (observation) => observation.group
    );

    const expected = {
        said: options.credentialSaid,
        issuer: options.expectedIssuer,
        schema: options.expectedSchema,
        issuee: options.expectedIssuee,
    };
    const credentials = await Promise.all(
        clients.map((client) =>
            selectCredential(client, expected)
        )
    );
    const snapshots = credentials.map((credential, index) =>
        credentialSnapshot(
            credential,
            memberPrefixes[index]
        )
    );
    snapshots.forEach((snapshot) =>
        assertExpectedCredential(snapshot, expected)
    );
    assertCredentialConvergence(snapshots, memberPrefixes);
    const expectedSequence =
        options.expectedStatus === 'active' ? '0' : '1';
    const credentialStatusMatches = snapshots.every(
        (snapshot) =>
            snapshot.statusSequence === expectedSequence
    );
    if (credentialStatusMatches === false) {
        throw new Error(
            `Credential ${options.credentialSaid} is not ${options.expectedStatus} on every QAR`
        );
    }

    const timestamp = createTimestamp();
    const grants = [];
    for (let index = 0; index < clients.length; index++) {
        const otherMembers = memberAids.filter(
            (_, memberIndex) => memberIndex !== index
        );
        const participantIsInitiator = index === 0;
        const coordinationOptions = participantIsInitiator
            ? {isInitiator: true}
            : {coordinator: memberAids[0].prefix};
        grants.push(
            await grantMultisig(
                clients[index],
                memberAids[index],
                otherMembers,
                groupAids[index],
                options.recipientPrefix,
                credentials[index],
                timestamp,
                coordinationOptions
            )
        );
    }
    await Promise.all(
        grants.map((grant, index) =>
            completeMultisigIpex(clients[index], grant)
        )
    );

    return {
        status: 'presented' as const,
        credential: snapshots[0],
        recipientPrefix: options.recipientPrefix,
        credentialStatus: options.expectedStatus,
        grantExchangeSaid: grants[0].innerExchangeSaid,
    };
}

function parsePresentationArguments(
    argv: string[]
): PresentCredentialOptions {
    const args = parseNamedArguments(argv, [
        'config',
        'group-name',
        'credential-said',
        'expected-issuer',
        'expected-schema',
        'expected-issuee',
        'recipient-prefix',
        'expected-status',
    ]);
    requireNamedArguments(args, [
        'config',
        'group-name',
        'credential-said',
        'expected-issuer',
        'expected-schema',
        'expected-issuee',
        'recipient-prefix',
        'expected-status',
    ]);
    const expectedStatus = args['expected-status'];
    const statusIsInvalid =
        expectedStatus !== 'active' &&
        expectedStatus !== 'revoked';
    if (statusIsInvalid) {
        throw new Error(
            '--expected-status must be active or revoked'
        );
    }
    return {
        configPath: args.config,
        groupName: args['group-name'],
        credentialSaid: args['credential-said'],
        expectedIssuer: args['expected-issuer'],
        expectedSchema: args['expected-schema'],
        expectedIssuee: args['expected-issuee'],
        recipientPrefix: args['recipient-prefix'],
        expectedStatus,
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const options = parsePresentationArguments(
            process.argv.slice(2)
        );
        return presentCredential(options);
    });
}
