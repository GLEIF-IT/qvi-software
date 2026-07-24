import type {SignifyClient} from 'signify-ts';

import type {GroupMember} from '../client.ts';
import {
    sortAgentEndpointsByEid,
    sortAids,
    sortOobis,
} from '../canonical-order.ts';
import {createTimestamp} from '../create-aid.ts';
import {
    addEndRoleMultisig,
    type EndRoleResult,
} from '../multisig-creation.ts';
import {
    completeMultisigOps,
} from '../coordinated-operation.ts';
import {retry} from '../retry.ts';
import {memberContexts} from '../multisig-coordinator.ts';

export interface AgentEndpoint {
    eid: string;
    url: string;
}

export interface QviMultisigOobi {
    qviPrefix: string;
    multisigOobi: string;
    agentEndpoints: AgentEndpoint[];
}

export interface AuthorizeEndRoleOptions {
    members: GroupMember[];
    groupName: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

function readEndpointUrl(value: unknown, eid: string): string {
    let endpoint: unknown = value;
    if (isRecord(value)) {
        endpoint = value.http ?? value.https;
    }
    const endpointIsMissing =
        typeof endpoint !== 'string' || endpoint.length === 0;
    if (endpointIsMissing) {
        throw new Error(
            `QVI member agent ${eid} has no HTTP or HTTPS endpoint`
        );
    }
    const endpointUrl = endpoint as string;

    let url: URL;
    try {
        url = new URL(endpointUrl);
    } catch (error: unknown) {
        throw new Error(
            `QVI member agent ${eid} has an invalid endpoint URL`,
            {cause: error}
        );
    }
    const schemeIsSupported =
        url.protocol === 'http:' || url.protocol === 'https:';
    if (schemeIsSupported === false) {
        throw new Error(
            `QVI member agent ${eid} uses unsupported endpoint scheme ${url.protocol}`
        );
    }
    return url.toString();
}

function readSigningMemberAgentEndpoint(member: unknown): AgentEndpoint {
    const memberIsAnObject = isRecord(member);
    const memberEnds = memberIsAnObject ? member.ends : undefined;
    const endsAreAnObject = isRecord(memberEnds);
    const agentEnds = endsAreAnObject ? memberEnds.agent : undefined;
    const memberIsInvalid = isRecord(agentEnds) === false;
    if (memberIsInvalid) {
        throw new Error(
            'A QVI signing member has no agent endpoint data'
        );
    }

    const concreteAgentEnds = agentEnds as Record<string, unknown>;
    const agentEntries = Object.entries(concreteAgentEnds);
    const hasExactlyOneAgent = agentEntries.length === 1;
    if (hasExactlyOneAgent === false) {
        throw new Error(
            'Each QVI signing member must expose exactly one agent endpoint'
        );
    }

    const [eid, endpoint] = agentEntries[0];
    return {
        eid,
        url: readEndpointUrl(endpoint, eid),
    };
}

function readMemberAgentEndpoints(
    members: unknown,
    expectedEids: string[]
): AgentEndpoint[] {
    const membersAreAnObject = isRecord(members);
    const signingMembers = membersAreAnObject
        ? members.signing
        : undefined;
    const membersAreInvalid =
        Array.isArray(signingMembers) === false;
    if (membersAreInvalid) {
        throw new Error('QVI group member data has no signing members');
    }
    const concreteSigningMembers = signingMembers as unknown[];

    const endpoints = sortAgentEndpointsByEid(
        concreteSigningMembers.map(readSigningMemberAgentEndpoint)
    );

    const observedEids = endpoints.map(({eid}) => eid);
    const endpointUrls = endpoints.map(({url}) => url);
    const endpointUrlsAreUnique =
        new Set(endpointUrls).size === endpointUrls.length;
    if (endpointUrlsAreUnique === false) {
        throw new Error(
            'QVI member agents must expose three distinct endpoint URLs'
        );
    }
    const expectedEidsInCanonicalOrder = sortAids(expectedEids);
    const endpointEidsAreExact =
        JSON.stringify(observedEids) ===
        JSON.stringify(expectedEidsInCanonicalOrder);
    if (endpointEidsAreExact === false) {
        throw new Error(
            'QVI member endpoint data does not cover the expected agent EIDs'
        );
    }
    return endpoints;
}

async function observeCommonMemberAgentEndpoints(
    clients: SignifyClient[],
    groupName: string,
    expectedEids: string[]
): Promise<AgentEndpoint[]> {
    const observations = await Promise.all(
        clients.map(async (client) =>
            readMemberAgentEndpoints(
                await client.identifiers().members(groupName),
                expectedEids
            )
        )
    );
    const expectedObservation = JSON.stringify(observations[0]);
    const everyClientAgrees = observations.every(
        (observation) =>
            JSON.stringify(observation) === expectedObservation
    );
    if (everyClientAgrees === false) {
        throw new Error(
            'QARs disagree on QVI member agent endpoint locations'
        );
    }
    return observations[0];
}

async function requireCommonAuthorizedAgentEids(
    clients: SignifyClient[],
    qviPrefix: string,
    expectedEids: string[]
): Promise<void> {
    const expectedEidsInCanonicalOrder = sortAids(expectedEids);
    const observations = await Promise.all(
        clients.map((client) =>
            client.oobis().endroles(qviPrefix, 'agent')
        )
    );
    const everyClientObservesExactRoles = observations.every((roles) => {
        const entriesAreScoped = roles.every(
            (role) =>
                role.cid === qviPrefix &&
                role.role === 'agent' &&
                typeof role.eid === 'string' &&
                role.eid.length > 0
        );
        const observedEids = sortAids([
            ...new Set(roles.map(({eid}) => eid)),
        ]);
        return (
            entriesAreScoped &&
            JSON.stringify(observedEids) ===
                JSON.stringify(expectedEidsInCanonicalOrder)
        );
    });
    if (everyClientObservesExactRoles === false) {
        throw new Error(
            'QARs do not observe the exact authorized QVI agent EIDs'
        );
    }
}

function qualifiedAgentOobi(
    endpoint: AgentEndpoint,
    qviPrefix: string
): string {
    return new URL(
        `/oobi/${qviPrefix}/agent/${endpoint.eid}`,
        endpoint.url
    ).toString();
}

function stripAgentSuffix(
    qualifiedOobi: string,
    qviPrefix: string
): string {
    const oobi = new URL(qualifiedOobi);
    oobi.pathname = `/oobi/${qviPrefix}`;
    return oobi.toString();
}

export async function collectQviMultisigOobi(
    clients: SignifyClient[],
    groupName: string,
    qviPrefix: string
): Promise<QviMultisigOobi> {
    const expectedEids = clients.map((client) => client.agent?.pre);
    const agentIsMissing = expectedEids.some(
        (eid) => typeof eid !== 'string' || eid.length === 0
    );
    if (agentIsMissing) {
        throw new Error('A QAR Signify client has no connected agent AID');
    }
    const concreteEids = expectedEids as string[];
    const agentEidsAreDuplicated =
        new Set(concreteEids).size !== concreteEids.length;
    if (agentEidsAreDuplicated) {
        throw new Error(
            `QAR agent EIDs are not unique: ${concreteEids.join(',')}`
        );
    }

    await requireCommonAuthorizedAgentEids(
        clients,
        qviPrefix,
        concreteEids
    );
    const endpoints = await observeCommonMemberAgentEndpoints(
        clients,
        groupName,
        concreteEids
    );
    const qualifiedAgentOobis = endpoints.map((endpoint) => ({
        eid: endpoint.eid,
        oobi: qualifiedAgentOobi(endpoint, qviPrefix),
    }));
    const expectedOobis = new Map(
        qualifiedAgentOobis.map(({eid, oobi}) => [oobi, eid])
    );

    const responses = await Promise.all(
        clients.map((client) =>
            client.oobis().get(groupName, 'agent')
        )
    );
    const enumeratedOobis = sortOobis([
        ...new Set(responses.flatMap((result) => result.oobis)),
    ]);
    const enumeratedOobiIsMissing = enumeratedOobis.length === 0;
    if (enumeratedOobiIsMissing) {
        throw new Error(
            'KERIA returned no qualified QVI agent OOBI to canonicalize'
        );
    }
    for (const oobi of enumeratedOobis) {
        const eid = expectedOobis.get(oobi);
        const enumeratedOobiIsUnexpected = eid === undefined;
        if (enumeratedOobiIsUnexpected) {
            throw new Error(
                `KERIA enumerated an unexpected QVI agent OOBI: ${oobi}`
            );
        }
    }

    const multisigOobi = stripAgentSuffix(
        enumeratedOobis[0],
        qviPrefix
    );
    return {
        qviPrefix,
        multisigOobi,
        agentEndpoints: endpoints,
    };
}

/** Authorize and verify the final QVI member-agent endpoint set. */
export async function authorizeAgentEndRoles(
    options: AuthorizeEndRoleOptions
): Promise<QviMultisigOobi> {
    const members = options.members;
    const clients = members.map(({client}) => client);
    const memberAids = members.map(({memberAid}) => memberAid);
    const groupAids = members.map(({groupAid}) => groupAid);
    const qviPrefix = groupAids[0].prefix;

    const existing = await Promise.all(
        clients.map((client) =>
            client.oobis().endroles(qviPrefix, 'agent')
        )
    );
    if (existing.some((roles) => roles.length > 0)) {
        throw new Error(
            'QVI agent roles already exist; authorization is a one-shot phase'
        );
    }

    const timestamp = createTimestamp();
    const coordinationResults: EndRoleResult[] = [];
    const contexts = memberContexts(
        members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        memberAids[0].prefix
    );
    for (let index = 0; index < contexts.length; index++) {
        const context = contexts[index];
        coordinationResults.push(
            await addEndRoleMultisig(
                context.client,
                options.groupName,
                context.aid,
                context.otherMembers,
                groupAids[index],
                timestamp,
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            )
        );
    }
    await completeMultisigOps(
        coordinationResults.flatMap((result, clientIndex) =>
            result.coordinatedOperations.map((operation) => ({
                client: clients[clientIndex],
                result: operation,
            }))
        )
    );
    return await retry(
        () =>
            collectQviMultisigOobi(
                clients,
                options.groupName,
                qviPrefix
            )
    );
}
