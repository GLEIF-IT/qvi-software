import {
    IPEX_GRANT_ROUTE,
    MULTISIG_EXN_ROUTE,
    MULTISIG_ICP_ROUTE,
    MULTISIG_ISS_ROUTE,
    MULTISIG_REV_ROUTE,
    MULTISIG_ROT_ROUTE,
    MULTISIG_RPY_ROUTE,
    MULTISIG_VCP_ROUTE,
    type SignifyClient,
} from 'signify-ts';

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
    exchangeRoute: string;
    notificationRoute?: string;
    sender: string;
    recipient?: string;
    groupPrefix?: string;
    payloadFields?: Record<string, string>;
    credentialSaid?: string;
    embeddedDigest?: string;
}

export interface MatchedExchange {
    said: string;
    exchange: Exchange;
    notificationIds: string[];
}

export interface Exchange {
    [key: string]: unknown;
    exn: {
        [key: string]: unknown;
        d: string;
        i: string;
        r: string;
        rp?: unknown;
        a?: unknown;
        e?: unknown;
    };
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

function nestedString(
    value: unknown,
    ...path: string[]
): string | undefined {
    let current = value;
    for (const key of path) {
        if (isRecord(current) === false) {
            return undefined;
        }
        current = current[key];
    }
    return typeof current === 'string' ? current : undefined;
}

function exactCredentialSaid(
    exchange: Exchange,
    payload: Record<string, unknown>
): string | undefined {
    switch (exchange.exn.r) {
        case MULTISIG_ISS_ROUTE:
        case IPEX_GRANT_ROUTE:
            return nestedString(exchange.exn.e, 'acdc', 'd');
        case MULTISIG_REV_ROUTE:
            return nestedString(exchange.exn.e, 'rev', 'i');
        default:
            return typeof payload.credentialSaid === 'string'
                ? payload.credentialSaid
                : typeof payload.said === 'string'
                  ? payload.said
                  : undefined;
    }
}

function exactEmbeddedDigest(
    exchange: Exchange
): string | undefined {
    const embeddedKey = {
        [MULTISIG_ICP_ROUTE]: 'icp',
        [MULTISIG_ROT_ROUTE]: 'rot',
        [MULTISIG_RPY_ROUTE]: 'rpy',
        [MULTISIG_VCP_ROUTE]: 'vcp',
        [MULTISIG_ISS_ROUTE]: 'iss',
        [MULTISIG_REV_ROUTE]: 'rev',
        [MULTISIG_EXN_ROUTE]: 'exn',
    }[exchange.exn.r];
    if (embeddedKey === undefined) {
        return undefined;
    }
    return nestedString(exchange.exn.e, embeddedKey, 'd');
}

function exactRecipient(
    exchange: Exchange,
    payload: Record<string, unknown>
): string | undefined {
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
    client: SignifyClient,
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
        const page: NotificationPage = await client
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
    exchange: Exchange,
    expectation: NotificationExpectation
): boolean {
    const routeMatches = exchange.exn.r === expectation.exchangeRoute;
    if (routeMatches === false) {
        return false;
    }

    const senderMatches = exchange.exn.i === expectation.sender;
    if (senderMatches === false) {
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
        exactCredentialSaid(exchange, payload) ===
            expectation.credentialSaid;
    if (credentialMatches === false) {
        return false;
    }

    const embeddedDigestMatches =
        expectation.embeddedDigest === undefined ||
        exactEmbeddedDigest(exchange) === expectation.embeddedDigest;

    return embeddedDigestMatches;
}

async function findMatchingNotifications(
    client: SignifyClient,
    expectation: NotificationExpectation
): Promise<MatchedExchange[]> {
    const notes = await listAllNotifications(client);
    const notificationRoute =
        expectation.notificationRoute ?? expectation.exchangeRoute;
    const candidates = notes.filter(
        (note) =>
            note.r === false &&
            note.a.r === notificationRoute
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
                `Notification ${note.i} for ${notificationRoute} has no exchange SAID`
            );
        }
        const existingDeliveries =
            candidateDeliveries.get(exchangeSaid) ?? [];
        existingDeliveries.push(note);
        candidateDeliveries.set(exchangeSaid, existingDeliveries);
    }

    const matches: MatchedExchange[] = [];
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
            const notificationIds = deliveryNotes.map((note) => note.i);
            validatedNotificationIds(notificationIds);
            matches.push({
                said: exchangeSaid,
                exchange,
                notificationIds,
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
    client: SignifyClient,
    expectation: NotificationExpectation,
    options: RetryOptions = {}
): Promise<MatchedExchange> {
    const notificationRoute =
        expectation.notificationRoute ?? expectation.exchangeRoute;
    if (expectation.sender.length === 0) {
        throw new Error(
            `Notification ${notificationRoute} requires an exact sender`
        );
    }

    return await retry(async () => {
        const matches = await findMatchingNotifications(
            client,
            expectation
        );
        const matchWasNotFound = matches.length === 0;
        if (matchWasNotFound) {
            throw new Error(
                `No correlated notification for ${notificationRoute}`
            );
        }

        const matchIsAmbiguous = matches.length > 1;
        if (matchIsAmbiguous) {
            throw new Error(
                `Found ${matches.length} correlated notifications for ${notificationRoute}; expected exactly one`
            );
        }
        return matches[0];
    }, {
        minSleep: 32,
        maxSleep: 32,
        ...options,
    });
}

function validatedNotificationIds(
    notificationIds: string[]
): string[] {
    const ids = notificationIds;
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

export async function consumeNotifications(
    client: SignifyClient,
    notificationIds: string[]
): Promise<void> {
    const validatedIds = validatedNotificationIds(notificationIds);
    for (const notificationId of validatedIds) {
        await client.notifications().mark(notificationId);
    }
    for (const notificationId of validatedIds) {
        await client.notifications().delete(notificationId);
    }
}
