import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
    buildGroupEvent,
    type GroupMemberEvent,
} from '../src/multisig.ts';

/** Build the small member event shape needed by aggregation tests. */
function memberEvent(
    memberPrefix: string,
    eventSaid = 'E-event'
): GroupMemberEvent {
    return {
        member: {
            memberPrefix,
            operation: `op-${memberPrefix}`,
            notifications: [],
        },
        groupPrefix: 'E-group',
        eventSaid,
        eventSequence: '2',
    };
}

describe('multisig event aggregation', () => {
    it('preserves separate signing and next rosters', () => {
        const signing = ['E1', 'E2', 'E3'].map(
            (prefix) => ({prefix}) as never
        );
        const rotation = ['E1', 'E2', 'E4'].map(
            (prefix) => ({prefix}) as never
        );
        const event = buildGroupEvent(
            signing,
            rotation,
            signing.map(({prefix}) => memberEvent(prefix))
        );

        assert.deepEqual(event.signingMembers, ['E1', 'E2', 'E3']);
        assert.deepEqual(event.rotationMembers, ['E1', 'E2', 'E4']);
    });

    it('rejects divergent member contributions', () => {
        assert.throws(
            () =>
                buildGroupEvent(
                    [{prefix: 'E1'} as never],
                    [{prefix: 'E1'} as never],
                    [
                        memberEvent('E1'),
                        memberEvent('E2', 'E-other'),
                    ]
                ),
            /divergent/
        );
    });
});
