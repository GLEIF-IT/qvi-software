import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import type {SignifyClient} from 'signify-ts';

import {
    collectQviAgentOobis,
} from '../src/qars/qars-authorize-endroles-get-qvi-oobi.ts';

const QVI_PREFIX = 'EQviPrefix';
const AGENT_EIDS = ['EAgentOne', 'EAgentTwo', 'EAgentThree'];
const AGENT_ENDPOINTS = [
    'http://keria1:3902/',
    'http://keria2:3902/',
    'http://keria3:3902/',
];

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
}: AgentClientOptions): SignifyClient {
    return {
        agent: {pre: eid},
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
    } as unknown as SignifyClient;
}

function qualifiedOobi(eid: string, index: number): string {
    return (
        `${AGENT_ENDPOINTS[index]}oobi/` +
        `${QVI_PREFIX}/agent/${eid}`
    );
}

describe('QVI endpoint-qualified agent OOBIs', () => {
    it('derives three qualified OOBIs from common authorized endpoints', async () => {
        const clients = AGENT_EIDS.map((eid) =>
            agentClient({eid})
        );

        const result = await collectQviAgentOobis(
            clients,
            'qvi',
            QVI_PREFIX
        );

        assert.equal(result.qviPrefix, QVI_PREFIX);
        assert.deepEqual(
            result.agentOobis,
            AGENT_EIDS.map((eid, index) => ({
                eid,
                oobi: qualifiedOobi(eid, index),
            })).sort((left, right) =>
                left.eid.localeCompare(right.eid)
            )
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
            collectQviAgentOobis(clients, 'qvi', QVI_PREFIX),
            /enumerated an unexpected QVI agent OOBI/
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
            collectQviAgentOobis(clients, 'qvi', QVI_PREFIX),
            /do not observe the exact authorized QVI agent EIDs/
        );
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
            collectQviAgentOobis(clients, 'qvi', QVI_PREFIX),
            /disagree on QVI member agent endpoint locations/
        );
    });

    it('rejects duplicate agent EIDs before accepting endpoint evidence', async () => {
        const clients = [
            agentClient({eid: AGENT_EIDS[0]}),
            agentClient({eid: AGENT_EIDS[0]}),
            agentClient({eid: AGENT_EIDS[2]}),
        ];

        await assert.rejects(
            collectQviAgentOobis(clients, 'qvi', QVI_PREFIX),
            /agent EIDs are not unique/
        );
    });
});
