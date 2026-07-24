import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    CompletedOperation,
    ExchangeResourceV1,
    Operation,
    SignifyClient,
} from 'signify-ts';

import {
    completeCoordinatedOperations,
    completeCoordinatedOperationsWithValidation,
} from '../src/coordinated-operation.ts';
import type {
    MatchedNotification,
    Notification,
} from '../src/notifications.ts';

type OperationOutcome = 'completed' | 'failed';

interface MemberHarness {
    client: SignifyClient;
    result: {
        operation: Operation;
        coordination: MatchedNotification[];
    };
}

function notification(
    member: string
): MatchedNotification {
    const note: Notification = {
        i: `N${member}`,
        dt: '2026-01-01T00:00:00.000000+00:00',
        r: false,
        a: {
            r: '/multisig/iss',
            d: `EExchange${member}`,
        },
    };
    return {
        note,
        deliveryNotes: [note],
        exchangeSaid: `EExchange${member}`,
        exchange: {
            exn: {
                d: `EExchange${member}`,
            },
        } as ExchangeResourceV1,
    };
}

function memberHarness(
    member: string,
    outcome: OperationOutcome,
    events: string[]
): MemberHarness {
    const operation = {
        name: `credential.${member}`,
        done: false,
    } as Operation;
    const completed = {
        name: operation.name,
        done: true,
        response: {
            d: `EIssuance${member}`,
        },
    } as CompletedOperation;
    const failed = {
        name: operation.name,
        done: true,
        error: {
            code: 500,
            message: `${member} failed`,
        },
    } as Operation;
    const client = {
        operations: () => ({
            wait: async () => {
                events.push(`completed:${member}`);
                return outcome === 'completed'
                    ? completed
                    : failed;
            },
        }),
        notifications: () => ({
            mark: async (notificationId: string) => {
                events.push(`marked:${notificationId}`);
                return notificationId;
            },
            delete: async (notificationId: string) => {
                events.push(`deleted:${notificationId}`);
            },
        }),
    } as unknown as SignifyClient;

    return {
        client,
        result: {
            operation,
            coordination: [notification(member)],
        },
    };
}

describe('coordinated operation completion', () => {
    it('consumes notices only after every member operation succeeds', async () => {
        const events: string[] = [];
        const members = [
            memberHarness('qar1', 'completed', events),
            memberHarness('qar2', 'completed', events),
            memberHarness('qar3', 'completed', events),
        ];

        const evidence = await completeCoordinatedOperations(
            members
        );

        assert.equal(evidence.length, 3);
        const lastCompletion = Math.max(
            ...members.map(({result}) =>
                events.indexOf(
                    `completed:${result.operation.name.split('.')[1]}`
                )
            )
        );
        const firstConsumption = events.findIndex(
            (event) => event.startsWith('marked:')
        );
        const allOperationsCompletedBeforeConsumption =
            lastCompletion >= 0 &&
            firstConsumption > lastCompletion;
        assert.equal(
            allOperationsCompletedBeforeConsumption,
            true
        );
    });

    it('retains every notice when one member operation fails', async () => {
        const events: string[] = [];
        const members = [
            memberHarness('qar1', 'completed', events),
            memberHarness('qar2', 'failed', events),
            memberHarness('qar3', 'completed', events),
        ];

        await assert.rejects(
            completeCoordinatedOperations(members),
            /qar2 failed/
        );

        const notificationWasConsumed = events.some(
            (event) =>
                event.startsWith('marked:') ||
                event.startsWith('deleted:')
        );
        assert.equal(notificationWasConsumed, false);
    });

    it('defers consumption until dependent state materializes and validates', async () => {
        const events: string[] = [];
        const members = [
            memberHarness('qar1', 'completed', events),
            memberHarness('qar2', 'completed', events),
            memberHarness('qar3', 'completed', events),
        ];

        const completion =
            await completeCoordinatedOperationsWithValidation(
                members,
                async (operationEvidence) => {
                    events.push('credential-materialized:qar1');
                    events.push('credential-materialized:qar2');
                    events.push('credential-materialized:qar3');
                    events.push('credential-convergence-validated');
                    return {
                        credentialSaid: 'ECredential',
                        operationCount: operationEvidence.length,
                    };
                }
            );

        assert.deepEqual(completion.validatedState, {
            credentialSaid: 'ECredential',
            operationCount: 3,
        });
        assert.equal(completion.operationEvidence.length, 3);
        const convergenceValidatedAt = events.indexOf(
            'credential-convergence-validated'
        );
        const firstConsumptionAt = events.findIndex(
            (event) => event.startsWith('marked:')
        );
        const convergenceValidatedBeforeConsumption =
            convergenceValidatedAt >= 0 &&
            firstConsumptionAt > convergenceValidatedAt;
        assert.equal(
            convergenceValidatedBeforeConsumption,
            true
        );
    });

    it('retains every notice when dependent state does not materialize', async () => {
        const events: string[] = [];
        const members = [
            memberHarness('qar1', 'completed', events),
            memberHarness('qar2', 'completed', events),
            memberHarness('qar3', 'completed', events),
        ];

        await assert.rejects(
            completeCoordinatedOperationsWithValidation(
                members,
                async () => {
                    events.push('credential-materialized:qar1');
                    events.push('credential-materialized:qar2');
                    throw new Error(
                        'QAR3 credential did not materialize'
                    );
                }
            ),
            /QAR3 credential did not materialize/
        );

        const everyOperationCompleted = [
            'qar1',
            'qar2',
            'qar3',
        ].every((member) =>
            events.includes(`completed:${member}`)
        );
        const notificationWasConsumed = events.some(
            (event) =>
                event.startsWith('marked:') ||
                event.startsWith('deleted:')
        );
        assert.equal(everyOperationCompleted, true);
        assert.equal(notificationWasConsumed, false);
    });

    it('retains every notice when materialized state does not converge', async () => {
        const events: string[] = [];
        const members = [
            memberHarness('qar1', 'completed', events),
            memberHarness('qar2', 'completed', events),
            memberHarness('qar3', 'completed', events),
        ];

        await assert.rejects(
            completeCoordinatedOperationsWithValidation(
                members,
                async () => {
                    events.push('credential-materialized:qar1');
                    events.push('credential-materialized:qar2');
                    events.push('credential-materialized:qar3');
                    throw new Error(
                        'QAR credential TEL state diverged'
                    );
                }
            ),
            /credential TEL state diverged/
        );

        const notificationWasConsumed = events.some(
            (event) =>
                event.startsWith('marked:') ||
                event.startsWith('deleted:')
        );
        assert.equal(notificationWasConsumed, false);
    });
});
