import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    CompletedDoneOperation,
    FailedDoneOperation,
    Operation,
    SignifyClient,
} from 'signify-ts';

import {
    completeMemberRotationOperations,
} from '../src/qars/qars-refresh-geda-multisig-state.ts';

interface GroupStateFixture {
    prefix: string;
    sequence: string;
    establishmentDigest: string;
}

const expectedGroupState: GroupStateFixture = {
    prefix: 'EQvi',
    sequence: '1',
    establishmentDigest: 'ERotation',
};

function operationClient(
    member: string,
    trace: string[],
    operation: Operation,
    completedMembers?: Set<string>,
    groupState: GroupStateFixture = expectedGroupState
): SignifyClient {
    return {
        operations: () => ({
            get: async (name: string) => {
                trace.push(`${member}:operation:${name}`);
                completedMembers?.add(member);
                return operation;
            },
        }),
        notifications: () => ({
            mark: async (notificationId: string) => {
                const everyOperationCompleted =
                    completedMembers?.size === 3;
                assert.equal(everyOperationCompleted, true);
                trace.push(`${member}:mark:${notificationId}`);
                return notificationId;
            },
            delete: async (notificationId: string) => {
                trace.push(`${member}:delete:${notificationId}`);
            },
        }),
        identifiers: () => ({
            get: async (groupName: string) => {
                const everyOperationCompleted =
                    completedMembers?.size === 3;
                assert.equal(everyOperationCompleted, true);
                trace.push(`${member}:group:${groupName}`);
                return {
                    prefix: groupState.prefix,
                    state: {
                        s: groupState.sequence,
                        ee: {
                            d: groupState.establishmentDigest,
                        },
                    },
                };
            },
        }),
    } as unknown as SignifyClient;
}

function rotationRequest(
    clients: {
        QAR1Client: SignifyClient;
        QAR2Client: SignifyClient;
        QAR3Client: SignifyClient;
    },
    operationNames = [
        'group.ERotation',
        'group.ERotation',
        'group.ERotation',
    ]
) {
    return {
        clients,
        operationNames,
        references: {
            qar2: {notificationIds: ['NQAR2']},
            qar3: {notificationIds: ['NQAR3']},
        },
        groupName: 'qvi',
        expectedQviPrefix: 'EQvi',
    };
}

describe('delegated multisig rotation completion', () => {
    it('consumes follower notices only after all member operations complete', async () => {
        const operationName = 'group.ERotation';
        const trace: string[] = [];
        const completedMembers = new Set<string>();
        const completedOperation = {
            name: operationName,
            done: true,
            response: {
                d: 'ERotation',
                i: 'EQvi',
                s: '1',
            },
        } as CompletedDoneOperation;
        const clients = {
            QAR1Client: operationClient(
                'QAR1',
                trace,
                completedOperation,
                completedMembers
            ),
            QAR2Client: operationClient(
                'QAR2',
                trace,
                completedOperation,
                completedMembers
            ),
            QAR3Client: operationClient(
                'QAR3',
                trace,
                completedOperation,
                completedMembers
            ),
        };

        const completion = await completeMemberRotationOperations(
            rotationRequest(clients, [
                operationName,
                operationName,
                operationName,
            ])
        );

        assert.deepEqual(trace, [
            `QAR1:operation:${operationName}`,
            `QAR2:operation:${operationName}`,
            `QAR3:operation:${operationName}`,
            'QAR1:group:qvi',
            'QAR2:group:qvi',
            'QAR3:group:qvi',
            'QAR2:mark:NQAR2',
            'QAR2:delete:NQAR2',
            'QAR3:mark:NQAR3',
            'QAR3:delete:NQAR3',
        ]);
        assert.equal(completion.operationEvidence.length, 3);
        assert.equal(
            completion.operationEvidence.every(
                (entry) => entry.done === true
            ),
            true
        );
        assert.deepEqual(completion.groupState, {
            prefix: 'EQvi',
            sequence: '1',
            establishmentDigest: 'ERotation',
            observerCount: 3,
        });
    });

    it('retains follower notices when a member operation fails', async () => {
        const operationName = 'group.ERotation';
        const trace: string[] = [];
        const completedMembers = new Set<string>();
        const completedOperation = {
            name: operationName,
            done: true,
            response: {
                d: 'ERotation',
                i: 'EQvi',
                s: '1',
            },
        } as CompletedDoneOperation;
        const failedOperation: FailedDoneOperation = {
            name: operationName,
            done: true,
            error: {
                code: 500,
                message: 'rotation escrow failed',
            },
        };
        const clients = {
            QAR1Client: operationClient(
                'QAR1',
                trace,
                completedOperation,
                completedMembers
            ),
            QAR2Client: operationClient(
                'QAR2',
                trace,
                failedOperation,
                completedMembers
            ),
            QAR3Client: operationClient(
                'QAR3',
                trace,
                completedOperation,
                completedMembers
            ),
        };

        await assert.rejects(
            completeMemberRotationOperations(
                rotationRequest(clients, [
                    operationName,
                    operationName,
                    operationName,
                ])
            ),
            /rotation escrow failed/
        );
        const notificationWasConsumed = trace.some(
            (entry) =>
                entry.includes(':mark:') ||
                entry.includes(':delete:')
        );
        assert.equal(notificationWasConsumed, false);
    });

    it('rejects missing or mismatched member operation names', async () => {
        const unexpectedClient = operationClient(
            'unexpected',
            [],
            {} as Operation
        );
        const clients = {
            QAR1Client: unexpectedClient,
            QAR2Client: unexpectedClient,
            QAR3Client: unexpectedClient,
        };

        await assert.rejects(
            completeMemberRotationOperations(
                rotationRequest(clients, [
                    'group.ERotation',
                    'group.EOther',
                    'group.ERotation',
                ])
            ),
            /three matching member-scoped operation names/
        );
    });

    it('rejects non-event, wrong-prefix, wrong-sequence, and missing-SAID results', async () => {
        const invalidResponses: Array<{
            description: string;
            response: unknown;
        }> = [
            {
                description: 'non-event',
                response: {
                    ced: {
                        d: 'ERotation',
                        i: 'EQvi',
                        s: 'ESchema',
                    },
                },
            },
            {
                description: 'wrong-prefix',
                response: {
                    d: 'ERotation',
                    i: 'EOther',
                    s: '1',
                },
            },
            {
                description: 'wrong-sequence',
                response: {
                    d: 'ERotation',
                    i: 'EQvi',
                    s: '2',
                },
            },
            {
                description: 'missing-SAID',
                response: {
                    i: 'EQvi',
                    s: '1',
                },
            },
        ];

        for (const invalid of invalidResponses) {
            const operationName = 'group.ERotation';
            const trace: string[] = [];
            const completedMembers = new Set<string>();
            const operation = {
                name: operationName,
                done: true,
                response: invalid.response,
            } as CompletedDoneOperation;
            const clients = {
                QAR1Client: operationClient(
                    'QAR1',
                    trace,
                    operation,
                    completedMembers
                ),
                QAR2Client: operationClient(
                    'QAR2',
                    trace,
                    operation,
                    completedMembers
                ),
                QAR3Client: operationClient(
                    'QAR3',
                    trace,
                    operation,
                    completedMembers
                ),
            };

            await assert.rejects(
                completeMemberRotationOperations(
                    rotationRequest(clients)
                ),
                /three matching QVI event results/,
                invalid.description
            );
            const noticeWasConsumed = trace.some(
                (entry) =>
                    entry.includes(':mark:') ||
                    entry.includes(':delete:')
            );
            assert.equal(
                noticeWasConsumed,
                false,
                invalid.description
            );
        }
    });

    it('rejects divergent member event SAIDs before consuming notices', async () => {
        const trace: string[] = [];
        const completedMembers = new Set<string>();
        const operation = (
            said: string
        ): CompletedDoneOperation => ({
            name: `group.${said}`,
            done: true,
            response: {
                d: said,
                i: 'EQvi',
                s: '1',
            },
        } as CompletedDoneOperation);
        const clients = {
            QAR1Client: operationClient(
                'QAR1',
                trace,
                operation('ERotation'),
                completedMembers
            ),
            QAR2Client: operationClient(
                'QAR2',
                trace,
                operation('EOther'),
                completedMembers
            ),
            QAR3Client: operationClient(
                'QAR3',
                trace,
                operation('ERotation'),
                completedMembers
            ),
        };

        await assert.rejects(
            completeMemberRotationOperations({
                ...rotationRequest(clients),
                operationNames: [
                    'group.ERotation',
                    'group.ERotation',
                    'group.ERotation',
                ],
            }),
            /three matching QVI event results/
        );
        const noticeWasConsumed = trace.some(
            (entry) =>
                entry.includes(':mark:') ||
                entry.includes(':delete:')
        );
        assert.equal(noticeWasConsumed, false);
    });

    it('rejects divergent group-state digests before consuming notices', async () => {
        const operationName = 'group.ERotation';
        const trace: string[] = [];
        const completedMembers = new Set<string>();
        const operation = {
            name: operationName,
            done: true,
            response: {
                d: 'ERotation',
                i: 'EQvi',
                s: '1',
            },
        } as CompletedDoneOperation;
        const clients = {
            QAR1Client: operationClient(
                'QAR1',
                trace,
                operation,
                completedMembers
            ),
            QAR2Client: operationClient(
                'QAR2',
                trace,
                operation,
                completedMembers,
                {
                    ...expectedGroupState,
                    establishmentDigest: 'EDiverged',
                }
            ),
            QAR3Client: operationClient(
                'QAR3',
                trace,
                operation,
                completedMembers
            ),
        };

        await assert.rejects(
            completeMemberRotationOperations(
                rotationRequest(clients)
            ),
            /group state does not converge/
        );
        const noticeWasConsumed = trace.some(
            (entry) =>
                entry.includes(':mark:') ||
                entry.includes(':delete:')
        );
        assert.equal(noticeWasConsumed, false);
    });
});
