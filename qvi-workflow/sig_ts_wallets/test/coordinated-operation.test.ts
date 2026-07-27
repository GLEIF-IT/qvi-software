import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    CompletedOperation,
    ExchangeResourceV1,
    Operation,
    SignifyClient,
} from 'signify-ts';

import {completeMultisigOps} from '../src/coordinated-operation.ts';
import type {
    MatchedNotification,
    Notification,
} from '../src/notifications.ts';

function member(
    name: string,
    outcome: 'success' | 'failure',
    trace: string[],
    options: {
        notificationCount?: number;
        onMark?: (id: string) => Promise<void>;
    } = {}
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
    const coordination = Array.from(
        {length: options.notificationCount ?? 1},
        (_, index): MatchedNotification => {
            const deliveryNote = {
                ...note,
                i: `${note.i}-${index}`,
            };
            return {
                note: deliveryNote,
                deliveryNotes: [deliveryNote],
                exchangeSaid: `E${name}-${index}`,
                exchange: {
                    exn: {d: `E${name}-${index}`},
                } as ExchangeResourceV1,
            };
        }
    );
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
                await options.onMark?.(id);
                return id;
            },
            delete: async (id: string) => {
                trace.push(`delete:${id}`);
            },
        }),
    } as unknown as SignifyClient;
    return {
        client,
        result: {operation, coordination},
    };
}

describe('coordinated operation completion', () => {
    it('consumes notices after every operation succeeds', async () => {
        const trace: string[] = [];
        await completeMultisigOps([
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
            completeMultisigOps([
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

    it('cleans independent member stores concurrently', async () => {
        const trace: string[] = [];
        let marksStarted = 0;
        let releaseMarks = () => {};
        let reportBothStarted = () => {};
        const marksMayFinish = new Promise<void>((resolve) => {
            releaseMarks = resolve;
        });
        const bothMarksStarted = new Promise<void>((resolve) => {
            reportBothStarted = resolve;
        });
        const onMark = async () => {
            marksStarted += 1;
            if (marksStarted === 2) {
                reportBothStarted();
            }
            await marksMayFinish;
        };

        const completion = completeMultisigOps([
            member('qar1', 'success', trace, {onMark}),
            member('qar2', 'success', trace, {onMark}),
        ]);
        await Promise.race([
            bothMarksStarted,
            new Promise((_, reject) =>
                setTimeout(
                    () => reject(new Error('member cleanup was serial')),
                    250
                )
            ),
        ]);

        assert.equal(marksStarted, 2);
        releaseMarks();
        await completion;
    });

    it('keeps notices serial within one member store', async () => {
        const trace: string[] = [];
        let marksStarted = 0;
        let releaseFirstMark = () => {};
        let reportFirstMark = () => {};
        const firstMarkMayFinish = new Promise<void>((resolve) => {
            releaseFirstMark = resolve;
        });
        const firstMarkStarted = new Promise<void>((resolve) => {
            reportFirstMark = resolve;
        });
        const onMark = async () => {
            marksStarted += 1;
            if (marksStarted === 1) {
                reportFirstMark();
                await firstMarkMayFinish;
            }
        };

        const completion = completeMultisigOps([
            member('qar1', 'success', trace, {
                notificationCount: 2,
                onMark,
            }),
        ]);
        await firstMarkStarted;
        await new Promise((resolve) => setTimeout(resolve, 20));

        assert.equal(marksStarted, 1);
        releaseFirstMark();
        await completion;
        assert.equal(marksStarted, 2);
    });
});
