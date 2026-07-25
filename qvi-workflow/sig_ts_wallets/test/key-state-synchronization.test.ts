import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {HabState, SignifyClient} from 'signify-ts';

import {refreshSubjectsForObserver} from '../src/sig-wallet.ts';

interface TestWallet {
    role: 'qar1' | 'qar2' | 'qar3';
    aid: HabState;
    client: SignifyClient;
}

function aid(prefix: string, sequence = '0'): HabState {
    return {
        name: prefix,
        prefix,
        state: {s: sequence},
    } as HabState;
}

function wallet(
    role: TestWallet['role'],
    prefix: string,
    query: (prefix: string, sequence?: string) => Promise<unknown>
): TestWallet {
    return {
        role,
        aid: aid(prefix),
        client: {
            keyStates: () => ({query}),
        } as unknown as SignifyClient,
    };
}

function completedOperation(name: string) {
    return {
        name,
        done: true,
        error: null,
        response: {},
    };
}

describe('observer key-state synchronization', () => {
    it('skips self, serializes each observer, overlaps observers, and counts exactly', async () => {
        let globallyActive = 0;
        let maximumGloballyActive = 0;
        const activeByObserver = new Map<string, number>();
        const maximumByObserver = new Map<string, number>();
        const queried = new Map<string, string[]>();

        function queryFor(observer: string) {
            return async (subject: string) => {
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
                return completedOperation(`${observer}-${subject}`);
            };
        }

        const qar1 = wallet('qar1', 'E-qar1', queryFor('E-qar1'));
        const qar2 = wallet('qar2', 'E-qar2', queryFor('E-qar2'));
        const qar3 = wallet('qar3', 'E-qar3', async () => {
            throw new Error('subject clients are not queried');
        });
        const subjects = [qar1, qar2, qar3];

        const counts = await Promise.all([
            refreshSubjectsForObserver(qar1, subjects),
            refreshSubjectsForObserver(qar2, subjects),
        ]);

        assert.deepEqual(counts, [2, 2]);
        assert.deepEqual(queried.get('E-qar1'), ['E-qar2', 'E-qar3']);
        assert.deepEqual(queried.get('E-qar2'), ['E-qar1', 'E-qar3']);
        assert.equal(maximumByObserver.get('E-qar1'), 1);
        assert.equal(maximumByObserver.get('E-qar2'), 1);
        assert.ok(maximumGloballyActive >= 2);
    });
});
