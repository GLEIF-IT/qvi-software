import {
    assertCredentialConvergence,
    assertExpectedCredential,
    credentialSnapshot,
    selectCredential,
    type CredentialSnapshot,
} from '../credential-state.ts';
import {
    isMainModule,
    parseNamedArguments,
    readParticipantConfig,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {createTimestamp} from '../create-aid.ts';
import {revokeCredentialMultisig} from '../credentials.ts';
import {getOrCreateClient} from '../keystore-creation.ts';
import {
    assertGroupStateConvergence,
    readGroupObservation,
} from '../group-state.ts';
import {
    type OperationEvidence,
} from '../operations.ts';
import {
    completeCoordinatedOperations,
} from '../coordinated-operation.ts';

export interface RevokeCredentialOptions {
    configPath: string;
    groupName: string;
    credentialSaid: string;
    expectedSchema: string;
    expectedIssuee: string;
}

export interface RevocationResult {
    status: 'already-revoked' | 'revoked';
    credentialSaid: string;
    qviPrefix: string;
    operationNames: string[];
    operationEvidence: OperationEvidence[];
    before: CredentialSnapshot[];
    after: CredentialSnapshot[];
    revocationTelDigest: string;
    revocationTimestamp: string;
    coordinationReceipts: Array<{
        sender: string;
        recipient: string;
        exnSaid: string;
        innerExchangeSaid: string;
    }>;
}

function assertRevocationEvent(
    event: {sad: {[key: string]: unknown}; said: string},
    credentialSaid: string,
    expectedPriorDigest: string
): void {
    const eventTargetsCredential =
        event.sad.i === credentialSaid;
    const eventSequenceIsOne = event.sad.s === '1';
    const priorDigestMatches =
        event.sad.p === expectedPriorDigest;
    if (
        eventTargetsCredential === false ||
        eventSequenceIsOne === false ||
        priorDigestMatches === false
    ) {
        throw new Error(
            `Revocation event ${event.said} does not target ${credentialSaid} at sequence 1 with prior digest ${expectedPriorDigest}`
        );
    }
}

export async function runRevocation(
    options: RevokeCredentialOptions
): Promise<RevocationResult> {
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
    const expectedMemberPrefixes = memberAids.map(
        (member) => member.prefix
    );
    const groupObservations = await Promise.all(
        clients.map((client, index) =>
            readGroupObservation(
                client,
                expectedMemberPrefixes[index],
                options.groupName,
                expectedMemberPrefixes
            )
        )
    );
    const qvi =
        assertGroupStateConvergence(
            groupObservations,
            expectedMemberPrefixes
        );

    const expectedCredential = {
        said: options.credentialSaid,
        issuer: qvi.prefix,
        schema: options.expectedSchema,
        issuee: options.expectedIssuee,
    };
    const credentials = await Promise.all(
        clients.map((client) =>
            selectCredential(client, expectedCredential)
        )
    );
    const before = credentials.map((credential, index) =>
        credentialSnapshot(
            credential,
            expectedMemberPrefixes[index]
        )
    );
    before.forEach((snapshot) =>
        assertExpectedCredential(snapshot, expectedCredential)
    );
    assertCredentialConvergence(
        before,
        expectedMemberPrefixes
    );

    const credentialIsRevokedOnEveryQar = before.every(
        (snapshot) => snapshot.statusSequence === '1'
    );
    if (credentialIsRevokedOnEveryQar) {
        return {
            status: 'already-revoked',
            credentialSaid: options.credentialSaid,
            qviPrefix: qvi.prefix,
            operationNames: [],
            operationEvidence: [],
            before,
            after: before,
            revocationTelDigest: before[0].currentTelDigest,
            revocationTimestamp: credentials[0].status.dt,
            coordinationReceipts: [],
        };
    }

    const credentialIsIssuedOnEveryQar = before.every(
        (snapshot) => snapshot.statusSequence === '0'
    );
    if (credentialIsIssuedOnEveryQar === false) {
        throw new Error(
            `Credential ${options.credentialSaid} must be issued on every QAR before revocation`
        );
    }

    const timestamp = createTimestamp();
    const revocations = [];
    for (let index = 0; index < clients.length; index++) {
        const otherMembers = memberAids.filter(
            (_, memberIndex) => memberIndex !== index
        );
        const participantIsInitiator = index === 0;
        const coordinationOptions = participantIsInitiator
            ? {isInitiator: true}
            : {coordinator: memberAids[0].prefix};
        const revocation = await revokeCredentialMultisig(
            clients[index],
            memberAids[index],
            otherMembers,
            options.groupName,
            options.credentialSaid,
            timestamp,
            coordinationOptions
        );
        assertRevocationEvent(
            revocation.rev,
            options.credentialSaid,
            before[index].currentTelDigest
        );
        revocations.push(revocation);
    }

    const operationEvidence = await completeCoordinatedOperations(
        revocations.map((revocation, index) => ({
            client: clients[index],
            result: revocation,
        }))
    );
    const localRevocationDigests = revocations.map(
        (revocation) => revocation.rev.said
    );
    const localEventsConverged = localRevocationDigests.every(
        (digest) => digest === localRevocationDigests[0]
    );
    if (localEventsConverged === false) {
        throw new Error(
            `QAR revocation events diverged: ${localRevocationDigests.join(',')}`
        );
    }

    const afterCredentials = await Promise.all(
        clients.map((client) =>
            selectCredential(client, expectedCredential)
        )
    );
    const after = afterCredentials.map((credential, index) =>
        credentialSnapshot(
            credential,
            expectedMemberPrefixes[index]
        )
    );
    after.forEach((snapshot) =>
        assertExpectedCredential(snapshot, expectedCredential)
    );
    assertCredentialConvergence(
        after,
        expectedMemberPrefixes
    );
    const revocationConverged = after.every(
        (snapshot) =>
            snapshot.statusSequence === '1' &&
            snapshot.priorTelDigest ===
                before[0].currentTelDigest &&
            snapshot.currentTelDigest ===
                localRevocationDigests[0]
    );
    if (revocationConverged === false) {
        throw new Error(
            `Credential ${options.credentialSaid} revocation did not converge on one linked TEL event`
        );
    }

    return {
        status: 'revoked',
        credentialSaid: options.credentialSaid,
        qviPrefix: qvi.prefix,
        operationNames: operationEvidence.map(
            (operation) => operation.name
        ),
        operationEvidence,
        before,
        after,
        revocationTelDigest: after[0].currentTelDigest,
        revocationTimestamp: timestamp,
        coordinationReceipts: revocations.flatMap(
            (revocation, index) =>
                revocation.wrapperReceipts.map((receipt) => ({
                    sender: memberAids[index].prefix,
                    ...receipt,
                }))
        ),
    };
}

function parseRevocationArguments(
    argv: string[]
): RevokeCredentialOptions {
    const args = parseNamedArguments(argv, [
        'config',
        'group-name',
        'credential-said',
        'expected-schema',
        'expected-issuee',
    ]);
    requireNamedArguments(args, [
        'config',
        'group-name',
        'credential-said',
        'expected-schema',
        'expected-issuee',
    ]);
    return {
        configPath: args.config,
        groupName: args['group-name'],
        credentialSaid: args['credential-said'],
        expectedSchema: args['expected-schema'],
        expectedIssuee: args['expected-issuee'],
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const options = parseRevocationArguments(
            process.argv.slice(2)
        );
        return runRevocation(options);
    });
}
