import {Serder} from 'signify-ts';

import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
} from '../cli.ts';
import {createTimestamp} from '../create-aid.ts';
import {getCredential} from '../credential-state.ts';
import {getOrCreateClient} from '../keystore-creation.ts';
import {
    requireOperationResponse,
    waitOperation,
} from '../operations.ts';

export interface PersonPresentationOptions {
    config: ParticipantConfig;
    credentialSaid: string;
    recipientPrefix: string;
}

export async function presentPersonCredential(
    options: PersonPresentationOptions
) {
    const person = options.config.participants.person;
    const client = await getOrCreateClient(
        person.salt,
        options.config.environment,
        person.keriaHost
    );
    const credential = await getCredential(
        client,
        options.credentialSaid
    );
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
    const operation = await client.ipex().submitGrant(
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
        credentialSaid: options.credentialSaid,
        recipientPrefix: options.recipientPrefix,
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const args = parseNamedArguments(process.argv.slice(2), [
            'config',
            'environment',
            'participant-source',
            'credential-said',
            'recipient-prefix',
        ]);
        requireNamedArguments(args, [
            'credential-said',
            'recipient-prefix',
        ]);
        return presentPersonCredential({
            config: participantConfigFromArguments(args),
            credentialSaid: args['credential-said'],
            recipientPrefix: args['recipient-prefix'],
        });
    });
}
