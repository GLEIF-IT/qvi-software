import {promises as fs} from 'node:fs';

import type {SignifyClient} from 'signify-ts';

import {
    isMainModule,
    parseNamedArguments,
    readParticipantConfig,
    requireNamedArguments,
    runJsonCli,
} from '../cli.ts';
import {createTimestamp} from '../create-aid.ts';
import {getOrCreateClient} from '../keystore-creation.ts';
import {
    assertGroupStateConvergence,
    readGroupObservation,
    type GroupStateSnapshot,
} from '../group-state.ts';
import {addEndRoleMultisig} from '../multisig-creation.ts';
import {
    type OperationEvidence,
} from '../operations.ts';
import {
    completeCoordinatedOperations,
} from '../coordinated-operation.ts';
import {retry} from '../retry.ts';

export interface AgentOobi {
    eid: string;
    oobi: string;
}

export interface QviAgentOobis {
    qviPrefix: string;
    agentOobis: AgentOobi[];
}

export interface QviAgentProof extends QviAgentOobis {
    groupState: GroupStateSnapshot;
    groupObservations: Array<{
        observerAid: string;
        snapshot: GroupStateSnapshot;
    }>;
    operationNames: string[];
    operationEvidence: OperationEvidence[];
    coordinationReceipts: Array<{
        sender: string;
        recipient: string;
        exnSaid: string;
        innerExchangeSaid: string;
    }>;
}

export interface AuthorizeEndRoleOptions {
    configPath: string;
    groupName: string;
    dataDir: string;
}

interface AgentEndpoint {
    eid: string;
    url: string;
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

async function assertCommonAuthorizedAgentEids(
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
): AgentOobi {
    const oobi = new URL(
        `/oobi/${qviPrefix}/agent/${endpoint.eid}`,
        endpoint.url
    ).toString();
    return {eid: endpoint.eid, oobi};
}

export async function collectQviAgentOobis(
    clients: SignifyClient[],
    groupName: string,
    qviPrefix: string
): Promise<QviAgentOobis> {
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

    await assertCommonAuthorizedAgentEids(
        clients,
        qviPrefix,
        concreteEids
    );
    const endpoints = await observeCommonMemberAgentEndpoints(
        clients,
        groupName,
        concreteEids
    );
    const agentOobis = endpoints.map((endpoint) =>
        qualifiedAgentOobi(endpoint, qviPrefix)
    );
    const expectedOobis = new Map(
        agentOobis.map(({eid, oobi}) => [oobi, eid])
    );

    // KERIA 0.4.0 enumerates only the first group agent even after all
    // endpoint roles converge. Treat that response as corroborating evidence,
    // while deriving each qualified URL from the common member endpoint and
    // exact group end-role state reported by every QAR.
    const responses = await Promise.all(
        clients.map((client) =>
            client.oobis().get(groupName, 'agent')
        )
    );
    const enumeratedOobis = [
        ...new Set(responses.flatMap((result) => result.oobis)),
    ];
    for (const oobi of enumeratedOobis) {
        const eid = expectedOobis.get(oobi);
        const enumeratedOobiIsUnexpected = eid === undefined;
        if (enumeratedOobiIsUnexpected) {
            throw new Error(
                `KERIA enumerated an unexpected QVI agent OOBI: ${oobi}`
            );
        }
    }

    agentOobis.sort((left, right) =>
        left.eid.localeCompare(right.eid)
    );
    return {qviPrefix, agentOobis};
}

export async function authorizeAgentEndRoles(
    options: AuthorizeEndRoleOptions
): Promise<QviAgentProof> {
    const config = readParticipantConfig(options.configPath);
    const participants = [
        config.participants.qar1,
        config.participants.qar2,
        config.participants.qar3,
    ];
    const clients = await Promise.all(
        participants.map((participant) =>
            getOrCreateClient(
                participant.salt,
                config.environment,
                participant.keriaHost
            )
        )
    );
    const memberAids = await Promise.all(
        participants.map((participant, index) =>
            clients[index]
                .identifiers()
                .get(participant.name)
        )
    );
    const memberPrefixes = memberAids.map((member) => member.prefix);
    const observations = await Promise.all(
        clients.map((client, index) =>
            readGroupObservation(
                client,
                memberPrefixes[index],
                options.groupName,
                memberPrefixes
            )
        )
    );
    const groupState =
        assertGroupStateConvergence(
            observations,
            memberPrefixes
        );
    const groupAids = observations.map(
        (observation) => observation.group
    );

    let agentOobis: QviAgentOobis | undefined;
    try {
        agentOobis = await collectQviAgentOobis(
            clients,
            options.groupName,
            groupState.prefix
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

    const coordinationResults: Array<{
        sender: string;
        result: Awaited<ReturnType<typeof addEndRoleMultisig>>;
    }> = [];
    let operationEvidence: OperationEvidence[] = [];
    if (agentOobis === undefined) {
        const timestamp = createTimestamp();
        for (let index = 0; index < clients.length; index++) {
            const otherMembers = memberAids.filter(
                (_, memberIndex) => memberIndex !== index
            );
            const participantIsInitiator = index === 0;
            const coordinationOptions = participantIsInitiator
                ? {isInitiator: true}
                : {coordinator: memberAids[0].prefix};
            coordinationResults.push({
                sender: memberAids[index].prefix,
                result: await addEndRoleMultisig(
                    clients[index],
                    options.groupName,
                    memberAids[index],
                    otherMembers,
                    groupAids[index],
                    timestamp,
                    coordinationOptions
                ),
            });
        }
        operationEvidence = await completeCoordinatedOperations(
            coordinationResults.flatMap((entry, clientIndex) =>
                entry.result.coordinatedOperations.map((result) => ({
                    client: clients[clientIndex],
                    result,
                }))
            )
        );

        agentOobis = await retry(
            () =>
                collectQviAgentOobis(
                    clients,
                    options.groupName,
                    groupState.prefix
                )
        );
    }

    const proof = {
        ...agentOobis,
        groupState,
        groupObservations: observations.map(
            ({observerAid, snapshot}) => ({
                observerAid,
                snapshot,
            })
        ),
        operationNames: operationEvidence.map(
            (operation) => operation.name
        ),
        operationEvidence,
        coordinationReceipts: coordinationResults.flatMap((entry) =>
            entry.result.wrapperReceipts.map((receipt) => ({
                sender: entry.sender,
                ...receipt,
            }))
        ),
    };
    const artifact: Omit<QviAgentProof, 'operationEvidence'> = {
        qviPrefix: proof.qviPrefix,
        agentOobis: proof.agentOobis,
        groupState: proof.groupState,
        groupObservations: proof.groupObservations,
        operationNames: proof.operationNames,
        coordinationReceipts: proof.coordinationReceipts,
    };
    await fs.writeFile(
        `${options.dataDir}/qvi-oobi.json`,
        JSON.stringify(artifact),
        {mode: 0o600}
    );
    return proof;
}

function parseAuthorizeArguments(
    argv: string[]
): AuthorizeEndRoleOptions {
    const args = parseNamedArguments(argv, [
        'config',
        'group-name',
        'data-dir',
    ]);
    requireNamedArguments(args, [
        'config',
        'group-name',
        'data-dir',
    ]);
    return {
        configPath: args.config,
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
