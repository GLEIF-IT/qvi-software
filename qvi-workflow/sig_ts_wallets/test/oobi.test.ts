import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {
    assertQviEndRoles,
} from '../src/assertions.ts';
import {testSignifyClient} from './test-signify-client.ts';

const QVI_PREFIX = 'EQviPrefix';
const AGENT_EIDS = ['EAgentOne', 'EAgentTwo', 'EAgentThree'];
const AGENT_ENDPOINTS = [
    'http://keria1:3902/',
    'http://keria2:3902/',
    'http://keria3:3902/',
];
const AGENT_ENDPOINTS_BY_EID = [
    {eid: 'EAgentOne', url: 'http://keria1:3902/'},
    {eid: 'EAgentThree', url: 'http://keria3:3902/'},
    {eid: 'EAgentTwo', url: 'http://keria2:3902/'},
];
const HISTORICAL_ENDPOINT = {
    eid: 'EHistoricalAgent',
    url: 'http://keria4:3902/',
};

interface AgentClientOptions {
    eid: string;
    enumeratedOobis?: string[];
    authorizedEids?: string[];
    endpointOverrides?: string[];
}

function agentClient({
    eid,
    enumeratedOobis = [qualifiedOobi(AGENT_EIDS[0], 0)],
    authorizedEids = AGENT_EIDS,
    endpointOverrides = AGENT_ENDPOINTS,
}: AgentClientOptions) {
    return testSignifyClient({
        oobis: () => ({
            get: async () => ({oobis: enumeratedOobis}),
            endroles: async () =>
                authorizedEids.map((authorizedEid) => ({
                    cid: QVI_PREFIX,
                    role: 'agent',
                    eid: authorizedEid,
                })),
        }),
        identifiers: () => ({
            members: async () => ({
                signing: AGENT_EIDS.map((agentEid, index) => ({
                    aid: `EMember${index + 1}`,
                    ends: {
                        agent: {
                            [agentEid]: {
                                http: endpointOverrides[index],
                            },
                        },
                    },
                })),
                rotation: [],
            }),
        }),
    });
}

function qualifiedOobi(eid: string, index: number): string {
    return (
        `${AGENT_ENDPOINTS[index]}oobi/` +
        `${QVI_PREFIX}/agent/${eid}`
    );
}

/** Assert endpoint evidence with the deterministic test fixture. */
async function assertOobi(
    clients: ReturnType<typeof agentClient>[],
    expectedEndpoints = AGENT_ENDPOINTS_BY_EID
) {
    return await assertQviEndRoles(
        clients,
        'qvi',
        QVI_PREFIX,
        expectedEndpoints
    );
}

describe('QVI multisig OOBI', () => {
    it('strips the agent suffix from one qualified multisig OOBI', async () => {
        const clients = AGENT_EIDS.map((eid) =>
            agentClient({eid})
        );

        const result = await assertOobi(clients);

        assert.equal(result.qviPrefix, QVI_PREFIX);
        assert.equal(
            result.multisigOobi,
            `${AGENT_ENDPOINTS[0]}oobi/${QVI_PREFIX}`
        );
        assert.deepEqual(
            result.agentEndpoints,
            AGENT_ENDPOINTS_BY_EID
        );
    });

    it('rejects an unexpected OOBI enumerated by KERIA', async () => {
        const clients = AGENT_EIDS.map((eid, index) =>
            agentClient({
                eid,
                enumeratedOobis: [
                    index === 1
                        ? `${qualifiedOobi(eid, index)}/trailing`
                        : qualifiedOobi(AGENT_EIDS[0], 0),
                ],
            })
        );

        await assert.rejects(
            assertOobi(clients),
            /enumerated an unexpected QVI agent OOBI/
        );
    });

    it('rejects missing qualified OOBI enumeration', async () => {
        const clients = AGENT_EIDS.map((eid) =>
            agentClient({eid, enumeratedOobis: []})
        );

        await assert.rejects(
            assertOobi(clients),
            /no qualified QVI agent OOBI to canonicalize/
        );
    });

    it('rejects a missing group end-role authorization', async () => {
        const clients = AGENT_EIDS.map((eid) =>
            agentClient({
                eid,
                authorizedEids: AGENT_EIDS.slice(0, 2),
            })
        );

        await assert.rejects(
            assertOobi(clients),
            /do not observe the exact authorized QVI agent EIDs/
        );
    });

    it('retains a historical authorization outside the signing roster', async () => {
        const authorizedEids = [
            ...AGENT_EIDS,
            HISTORICAL_ENDPOINT.eid,
        ];
        const clients = AGENT_EIDS.map((eid) =>
            agentClient({eid, authorizedEids})
        );

        const result = await assertQviEndRoles(
            clients,
            'qvi',
            QVI_PREFIX,
            AGENT_ENDPOINTS_BY_EID,
            [...AGENT_ENDPOINTS_BY_EID, HISTORICAL_ENDPOINT]
        );

        assert.deepEqual(result.agentEndpoints, [
            ...AGENT_ENDPOINTS_BY_EID,
            HISTORICAL_ENDPOINT,
        ]);
    });

    it('rejects divergent member endpoint observations', async () => {
        const clients = AGENT_EIDS.map((eid, index) =>
            agentClient({
                eid,
                endpointOverrides:
                    index === 1
                        ? [
                            AGENT_ENDPOINTS[0],
                            'http://unexpected-keria:3902/',
                            AGENT_ENDPOINTS[2],
                        ]
                        : AGENT_ENDPOINTS,
            })
        );

        await assert.rejects(
            assertOobi(clients),
            /disagree on QVI member agent endpoint locations/
        );
    });

    it('rejects a converged endpoint outside workflow config', async () => {
        const endpoints = [
            'http://unexpected-1:3902/',
            'http://unexpected-2:3902/',
            'http://unexpected-3:3902/',
        ];
        const clients = AGENT_EIDS.map((eid) =>
            agentClient({eid, endpointOverrides: endpoints})
        );

        await assert.rejects(
            assertOobi(clients),
            /do not match the workflow/
        );
    });

    it('rejects duplicate agent EIDs before accepting endpoint evidence', async () => {
        const clients = AGENT_EIDS.map((eid) =>
            agentClient({eid})
        );

        await assert.rejects(
            assertOobi(clients, [
                AGENT_ENDPOINTS_BY_EID[0],
                AGENT_ENDPOINTS_BY_EID[0],
                AGENT_ENDPOINTS_BY_EID[2],
            ]),
            /agent EIDs and URLs must be unique/
        );
    });
});
