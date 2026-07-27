import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
    consumeNotifications,
    listAllNotifications,
    waitForMatchingNotification,
    type Exchange,
    type Notification,
} from '../src/notifications.ts';

interface ExchangeFixture {
    said: string;
    sender: string;
    embeddedDigest: string;
    recipient?: string;
    groupPrefix?: string;
    credentialSaid?: string;
    route?: string;
}

function exchange({
    said,
    sender,
    embeddedDigest,
    recipient = 'EFollower',
    groupPrefix = 'EGroup',
    credentialSaid = 'ECredential',
    route = '/multisig/rev',
}: ExchangeFixture): Exchange {
    return {
        exn: {
            v: 'KERI10JSON000000_',
            t: 'exn',
            d: said,
            i: sender,
            rp: recipient,
            p: '',
            dt: '2026-01-01T00:00:00.000000+00:00',
            r: route,
            q: {},
            a: {
                gid: groupPrefix,
                credentialSaid,
            },
            e: {
                rev: {
                    d: embeddedDigest,
                    i: credentialSaid,
                },
            },
        },
        pathed: {},
    };
}

function notification(
    index: number,
    exchangeSaid?: string
): Notification {
    return {
        i: `N${index}`,
        dt: '2026-01-01T00:00:00.000000+00:00',
        r: false,
        a: {
            r: '/multisig/rev',
            d: exchangeSaid,
        },
    };
}

function ipexGrant(
    recipient: string,
    routedRecipient = ''
): Exchange {
    const grant = exchange({
        said: 'EGrant',
        sender: 'EIssuer',
        embeddedDigest: 'EUnused',
        recipient: routedRecipient,
        credentialSaid: 'ECredential',
        route: '/ipex/grant',
    });
    grant.exn.a = {
        i: recipient,
    };
    grant.exn.e = {
        acdc: {
            d: 'ECredential',
        },
    };
    return grant;
}

function clientFor(
    notes: Notification[],
    exchanges: Map<string, Exchange>
) {
    const marked: string[] = [];
    const deleted: string[] = [];
    return {
        marked,
        deleted,
        notifications: () => ({
            list: async (start = 0, end = 24) => ({
                start,
                end: Math.min(end, notes.length - 1),
                total: notes.length,
                notes: notes.slice(start, end + 1),
            }),
            mark: async (said: string) => {
                marked.push(said);
                return said;
            },
            delete: async (said: string) => {
                deleted.push(said);
            },
        }),
        exchanges: () => ({
            get: async (said: string) => {
                const found = exchanges.get(said);
                if (found === undefined) {
                    throw new Error(`missing ${said}`);
                }
                return found;
            },
        }),
    };
}

describe('notification correlation', () => {
    it('polls delayed local notifications without exponential overshoot', async () => {
        const expectedNote = notification(1, 'EDelayed');
        const expectedExchange = exchange({
            said: 'EDelayed',
            sender: 'EInitiator',
            embeddedDigest: 'ECurrentRev',
        });
        let listCalls = 0;
        const client = {
            notifications: () => ({
                list: async () => {
                    listCalls += 1;
                    const notes = listCalls < 5
                        ? []
                        : [expectedNote];
                    return {
                        start: 0,
                        end: Math.max(0, notes.length - 1),
                        total: notes.length,
                        notes,
                    };
                },
                mark: async (said: string) => said,
                delete: async () => undefined,
            }),
            exchanges: () => ({
                get: async () => expectedExchange,
            }),
        };
        const startedAt = performance.now();

        const matched = await waitForMatchingNotification(
            client,
            {
                exchangeRoute: '/multisig/rev',
                sender: 'EInitiator',
                embeddedDigest: 'ECurrentRev',
            }
        );

        assert.equal(matched.said, 'EDelayed');
        assert.equal(listCalls, 5);
        assert.ok(performance.now() - startedAt < 500);
    });

    it('paginates beyond 25 entries and ignores stale same-route traffic', async () => {
        const notes = Array.from({length: 27}, (_, index) =>
            notification(index, `E${index}`)
        );
        const exchanges = new Map(
            notes.map((note, index) => {
                const isCurrentExchange = index === 26;
                return [
                    note.a.d as string,
                    exchange({
                        said: note.a.d as string,
                        sender: isCurrentExchange
                            ? 'EInitiator'
                            : 'EStaleSender',
                        embeddedDigest: isCurrentExchange
                            ? 'ECurrentRev'
                            : 'EStaleRev',
                    }),
                ];
            })
        );
        const client = clientFor(notes, exchanges);

        const listed = await listAllNotifications(client, 25);
        assert.equal(listed.length, 27);

        const matched = await waitForMatchingNotification(
            client,
            {
                exchangeRoute: '/multisig/rev',
                sender: 'EInitiator',
                recipient: 'EFollower',
                groupPrefix: 'EGroup',
                credentialSaid: 'ECredential',
                embeddedDigest: 'ECurrentRev',
            },
            {timeout: 100, maxRetries: 1}
        );
        assert.deepEqual(matched.notificationIds, ['N26']);
        assert.deepEqual(client.marked, []);
        assert.deepEqual(client.deleted, []);

        await consumeNotifications(client, matched.notificationIds);
        assert.deepEqual(client.marked, ['N26']);
        assert.deepEqual(client.deleted, ['N26']);
    });

    it('selects only the designated coordinator when two senders are valid', async () => {
        const notes = [
            notification(1, 'EFromInitiator'),
            notification(2, 'EFromPeer'),
        ];
        const exchanges = new Map([
            [
                'EFromInitiator',
                exchange({
                    said: 'EFromInitiator',
                    sender: 'EInitiator',
                    embeddedDigest: 'ECurrentRev',
                }),
            ],
            [
                'EFromPeer',
                exchange({
                    said: 'EFromPeer',
                    sender: 'EPeer',
                    embeddedDigest: 'ECurrentRev',
                }),
            ],
        ]);
        const client = clientFor(notes, exchanges);

        const matched = await waitForMatchingNotification(
            client,
            {
                exchangeRoute: '/multisig/rev',
                sender: 'EInitiator',
                recipient: 'EFollower',
                groupPrefix: 'EGroup',
                embeddedDigest: 'ECurrentRev',
            },
            {timeout: 100, maxRetries: 1}
        );
        assert.equal(matched.said, 'EFromInitiator');
    });

    it('ignores same-route noise that differs in any exact correlation field', async () => {
        const fixtures: ExchangeFixture[] = [
            {
                said: 'EWrongSender',
                sender: 'EPeer',
                embeddedDigest: 'ECurrentRev',
            },
            {
                said: 'EWrongRecipient',
                sender: 'EInitiator',
                recipient: 'EAnotherFollower',
                embeddedDigest: 'ECurrentRev',
            },
            {
                said: 'EWrongGroup',
                sender: 'EInitiator',
                groupPrefix: 'EAnotherGroup',
                embeddedDigest: 'ECurrentRev',
            },
            {
                said: 'EWrongCredential',
                sender: 'EInitiator',
                credentialSaid: 'EAnotherCredential',
                embeddedDigest: 'ECurrentRev',
            },
            {
                said: 'EWrongDigest',
                sender: 'EInitiator',
                embeddedDigest: 'EAnotherRev',
            },
            {
                said: 'EWrongRoute',
                sender: 'EInitiator',
                embeddedDigest: 'ECurrentRev',
                route: '/multisig/iss',
            },
            {
                said: 'ETarget',
                sender: 'EInitiator',
                embeddedDigest: 'ECurrentRev',
            },
        ];
        const notes = fixtures.map((fixture, index) =>
            notification(index, fixture.said)
        );
        const exchanges = new Map(
            fixtures.map((fixture) => [
                fixture.said,
                exchange(fixture),
            ])
        );
        const client = clientFor(notes, exchanges);

        const matched = await waitForMatchingNotification(
            client,
            {
                exchangeRoute: '/multisig/rev',
                sender: 'EInitiator',
                recipient: 'EFollower',
                groupPrefix: 'EGroup',
                credentialSaid: 'ECredential',
                embeddedDigest: 'ECurrentRev',
            },
            {timeout: 100, maxRetries: 1}
        );

        assert.equal(matched.said, 'ETarget');
        assert.deepEqual(client.marked, []);
        assert.deepEqual(client.deleted, []);
    });

    it('uses the embedded revocation credential SAID instead of a payload claim', async () => {
        const misleading = exchange({
            said: 'EMisleading',
            sender: 'EInitiator',
            embeddedDigest: 'ECurrentRev',
            credentialSaid: 'EEmbeddedCredential',
        });
        misleading.exn.a = {
            gid: 'EGroup',
            credentialSaid: 'ECredential',
        };
        const client = clientFor(
            [notification(1, 'EMisleading')],
            new Map([['EMisleading', misleading]])
        );

        await assert.rejects(
            waitForMatchingNotification(
                client,
                {
                    exchangeRoute: '/multisig/rev',
                    sender: 'EInitiator',
                    recipient: 'EFollower',
                    groupPrefix: 'EGroup',
                    credentialSaid: 'ECredential',
                    embeddedDigest: 'ECurrentRev',
                },
                {timeout: 100, maxRetries: 1}
            ),
            /No correlated notification/
        );
    });

    it('matches a KERIpy IPEX grant recipient from a.i when rp is empty', async () => {
        const note = notification(1, 'EGrant');
        note.a.r = '/exn/ipex/grant';
        const client = clientFor(
            [note],
            new Map([['EGrant', ipexGrant('EGroup')]])
        );

        const matched = await waitForMatchingNotification(
            client,
            {
                notificationRoute: '/exn/ipex/grant',
                exchangeRoute: '/ipex/grant',
                sender: 'EIssuer',
                recipient: 'EGroup',
                credentialSaid: 'ECredential',
            },
            {timeout: 100, maxRetries: 1}
        );

        assert.equal(matched.said, 'EGrant');
    });

    it('treats duplicate notification records for one EXN as one logical grant', async () => {
        const notes = [1, 2, 3].map((index) => {
            const note = notification(index, 'EGrant');
            note.a.r = '/exn/ipex/grant';
            return note;
        });
        const client = clientFor(
            notes,
            new Map([['EGrant', ipexGrant('EGroup')]])
        );

        const matched = await waitForMatchingNotification(
            client,
            {
                notificationRoute: '/exn/ipex/grant',
                exchangeRoute: '/ipex/grant',
                sender: 'EIssuer',
                recipient: 'EGroup',
                credentialSaid: 'ECredential',
            },
            {timeout: 100, maxRetries: 1}
        );

        assert.equal(matched.said, 'EGrant');
        assert.deepEqual(matched.notificationIds, ['N1', 'N2', 'N3']);
        await consumeNotifications(client, matched.notificationIds);
        assert.deepEqual(client.marked, ['N1', 'N2', 'N3']);
        assert.deepEqual(client.deleted, ['N1', 'N2', 'N3']);
    });

    it('rejects distinct matching EXNs as ambiguous', async () => {
        const firstNote = notification(1, 'EGrantOne');
        firstNote.a.r = '/exn/ipex/grant';
        const secondNote = notification(2, 'EGrantTwo');
        secondNote.a.r = '/exn/ipex/grant';
        const firstGrant = ipexGrant('EGroup');
        firstGrant.exn.d = 'EGrantOne';
        const secondGrant = ipexGrant('EGroup');
        secondGrant.exn.d = 'EGrantTwo';
        const client = clientFor(
            [firstNote, secondNote],
            new Map([
                ['EGrantOne', firstGrant],
                ['EGrantTwo', secondGrant],
            ])
        );

        await assert.rejects(
            waitForMatchingNotification(
                client,
                {
                    notificationRoute: '/exn/ipex/grant',
                    exchangeRoute: '/ipex/grant',
                    sender: 'EIssuer',
                    recipient: 'EGroup',
                    credentialSaid: 'ECredential',
                },
                {timeout: 100, maxRetries: 1}
            ),
            /Found 2 correlated notifications/
        );
    });

    it('rejects a notification whose fetched EXN has a different SAID', async () => {
        const note = notification(1, 'ELookupSaid');
        note.a.r = '/exn/ipex/grant';
        const mismatchedGrant = ipexGrant('EGroup');
        mismatchedGrant.exn.d = 'EContentSaid';
        const client = clientFor(
            [note],
            new Map([['ELookupSaid', mismatchedGrant]])
        );

        await assert.rejects(
            waitForMatchingNotification(
                client,
                {
                    notificationRoute: '/exn/ipex/grant',
                    exchangeRoute: '/ipex/grant',
                    sender: 'EIssuer',
                    recipient: 'EGroup',
                    credentialSaid: 'ECredential',
                },
                {timeout: 100, maxRetries: 1}
            ),
            /resolved to EContentSaid/
        );
    });

    it('does not replace a nonempty rp with the IPEX payload recipient', async () => {
        const note = notification(1, 'EGrant');
        note.a.r = '/exn/ipex/grant';
        const client = clientFor(
            [note],
            new Map([
                ['EGrant', ipexGrant('EGroup', 'EWrongRecipient')],
            ])
        );

        await assert.rejects(
            waitForMatchingNotification(
                client,
                {
                    notificationRoute: '/exn/ipex/grant',
                    exchangeRoute: '/ipex/grant',
                    sender: 'EIssuer',
                    recipient: 'EGroup',
                    credentialSaid: 'ECredential',
                },
                {timeout: 100, maxRetries: 1}
            ),
            /No correlated notification/
        );
    });

    it('fails when a matching-route notification has no EXN SAID', async () => {
        const client = clientFor([notification(1)], new Map());
        await assert.rejects(
            waitForMatchingNotification(
                client,
                {
                    exchangeRoute: '/multisig/rev',
                    sender: 'EInitiator',
                },
                {timeout: 100, maxRetries: 1}
            ),
            /has no exchange SAID/
        );
    });

    it('does not delete evidence when marking fails', async () => {
        const deleted: string[] = [];
        const client = {
            notifications: () => ({
                list: async () => ({
                    start: 0,
                    end: 0,
                    total: 0,
                    notes: [],
                }),
                mark: async () => {
                    throw new Error('mark failed');
                },
                delete: async (said: string) => {
                    deleted.push(said);
                },
            }),
            exchanges: () => ({
                get: async () => {
                    throw new Error('unused');
                },
            }),
        };

        await assert.rejects(
            consumeNotifications(client, ['N1', 'N2']),
            /mark failed/
        );
        assert.deepEqual(deleted, []);
    });
});
