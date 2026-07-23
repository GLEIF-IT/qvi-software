import { SignifyClient } from "signify-ts";
import { retry, RetryOptions } from "./retry";
import {waitOperation} from "./operations.ts";

export interface Notification {
    i: string;
    dt: string;
    r: boolean;
    a: { r: string; d?: string; m?: string };
}

/**
 * Wait for a notification, consume it, and return the SAID of its Exchange message.
 *
 * Removing consumed notifications keeps later workflow messages visible in
 * SignifyTS 0.3.0-rc1, whose notification client reads 25 entries by default.
 * @param client SignifyClient representing the Client AID
 * @param route Route of the notification to wait for
 * @returns SAID of the Exchange (exn) message
 */
export async function waitAndRemoveNotification(
    client: SignifyClient,
    route: string,
    options: RetryOptions = {}
): Promise<string> {
    const notes = await waitForNotifications(client, route, options);

    await Promise.all(
        notes.map(async (note) => {
            await markAndRemoveNotification(client, note);
        })
    );

    return notes[notes.length - 1]?.a.d ?? '';
}

export async function waitForNotifications(
    client: SignifyClient,
    route: string,
    options: RetryOptions = {}
): Promise<Notification[]> {
    return retry(async () => {
        const response: { notes: Notification[] } = await client
            .notifications()
            .list();

        const notes = response.notes.filter(
            (note) => note.a.r === route && note.r === false
        );

        const matchingNotificationWasNotFound = notes.length === 0;
        if (matchingNotificationWasNotFound) {
            throw new Error(`No notifications with route ${route}`);
        }

        return notes;
    }, options);
}

/**
 * Mark and remove notification.
 */
export async function markAndRemoveNotification(
    client: SignifyClient,
    note: Notification
): Promise<void> {
    try {
        await client.notifications().mark(note.i);
    } finally {
        await client.notifications().delete(note.i);
    }
}

export async function resolveOobi(
    client: SignifyClient,
    oobi: string,
    alias?: string
) {
    const op = await client.oobis().resolve(oobi, alias);
    await waitOperation(client, op);
}
