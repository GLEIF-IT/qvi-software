import type {HabState, SignifyClient} from 'signify-ts';

import {
    sortAgentEndpointsByEid,
    sortAids,
    sortOobis,
} from './canonical-order.ts';
import {
    credentialSnapshot,
    getCredential,
    type CredentialSnapshot,
} from './credential-state.ts';
import {
    readGroupObservation,
    type GroupStateSnapshot,
} from './group-state.ts';
import {
    assertCredentialConvergence,
    assertGroupStateConvergence,
    type ExpectedGroupState,
} from './workflow-assertions.ts';

export interface ExpectedCredentialState {
    credentialSaid: string;
    issuerPrefix: string;
    schema: string;
    issueePrefix: string;
    statusSequence: string;
}

export interface WalletObserver {
    client: SignifyClient;
    aid: HabState;
}

export interface AgentEndpoint {
    eid: string;
    url: string;
}

export interface QviMultisigOobi {
    qviPrefix: string;
    multisigOobi: string;
    agentEndpoints: AgentEndpoint[];
}

/** Return whether a value is a non-null object. */
function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

/** Read and validate one member-agent endpoint URL. */
function readEndpointUrl(value: unknown, eid: string): string {
    let endpoint: unknown = value;
    if (isRecord(value)) {
        endpoint = value.http ?? value.https;
    }
    if (typeof endpoint !== 'string' || endpoint.length === 0) {
        throw new Error(
            `QVI member agent ${eid} has no HTTP or HTTPS endpoint`
        );
    }
    let url: URL;
    try {
        url = new URL(endpoint);
    } catch (error: unknown) {
        throw new Error(
            `QVI member agent ${eid} has an invalid endpoint URL`,
            {cause: error}
        );
    }
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
        throw new Error(
            `QVI member agent ${eid} uses unsupported endpoint scheme ${url.protocol}`
        );
    }
    return url.toString();
}

/** Read one signing member's single advertised agent endpoint. */
function readAgentEndpoint(member: unknown): AgentEndpoint {
    const ends = isRecord(member) ? member.ends : undefined;
    const agentEnds = isRecord(ends) ? ends.agent : undefined;
    if (isRecord(agentEnds) === false) {
        throw new Error(
            'A QVI signing member has no agent endpoint data'
        );
    }
    const entries = Object.entries(agentEnds);
    if (entries.length !== 1) {
        throw new Error(
            'Each QVI signing member must expose exactly one agent endpoint'
        );
    }
    const [eid, endpoint] = entries[0];
    return {eid, url: readEndpointUrl(endpoint, eid)};
}

/** Validate the exact endpoint set in one group-members response. */
function readAgentEndpoints(
    members: unknown,
    expectedEids: string[]
): AgentEndpoint[] {
    const signing = isRecord(members) ? members.signing : undefined;
    if (Array.isArray(signing) === false) {
        throw new Error('QVI group member data has no signing members');
    }
    const endpoints = sortAgentEndpointsByEid(
        signing.map(readAgentEndpoint)
    );
    const urls = endpoints.map(({url}) => url);
    if (new Set(urls).size !== urls.length) {
        throw new Error(
            'QVI member agents must expose distinct endpoint URLs'
        );
    }
    if (
        JSON.stringify(endpoints.map(({eid}) => eid)) !==
        JSON.stringify(sortAids(expectedEids))
    ) {
        throw new Error(
            'QVI member endpoint data does not cover the expected agent EIDs'
        );
    }
    return endpoints;
}

/** Require every observer to report the same member-agent endpoints. */
export async function observeQviEndpoints(
    clients: SignifyClient[],
    groupName: string,
    expectedEids: string[]
): Promise<AgentEndpoint[]> {
    const observations = await Promise.all(
        clients.map(async (client) =>
            readAgentEndpoints(
                await client.identifiers().members(groupName),
                expectedEids
            )
        )
    );
    const expected = JSON.stringify(observations[0]);
    if (
        observations.every(
            (observation) => JSON.stringify(observation) === expected
        ) === false
    ) {
        throw new Error(
            'QARs disagree on QVI member agent endpoint locations'
        );
    }
    return observations[0];
}

/** Require every observer to report the exact authorized agent EIDs. */
async function exactAuthorizedEids(
    clients: SignifyClient[],
    qviPrefix: string,
    expectedEids: string[]
): Promise<void> {
    const expected = sortAids(expectedEids);
    const observations = await Promise.all(
        clients.map((client) =>
            client.oobis().endroles(qviPrefix, 'agent')
        )
    );
    const exact = observations.every((roles) => {
        const scoped = roles.every(
            (role) =>
                role.cid === qviPrefix &&
                role.role === 'agent' &&
                typeof role.eid === 'string' &&
                role.eid.length > 0
        );
        const observed = sortAids([
            ...new Set(roles.map(({eid}) => eid)),
        ]);
        return (
            scoped &&
            JSON.stringify(observed) === JSON.stringify(expected)
        );
    });
    if (exact === false) {
        throw new Error(
            'QARs do not observe the exact authorized QVI agent EIDs'
        );
    }
}

/** Construct one endpoint-qualified agent OOBI. */
function qualifiedAgentOobi(
    endpoint: AgentEndpoint,
    qviPrefix: string
): string {
    return new URL(
        `/oobi/${qviPrefix}/agent/${endpoint.eid}`,
        endpoint.url
    ).toString();
}

/** Remove the agent suffix from one validated group OOBI. */
function groupOobi(
    qualifiedOobi: string,
    qviPrefix: string
): string {
    const oobi = new URL(qualifiedOobi);
    oobi.pathname = `/oobi/${qviPrefix}`;
    return oobi.toString();
}

/** Assert the exact authorized endpoints and return the QVI OOBI. */
export async function assertQviEndRoles(
    clients: SignifyClient[],
    groupName: string,
    qviPrefix: string,
    expectedEndpoints: AgentEndpoint[]
): Promise<QviMultisigOobi> {
    const normalizedEndpoints = sortAgentEndpointsByEid(
        expectedEndpoints.map(({eid, url}) => ({
            eid,
            url: new URL(url).toString(),
        }))
    );
    const expectedEids = normalizedEndpoints.map(({eid}) => eid);
    if (
        expectedEids.length === 0 ||
        new Set(expectedEids).size !== expectedEids.length ||
        new Set(normalizedEndpoints.map(({url}) => url)).size !==
            normalizedEndpoints.length
    ) {
        throw new Error(
            'Expected QVI agent EIDs and URLs must be unique'
        );
    }
    await exactAuthorizedEids(clients, qviPrefix, expectedEids);
    const endpoints = await observeQviEndpoints(
        clients,
        groupName,
        expectedEids
    );
    if (
        JSON.stringify(endpoints) !==
        JSON.stringify(normalizedEndpoints)
    ) {
        throw new Error(
            'QVI member endpoint locations do not match the workflow'
        );
    }
    const expectedOobis = new Set(
        endpoints.map((endpoint) =>
            qualifiedAgentOobi(endpoint, qviPrefix)
        )
    );
    const responses = await Promise.all(
        clients.map((client) =>
            client.oobis().get(groupName, 'agent')
        )
    );
    const enumeratedOobis = sortOobis([
        ...new Set(responses.flatMap(({oobis}) => oobis)),
    ]);
    if (enumeratedOobis.length === 0) {
        throw new Error(
            'KERIA returned no qualified QVI agent OOBI to canonicalize'
        );
    }
    for (const oobi of enumeratedOobis) {
        if (expectedOobis.has(oobi) === false) {
            throw new Error(
                `KERIA enumerated an unexpected QVI agent OOBI: ${oobi}`
            );
        }
    }
    return {
        qviPrefix,
        multisigOobi: groupOobi(enumeratedOobis[0], qviPrefix),
        agentEndpoints: endpoints,
    };
}

/** Assert exact QVI KEL, signing-roster, next-roster, and observer convergence. */
export async function assertGroupConvergence(
    observers: WalletObserver[],
    groupName: string,
    expected: ExpectedGroupState,
    eventSaid?: string
): Promise<GroupStateSnapshot> {
    const observations = await Promise.all(
        observers.map(({client, aid}) =>
            readGroupObservation(
                client,
                aid.prefix,
                groupName
            )
        )
    );
    const snapshot = assertGroupStateConvergence(
        observations,
        expected
    );
    if (
        eventSaid !== undefined &&
        snapshot.establishmentDigest !== eventSaid
    ) {
        throw new Error(
            `Group establishment digest ${snapshot.establishmentDigest} does not match ${eventSaid}`
        );
    }
    return snapshot;
}

/** Assert credential and TEL convergence across concrete wallet observers. */
export async function assertQviCredentialConvergence(
    observers: WalletObserver[],
    expected: ExpectedCredentialState
): Promise<CredentialSnapshot> {
    const snapshots = await Promise.all(
        observers.map(async ({client, aid}) => {
            return credentialSnapshot(
                await getCredential(client, expected.credentialSaid),
                aid.prefix
            );
        })
    );
    return assertCredentialConvergence(
        snapshots,
        snapshots.map(({observerAid}) => observerAid),
        {
            said: expected.credentialSaid,
            issuer: expected.issuerPrefix,
            schema: expected.schema,
            issuee: expected.issueePrefix,
            statusSequence: expected.statusSequence,
        }
    );
}

/** Assert the holder observes the expected credential and TEL state. */
export async function assertPersonCredentialState(
    observer: WalletObserver,
    expected: ExpectedCredentialState
): Promise<CredentialSnapshot> {
    const snapshot = credentialSnapshot(
        await getCredential(
            observer.client,
            expected.credentialSaid
        ),
        observer.aid.prefix
    );
    const actual = {
        credentialSaid: snapshot.said,
        issuerPrefix: snapshot.issuer,
        schema: snapshot.schema,
        issueePrefix: snapshot.issuee,
        statusSequence: snapshot.statusSequence,
    };
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        throw new Error(
            `Person credential state ${JSON.stringify(actual)} does not match ${JSON.stringify(expected)}`
        );
    }
    return snapshot;
}
