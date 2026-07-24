import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    CompletedOperation,
    ExchangeResourceV1,
    Operation,
    SignifyClient,
} from 'signify-ts';

import {completeCoordinatedOperations} from '../src/coordinated-operation.ts';
import type {
    MatchedNotification,
    Notification,
} from '../src/notifications.ts';

function member(
    name: string,
    outcome: 'success' | 'failure',
    trace: string[]
) {
    const operation = {
        name: `group.${name}`,
        done: false,
    } as Operation;
    const note: Notification = {
        i: `N${name}`,
        dt: '',
        r: false,
        a: {r: '/multisig/rot', d: `E${name}`},
    };
    const notification: MatchedNotification = {
        note,
        deliveryNotes: [note],
        exchangeSaid: `E${name}`,
        exchange: {exn: {d: `E${name}`}} as ExchangeResourceV1,
    };
    const client = {
        operations: () => ({
            wait: async () => {
                trace.push(`complete:${name}`);
                if (outcome === 'failure') {
                    return {
                        name: operation.name,
                        done: true,
                        error: {code: 500, message: `${name} failed`},
                    };
                }
                return {
                    name: operation.name,
                    done: true,
                    response: {},
                } as CompletedOperation;
            },
        }),
        notifications: () => ({
            mark: async (id: string) => {
                trace.push(`mark:${id}`);
                return id;
            },
            delete: async (id: string) => {
                trace.push(`delete:${id}`);
            },
        }),
    } as unknown as SignifyClient;
    return {
        client,
        result: {operation, coordination: [notification]},
    };
}

describe('coordinated operation completion', () => {
    it('consumes notices after every operation succeeds', async () => {
        const trace: string[] = [];
        await completeCoordinatedOperations([
            member('qar1', 'success', trace),
            member('qar2', 'success', trace),
            member('qar3', 'success', trace),
        ]);
        const firstNotice = trace.findIndex((entry) =>
            entry.startsWith('mark:')
        );
        assert.equal(firstNotice, 3);
    });

    it('retains notices when one operation fails', async () => {
        const trace: string[] = [];
        await assert.rejects(
            completeCoordinatedOperations([
                member('qar1', 'success', trace),
                member('qar2', 'failure', trace),
                member('qar3', 'success', trace),
            ]),
            /qar2 failed/
        );
        assert.equal(
            trace.some((entry) => entry.startsWith('mark:')),
            false
        );
    });
});
