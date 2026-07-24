import {Serder, type HabState, type SignifyClient} from 'signify-ts';

import {createTimestamp} from '../create-aid.ts';
import {getCredential} from '../credential-state.ts';
import {
    requireOperationResponse,
    waitOperation,
} from '../operations.ts';

export interface PersonPresentationOptions {
    client: SignifyClient;
    personAid: HabState;
    credentialSaid: string;
    recipientPrefix: string;
}

/** Present one credential directly from a concrete person wallet. */
export async function presentPersonCredential(
    options: PersonPresentationOptions
) {
    const client = options.client;
    const credential = await getCredential(
        client,
        options.credentialSaid
    );
    const [grant, signatures, attachment] =
        await client.ipex().grant({
            senderName: options.personAid.name,
            acdc: new Serder(credential.sad),
            anc: new Serder(credential.anc),
            iss: new Serder(credential.iss),
            ancAttachment: credential.ancatc,
            recipient: options.recipientPrefix,
            datetime: createTimestamp(),
        });
    const operation = await client.ipex().submitGrant(
        options.personAid.name,
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
