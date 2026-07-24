import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {HabState} from 'signify-ts';

import type {
    GroupObservation,
    GroupStateSnapshot,
} from '../src/group-state.ts';
import {assertGroupStateConvergence} from '../src/workflow-assertions.ts';

const memberAids = ['EQar1', 'EQar2', 'EQar3'];
const expected = {
    prefix: 'EQvi',
    delegator: 'EGeda',
    sequence: '0',
    signingThreshold: ['1/3', '1/3', '1/3'],
    nextThreshold: ['1/3', '1/3', '1/3'],
    members: memberAids,
};

function snapshot(
    digest = 'EEstablishment'
): GroupStateSnapshot {
    return {
        ...expected,
        establishmentDigest: digest,
        signingMembers: memberAids,
        rotationMembers: memberAids,
    };
}

function observations(
    states = memberAids.map(() => snapshot())
): GroupObservation[] {
    return states.map((state, index) => ({
        observerAid: memberAids[index],
        group: {prefix: state.prefix} as HabState,
        snapshot: state,
    }));
}

describe('workflow group assertions', () => {
    it('accepts the configured converged state', () => {
        assert.equal(
            assertGroupStateConvergence(
                observations(),
                expected
            ).establishmentDigest,
            'EEstablishment'
        );
    });

    it('rejects divergent member state', () => {
        assert.throws(
            () =>
                assertGroupStateConvergence(
                    observations([
                        snapshot(),
                        snapshot(),
                        snapshot('EDiverged'),
                    ]),
                    expected
                ),
            /group state diverged/
        );
    });

    it('rejects a test expectation that does not match reality', () => {
        assert.throws(
            () =>
                assertGroupStateConvergence(observations(), {
                    ...expected,
                    sequence: '1',
                }),
            /does not match/
        );
    });
});
