import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {HabState} from 'signify-ts';

import {
    assertGroupStateConvergence,
    type GroupObservation,
    type GroupStateSnapshot,
} from '../src/group-state.ts';

function snapshot(
    digest = 'EEstablishment'
): GroupStateSnapshot {
    return {
        prefix: 'EQvi',
        delegator: 'EGeda',
        sequence: '0',
        establishmentDigest: digest,
        signingThreshold: ['1/3', '1/3', '1/3'],
        nextThreshold: ['1/3', '1/3', '1/3'],
        signingMembers: ['EQar1', 'EQar2', 'EQar3'],
        rotationMembers: ['EQar1', 'EQar2', 'EQar3'],
    };
}

function observation(
    observerAid: string,
    state: GroupStateSnapshot
): GroupObservation {
    return {
        observerAid,
        group: {prefix: state.prefix} as HabState,
        snapshot: state,
    };
}

describe('group state convergence', () => {
    it('accepts three matching configured QVI threshold snapshots', () => {
        const observations = [
            observation('EQar1', snapshot()),
            observation('EQar2', snapshot()),
            observation('EQar3', snapshot()),
        ];
        const result = assertGroupStateConvergence(
            observations,
            ['EQar1', 'EQar2', 'EQar3'],
            {
                prefix: 'EQvi',
                delegator: 'EGeda',
                signingThreshold: ['1/3', '1/3', '1/3'],
                nextThreshold: ['1/3', '1/3', '1/3'],
            }
        );
        assert.equal(result.establishmentDigest, 'EEstablishment');
    });

    it('rejects a member with a different establishment digest', () => {
        const observations = [
            observation('EQar1', snapshot()),
            observation('EQar2', snapshot()),
            observation('EQar3', snapshot('EDiverged')),
        ];
        assert.throws(
            () =>
                assertGroupStateConvergence(observations, [
                    'EQar1',
                    'EQar2',
                    'EQar3',
                ]),
            /group state diverged/
        );
    });

    it('rejects an unexpected configured threshold', () => {
        const observations = [
            observation('EQar1', snapshot()),
            observation('EQar2', snapshot()),
            observation('EQar3', snapshot()),
        ];
        assert.throws(
            () =>
                assertGroupStateConvergence(
                    observations,
                    ['EQar1', 'EQar2', 'EQar3'],
                    {
                        signingThreshold: ['1', '1', '1'],
                    }
                ),
            /does not match expected/
        );
    });

    it('rejects duplicate observers even when group state agrees', () => {
        const observations = [
            observation('EQar1', snapshot()),
            observation('EQar1', snapshot()),
            observation('EQar3', snapshot()),
        ];
        assert.throws(
            () =>
                assertGroupStateConvergence(observations, [
                    'EQar1',
                    'EQar2',
                    'EQar3',
                ]),
            /do not match expected member AIDs/
        );
    });

    it('rejects an unexpected observer in place of a configured member', () => {
        const observations = [
            observation('EQar1', snapshot()),
            observation('EQar2', snapshot()),
            observation('EOutsider', snapshot()),
        ];
        assert.throws(
            () =>
                assertGroupStateConvergence(observations, [
                    'EQar1',
                    'EQar2',
                    'EQar3',
                ]),
            /do not match expected member AIDs/
        );
    });

    it('rejects a missing configured observer', () => {
        const observations = [
            observation('EQar1', snapshot()),
            observation('EQar2', snapshot()),
            observation('EQar3', snapshot()),
        ];
        assert.throws(
            () =>
                assertGroupStateConvergence(observations, [
                    'EQar1',
                    'EQar2',
                ]),
            /requires exactly three unique expected observer AIDs/
        );
    });
});
