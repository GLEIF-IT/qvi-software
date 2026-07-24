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
    completedOperationEvidence,
    isCompletedOperation,
    isFailedOperation,
    isPendingOperation,
    operationResultIdentity,
    waitOperation,
    waitOperationEvidence,
} from '../src/operations.ts';

const pendingOperation: PendingDoneOperation = {
    name: 'done.pending',
    done: false,
};

const completedOperation = {
    name: 'done.completed',
    done: true,
    response: {
        d: 'ECompletedEvent',
    },
} as CompletedDoneOperation;

const failedOperation: FailedDoneOperation = {
    name: 'done.failed',
    done: true,
    error: {
        code: 500,
        message: 'coordination failed',
        details: {
            member: 'QAR3',
        },
    },
};

interface OperationClientOptions {
    get?: (name: string) => Promise<Operation>;
    wait?: (
        operation: Operation,
        options?: {signal?: AbortSignal}
    ) => Promise<CompletedDoneOperation>;
}

function operationClient({
    get = async () => {
        throw new Error('unexpected operation lookup');
    },
    wait = async () => {
        throw new Error('unexpected operation wait');
    },
}: OperationClientOptions): SignifyClient {
    return {
        operations: () => ({
            get,
            wait,
        }),
    } as unknown as SignifyClient;
}

describe('operation state handling', () => {
    it('narrows pending, completed, and failed operation variants', () => {
        assert.equal(isPendingOperation(pendingOperation), true);
        assert.equal(isCompletedOperation(pendingOperation), false);
        assert.equal(isFailedOperation(pendingOperation), false);

        assert.equal(isPendingOperation(completedOperation), false);
        assert.equal(isCompletedOperation(completedOperation), true);
        assert.equal(isFailedOperation(completedOperation), false);

        assert.equal(isPendingOperation(failedOperation), false);
        assert.equal(isCompletedOperation(failedOperation), false);
        assert.equal(isFailedOperation(failedOperation), true);
    });

    it('returns an already-completed operation without polling', async () => {
        const client = operationClient({});

        const result = await waitOperation(
            client,
            completedOperation
        );

        assert.equal(result, completedOperation);
    });

    it('projects only bounded event identity into terminal evidence', async () => {
        const operation = {
            name: 'delegation.EOperation',
            done: true,
            metadata: {
                words: ['must-not-appear'],
            },
            response: {
                v: 'KERI10JSON',
                t: 'dip',
                d: 'EDelegatedInception',
                i: 'EQvi',
                s: '0',
                di: 'EGeda',
                a: {
                    private: 'must-not-appear',
                },
            },
        } as unknown as Operation;

        assert.deepEqual(completedOperationEvidence(operation), {
            name: 'delegation.EOperation',
            done: true,
            result: {
                kind: 'event',
                said: 'EDelegatedInception',
                prefix: 'EQvi',
                sequence: '0',
            },
        });
    });

    it('projects credential and registry response identities', () => {
        assert.deepEqual(
            operationResultIdentity({
                ced: {
                    d: 'ECredential',
                    i: 'EIssuer',
                    s: 'ESchema',
                    a: {i: 'EIssuee'},
                },
            }),
            {
                kind: 'credential',
                said: 'ECredential',
                prefix: 'EIssuer',
                schema: 'ESchema',
            }
        );
        assert.deepEqual(
            operationResultIdentity({
                anchor: {
                    i: 'ERegistry',
                    s: '0',
                    d: 'ERegistryAnchor',
                },
                ignored: {secret: 'not retained'},
            }),
            {
                kind: 'registry-anchor',
                said: 'ERegistryAnchor',
                prefix: 'ERegistry',
                sequence: '0',
            }
        );
    });

    it('does not create evidence for pending or failed operations', () => {
        assert.throws(
            () => completedOperationEvidence(pendingOperation),
            /without reaching a completed state/
        );
        assert.throws(
            () => completedOperationEvidence(failedOperation),
            /done\.failed.*coordination failed/
        );
    });

    it('does not retain unbounded response strings', () => {
        assert.deepEqual(
            operationResultIdentity({
                d: 'E'.repeat(513),
                i: 'EQvi',
                s: '0',
            }),
            {kind: 'object'}
        );
    });

    it('looks up and polls a pending named operation', async () => {
        const lookedUpNames: string[] = [];
        const waitedOperations: string[] = [];
        const client = operationClient({
            get: async (name) => {
                lookedUpNames.push(name);
                return pendingOperation;
            },
            wait: async (operation, options) => {
                waitedOperations.push(operation.name);
                const signalWasProvided =
                    options?.signal !== undefined;
                assert.equal(signalWasProvided, true);
                return completedOperation;
            },
        });

        const result = await waitOperation(
            client,
            pendingOperation.name
        );

        assert.equal(result, completedOperation);
        assert.deepEqual(lookedUpNames, [pendingOperation.name]);
        assert.deepEqual(waitedOperations, [
            pendingOperation.name,
        ]);
    });

    it('waits before emitting terminal operation evidence', async () => {
        const client = operationClient({
            get: async () => pendingOperation,
            wait: async () => completedOperation,
        });

        const evidence = await waitOperationEvidence(
            client,
            pendingOperation.name
        );

        assert.deepEqual(evidence, {
            name: completedOperation.name,
            done: true,
            result: {
                kind: 'event',
                said: 'ECompletedEvent',
            },
        });
    });

    it('fails immediately when the current operation state is failed', async () => {
        let waitWasCalled = false;
        const client = operationClient({
            wait: async () => {
                waitWasCalled = true;
                return completedOperation;
            },
        });

        await assert.rejects(
            waitOperation(client, failedOperation),
            /done\.failed.*Code 500.*coordination failed.*QAR3/
        );
        assert.equal(waitWasCalled, false);
    });

    it('rejects a failed state returned by a nonconforming wait implementation', async () => {
        const client = operationClient({
            wait: async () =>
                failedOperation as unknown as CompletedDoneOperation,
        });

        await assert.rejects(
            waitOperation(client, pendingOperation),
            /done\.failed.*coordination failed/
        );
    });

    it('does not poll when the caller signal is already aborted', async () => {
        let waitWasCalled = false;
        const client = operationClient({
            wait: async () => {
                waitWasCalled = true;
                return completedOperation;
            },
        });
        const signal = AbortSignal.abort(
            new Error('workflow interrupted')
        );

        await assert.rejects(
            waitOperation(client, pendingOperation, signal),
            /workflow interrupted/
        );
        assert.equal(waitWasCalled, false);
    });

    it('propagates a timeout while a pending operation is polling', async () => {
        const client = operationClient({
            wait: async (_operation, options) => {
                const signal = options?.signal;
                const signalIsMissing = signal === undefined;
                if (signalIsMissing) {
                    throw new Error('expected a timeout signal');
                }

                return new Promise((_resolve, reject) => {
                    const rejectWithTimeout = () => {
                        reject(signal.reason);
                    };
                    signal.addEventListener(
                        'abort',
                        rejectWithTimeout,
                        {once: true}
                    );
                });
            },
        });

        await assert.rejects(
            waitOperation(
                client,
                pendingOperation,
                AbortSignal.timeout(10)
            ),
            (error: unknown) => {
                const errorIsTimeout =
                    error instanceof DOMException &&
                    error.name === 'TimeoutError';
                return errorIsTimeout;
            }
        );
    });
});
