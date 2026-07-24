import type {
    Dict,
    HabState,
    Serder,
    SignifyClient,
} from 'signify-ts';

export interface ExchangeReceipt {
    recipient: string;
    exnSaid: string;
}

export interface CoordinatedExchangeReceipt extends ExchangeReceipt {
    innerExchangeSaid: string;
}

export interface SendExchangeOptions {
    name: string;
    topic: string;
    sender: HabState;
    route: string;
    payload: Dict<unknown>;
    embeds: Dict<unknown>;
    recipients: string[];
}

interface ExchangeApi {
    createExchangeMessage(
        sender: HabState,
        route: string,
        payload: Dict<unknown>,
        embeds: Dict<unknown>,
        recipient: string
    ): Promise<[Serder, string[], string]>;
    sendFromEvents(
        name: string,
        topic: string,
        exn: Serder,
        signatures: string[],
        attachment: string,
        recipients: string[]
    ): Promise<unknown>;
}

export interface ExchangeClient {
    exchanges(): ExchangeApi;
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
    client: ExchangeClient | SignifyClient,
    options: SendExchangeOptions
): Promise<ExchangeReceipt[]> {
    const uniqueRecipients = [...new Set(options.recipients)];
    const hasRecipients = uniqueRecipients.length > 0;
    if (hasRecipients === false) {
        throw new Error(
            `Cannot send ${options.route}: recipient list is empty`
        );
    }

    const exchangeApi = client.exchanges();
    const receipts: ExchangeReceipt[] = [];

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

            receipts.push({
                recipient,
                exnSaid: exn.said,
            });
        } catch (error: unknown) {
            const reason =
                error instanceof Error ? error.message : String(error);
            throw new Error(
                `Failed to send ${options.route} exchange to ${recipient}: ${reason}`,
                {cause: error}
            );
        }
    }

    return receipts;
}
