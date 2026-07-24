import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {CredentialResult} from 'signify-ts';

import {credentialSnapshot} from '../src/credential-state.ts';
import {assertCredentialConvergence} from '../src/workflow-assertions.ts';

const observers = ['EQar1', 'EQar2', 'EQar3'];

function credential(
    sequence: '0' | '1',
    digest: string
): CredentialResult {
    return {
        sad: {
            d: 'ECredential',
            i: 'EIssuer',
            s: 'ESchema',
            a: {i: 'EIssuee'},
        },
        iss: {d: 'EIssuance'},
        status: {
            s: sequence,
            d: digest,
            ri: 'ERegistry',
        },
    } as unknown as CredentialResult;
}

function expected(sequence: string) {
    return {
        said: 'ECredential',
        issuer: 'EIssuer',
        schema: 'ESchema',
        issuee: 'EIssuee',
        statusSequence: sequence,
    };
}

describe('credential observations and workflow assertions', () => {
    it('models issuance and revocation TEL links', () => {
        const issued = credentialSnapshot(
            credential('0', 'EIssuance'),
            'EQar1'
        );
        const revoked = credentialSnapshot(
            credential('1', 'ERevocation'),
            'EQar1'
        );
        assert.equal(issued.priorTelDigest, null);
        assert.equal(revoked.priorTelDigest, 'EIssuance');
    });

    it('rejects aggregate credentials at the API boundary', () => {
        const aggregate = credential('0', 'EIssuance');
        aggregate.sad = {
            v: 'ACDC10JSON000000_',
            d: 'EAggregate',
            i: 'EIssuer',
            s: 'ESchema',
            A: [],
        };
        assert.throws(
            () => credentialSnapshot(aggregate, 'EQar1'),
            /aggregate attributes/
        );
    });

    it('accepts matching QAR observations', () => {
        const snapshots = observers.map((observer) =>
            credentialSnapshot(
                credential('0', 'EIssuance'),
                observer
            )
        );
        assert.equal(
            assertCredentialConvergence(
                snapshots,
                observers,
                expected('0')
            ).said,
            'ECredential'
        );
    });

    it('rejects divergent TEL state and wrong expectations', () => {
        const snapshots = observers.map((observer, index) =>
            credentialSnapshot(
                credential(
                    '1',
                    index === 2
                        ? 'EDiverged'
                        : 'ERevocation'
                ),
                observer
            )
        );
        assert.throws(
            () =>
                assertCredentialConvergence(
                    snapshots,
                    observers,
                    expected('1')
                ),
            /credential state diverged/
        );
        const issued = observers.map((observer) =>
            credentialSnapshot(
                credential('0', 'EIssuance'),
                observer
            )
        );
        assert.throws(
            () =>
                assertCredentialConvergence(
                    issued,
                    observers,
                    expected('1')
                ),
            /does not match/
        );
    });
});
