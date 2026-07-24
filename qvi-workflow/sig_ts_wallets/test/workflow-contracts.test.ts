import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {CredentialSnapshot} from '../src/credential-state.ts';
import type {OperationEvidence} from '../src/operations.ts';
import {
    assertExactDirectedFanout,
    assertIssuanceContract,
    assertRevocationContract,
    assertTerminalOperationEvidence,
    canonicalReceipts,
} from '../src/workflow-contracts.ts';

const members = ['EQar1', 'EQar2', 'EQar3'];

function fanout(innerExchangeSaid: string) {
    return members.flatMap((sender) =>
        members
            .filter((recipient) => recipient !== sender)
            .map((recipient) => ({
                sender,
                recipient,
                exnSaid: `E-${sender}-${recipient}`,
                innerExchangeSaid,
            }))
    );
}

function observations(): CredentialSnapshot[] {
    return members.map((observerAid) => ({
        observerAid,
        said: 'ECredential',
        issuer: 'EQvi',
        schema: 'ESchema',
        issuee: 'EIssuee',
        registry: 'ERegistry',
        statusSequence: '0',
        priorTelDigest: null,
        currentTelDigest: 'EIssuance',
    }));
}

function issuanceEvidence(): OperationEvidence[] {
    return members.map(() => ({
        name: 'credential.ECredential',
        done: true,
        result: {
            kind: 'credential',
            said: 'ECredential',
            prefix: 'EQvi',
            schema: 'ESchema',
        },
    }));
}

function revokedObservations(): CredentialSnapshot[] {
    return observations().map((snapshot) => ({
        ...snapshot,
        statusSequence: '1',
        priorTelDigest: 'EIssuance',
        currentTelDigest: 'ERevocation',
    }));
}

function revocationEvidence(): OperationEvidence[] {
    return members.map(() => ({
        name: 'group.ERevocationAnchor',
        done: true,
        result: {
            kind: 'event',
            said: 'ERevocationAnchor',
            prefix: 'EQvi',
            sequence: '7',
        },
    }));
}

describe('workflow producer contracts', () => {
    it('accepts and canonicalizes exact directed fan-out', () => {
        const receipts = fanout('EInner').reverse();
        assert.doesNotThrow(() =>
            assertExactDirectedFanout(
                receipts,
                members,
                'test fan-out',
                'EInner'
            )
        );
        assert.deepEqual(
            canonicalReceipts(receipts).map(
                ({sender, recipient}) => `${sender}->${recipient}`
            ),
            [
                'EQar1->EQar2',
                'EQar1->EQar3',
                'EQar2->EQar1',
                'EQar2->EQar3',
                'EQar3->EQar1',
                'EQar3->EQar2',
            ]
        );
    });

    it('rejects missing, duplicate, and misdirected fan-out', () => {
        const exact = fanout('EInner');
        const fixtures = [
            exact.slice(1),
            [...exact.slice(1), exact[1]],
            [
                ...exact.slice(1),
                {...exact[0], recipient: 'EOutsider'},
            ],
        ];
        for (const fixture of fixtures) {
            assert.throws(
                () =>
                    assertExactDirectedFanout(
                        fixture,
                        members,
                        'test fan-out',
                        'EInner'
                    ),
                /exact directed member fan-out/
            );
        }
    });

    it('rejects wrong terminal operation identity', () => {
        assert.throws(
            () =>
                assertTerminalOperationEvidence(
                    [
                        {
                            name: 'credential.EWrong',
                            done: true,
                            result: {
                                kind: 'credential',
                                said: 'EWrong',
                            },
                        },
                    ],
                    [
                        {
                            name: 'credential.ECredential',
                            result: {
                                kind: 'credential',
                                said: 'ECredential',
                            },
                        },
                    ],
                    'credential issuance'
                ),
            /does not match expected/
        );
    });

    it('accepts exact issuance identity, TEL state, operations, and fan-out', () => {
        assert.doesNotThrow(() =>
            assertIssuanceContract(
                {
                    observations: observations(),
                    operationEvidence: issuanceEvidence(),
                    issuanceReceipts: fanout('EIssuance'),
                    coordinationReceipts: fanout('EGrant'),
                },
                members,
                {
                    issuer: 'EQvi',
                    schema: 'ESchema',
                    issuee: 'EIssuee',
                },
                'OOR credential'
            )
        );
    });

    it('rejects divergent issuance identity, TEL state, and operations', () => {
        const wrongIdentity = observations();
        wrongIdentity[2] = {
            ...wrongIdentity[2],
            schema: 'EWrongSchema',
        };
        assert.throws(
            () =>
                assertIssuanceContract(
                    {
                        observations: wrongIdentity,
                        operationEvidence: issuanceEvidence(),
                        issuanceReceipts: fanout('EIssuance'),
                        coordinationReceipts: fanout('EGrant'),
                    },
                    members,
                    {
                        issuer: 'EQvi',
                        schema: 'ESchema',
                        issuee: 'EIssuee',
                    },
                    'OOR credential'
                ),
            /identity or TEL state diverged/
        );

        const wrongEvidence = issuanceEvidence();
        wrongEvidence[1] = {
            ...wrongEvidence[1],
            result: {
                ...wrongEvidence[1].result,
                schema: 'EWrongSchema',
            },
        };
        assert.throws(
            () =>
                assertIssuanceContract(
                    {
                        observations: observations(),
                        operationEvidence: wrongEvidence,
                        issuanceReceipts: fanout('EIssuance'),
                        coordinationReceipts: fanout('EGrant'),
                    },
                    members,
                    {
                        issuer: 'EQvi',
                        schema: 'ESchema',
                        issuee: 'EIssuee',
                    },
                    'OOR credential'
                ),
            /has schema EWrongSchema/
        );
    });

    it('accepts one linked three-member revocation transition', () => {
        assert.doesNotThrow(() =>
            assertRevocationContract(
                {
                    status: 'revoked',
                    credentialSaid: 'ECredential',
                    qviPrefix: 'EQvi',
                    operationNames: revocationEvidence().map(
                        ({name}) => name
                    ),
                    operationEvidence: revocationEvidence(),
                    before: observations(),
                    after: revokedObservations(),
                    revocationTelDigest: 'ERevocation',
                    revocationTimestamp:
                        '2026-07-24T12:00:00Z',
                    coordinationReceipts:
                        fanout('ERevocation'),
                },
                members,
                {
                    said: 'ECredential',
                    issuer: 'EQvi',
                    schema: 'ESchema',
                    issuee: 'EIssuee',
                }
            )
        );
    });

    it('rejects mixed TEL state and misdirected revocation fan-out', () => {
        const mixedAfter = revokedObservations();
        mixedAfter[2] = {
            ...mixedAfter[2],
            statusSequence: '0',
            priorTelDigest: null,
            currentTelDigest: 'EIssuance',
        };
        const base = {
            status: 'revoked' as const,
            credentialSaid: 'ECredential',
            qviPrefix: 'EQvi',
            operationNames: revocationEvidence().map(
                ({name}) => name
            ),
            operationEvidence: revocationEvidence(),
            before: observations(),
            after: mixedAfter,
            revocationTelDigest: 'ERevocation',
            revocationTimestamp: '2026-07-24T12:00:00Z',
            coordinationReceipts: fanout('ERevocation'),
        };
        assert.throws(
            () =>
                assertRevocationContract(
                    base,
                    members,
                    {
                        said: 'ECredential',
                        issuer: 'EQvi',
                        schema: 'ESchema',
                        issuee: 'EIssuee',
                    }
                ),
            /TEL state diverged/
        );

        const misdirected = fanout('ERevocation');
        misdirected[0] = {
            ...misdirected[0],
            recipient: 'EOutsider',
        };
        assert.throws(
            () =>
                assertRevocationContract(
                    {
                        ...base,
                        after: revokedObservations(),
                        coordinationReceipts: misdirected,
                    },
                    members,
                    {
                        said: 'ECredential',
                        issuer: 'EQvi',
                        schema: 'ESchema',
                        issuee: 'EIssuee',
                    }
                ),
            /exact directed member fan-out/
        );
    });
});
