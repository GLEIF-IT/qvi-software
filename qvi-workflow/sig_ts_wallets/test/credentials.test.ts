import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    CompletedOperation,
    CredentialResult,
    ExchangeResourceV1,
    SignifyClient,
} from 'signify-ts';

import {admitSinglesig} from '../src/credentials.ts';
import type {Notification} from '../src/notifications.ts';

const AID_NAME = 'person';
const HOLDER_PREFIX = 'EHolder';
const ISSUER_PREFIX = 'EIssuer';
const CREDENTIAL_SAID = 'ECredential';
const GRANT_SAID = 'EGrant';
const ADMIT_OPERATION_NAME = 'exchange.EAdmit';

type OperationOutcome = 'completed' | 'failed';
type CredentialAvailability = 'available' | 'missing';

interface AdmissionHarnessOptions {
    deliveryCount?: number;
    operationOutcome?: OperationOutcome;
    credentialAvailability?: CredentialAvailability;
}

interface SubmitAdmitCall {
    aidName: string;
    recipients: string[];
}

interface AdmissionTrace {
    events: string[];
    marked: string[];
    deleted: string[];
    submitAdmitCalls: SubmitAdmitCall[];
    credentialLookups: number;
}

interface AdmissionHarness {
    client: SignifyClient;
    credential: CredentialResult;
    deliveryIds: string[];
    trace: AdmissionTrace;
}

function grantExchange(): ExchangeResourceV1 {
    return {
        exn: {
            v: 'KERI10JSON000000_',
            t: 'exn',
            d: GRANT_SAID,
            i: ISSUER_PREFIX,
            rp: HOLDER_PREFIX,
            p: '',
            dt: '2026-01-01T00:00:00.000000+00:00',
            r: '/ipex/grant',
            q: {},
            a: {
                i: HOLDER_PREFIX,
            },
            e: {
                acdc: {
                    d: CREDENTIAL_SAID,
                },
            },
        },
        pathed: {},
    };
}

function grantNotification(index: number): Notification {
    return {
        i: `N${index}`,
        dt: '2026-01-01T00:00:00.000000+00:00',
        r: false,
        a: {
            r: '/exn/ipex/grant',
            d: GRANT_SAID,
        },
    };
}

function admissionHarness({
    deliveryCount = 1,
    operationOutcome = 'completed',
    credentialAvailability = 'available',
}: AdmissionHarnessOptions = {}): AdmissionHarness {
    const notifications = Array.from(
        {length: deliveryCount},
        (_, index) => grantNotification(index + 1)
    );
    const credential = {
        sad: {
            d: CREDENTIAL_SAID,
            i: ISSUER_PREFIX,
            s: 'ESchema',
            a: {
                i: HOLDER_PREFIX,
            },
        },
    } as unknown as CredentialResult;
    const trace: AdmissionTrace = {
        events: [],
        marked: [],
        deleted: [],
        submitAdmitCalls: [],
        credentialLookups: 0,
    };
    const pendingOperation = {
        name: ADMIT_OPERATION_NAME,
        done: false,
    };
    const completedOperation = {
        name: ADMIT_OPERATION_NAME,
        done: true,
        response: {
            d: 'EAdmit',
        },
    } as CompletedOperation;
    const failedOperation = {
        name: ADMIT_OPERATION_NAME,
        done: true,
        error: {
            code: 500,
            message: 'admit processing failed',
        },
    };

    const client = {
        identifiers: () => ({
            get: async () => ({
                name: AID_NAME,
                prefix: HOLDER_PREFIX,
            }),
        }),
        notifications: () => ({
            list: async (start = 0, end = 24) => ({
                start,
                end: Math.min(end, notifications.length - 1),
                total: notifications.length,
                notes: notifications.slice(start, end + 1),
            }),
            mark: async (notificationId: string) => {
                trace.events.push(`marked:${notificationId}`);
                trace.marked.push(notificationId);
                return notificationId;
            },
            delete: async (notificationId: string) => {
                trace.events.push(`deleted:${notificationId}`);
                trace.deleted.push(notificationId);
            },
        }),
        exchanges: () => ({
            get: async () => grantExchange(),
        }),
        ipex: () => ({
            admit: async () => [{said: 'EAdmit'}, ['signature'], '-AAB'],
            submitAdmit: async (
                aidName: string,
                _admit: unknown,
                _signatures: string[],
                _attachment: string,
                recipients: string[]
            ) => {
                trace.events.push('admit-submitted');
                trace.submitAdmitCalls.push({aidName, recipients});
                return pendingOperation;
            },
        }),
        operations: () => ({
            wait: async () => {
                const operationCompleted =
                    operationOutcome === 'completed';
                if (operationCompleted) {
                    trace.events.push('operation-completed');
                    return completedOperation;
                }

                trace.events.push('operation-failed');
                return failedOperation;
            },
        }),
        credentials: () => ({
            list: async () => {
                trace.credentialLookups += 1;
                const credentialIsAvailable =
                    credentialAvailability === 'available';
                if (credentialIsAvailable) {
                    trace.events.push('credential-materialized');
                    return [credential];
                }

                trace.events.push('credential-missing');
                return [];
            },
        }),
    } as unknown as SignifyClient;

    return {
        client,
        credential,
        deliveryIds: notifications.map((note) => note.i),
        trace,
    };
}

describe('single-signature credential admission', () => {
    it('submits one admit for three delivery rows naming the same grant', async () => {
        const harness = admissionHarness({deliveryCount: 3});

        const credential = await admitSinglesig(
            harness.client,
            AID_NAME,
            ISSUER_PREFIX,
            CREDENTIAL_SAID
        );

        assert.equal(credential, harness.credential);
        assert.deepEqual(harness.trace.submitAdmitCalls, [
            {
                aidName: AID_NAME,
                recipients: [ISSUER_PREFIX],
            },
        ]);
        assert.deepEqual(
            harness.trace.marked,
            harness.deliveryIds
        );
        assert.deepEqual(
            harness.trace.deleted,
            harness.deliveryIds
        );

        const operationCompletedAt =
            harness.trace.events.indexOf('operation-completed');
        const credentialMaterializedAt =
            harness.trace.events.indexOf('credential-materialized');
        const firstConsumptionAt = harness.trace.events.findIndex(
            (event) =>
                event.startsWith('marked:') ||
                event.startsWith('deleted:')
        );
        const operationCompletedBeforeConsumption =
            operationCompletedAt >= 0 &&
            operationCompletedAt < firstConsumptionAt;
        const credentialMaterializedBeforeConsumption =
            credentialMaterializedAt >= 0 &&
            credentialMaterializedAt < firstConsumptionAt;

        assert.equal(operationCompletedBeforeConsumption, true);
        assert.equal(credentialMaterializedBeforeConsumption, true);
    });

    it('retains every delivery row when the admit operation fails', async () => {
        const harness = admissionHarness({
            deliveryCount: 3,
            operationOutcome: 'failed',
        });

        await assert.rejects(
            admitSinglesig(
                harness.client,
                AID_NAME,
                ISSUER_PREFIX,
                CREDENTIAL_SAID
            ),
            /admit processing failed/
        );

        const notificationWasConsumed =
            harness.trace.marked.length > 0 ||
            harness.trace.deleted.length > 0;
        assert.equal(notificationWasConsumed, false);
        assert.equal(harness.trace.credentialLookups, 0);
        assert.equal(harness.trace.submitAdmitCalls.length, 1);
    });

    it('retains every delivery row when credential materialization times out', async () => {
        const previousTimeout =
            process.env.QVI_OPERATION_TIMEOUT_SECONDS;
        process.env.QVI_OPERATION_TIMEOUT_SECONDS = '1';
        const harness = admissionHarness({
            deliveryCount: 3,
            credentialAvailability: 'missing',
        });

        try {
            await assert.rejects(
                admitSinglesig(
                    harness.client,
                    AID_NAME,
                    ISSUER_PREFIX,
                    CREDENTIAL_SAID
                ),
                /Credential ECredential has not been received/
            );
        } finally {
            if (previousTimeout === undefined) {
                delete process.env.QVI_OPERATION_TIMEOUT_SECONDS;
            } else {
                process.env.QVI_OPERATION_TIMEOUT_SECONDS =
                    previousTimeout;
            }
        }

        const operationDidComplete =
            harness.trace.events.includes('operation-completed');
        const credentialLookupWasRetried =
            harness.trace.credentialLookups > 1;
        const notificationWasConsumed =
            harness.trace.marked.length > 0 ||
            harness.trace.deleted.length > 0;
        assert.equal(operationDidComplete, true);
        assert.equal(credentialLookupWasRetried, true);
        assert.equal(notificationWasConsumed, false);
    });

    it('continues to admit and consume one ordinary delivery row', async () => {
        const harness = admissionHarness();

        const credential = await admitSinglesig(
            harness.client,
            AID_NAME,
            ISSUER_PREFIX,
            CREDENTIAL_SAID
        );

        assert.equal(credential, harness.credential);
        assert.equal(harness.trace.submitAdmitCalls.length, 1);
        assert.deepEqual(harness.trace.marked, ['N1']);
        assert.deepEqual(harness.trace.deleted, ['N1']);
    });
});
