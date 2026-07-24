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
import {
    QVI_INITIAL_SEQUENCE,
    qviNextThreshold,
    qviSigningThreshold,
} from '../qvi-configuration.ts';
import {
    assertRepeatedDirectedFanout,
    canonicalOperationEvidence,
    canonicalReceipts,
    canonicalStrings,
} from '../workflow-contracts.ts';

export interface AgentEndpoint {
    eid: string;
    url: string;
}

export interface QviMultisigOobi {
    qviPrefix: string;
    multisigOobi: string;
    agentEndpoints: AgentEndpoint[];
}

export interface QviAgentProof extends QviMultisigOobi {
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
    groupPrefix?: string;
    delegatorPrefix?: string;
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
            memberPrefixes,
            {
                prefix: options.groupPrefix,
                delegator: options.delegatorPrefix,
                sequence: QVI_INITIAL_SEQUENCE,
                signingThreshold: qviSigningThreshold(),
                nextThreshold: qviNextThreshold(),
            }
        );
    const groupAids = observations.map(
        (observation) => observation.group
    );

    let qviOobi: QviMultisigOobi | undefined;
    try {
        qviOobi = await collectQviMultisigOobi(
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
    if (qviOobi === undefined) {
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

        qviOobi = await retry(
            () =>
                collectQviMultisigOobi(
                    clients,
                    options.groupName,
                    groupState.prefix
                )
        );
    }

    const coordinationReceipts = coordinationResults.flatMap((entry) =>
        entry.result.wrapperReceipts.map((receipt) => ({
            sender: entry.sender,
            ...receipt,
        }))
    );
    if (operationEvidence.length > 0) {
        const expectedOperationNames = qviOobi.agentEndpoints.flatMap(
            ({eid}) =>
                Array.from(
                    {length: 3},
                    () =>
                        `endrole.${groupState.prefix}.agent.${eid}`
                )
        );
        const observedOperationNames = operationEvidence.map(
            ({name}) => name
        );
        const operationNamesAreExact =
            JSON.stringify(canonicalStrings(observedOperationNames)) ===
            JSON.stringify(canonicalStrings(expectedOperationNames));
        if (operationNamesAreExact === false) {
            throw new Error(
                'QVI agent end-role operation names do not cover each agent on every QAR'
            );
        }
        const terminalEvidenceIsExact = operationEvidence.every(
            ({done, result}) =>
                done === true &&
                result.kind === 'event' &&
                typeof result.said === 'string' &&
                result.said.length > 0 &&
                result.route === '/end/role/add'
        );
        if (terminalEvidenceIsExact === false) {
            throw new Error(
                'QVI agent end-role operations did not return terminal /end/role/add reply events'
            );
        }
        assertRepeatedDirectedFanout(
            coordinationReceipts,
            memberPrefixes,
            3,
            'QVI agent end-role coordination'
        );
        const innerEventSaids = coordinationReceipts.map(
            ({innerExchangeSaid}) => innerExchangeSaid
        );
        const uniqueInnerEventSaids = new Set(innerEventSaids);
        const eachEndRoleWasSentToEveryPeer =
            uniqueInnerEventSaids.size === 3 &&
            [...uniqueInnerEventSaids].every(
                (said) =>
                    innerEventSaids.filter(
                        (candidate) => candidate === said
                    ).length === 6
            );
        if (eachEndRoleWasSentToEveryPeer === false) {
            throw new Error(
                'QVI agent end-role coordination did not fan out each endpoint event to every peer'
            );
        }
        const evidenceSaids = new Set(
            operationEvidence.map(({result}) => result.said)
        );
        const evidenceMatchesCoordinatedEvents =
            evidenceSaids.size === uniqueInnerEventSaids.size &&
            [...evidenceSaids].every(
                (said) =>
                    typeof said === 'string' &&
                    uniqueInnerEventSaids.has(said)
            );
        if (evidenceMatchesCoordinatedEvents === false) {
            throw new Error(
                'QVI endpoint-role terminal events do not match the coordinated events'
            );
        }
    }

    const proof = {
        ...qviOobi,
        groupState,
        groupObservations: observations
            .map(({observerAid, snapshot}) => ({
                observerAid,
                snapshot,
            }))
            .sort((left, right) =>
                left.observerAid.localeCompare(right.observerAid)
            ),
        operationNames: canonicalStrings(
            operationEvidence.map((operation) => operation.name)
        ),
        operationEvidence:
            canonicalOperationEvidence(operationEvidence),
        coordinationReceipts:
            canonicalReceipts(coordinationReceipts),
    };
    const artifact: Omit<QviAgentProof, 'operationEvidence'> = {
        qviPrefix: proof.qviPrefix,
        multisigOobi: proof.multisigOobi,
        agentEndpoints: proof.agentEndpoints,
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
        'group-prefix',
        'delegator-prefix',
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
        groupPrefix: args['group-prefix'],
        delegatorPrefix: args['delegator-prefix'],
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
