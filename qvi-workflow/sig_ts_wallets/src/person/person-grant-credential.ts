import {Serder} from 'signify-ts';

import {
    assertExpectedCredential,
    credentialSnapshot,
    selectCredential,
} from '../credential-state.ts';
import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
} from '../cli.ts';
import {createTimestamp} from '../create-aid.ts';
import {getOrCreateClient} from '../keystore-creation.ts';
import {
    requireOperationResponse,
    waitOperation,
} from '../operations.ts';

export interface PersonPresentationOptions {
    config: ParticipantConfig;
    credentialSaid: string;
    expectedIssuer: string;
    expectedSchema: string;
    expectedIssuee: string;
    recipientPrefix: string;
}

export async function presentPersonCredential(
    options: PersonPresentationOptions
) {
    const config = options.config;
    const person = config.participants.person;
    const client = await getOrCreateClient(
        person.salt,
        config.environment,
        person.keriaHost
    );
    const personAid = await client
        .identifiers()
        .get(person.name);
    const expected = {
        said: options.credentialSaid,
        issuer: options.expectedIssuer,
        schema: options.expectedSchema,
        issuee: options.expectedIssuee,
    };
    const credential = await selectCredential(client, expected);
    const snapshot = credentialSnapshot(
        credential,
        personAid.prefix
    );
    assertExpectedCredential(snapshot, expected);
    const credentialIsActive = snapshot.statusSequence === '0';
    if (credentialIsActive === false) {
        throw new Error(
            `Person credential ${snapshot.said} is not active`
        );
    }
    const personIsIssuee =
        personAid.prefix === options.expectedIssuee;
    if (personIsIssuee === false) {
        throw new Error(
            `Person AID ${personAid.prefix} does not match credential issuee ${options.expectedIssuee}`
        );
    }

    const [grant, signatures, attachment] =
        await client.ipex().grant({
            senderName: person.name,
            acdc: new Serder(credential.sad),
            anc: new Serder(credential.anc),
            iss: new Serder(credential.iss),
            ancAttachment: credential.ancatc,
            recipient: options.recipientPrefix,
            datetime: createTimestamp(),
        });
    const operation = await client
        .ipex()
        .submitGrant(
            person.name,
            grant,
            signatures,
            attachment,
            [options.recipientPrefix]
        );
    const completed = await waitOperation(client, operation);
    requireOperationResponse(
        completed,
        (value): value is {said: string} =>
            typeof value === 'object' &&
            value !== null &&
            typeof (value as {said?: unknown}).said === 'string',
        'Person IPEX grant'
    );

    return {
        status: 'presented' as const,
        credentialSaid: snapshot.said,
        recipientPrefix: options.recipientPrefix,
    };
}

function parsePresentationArguments(
    argv: string[]
): PersonPresentationOptions {
    const args = parseNamedArguments(argv, [
        'config',
        'environment',
        'participant-source',
        'credential-said',
        'expected-issuer',
        'expected-schema',
        'expected-issuee',
        'recipient-prefix',
    ]);
    requireNamedArguments(args, [
        'credential-said',
        'expected-issuer',
        'expected-schema',
        'expected-issuee',
        'recipient-prefix',
    ]);
    return {
        config: participantConfigFromArguments(args),
        credentialSaid: args['credential-said'],
        expectedIssuer: args['expected-issuer'],
        expectedSchema: args['expected-schema'],
        expectedIssuee: args['expected-issuee'],
        recipientPrefix: args['recipient-prefix'],
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const options = parsePresentationArguments(
            process.argv.slice(2)
        );
        return presentPersonCredential(options);
    });
}
