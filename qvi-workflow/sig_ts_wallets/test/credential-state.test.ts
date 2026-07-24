import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {CredentialResult} from 'signify-ts';

import {
    assertCredentialConvergence,
    assertExpectedCredential,
    assertIssuedCredentialConvergence,
    credentialSnapshot,
} from '../src/credential-state.ts';

function credential(
    statusSequence: '0' | '1',
    statusDigest: string
): CredentialResult {
    return {
        sad: {
            v: 'ACDC10JSON000000_',
            d: 'ECredential',
            i: 'EIssuer',
            s: 'ESchema',
            ri: 'ERegistry',
            a: {
                i: 'EIssuee',
                dt: '2026-01-01T00:00:00.000000+00:00',
            },
        },
        iss: {
            d: 'EIssuance',
        },
        status: {
            s: statusSequence,
            d: statusDigest,
            ri: 'ERegistry',
        },
    } as unknown as CredentialResult;
}

describe('credential snapshots', () => {
    it('models an issued credential with no prior TEL link', () => {
        const snapshot = credentialSnapshot(
            credential('0', 'EIssuance'),
            'EQar1'
        );
        assert.equal(snapshot.observerAid, 'EQar1');
        assert.equal(snapshot.statusSequence, '0');
        assert.equal(snapshot.priorTelDigest, null);
        assert.equal(snapshot.currentTelDigest, 'EIssuance');
    });

    it('models a revoked credential with the issuance event as its prior TEL link', () => {
        const snapshot = credentialSnapshot(
            credential('1', 'ERevocation'),
            'EQar1'
        );
        assert.equal(snapshot.statusSequence, '1');
        assert.equal(snapshot.priorTelDigest, 'EIssuance');
        assert.equal(snapshot.currentTelDigest, 'ERevocation');
    });

    it('rejects aggregate credentials', () => {
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

    it('rejects the wrong issuer, schema, issuee, or SAID', () => {
        const snapshot = credentialSnapshot(
            credential('0', 'EIssuance'),
            'EQar1'
        );
        const expectations = [
            {
                said: 'EWrong',
                issuer: 'EIssuer',
                schema: 'ESchema',
                issuee: 'EIssuee',
            },
            {
                said: 'ECredential',
                issuer: 'EWrong',
                schema: 'ESchema',
                issuee: 'EIssuee',
            },
            {
                said: 'ECredential',
                issuer: 'EIssuer',
                schema: 'EWrong',
                issuee: 'EIssuee',
            },
            {
                said: 'ECredential',
                issuer: 'EIssuer',
                schema: 'ESchema',
                issuee: 'EWrong',
            },
        ];
        for (const expected of expectations) {
            assert.throws(
                () => assertExpectedCredential(snapshot, expected),
                /expected/
            );
        }
    });

    it('rejects divergent three-member TEL state', () => {
        const snapshots = [
            credentialSnapshot(
                credential('1', 'ERevocation'),
                'EQar1'
            ),
            credentialSnapshot(
                credential('1', 'ERevocation'),
                'EQar2'
            ),
            credentialSnapshot(
                credential('1', 'EOtherRevocation'),
                'EQar3'
            ),
        ];
        assert.throws(
            () =>
                assertCredentialConvergence(snapshots, [
                    'EQar1',
                    'EQar2',
                    'EQar3',
                ]),
            /TEL state diverged/
        );
    });

    it('accepts issuance success only at sequence zero on every QAR', () => {
        const snapshots = [
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar1'
            ),
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar2'
            ),
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar3'
            ),
        ];

        assert.doesNotThrow(() =>
            assertIssuedCredentialConvergence(
                snapshots,
                ['EQar1', 'EQar2', 'EQar3'],
                'OOR credential'
            )
        );
    });

    it('rejects a converged revoked credential as issuance success', () => {
        const snapshots = [
            credentialSnapshot(
                credential('1', 'ERevocation'),
                'EQar1'
            ),
            credentialSnapshot(
                credential('1', 'ERevocation'),
                'EQar2'
            ),
            credentialSnapshot(
                credential('1', 'ERevocation'),
                'EQar3'
            ),
        ];

        assert.throws(
            () =>
                assertIssuedCredentialConvergence(
                    snapshots,
                    ['EQar1', 'EQar2', 'EQar3'],
                    'OOR credential'
                ),
            /OOR credential must be active at TEL sequence 0 on every QAR/
        );
    });

    it('rejects duplicate observers even when three snapshots agree', () => {
        const snapshots = [
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar1'
            ),
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar1'
            ),
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar3'
            ),
        ];
        assert.throws(
            () =>
                assertCredentialConvergence(snapshots, [
                    'EQar1',
                    'EQar2',
                    'EQar3',
                ]),
            /do not match expected member AIDs/
        );
    });

    it('rejects an unexpected observer in place of a configured member', () => {
        const snapshots = [
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar1'
            ),
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar2'
            ),
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EOutsider'
            ),
        ];
        assert.throws(
            () =>
                assertCredentialConvergence(snapshots, [
                    'EQar1',
                    'EQar2',
                    'EQar3',
                ]),
            /do not match expected member AIDs/
        );
    });

    it('rejects a duplicate configured observer set', () => {
        const snapshots = [
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar1'
            ),
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar2'
            ),
            credentialSnapshot(
                credential('0', 'EIssuance'),
                'EQar3'
            ),
        ];
        assert.throws(
            () =>
                assertCredentialConvergence(snapshots, [
                    'EQar1',
                    'EQar1',
                    'EQar3',
                ]),
            /requires exactly three unique expected observer AIDs/
        );
    });
});
