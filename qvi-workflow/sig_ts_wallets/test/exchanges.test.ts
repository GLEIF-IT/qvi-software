import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {
    Dict,
    HabState,
    Serder,
} from 'signify-ts';

import {sendExchangeToEachRecipient} from '../src/exchanges.ts';
import {testSignifyClient} from './test-signify-client.ts';

function sender(): HabState {
    return {
        name: 'member',
        prefix: 'EMember',
    } as HabState;
}

describe('sendExchangeToEachRecipient', () => {
    it('creates and transmits one recipient-bound EXN per unique recipient', async () => {
        const created: string[] = [];
        const transmitted: string[][] = [];
        const client = testSignifyClient({
            exchanges: () => ({
                createExchangeMessage: async (
                    _sender: HabState,
                    _route: string,
                    _payload: Dict<unknown>,
                    _embeds: Dict<unknown>,
                    recipient: string
                ) => {
                    created.push(recipient);
                    return [
                        {
                            said: `E${recipient}`,
                        } as Serder,
                        [`sig-${recipient}`],
                        `atc-${recipient}`,
                    ];
                },
                sendFromEvents: async (
                    _name: string,
                    _topic: string,
                    _exn: Serder,
                    _signatures: string[],
                    _attachment: string,
                    recipients: string[]
                ) => {
                    transmitted.push(recipients);
                    return {};
                },
            }),
        });

        await sendExchangeToEachRecipient(client, {
            name: 'member',
            topic: 'multisig',
            sender: sender(),
            route: '/multisig/rev',
            payload: {},
            embeds: {},
            recipients: ['E2', 'E3', 'E2'],
        });

        assert.deepEqual(created, ['E2', 'E3']);
        assert.deepEqual(transmitted, [['E2'], ['E3']]);
    });

    it('rejects an empty recipient set before creating an EXN', async () => {
        const client = testSignifyClient({
            exchanges: () => {
                throw new Error('must not be called');
            },
        });

        await assert.rejects(
            sendExchangeToEachRecipient(client, {
                name: 'member',
                topic: 'multisig',
                sender: sender(),
                route: '/multisig/rev',
                payload: {},
                embeds: {},
                recipients: [],
            }),
            /recipient list is empty/
        );
    });

    it('reports the exact recipient when fan-out partially fails', async () => {
        const client = testSignifyClient({
            exchanges: () => ({
                createExchangeMessage: async (
                    _sender: HabState,
                    _route: string,
                    _payload: Dict<unknown>,
                    _embeds: Dict<unknown>,
                    recipient: string
                ) => [
                    {said: `E${recipient}`} as Serder,
                    [],
                    '',
                ],
                sendFromEvents: async (
                    _name: string,
                    _topic: string,
                    _exn: Serder,
                    _signatures: string[],
                    _attachment: string,
                    recipients: string[]
                ) => {
                    if (recipients[0] === 'E3') {
                        throw new Error('offline');
                    }
                    return {};
                },
            }),
        });

        await assert.rejects(
            sendExchangeToEachRecipient(client, {
                name: 'member',
                topic: 'multisig',
                sender: sender(),
                route: '/multisig/rev',
                payload: {},
                embeds: {},
                recipients: ['E2', 'E3'],
            }),
            /exchange to E3: offline/
        );
    });
});
