import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
    expectedChallengeDirections,
    validateChallengeReceipts,
} from '../src/challenge-graph.ts';

describe('challenge trust graph', () => {
    it('derives and validates exactly 16 directions across 8 relationships', () => {
        const expected = expectedChallengeDirections();
        assert.equal(expected.length, 16);
        assert.equal(
            new Set(
                expected.map(
                    (direction) => direction.relationship
                )
            ).size,
            8
        );

        const validated = validateChallengeReceipts(
            expected.map((direction) => ({
                relationship: direction.relationship,
                from: direction.from,
                to: direction.to,
            }))
        );
        assert.equal(validated.length, 16);
    });

    it('rejects a duplicate direction', () => {
        const expected = expectedChallengeDirections();
        const receipts = expected.map((direction) => ({
            relationship: direction.relationship,
            from: direction.from,
            to: direction.to,
        }));
        receipts[15] = receipts[0];
        assert.throws(
            () => validateChallengeReceipts(receipts),
            /do not match/
        );
    });

    it('rejects a mislabeled relationship', () => {
        const expected = expectedChallengeDirections();
        const receipts = expected.map((direction) => ({
            relationship: direction.relationship,
            from: direction.from,
            to: direction.to,
        }));
        receipts[0] = {
            ...receipts[0],
            relationship: 'wrong-relationship',
        };
        assert.throws(
            () => validateChallengeReceipts(receipts),
            /do not match/
        );
    });
});
