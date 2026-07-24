import {Serder} from 'signify-ts';

import {createTimestamp} from '../create-aid.ts';
import {getCredential} from '../credential-state.ts';
import {
    connectClient,
    type WorkflowConfig,
} from '../client.ts';
import {
    requireOperationResponse,
    waitOperation,
} from '../operations.ts';

export interface PersonPresentationOptions {
    config: WorkflowConfig;
    credentialSaid: string;
    recipientPrefix: string;
}

/** Present one credential directly from the configured person wallet. */
export async function presentPersonCredential(
    options: PersonPresentationOptions
) {
    const person = options.config.participants.person;
    const client = await connectClient(person);
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
