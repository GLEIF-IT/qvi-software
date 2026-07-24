import {promises as fs} from 'node:fs';

import type {SignifyClient} from 'signify-ts';

import {
    isMainModule,
    parseNamedArguments,
    participantConfigFromArguments,
    requireNamedArguments,
    runJsonCli,
    type ParticipantConfig,
} from '../cli.ts';
import {createTimestamp} from '../create-aid.ts';
import {addEndRoleMultisig} from '../multisig-creation.ts';
import {
    completeCoordinatedOperations,
} from '../coordinated-operation.ts';
import {retry} from '../retry.ts';
import {memberContexts} from '../multisig-coordinator.ts';
import {loadQviMembers} from './qvi-context.ts';

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
    config: ParticipantConfig;
    groupName: string;
    dataDir: string;
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

    const endpoints: AgentEndpoint[] = concreteSigningMembers.map(
        (member: unknown) => {
            const memberIsAnObject = isRecord(member);
            const memberEnds = memberIsAnObject
                ? member.ends
                : undefined;
            const endsAreAnObject = isRecord(memberEnds);
            const agentEnds = endsAreAnObject
                ? memberEnds.agent
                : undefined;
            const memberIsInvalid =
                isRecord(agentEnds) === false;
            if (memberIsInvalid) {
                throw new Error(
                    'A QVI signing member has no agent endpoint data'
                );
            }
            const concreteAgentEnds =
                agentEnds as Record<string, unknown>;
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
    );
    endpoints.sort((left, right) => left.eid.localeCompare(right.eid));

    const observedEids = endpoints.map(({eid}) => eid);
    const endpointUrls = endpoints.map(({url}) => url);
    const endpointUrlsAreUnique =
        new Set(endpointUrls).size === endpointUrls.length;
    if (endpointUrlsAreUnique === false) {
        throw new Error(
            'QVI member agents must expose three distinct endpoint URLs'
        );
    }
    const expectedSorted = [...expectedEids].sort();
    const endpointEidsAreExact =
        JSON.stringify(observedEids) === JSON.stringify(expectedSorted);
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
    const expectedSorted = [...expectedEids].sort();
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
        const observedEids = [
            ...new Set(roles.map(({eid}) => eid)),
        ].sort();
        return (
            entriesAreScoped &&
            JSON.stringify(observedEids) ===
                JSON.stringify(expectedSorted)
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
    const enumeratedOobis = [
        ...new Set(responses.flatMap((result) => result.oobis)),
    ].sort();
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

export async function authorizeAgentEndRoles(
    options: AuthorizeEndRoleOptions
): Promise<QviMultisigOobi> {
    const members = await loadQviMembers(
        options.config,
        options.groupName
    );
    const clients = members.map(({client}) => client);
    const memberAids = members.map(({memberAid}) => memberAid);
    const groupAids = members.map(({groupAid}) => groupAid);
    const qviPrefix = groupAids[0].prefix;

    let qviOobi: QviMultisigOobi | undefined;
    try {
        qviOobi = await collectQviMultisigOobi(
            clients,
            options.groupName,
            qviPrefix
        );
    } catch {
        const responses = await Promise.all(
            clients.map((client) =>
                client.oobis().get(options.groupName, 'agent')
            )
        );
        const noAgentOobisExist = responses.every(
            (response) => response.oobis.length === 0
        );
        if (noAgentOobisExist === false) {
            throw new Error(
                'QVI agent end-role state is partial or contains unexpected OOBIs'
            );
        }
    }

    if (qviOobi === undefined) {
        const timestamp = createTimestamp();
        const coordinationResults: Array<
            Awaited<ReturnType<typeof addEndRoleMultisig>>
        > = [];
        const contexts = memberContexts(
            members.map(({client, memberAid}) => ({
                client,
                aid: memberAid,
            }))
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
        await completeCoordinatedOperations(
            coordinationResults.flatMap((result, clientIndex) =>
                result.coordinatedOperations.map((operation) => ({
                    client: clients[clientIndex],
                    result: operation,
                }))
            )
        );

        qviOobi = await retry(
            () =>
                collectQviMultisigOobi(
                    clients,
                    options.groupName,
                    qviPrefix
                )
        );
    }

    await fs.writeFile(
        `${options.dataDir}/qvi-oobi.json`,
        JSON.stringify(qviOobi)
    );
    return qviOobi;
}

function parseAuthorizeArguments(
    argv: string[]
): AuthorizeEndRoleOptions {
    const args = parseNamedArguments(argv, [
        'config',
        'environment',
        'participant-source',
        'group-name',
        'data-dir',
    ]);
    requireNamedArguments(args, [
        'group-name',
        'data-dir',
    ]);
    return {
        config: participantConfigFromArguments(args),
        groupName: args['group-name'],
        dataDir: args['data-dir'],
    };
}

if (isMainModule(import.meta.url)) {
    await runJsonCli(async () => {
        const options = parseAuthorizeArguments(
            process.argv.slice(2)
        );
        return authorizeAgentEndRoles(options);
    });
}
