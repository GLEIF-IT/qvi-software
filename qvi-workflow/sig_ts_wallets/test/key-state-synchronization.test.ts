import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    CompletedOOBIOperation,
    Operation,
} from 'signify-ts';

import {
    refreshSubjectsForObserver,
    type KeyStateRefreshConfig,
    type KeyStateRefreshWallet,
} from '../src/sig-wallet.ts';

interface TestWallet {
    role: 'qar1' | 'qar2' | 'qar3';
    aid: KeyStateRefreshWallet['aid'];
    client: KeyStateRefreshWallet['client'];
}

function aid(prefix: string, sequence = '0') {
    return {
        prefix,
        state: {i: prefix, s: sequence, d: `${prefix}-${sequence}`},
    };
}

function wallet(
    role: TestWallet['role'],
    prefix: string,
    resolve: (oobi: string) => Promise<Operation>
): TestWallet {
    return {
        role,
        aid: aid(prefix),
        client: {
            oobis: () => ({resolve}),
            operations: () => ({
                get: async () => {
                    throw new Error('unexpected operation lookup');
                },
                wait: async () => {
                    throw new Error('unexpected operation wait');
                },
            }),
        },
    };
}

function completedOperation(
    name: string,
    prefix: string
): CompletedOOBIOperation {
    const digest = `${prefix}-0`;
    return {
        name,
        done: true,
        response: {
            i: prefix,
            s: '0',
            p: '',
            d: digest,
            f: '0',
            dt: '2026-01-01T00:00:00.000000+00:00',
            et: 'icp',
            kt: '1',
            k: [],
            nt: '1',
            n: [],
            bt: '0',
            b: [],
            c: [],
            ee: {s: '0', d: digest},
            di: '',
        },
    };
}

describe('observer key-state synchronization', () => {
    it('skips self, serializes each observer, overlaps observers, and counts exactly', async () => {
        const config: KeyStateRefreshConfig = {
            participants: {
                qar1: {oobiUrl: 'http://127.0.0.1:3901'},
                qar2: {oobiUrl: 'http://127.0.0.1:3902'},
                qar3: {oobiUrl: 'http://127.0.0.1:3903'},
                qar4: {oobiUrl: 'http://127.0.0.1:6903'},
                person: {oobiUrl: 'http://127.0.0.1:7903'},
            },
        };
        let globallyActive = 0;
        let maximumGloballyActive = 0;
        const activeByObserver = new Map<string, number>();
        const maximumByObserver = new Map<string, number>();
        const queried = new Map<string, string[]>();

        function resolveFor(observer: string) {
            return async (oobi: string): Promise<Operation> => {
                const subject = new URL(oobi).pathname.split('/').at(-1);
                assert.ok(subject);
                const observerActive =
                    (activeByObserver.get(observer) ?? 0) + 1;
                activeByObserver.set(observer, observerActive);
                maximumByObserver.set(
                    observer,
                    Math.max(
                        maximumByObserver.get(observer) ?? 0,
                        observerActive
                    )
                );
                globallyActive += 1;
                maximumGloballyActive = Math.max(
                    maximumGloballyActive,
                    globallyActive
                );
                queried.set(observer, [
                    ...(queried.get(observer) ?? []),
                    subject,
                ]);

                await new Promise((resolve) => setTimeout(resolve, 10));

                activeByObserver.set(observer, observerActive - 1);
                globallyActive -= 1;
                return completedOperation(
                    `${observer}-${subject}`,
                    subject
                );
            };
        }

        const qar1 = wallet('qar1', 'E-qar1', resolveFor('E-qar1'));
        const qar2 = wallet('qar2', 'E-qar2', resolveFor('E-qar2'));
        const qar3 = wallet('qar3', 'E-qar3', async () => {
            throw new Error('subject clients are not queried');
        });
        const subjects = [qar1, qar2, qar3];

        const counts = await Promise.all([
            refreshSubjectsForObserver(config, qar1, subjects),
            refreshSubjectsForObserver(config, qar2, subjects),
        ]);

        assert.deepEqual(counts, [2, 2]);
        assert.deepEqual(queried.get('E-qar1'), ['E-qar2', 'E-qar3']);
        assert.deepEqual(queried.get('E-qar2'), ['E-qar1', 'E-qar3']);
        assert.equal(maximumByObserver.get('E-qar1'), 1);
        assert.equal(maximumByObserver.get('E-qar2'), 1);
        assert.ok(maximumGloballyActive >= 2);
    });
});
