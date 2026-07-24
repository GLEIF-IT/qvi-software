import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
    sortAgentEndpointsByEid,
    sortAids,
    sortOobis,
} from '../src/canonical-order.ts';

describe('canonical workflow ordering', () => {
    it('sorts AIDs without changing the caller collection', () => {
        const aids = ['ECharlie', 'EAlpha', 'EBravo'];

        assert.deepEqual(
            sortAids(aids),
            ['EAlpha', 'EBravo', 'ECharlie']
        );
        assert.deepEqual(aids, ['ECharlie', 'EAlpha', 'EBravo']);
    });

    it('sorts OOBIs without changing the caller collection', () => {
        const oobis = [
            'http://keria3/oobi/EQvi',
            'http://keria1/oobi/EQvi',
            'http://keria2/oobi/EQvi',
        ];

        assert.deepEqual(sortOobis(oobis), [
            'http://keria1/oobi/EQvi',
            'http://keria2/oobi/EQvi',
            'http://keria3/oobi/EQvi',
        ]);
        assert.deepEqual(oobis, [
            'http://keria3/oobi/EQvi',
            'http://keria1/oobi/EQvi',
            'http://keria2/oobi/EQvi',
        ]);
    });

    it('sorts agent endpoints by EID without changing them', () => {
        const endpoints = [
            {eid: 'EAgentThree', url: 'http://keria3/'},
            {eid: 'EAgentOne', url: 'http://keria1/'},
            {eid: 'EAgentTwo', url: 'http://keria2/'},
        ];

        assert.deepEqual(sortAgentEndpointsByEid(endpoints), [
            {eid: 'EAgentOne', url: 'http://keria1/'},
            {eid: 'EAgentThree', url: 'http://keria3/'},
            {eid: 'EAgentTwo', url: 'http://keria2/'},
        ]);
        assert.deepEqual(endpoints, [
            {eid: 'EAgentThree', url: 'http://keria3/'},
            {eid: 'EAgentOne', url: 'http://keria1/'},
            {eid: 'EAgentTwo', url: 'http://keria2/'},
        ]);
    });
});
