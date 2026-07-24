import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {memberContexts} from '../src/multisig-coordinator.ts';

describe('multisig coordinator', () => {
    it('assigns one initiator and one explicit coordinator', () => {
        const members = ['EQar1', 'EQar2', 'EQar3'].map(
            (prefix, index) => ({
                aid: {prefix, name: `qar${index + 1}`} as never,
                client: {} as never,
            })
        );
        const contexts = memberContexts(members, 'EQar2');
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
                    isInitiator: false,
                    coordinatorPrefix: 'EQar2',
                    recipients: ['EQar2', 'EQar3'],
                },
                {
                    prefix: 'EQar2',
                    isInitiator: true,
                    coordinatorPrefix: 'EQar2',
                    recipients: ['EQar1', 'EQar3'],
                },
                {
                    prefix: 'EQar3',
                    isInitiator: false,
                    coordinatorPrefix: 'EQar2',
                    recipients: ['EQar1', 'EQar2'],
                },
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
                    })),
                    'EQar1'
                ),
            /prefixes must be unique/
        );
    });

    it('does not impose the workflow three-member fixture', () => {
        const members = ['E1', 'E2'].map((prefix) => ({
            aid: {prefix, name: prefix} as never,
            client: {} as never,
        }));
        assert.equal(memberContexts(members, 'E1').length, 2);
    });

    it('rejects an initiator outside the member set', () => {
        assert.throws(
            () =>
                memberContexts(
                    ['1', '2'].map((suffix) => ({
                        aid: {
                            prefix: `EQar${suffix}`,
                            name: `qar${suffix}`,
                        } as never,
                        client: {} as never,
                    })),
                    'EQar3'
                ),
            /is not a member/
        );
    });
});
