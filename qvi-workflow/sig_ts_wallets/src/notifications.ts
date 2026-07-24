import {
    assertIpexGrant,
    assertMultisigIss,
    assertMultisigRev,
    IPEX_GRANT_ROUTE,
    MULTISIG_ISS_ROUTE,
    MULTISIG_REV_ROUTE,
    ExchangeResourceV1,
    SignifyClient,
} from 'signify-ts';

import {
    coordinatedEventDigest,
    type CoordinatedEventRoute,
} from './multisig-coordination.ts';
import {waitOperation} from './operations.ts';
import {retry, type RetryOptions} from './retry.ts';

export interface Notification {
    i: string;
    dt: string;
    r: boolean;
    a: {r?: string; d?: string; m?: string};
}

interface NotificationPage {
    start: number;
    end: number;
    total: number;
    notes: Notification[];
}

export interface NotificationExpectation {
    notificationRoute: string;
    exchangeRoute: string;
    sender?: string;
    allowedSenders?: string[];
    recipient?: string;
    groupPrefix?: string;
    payloadFields?: Record<string, string>;
    credentialSaid?: string;
    embeddedDigest?: string;
}

export interface MatchedNotification {
    /**
     * The first delivery record, retained for concise caller diagnostics.
     */
    note: Notification;
    /**
     * Every unread delivery record that names this exact EXN SAID.
     */
    deliveryNotes: Notification[];
    exchangeSaid: string;
    exchange: ExchangeResourceV1;
}

export interface NotificationReference {
    notificationIds: string[];
}

interface NotificationApi {
    list(start?: number, end?: number): Promise<NotificationPage>;
    mark(said: string): Promise<string>;
    delete(said: string): Promise<void>;
}

interface NotificationClient {
    notifications(): NotificationApi;
    exchanges(): {
        get(said: string): Promise<ExchangeResourceV1>;
    };
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

function isExnV1(
    exchange: ExchangeResourceV1
): exchange is ExchangeResourceV1 & {
    exn: ExchangeResourceV1['exn'] & {
        rp: string;
        e: Record<string, unknown>;
    };
} {
    return 'rp' in exchange.exn && 'e' in exchange.exn;
}

function exactCredentialSaid(
    exchange: ExchangeResourceV1,
    payload: Record<string, unknown>
): string | undefined {
    try {
        switch (exchange.exn.r) {
            case MULTISIG_ISS_ROUTE:
                return assertMultisigIss(exchange).exn.e.acdc.d;
            case MULTISIG_REV_ROUTE:
                return assertMultisigRev(exchange).exn.e.rev.i;
            case IPEX_GRANT_ROUTE:
                return assertIpexGrant(exchange).exn.e.acdc.d;
            default:
                return typeof payload.credentialSaid === 'string'
                    ? payload.credentialSaid
                    : typeof payload.said === 'string'
                      ? payload.said
                      : undefined;
        }
    } catch {
        return undefined;
    }
}

function exactEmbeddedDigest(
    exchange: ExchangeResourceV1
): string | undefined {
    try {
        return coordinatedEventDigest(
            exchange,
            exchange.exn.r as CoordinatedEventRoute
        );
    } catch {
        return undefined;
    }
}

function exactRecipient(
    exchange: ExchangeResourceV1,
    payload: Record<string, unknown>
): string | undefined {
    const exchangeIsV1 = isExnV1(exchange);
    if (exchangeIsV1 === false) {
        return undefined;
    }

    const routedRecipient = exchange.exn.rp;
    const routedRecipientIsPresent =
        typeof routedRecipient === 'string' &&
        routedRecipient.length > 0;
    if (routedRecipientIsPresent) {
        return routedRecipient;
    }

    // KERIpy-produced IPEX grants place the recipient in `a.i` while leaving
    // `rp` empty. SignifyTS-produced grants populate both fields. Limit this
    // compatibility normalization to the grant route.
    const isIpexGrant = exchange.exn.r === IPEX_GRANT_ROUTE;
    const payloadRecipient =
        typeof payload.i === 'string' ? payload.i : undefined;
    if (isIpexGrant && payloadRecipient !== undefined) {
        return payloadRecipient;
    }

    return undefined;
}

export async function listAllNotifications(
    client: NotificationClient | SignifyClient,
    pageSize = 25
): Promise<Notification[]> {
    const pageSizeIsInvalid =
        Number.isInteger(pageSize) === false || pageSize < 1;
    if (pageSizeIsInvalid) {
        throw new Error('Notification page size must be a positive integer');
    }

    const notifications: Notification[] = [];
    let start = 0;

    while (true) {
        const page = await client
            .notifications()
            .list(start, start + pageSize - 1);
        notifications.push(...page.notes);

        const pageReachedTotal = notifications.length >= page.total;
        const pageWasEmpty = page.notes.length === 0;
        if (pageReachedTotal || pageWasEmpty) {
            break;
        }
        start += page.notes.length;
    }

    return notifications;
}

export function exchangeMatchesExpectation(
    exchange: ExchangeResourceV1,
    expectation: NotificationExpectation
): boolean {
    const routeMatches = exchange.exn.r === expectation.exchangeRoute;
    if (routeMatches === false) {
        return false;
    }

    const senderMatches =
        expectation.sender === undefined ||
        exchange.exn.i === expectation.sender;
    if (senderMatches === false) {
        return false;
    }

    const allowedSenderMatches =
        expectation.allowedSenders === undefined ||
        expectation.allowedSenders.includes(exchange.exn.i);
    if (allowedSenderMatches === false) {
        return false;
    }

    const requiresV1Fields =
        expectation.recipient !== undefined ||
        expectation.credentialSaid !== undefined ||
        expectation.embeddedDigest !== undefined;
    const exchangeIsV1 = isExnV1(exchange);
    if (requiresV1Fields && exchangeIsV1 === false) {
        return false;
    }

    const payload = isRecord(exchange.exn.a) ? exchange.exn.a : {};
    const recipientMatches =
        expectation.recipient === undefined ||
        exactRecipient(exchange, payload) === expectation.recipient;
    if (recipientMatches === false) {
        return false;
    }

    const groupMatches =
        expectation.groupPrefix === undefined ||
        payload.gid === expectation.groupPrefix;
    if (groupMatches === false) {
        return false;
    }

    const payloadFieldsMatch =
        expectation.payloadFields === undefined ||
        Object.entries(expectation.payloadFields).every(
            ([key, expected]) => payload[key] === expected
        );
    if (payloadFieldsMatch === false) {
        return false;
    }

    const credentialMatches =
        expectation.credentialSaid === undefined ||
        (exchangeIsV1 &&
            exactCredentialSaid(exchange, payload) ===
                expectation.credentialSaid);
    if (credentialMatches === false) {
        return false;
    }

    const embeddedDigestMatches =
        expectation.embeddedDigest === undefined ||
        (exchangeIsV1 &&
            exactEmbeddedDigest(exchange) ===
                expectation.embeddedDigest);

    return embeddedDigestMatches;
}

async function findMatchingNotifications(
    client: NotificationClient | SignifyClient,
    expectation: NotificationExpectation
): Promise<MatchedNotification[]> {
    const notes = await listAllNotifications(client);
    const candidates = notes.filter(
        (note) =>
            note.r === false &&
            note.a.r === expectation.notificationRoute
    );

    // A multisig group member may deliver the same recipient-bound EXN more
    // than once. The EXN SAID identifies the logical exchange, so duplicate
    // notification records for that exact SAID are one candidate. Distinct
    // matching EXN SAIDs remain ambiguous and fail closed below.
    const candidateDeliveries = new Map<string, Notification[]>();
    for (const note of candidates) {
        const exchangeSaid = note.a.d;
        const exchangeSaidIsMissing =
            typeof exchangeSaid !== 'string' ||
            exchangeSaid.length === 0;
        if (exchangeSaidIsMissing) {
            throw new Error(
                `Notification ${note.i} for ${expectation.notificationRoute} has no exchange SAID`
            );
        }
        const existingDeliveries =
            candidateDeliveries.get(exchangeSaid) ?? [];
        existingDeliveries.push(note);
        candidateDeliveries.set(exchangeSaid, existingDeliveries);
    }

    const matches: MatchedNotification[] = [];
    for (const [exchangeSaid, deliveryNotes] of candidateDeliveries) {
        const exchange = await client.exchanges().get(exchangeSaid);
        const fetchedExchangeMatchesSaid =
            exchange.exn.d === exchangeSaid;
        if (fetchedExchangeMatchesSaid === false) {
            throw new Error(
                `Notification exchange ${exchangeSaid} resolved to ${exchange.exn.d}`
            );
        }
        const exchangeMatches = exchangeMatchesExpectation(
            exchange,
            expectation
        );
        if (exchangeMatches) {
            matches.push({
                note: deliveryNotes[0],
                deliveryNotes,
                exchangeSaid,
                exchange,
            });
        }
    }

    return matches;
}

/**
 * Waits for one unread notification correlated to one exact exchange.
 *
 * This function is deliberately read-only. The caller consumes the returned
 * notification only after the dependent protocol action succeeds.
 */
export async function waitForMatchingNotification(
    client: NotificationClient | SignifyClient,
    expectation: NotificationExpectation,
    options: RetryOptions = {}
): Promise<MatchedNotification> {
    const hasCorrelation =
        expectation.sender !== undefined ||
        expectation.allowedSenders !== undefined ||
        expectation.recipient !== undefined ||
        expectation.groupPrefix !== undefined ||
        expectation.payloadFields !== undefined ||
        expectation.credentialSaid !== undefined ||
        expectation.embeddedDigest !== undefined;
    if (hasCorrelation === false) {
        throw new Error(
            `Notification ${expectation.notificationRoute} requires an identity or event correlation field`
        );
    }

    return retry(async () => {
        const matches = await findMatchingNotifications(
            client,
            expectation
        );
        const matchWasNotFound = matches.length === 0;
        if (matchWasNotFound) {
            throw new Error(
                `No correlated notification for ${expectation.notificationRoute}`
            );
        }

        const matchIsAmbiguous = matches.length > 1;
        if (matchIsAmbiguous) {
            throw new Error(
                `Found ${matches.length} correlated notifications for ${expectation.notificationRoute}; expected exactly one`
            );
        }
        return matches[0];
    }, options);
}

export async function consumeNotification(
    client: NotificationClient | SignifyClient,
    matched: MatchedNotification
): Promise<void> {
    await consumeNotificationReference(
        client,
        notificationReference(matched)
    );
}

export function notificationReference(
    matched: MatchedNotification
): NotificationReference {
    const reference = {
        notificationIds: matched.deliveryNotes.map((note) => note.i),
    };
    validatedNotificationIds(reference);
    return reference;
}

function validatedNotificationIds(
    reference: NotificationReference
): string[] {
    const ids = reference.notificationIds;
    const idsAreInvalid =
        Array.isArray(ids) === false ||
        ids.length === 0 ||
        ids.some(
            (id) => typeof id !== 'string' || id.length === 0
        ) ||
        new Set(ids).size !== ids.length;
    if (idsAreInvalid) {
        throw new Error(
            'Coordination notification reference requires unique nonempty IDs'
        );
    }

    return ids;
}

export async function consumeNotificationReference(
    client: NotificationClient | SignifyClient,
    reference: NotificationReference
): Promise<void> {
    const notificationIds = validatedNotificationIds(reference);
    for (const notificationId of notificationIds) {
        await client.notifications().mark(notificationId);
    }
    for (const notificationId of notificationIds) {
        await client.notifications().delete(notificationId);
    }
}

export async function resolveOobi(
    client: SignifyClient,
    oobi: string,
    alias?: string
): Promise<void> {
    const op = await client.oobis().resolve(oobi, alias);
    await waitOperation(client, op);
}
