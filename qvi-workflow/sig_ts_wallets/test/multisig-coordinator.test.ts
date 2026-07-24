import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
    memberContexts,
    submitMemberContributions,
} from '../src/multisig-coordinator.ts';

describe('multisig coordinator', () => {
    it('assigns one initiator and one explicit coordinator', () => {
        const members = ['EQar1', 'EQar2', 'EQar3'].map(
            (prefix, index) => ({
                aid: {prefix, name: `qar${index + 1}`} as never,
                client: {} as never,
            })
        );
        const contexts = memberContexts(members);
        assert.deepEqual(
            contexts.map(
                ({
                    aid,
                    isInitiator,
                    coordinatorPrefix,
                    otherMembers,
                }) => ({
                    prefix: aid.prefix,
                    isInitiator,
                    coordinatorPrefix,
                    recipients: otherMembers.map(({prefix}) => prefix),
                })
            ),
            [
                {
                    prefix: 'EQar1',
                    isInitiator: true,
                    coordinatorPrefix: 'EQar1',
                    recipients: ['EQar2', 'EQar3'],
                },
                {
                    prefix: 'EQar2',
                    isInitiator: false,
                    coordinatorPrefix: 'EQar1',
                    recipients: ['EQar1', 'EQar3'],
                },
                {
                    prefix: 'EQar3',
                    isInitiator: false,
                    coordinatorPrefix: 'EQar1',
                    recipients: ['EQar1', 'EQar2'],
                },
            ]
        );
    });

    it('returns live contributions in protocol order', async () => {
        const members = ['EQar1', 'EQar2', 'EQar3'].map(
            (prefix, index) => ({
                aid: {prefix, name: `qar${index + 1}`} as never,
                client: {} as never,
            })
        );
        const executionOrder: string[] = [];
        const submissions = await submitMemberContributions(
            members,
            async (context) => {
                executionOrder.push(context.aid.prefix);
                return {
                    operation: `op-${context.aid.prefix}`,
                    coordination: [],
                };
            }
        );

        assert.deepEqual(executionOrder, ['EQar1', 'EQar2', 'EQar3']);
        assert.deepEqual(
            submissions.map(({memberPrefix, operation}) => ({
                memberPrefix,
                operation,
            })),
            [
                {memberPrefix: 'EQar1', operation: 'op-EQar1'},
                {memberPrefix: 'EQar2', operation: 'op-EQar2'},
                {memberPrefix: 'EQar3', operation: 'op-EQar3'},
            ]
        );
    });

    it('rejects duplicate member prefixes', () => {
        assert.throws(
            () =>
                memberContexts(
                    ['1', '1', '3'].map((suffix) => ({
                        aid: {
                            prefix: `EQar${suffix}`,
                            name: `qar${suffix}`,
                        } as never,
                        client: {} as never,
                    }))
                ),
            /prefixes must be unique/
        );
    });
});
