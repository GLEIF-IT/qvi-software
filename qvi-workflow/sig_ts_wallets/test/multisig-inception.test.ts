import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
    validateMemberScopedInceptionOperations,
} from '../src/qars/qars-complete-multisig-incept.ts';

describe('delegated inception operation identity', () => {
    it('accepts the same logical operation from three agent stores', () => {
        const operationName = 'group.EDelegatedQvi';

        const operations = validateMemberScopedInceptionOperations([
            operationName,
            operationName,
            operationName,
        ]);

        assert.deepEqual(operations, [
            operationName,
            operationName,
            operationName,
        ]);
    });

    it('rejects missing, empty, or mismatched member operations', () => {
        const operationName = 'group.EDelegatedQvi';

        assert.throws(
            () => validateMemberScopedInceptionOperations([
                operationName,
                operationName,
            ]),
            /three matching member-scoped operation names/
        );
        assert.throws(
            () => validateMemberScopedInceptionOperations([
                operationName,
                '',
                operationName,
            ]),
            /three matching member-scoped operation names/
        );
        assert.throws(
            () => validateMemberScopedInceptionOperations([
                operationName,
                'group.EOtherQvi',
                operationName,
            ]),
            /three matching member-scoped operation names/
        );
    });
});
