import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    CompletedOperation,
    Operation,
} from 'signify-ts';

import {completeMultisigOperations} from '../src/multisig-coordinator.ts';
import {testSignifyClient} from './test-signify-client.ts';

interface MemberOptions {
    notificationCount?: number;
    onMark?: (id: string) => Promise<void>;
}

function member(
    name: string,
    outcome: 'success' | 'failure',
    trace: string[],
    options: MemberOptions = {}
) {
    const operation = {
        name: `group.${name}`,
        done: false,
    } as Operation;
    const client = testSignifyClient({
        operations: () => ({
            get: async () => operation,
            wait: async (): Promise<CompletedOperation> => {
                trace.push(`complete:${name}`);
                if (outcome === 'failure') {
                    throw new Error(`${name} failed`);
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
    });
    return {
        client,
        result: {
            operation,
            notificationIds: Array.from(
                {length: options.notificationCount ?? 1},
                (_, index) => `N${name}-${index}`
            ),
        },
    };
}

describe('multisig operation completion', () => {
    it('consumes notifications after every operation succeeds', async () => {
        const trace: string[] = [];
        await completeMultisigOperations([
            member('qar1', 'success', trace),
            member('qar2', 'success', trace),
            member('qar3', 'success', trace),
        ]);
        const firstNotification = trace.findIndex((entry) =>
            entry.startsWith('mark:')
        );
        assert.equal(firstNotification, 3);
    });

    it('retains every notification when one operation fails', async () => {
        const trace: string[] = [];
        await assert.rejects(
            completeMultisigOperations([
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

    it('cleans member stores serially', async () => {
        const trace: string[] = [];
        let releaseFirstMark = () => {};
        let reportFirstMark = () => {};
        const firstMarkMayFinish = new Promise<void>((resolve) => {
            releaseFirstMark = resolve;
        });
        const firstMarkStarted = new Promise<void>((resolve) => {
            reportFirstMark = resolve;
        });
        const completion = completeMultisigOperations([
            member('qar1', 'success', trace, {
                onMark: async () => {
                    reportFirstMark();
                    await firstMarkMayFinish;
                },
            }),
            member('qar2', 'success', trace),
        ]);

        await firstMarkStarted;
        assert.equal(
            trace.some((entry) => entry === 'mark:Nqar2-0'),
            false
        );
        releaseFirstMark();
        await completion;
        assert.ok(
            trace.indexOf('delete:Nqar1-0') <
                trace.indexOf('mark:Nqar2-0')
        );
    });

    it('marks every member notification before deleting any', async () => {
        const trace: string[] = [];
        await completeMultisigOperations([
            member('qar1', 'success', trace, {notificationCount: 2}),
        ]);

        assert.deepEqual(trace.slice(1), [
            'mark:Nqar1-0',
            'mark:Nqar1-1',
            'delete:Nqar1-0',
            'delete:Nqar1-1',
        ]);
    });
});
