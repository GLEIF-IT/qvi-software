import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    CompletedOperation,
    HabState,
    Operation,
} from 'signify-ts';

import {
    coordinateMultisigOperation,
    memberContexts,
} from '../src/multisig-coordinator.ts';
import type {NotificationWriter} from '../src/notifications.ts';
import type {OperationClient} from '../src/operations.ts';

function aid(prefix: string): HabState {
    return {prefix, name: prefix} as HabState;
}

function completionClient(): OperationClient & NotificationWriter {
    const operation = {
        name: 'done',
        done: true,
        response: {},
    } as Operation;
    return {
        operations: () => ({
            get: async () => operation,
            wait: async () => operation as CompletedOperation,
        }),
        notifications: () => ({
            mark: async (id: string) => id,
            delete: async () => {},
        }),
    };
}

function members(prefixes: string[]) {
    return prefixes.map((prefix) => ({
        aid: aid(prefix),
        client: completionClient(),
    }));
}

describe('multisig coordinator', () => {
    it('derives one initiator from its prefix', () => {
        const contexts = memberContexts(
            members(['EQar1', 'EQar2', 'EQar3']),
            'EQar2'
        );
        assert.deepEqual(
            contexts.map(
                ({
                    aid: memberAid,
                    isInitiator,
                    initiatorPrefix,
                    otherMembers,
                }) => ({
                    prefix: memberAid.prefix,
                    isInitiator,
                    initiatorPrefix,
                    recipients: otherMembers.map(({prefix}) => prefix),
                })
            ),
            [
                {
                    prefix: 'EQar1',
                    isInitiator: false,
                    initiatorPrefix: 'EQar2',
                    recipients: ['EQar2', 'EQar3'],
                },
                {
                    prefix: 'EQar2',
                    isInitiator: true,
                    initiatorPrefix: 'EQar2',
                    recipients: ['EQar1', 'EQar3'],
                },
                {
                    prefix: 'EQar3',
                    isInitiator: false,
                    initiatorPrefix: 'EQar2',
                    recipients: ['EQar1', 'EQar2'],
                },
            ]
        );
    });

    it('rejects duplicate member prefixes', () => {
        assert.throws(
            () =>
                memberContexts(
                    members(['EQar1', 'EQar1', 'EQar3']),
                    'EQar1'
                ),
            /prefixes must be unique/
        );
    });

    it('does not impose the workflow three-member fixture', () => {
        assert.equal(
            memberContexts(members(['E1', 'E2']), 'E1').length,
            2
        );
    });

    it('rejects an initiator outside the member set', () => {
        assert.throws(
            () =>
                memberContexts(
                    members(['EQar1', 'EQar2']),
                    'EQar3'
                ),
            /is not a member/
        );
    });

    it('submits the initiator before overlapping followers', async () => {
        let releaseInitiator = () => {};
        let reportInitiatorStarted = () => {};
        let releaseFollowers = () => {};
        let reportFollowersStarted = () => {};
        const initiatorMayFinish = new Promise<void>((resolve) => {
            releaseInitiator = resolve;
        });
        const initiatorStarted = new Promise<void>((resolve) => {
            reportInitiatorStarted = resolve;
        });
        const followersMayFinish = new Promise<void>((resolve) => {
            releaseFollowers = resolve;
        });
        const followersStarted = new Promise<void>((resolve) => {
            reportFollowersStarted = resolve;
        });
        let activeFollowers = 0;

        const completion = coordinateMultisigOperation(
            members(['E1', 'E2', 'E3']),
            'E2',
            async ({aid: memberAid, isInitiator}) => {
                if (isInitiator) {
                    reportInitiatorStarted();
                    await initiatorMayFinish;
                } else {
                    activeFollowers += 1;
                    if (activeFollowers === 2) {
                        reportFollowersStarted();
                    }
                    await followersMayFinish;
                    activeFollowers -= 1;
                }
                return {
                    operation: `done.${memberAid.prefix}`,
                    notificationIds: [],
                };
            }
        );

        await initiatorStarted;
        assert.equal(activeFollowers, 0);
        releaseInitiator();
        await followersStarted;
        assert.equal(activeFollowers, 2);
        releaseFollowers();
        await completion;
    });
});
