import type {
    Dict,
    HabState,
    SignifyClient,
} from 'signify-ts';

export interface SendExchangeOptions {
    name: string;
    topic: string;
    sender: HabState;
    route: string;
    payload: Dict<unknown>;
    embeds: Dict<unknown>;
    recipients: string[];
}

/**
 * Creates a recipient-bound EXN for every recipient.
 *
 * SignifyTS 0.4.0's Exchanges.send() returns during its first recipient loop
 * and submits that first recipient's EXN to the full recipient list. Keeping
 * this compatibility adapter local makes every transmitted EXN's `rp` field
 * agree with its sole transport recipient.
 */
export async function sendExchangeToEachRecipient(
    client: SignifyClient,
    options: SendExchangeOptions
): Promise<void> {
    // Compatibility adapter for https://github.com/WebOfTrust/signify-ts/issues/310.
    // Delete this only when the minimum supported *published npm package*
    // passes this module's contract test: Exchanges.send() must build and
    // transmit one recipient-bound EXN per recipient, call transport with only
    // that recipient, and never return after the first recipient.
    const uniqueRecipients = [...new Set(options.recipients)];
    const hasRecipients = uniqueRecipients.length > 0;
    if (hasRecipients === false) {
        throw new Error(
            `Cannot send ${options.route}: recipient list is empty`
        );
    }

    const exchangeApi = client.exchanges();
    // One KERIA agency serializes requests from its Signify controller.
    // Sending these in parallel only makes both requests contend and take
    // longer, so keep each sender's recipient deliveries serial.
    for (const recipient of uniqueRecipients) {
        try {
            const [exn, signatures, attachment] =
                await exchangeApi.createExchangeMessage(
                    options.sender,
                    options.route,
                    options.payload,
                    options.embeds,
                    recipient
                );

            await exchangeApi.sendFromEvents(
                options.name,
                options.topic,
                exn,
                signatures,
                attachment,
                [recipient]
            );

        } catch (error: unknown) {
            const reason =
                error instanceof Error ? error.message : String(error);
            throw new Error(
                `Failed to send ${options.route} exchange to ${recipient}: ${reason}`,
                {cause: error}
            );
        }
    }
}
