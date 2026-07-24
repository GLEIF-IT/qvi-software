import type {Operation, SignifyClient} from 'signify-ts';

import {
    consumeNotification,
    consumeNotificationReference,
    type MatchedNotification,
    type NotificationReference,
} from './notifications.ts';
import {waitOperation} from './operations.ts';

export interface CoordinatedOperation {
    operation: Operation | string;
    coordination: MatchedNotification[];
}

export interface PersistedCoordinatedOperation {
    operationName: string;
    notificationIds: string[];
}

/**
 * Waits for every member operation before consuming any coordination notice.
 *
 * Notification consumption belongs here because it is part of the multisig
 * protocol lifecycle: followers must keep the request available until their
 * local operation succeeds.
 */
export async function completeCoordinatedOperations(
    members: Array<{
        client: SignifyClient;
        result: CoordinatedOperation;
    }>
): Promise<void> {
    await Promise.all(
        members.map(({client, result}) =>
            waitOperation(client, result.operation)
        )
    );

    for (const {client, result} of members) {
        for (const notification of result.coordination) {
            await consumeNotification(client, notification);
        }
    }
}

/**
 * Completes operations restored after an external delegation approval.
 */
export async function completePersistedCoordinatedOperations(
    members: Array<{
        client: SignifyClient;
        result: PersistedCoordinatedOperation;
    }>
): Promise<void> {
    await Promise.all(
        members.map(({client, result}) =>
            waitOperation(client, result.operationName)
        )
    );

    for (const {client, result} of members) {
        if (result.notificationIds.length === 0) {
            continue;
        }
        const reference: NotificationReference = {
            notificationIds: result.notificationIds,
        };
        await consumeNotificationReference(client, reference);
    }
}
