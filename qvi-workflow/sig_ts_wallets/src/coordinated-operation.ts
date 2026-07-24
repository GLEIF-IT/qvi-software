import type {Operation, SignifyClient} from 'signify-ts';

import {
    consumeNotification,
    consumeNotificationReference,
    type MatchedNotification,
    type NotificationReference,
} from './notifications.ts';
import {waitOperation} from './operations.ts';

export interface MultisigResult {
    operation: Operation | string;
    coordination: MatchedNotification[];
}

export interface SavedMultisigResult {
    operationName: string;
    notificationIds: string[];
}

interface MemberResult {
    client: SignifyClient;
    result: MultisigResult;
}

interface SavedMemberResult {
    client: SignifyClient;
    result: SavedMultisigResult;
}

/**
 * Waits for every member operation before consuming any coordination notice.
 *
 * Notification consumption belongs here because it is part of the multisig
 * protocol lifecycle: followers must keep the request available until their
 * local operation succeeds.
 */
export async function completeMultisigOps(
    members: MemberResult[]
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
export async function completeSavedMultisigOps(
    members: SavedMemberResult[]
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
