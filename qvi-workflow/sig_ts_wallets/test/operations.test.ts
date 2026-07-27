import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    CompletedDoneOperation,
    FailedDoneOperation,
    Operation,
    PendingDoneOperation,
    SignifyClient,
} from 'signify-ts';

import {
    isCompletedOperation,
    isFailedOperation,
    isPendingOperation,
    waitOperation,
} from '../src/operations.ts';

const pending: PendingDoneOperation = {
    name: 'group.EEvent',
    done: false,
};
const completed = {
    name: pending.name,
    done: true,
    response: {d: 'EEvent'},
} as CompletedDoneOperation;
const failed: FailedDoneOperation = {
    name: pending.name,
    done: true,
    error: {
        code: 500,
        message: 'escrow failed',
        details: {member: 'QAR3'},
    },
};

function client(options: {
    get?: (name: string) => Promise<Operation>;
    wait?: (
        operation: Operation,
        options?: {
            signal?: AbortSignal;
            minSleep?: number;
            maxSleep?: number;
            increaseFactor?: number;
        }
    ) => Promise<CompletedDoneOperation>;
}): SignifyClient {
    return {
        operations: () => ({
            get:
                options.get ??
                (async () => {
                    throw new Error('unexpected lookup');
                }),
            wait:
                options.wait ??
                (async () => {
                    throw new Error('unexpected wait');
                }),
        }),
    } as unknown as SignifyClient;
}

describe('operation lifecycle', () => {
    it('narrows pending, completed, and failed variants', () => {
        assert.equal(isPendingOperation(pending), true);
        assert.equal(isCompletedOperation(completed), true);
        assert.equal(isFailedOperation(failed), true);
    });

    it('looks up and waits for a named pending operation', async () => {
        const calls: string[] = [];
        const result = await waitOperation(
            client({
                get: async (name) => {
                    calls.push(`get:${name}`);
                    return pending;
                },
                wait: async (operation, options) => {
                    calls.push(`wait:${operation.name}`);
                    assert.ok(options?.signal);
                    assert.deepEqual(
                        {
                            minSleep: options?.minSleep,
                            maxSleep: options?.maxSleep,
                            increaseFactor: options?.increaseFactor,
                        },
                        {
                            minSleep: 32,
                            maxSleep: 32,
                            increaseFactor: 32,
                        }
                    );
                    return completed;
                },
            }),
            pending.name
        );
        assert.equal(result, completed);
        assert.deepEqual(calls, [
            `get:${pending.name}`,
            `wait:${pending.name}`,
        ]);
    });

    it('returns completed operations without polling', async () => {
        assert.equal(
            await waitOperation(client({}), completed),
            completed
        );
    });

    it('reports failed operation details', async () => {
        await assert.rejects(
            waitOperation(client({}), failed),
            /Code 500.*escrow failed.*QAR3/
        );
    });

    it('honors an already-aborted caller signal', async () => {
        let waited = false;
        await assert.rejects(
            waitOperation(
                client({
                    wait: async () => {
                        waited = true;
                        return completed;
                    },
                }),
                pending,
                AbortSignal.abort(new Error('interrupted'))
            ),
            /interrupted/
        );
        assert.equal(waited, false);
    });
});
