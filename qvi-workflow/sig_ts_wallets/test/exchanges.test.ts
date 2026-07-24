import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {HabState, Serder} from 'signify-ts';

import {
    sendExchangeToEachRecipient,
    type ExchangeClient,
} from '../src/exchanges.ts';

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
        const client: ExchangeClient = {
            exchanges: () => ({
                createExchangeMessage: async (
                    _sender,
                    _route,
                    _payload,
                    _embeds,
                    recipient
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
                    _name,
                    _topic,
                    _exn,
                    _signatures,
                    _attachment,
                    recipients
                ) => {
                    transmitted.push(recipients);
                    return {};
                },
            }),
        };

        const receipts = await sendExchangeToEachRecipient(client, {
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
        assert.deepEqual(receipts, [
            {recipient: 'E2', exnSaid: 'EE2'},
            {recipient: 'E3', exnSaid: 'EE3'},
        ]);
    });

    it('rejects an empty recipient set before creating an EXN', async () => {
        const client = {
            exchanges: () => {
                throw new Error('must not be called');
            },
        } as ExchangeClient;

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
        const client: ExchangeClient = {
            exchanges: () => ({
                createExchangeMessage: async (
                    _sender,
                    _route,
                    _payload,
                    _embeds,
                    recipient
                ) => [
                    {said: `E${recipient}`} as Serder,
                    [],
                    '',
                ],
                sendFromEvents: async (
                    _name,
                    _topic,
                    _exn,
                    _signatures,
                    _attachment,
                    recipients
                ) => {
                    if (recipients[0] === 'E3') {
                        throw new Error('offline');
                    }
                    return {};
                },
            }),
        };

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
