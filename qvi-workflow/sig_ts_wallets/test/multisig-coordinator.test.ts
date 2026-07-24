import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
    parsePendingMultisigOperation,
    memberContexts,
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

    it('parses the minimal delegated-operation handle', () => {
        const pending = parsePendingMultisigOperation({
            route: '/multisig/icp',
            groupPrefix: 'EQvi',
            members: ['1', '2', '3'].map((suffix) => ({
                memberPrefix: `EQar${suffix}`,
                operationName: 'group.EQvi',
                notificationIds:
                    suffix === '1' ? [] : [`N${suffix}`],
            })),
        });
        assert.equal(pending.members.length, 3);
        assert.equal(pending.groupPrefix, 'EQvi');
    });

    it('rejects malformed or duplicate member handles', () => {
        assert.throws(
            () =>
                parsePendingMultisigOperation({
                    route: '/multisig/icp',
                    groupPrefix: 'EQvi',
                    members: ['1', '1', '3'].map((suffix) => ({
                        memberPrefix: `EQar${suffix}`,
                        operationName: 'group.EQvi',
                        notificationIds: [],
                    })),
                }),
            /three unique members/
        );
    });
});
