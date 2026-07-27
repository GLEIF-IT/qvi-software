import {readFileSync} from 'node:fs';

import {
    type CreateIdentiferArgs,
    type EventResult,
    type HabState,
    type KeyState,
    ready,
    SignifyClient,
    Tier,
} from 'signify-ts';
import {
    waitOperation,
} from './operations.ts';

export {waitOperation} from './operations.ts';

export type ParticipantRole =
    | 'qar1'
    | 'qar2'
    | 'qar3'
    | 'qar4'
    | 'person';

export interface Participant {
    name: string;
    salt: string;
    adminUrl: string;
    bootUrl: string;
    oobiUrl: string;
}

export interface Witness {
    id: string;
    url: string;
}

interface OobiResponse {
    oobi: string;
    response: unknown;
}

export interface WorkflowConfig {
    services: {
        vleiServerUrl: string;
        witnesses: Witness[];
    };
    participants: Record<ParticipantRole, Participant>;
    qvi: {
        name: string;
        initialMembers: ParticipantRole[];
        finalMembers: ParticipantRole[];
        signingThreshold: string[];
        nextThreshold: string[];
    };
}

const PARTICIPANT_ROLES: readonly ParticipantRole[] = [
    'qar1',
    'qar2',
    'qar3',
    'qar4',
    'person',
];
const EXPECTED_SIGNIFY_VERSION = '0.4.0';
let readyPromise: Promise<void> | undefined;
const connectedClients = new Map<string, SignifyClient>();

/** Return whether a value is a non-null object with string keys. */
function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

/** Validate and normalize an HTTP(S) URL used by the workflow. */
export function requireHttpUrl(value: unknown, description: string): string {
    if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${description} must be a nonempty URL`);
    }

    let parsed: URL;
    try {
        parsed = new URL(value);
    } catch (error: unknown) {
        throw new Error(`${description} is malformed: ${value}`, {
            cause: error,
        });
    }
    if (
        (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') ||
        parsed.hostname.length === 0 ||
        parsed.username.length > 0 ||
        parsed.password.length > 0
    ) {
        throw new Error(
            `${description} must be an HTTP(S) URL without credentials`
        );
    }
    return parsed.toString().replace(/\/$/, '');
}

/** Require a nonempty configuration string. */
function requireString(value: unknown, description: string): string {
    if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${description} must be a nonempty string`);
    }
    return value;
}

/** Validate a unique, three-participant roster. */
function requireRoster(
    value: unknown,
    description: string
): ParticipantRole[] {
    if (
        Array.isArray(value) === false ||
        value.length !== 3 ||
        value.some(
            (entry) =>
                typeof entry !== 'string' ||
                PARTICIPANT_ROLES.includes(entry as ParticipantRole) === false
        )
    ) {
        throw new Error(
            `${description} must contain exactly three participant roles`
        );
    }
    const roster = value as ParticipantRole[];
    if (new Set(roster).size !== roster.length) {
        throw new Error(`${description} contains duplicate members`);
    }
    return [...roster];
}

/** Validate the exact weighted three-of-three threshold used by the fixture. */
function requireThreshold(
    value: unknown,
    description: string
): string[] {
    const expected = ['1/3', '1/3', '1/3'];
    if (
        Array.isArray(value) === false ||
        value.length !== expected.length ||
        value.some((entry, index) => entry !== expected[index])
    ) {
        throw new Error(
            `${description} must be exactly three weighted 1/3 clauses`
        );
    }
    return [...expected];
}

/** Read and fail-closed validate the generated participant configuration. */
export function readWorkflowConfig(path: string): WorkflowConfig {
    let decoded: unknown;
    try {
        decoded = JSON.parse(readFileSync(path, 'utf8')) as unknown;
    } catch (error: unknown) {
        throw new Error(`Unable to read participant config ${path}`, {
            cause: error,
        });
    }
    if (isRecord(decoded) === false) {
        throw new Error('Participant config must be a JSON object');
    }

    const servicesValue = decoded.services;
    const participantsValue = decoded.participants;
    const qviValue = decoded.qvi;
    if (
        isRecord(servicesValue) === false ||
        isRecord(participantsValue) === false ||
        isRecord(qviValue) === false
    ) {
        throw new Error(
            'Participant config requires services, participants, and qvi objects'
        );
    }

    const witnessesValue = servicesValue.witnesses;
    if (
        Array.isArray(witnessesValue) === false ||
        witnessesValue.length !== 3
    ) {
        throw new Error('services.witnesses must contain exactly three entries');
    }
    const witnesses = witnessesValue.map((value, index): Witness => {
        if (isRecord(value) === false) {
            throw new Error(`Witness ${index} must be an object`);
        }
        return {
            id: requireString(value.id, `Witness ${index} identifier`),
            url: requireHttpUrl(value.url, `Witness ${index} URL`),
        };
    });

    const participants = Object.fromEntries(
        PARTICIPANT_ROLES.map((role) => {
            const value = participantsValue[role];
            if (isRecord(value) === false) {
                throw new Error(`Missing participant ${role}`);
            }
            return [
                role,
                {
                    name: requireString(value.name, `${role} name`),
                    salt: requireString(value.salt, `${role} salt`),
                    adminUrl: requireHttpUrl(
                        value.adminUrl,
                        `${role} admin URL`
                    ),
                    bootUrl: requireHttpUrl(
                        value.bootUrl,
                        `${role} boot URL`
                    ),
                    oobiUrl: requireHttpUrl(
                        value.oobiUrl,
                        `${role} OOBI URL`
                    ),
                },
            ];
        })
    ) as Record<ParticipantRole, Participant>;

    const initialMembers = requireRoster(
        qviValue.initialMembers,
        'qvi.initialMembers'
    );
    const finalMembers = requireRoster(
        qviValue.finalMembers,
        'qvi.finalMembers'
    );
    const expectedInitial = ['qar1', 'qar2', 'qar3'];
    const replacementMembers = ['qar1', 'qar2', 'qar4'];
    const finalRosterIsInitial = finalMembers.every(
        (member, index) => member === expectedInitial[index]
    );
    const finalRosterIsReplacement = finalMembers.every(
        (member, index) => member === replacementMembers[index]
    );
    if (
        initialMembers.some(
            (member, index) => member !== expectedInitial[index]
        ) ||
        (finalRosterIsInitial === false &&
            finalRosterIsReplacement === false)
    ) {
        throw new Error(
            'QVI membership must either retain qar3 or replace it with qar4'
        );
    }

    return {
        services: {
            vleiServerUrl: requireHttpUrl(
                servicesValue.vleiServerUrl,
                'vLEI server URL'
            ),
            witnesses,
        },
        participants,
        qvi: {
            name: requireString(qviValue.name, 'QVI name'),
            initialMembers,
            finalMembers,
            signingThreshold: requireThreshold(
                qviValue.signingThreshold,
                'qvi.signingThreshold'
            ),
            nextThreshold: requireThreshold(
                qviValue.nextThreshold,
                'qvi.nextThreshold'
            ),
        },
    };
}

/** Assert that the installed published SignifyTS package matches the pin. */
export function assertSignifyVersion(): void {
    const packagePath = new URL(
        '../node_modules/signify-ts/package.json',
        import.meta.url
    );
    const packageJson = JSON.parse(
        readFileSync(packagePath, 'utf8')
    ) as {version?: unknown};
    if (packageJson.version !== EXPECTED_SIGNIFY_VERSION) {
        throw new Error(
            `Expected signify-ts ${EXPECTED_SIGNIFY_VERSION}, found ${String(packageJson.version)}`
        );
    }
}

/** Initialize SignifyTS exactly once for this process. */
async function initializeSignify(): Promise<void> {
    readyPromise ??= ready();
    await readyPromise;
}

/** Construct a client for one validated participant endpoint pair. */
function createClient(participant: Participant): SignifyClient {
    return new SignifyClient(
        participant.adminUrl,
        participant.salt,
        Tier.low,
        participant.bootUrl
    );
}

/** Identify one participant cache entry by its concrete local endpoints. */
function clientCacheKey(participant: Participant): string {
    return [
        participant.name,
        participant.adminUrl,
        participant.bootUrl,
    ].join('|');
}

/** Require a connected client to expose its controller and agent identities. */
function requireConnectedAgent(client: SignifyClient): void {
    if (
        typeof client.agent?.pre !== 'string' ||
        client.agent.pre.length === 0
    ) {
        throw new Error('KERIA connect completed without an agent AID');
    }
}

/** Boot a fresh participant and connect only after boot succeeds. */
export async function bootClient(
    participant: Participant
): Promise<SignifyClient> {
    await initializeSignify();
    const client = createClient(participant);
    const response = await client.boot();
    if (response.ok === false) {
        const body = await response.text();
        throw new Error(
            `KERIA boot failed: ${response.status} ${response.statusText} ${body}`
        );
    }
    await client.connect();
    requireConnectedAgent(client);
    connectedClients.set(clientCacheKey(participant), client);
    return client;
}

/** Connect to an already booted participant without creating fallback state. */
export async function connectClient(
    participant: Participant
): Promise<SignifyClient> {
    const cacheKey = clientCacheKey(participant);
    const cached = connectedClients.get(cacheKey);
    if (cached !== undefined) {
        return cached;
    }

    await initializeSignify();
    const client = createClient(participant);
    await client.connect();
    requireConnectedAgent(client);
    connectedClients.set(cacheKey, client);
    return client;
}

/** Narrow an OOBI response to the key-state shape the workflow consumes. */
function isKeyState(value: unknown): value is KeyState {
    return (
        isRecord(value) &&
        typeof value.i === 'string' &&
        typeof value.s === 'string' &&
        typeof value.d === 'string'
    );
}

/** Accept KERIA's documented non-AID OOBI acknowledgement. */
function isOobiAcknowledgement(
    value: unknown,
    expectedOobi: string
): boolean {
    return isRecord(value) && value.oobi === expectedOobi;
}

/** Submit and complete one validated OOBI resolution request. */
async function resolveOobiResponse(
    client: SignifyClient,
    oobi: string,
    alias?: string
): Promise<OobiResponse> {
    const validatedOobi = requireHttpUrl(oobi, 'OOBI');
    const operation = await client.oobis().resolve(validatedOobi, alias);
    const completed = await waitOperation(client, operation);
    return {oobi: validatedOobi, response: completed.response};
}

/** Resolve any OOBI and accept only KERIA's two documented response shapes. */
export async function resolveOobi(
    client: SignifyClient,
    oobi: string,
    alias?: string
): Promise<void> {
    const result = await resolveOobiResponse(client, oobi, alias);
    if (
        isKeyState(result.response) === false &&
        isOobiAcknowledgement(result.response, result.oobi) === false
    ) {
        throw new Error('OOBI resolution returned an incompatible response');
    }
}

/** Resolve an identifier OOBI and require the resulting key state. */
export async function resolveAidOobi(
    client: SignifyClient,
    oobi: string,
    alias?: string
): Promise<KeyState> {
    const result = await resolveOobiResponse(client, oobi, alias);
    if (isKeyState(result.response) === false) {
        throw new Error(
            'Identifier OOBI resolution returned no key state'
        );
    }
    return result.response;
}

/** Incept one fresh identifier and require its operation to complete. */
export async function inceptAid(
    client: SignifyClient,
    name: string,
    args: CreateIdentiferArgs
): Promise<HabState> {
    const result: EventResult = await client.identifiers().create(name, args);
    await waitOperation(client, await result.op());
    return await client.identifiers().get(name);
}

/** Authorize the connected KERIA agent for one concrete identifier. */
export async function authorizeAidAgent(
    client: SignifyClient,
    aid: HabState
): Promise<void> {
    const agentPrefix = client.agent?.pre;
    if (typeof agentPrefix !== 'string' || agentPrefix.length === 0) {
        throw new Error(
            `Cannot authorize ${aid.name} without a KERIA agent`
        );
    }
    const role = await client
        .identifiers()
        .addEndRole(aid.name, 'agent', agentPrefix);
    await waitOperation(client, await role.op());
}

/** Retrieve an existing identifier without any create-on-missing fallback. */
export async function getAid(
    client: SignifyClient,
    name: string
): Promise<HabState> {
    return await client.identifiers().get(name);
}

/** Validate the exact OOBI response shape returned by SignifyTS. */
export function requireOobiResponse(
    value: unknown,
    description: string
): string {
    if (
        isRecord(value) === false ||
        Array.isArray(value.oobis) === false ||
        value.oobis.length !== 1 ||
        typeof value.oobis[0] !== 'string'
    ) {
        throw new Error(`${description} returned an invalid OOBI response`);
    }
    return requireHttpUrl(value.oobis[0], `${description} OOBI`);
}

export interface ParticipantEvidence {
    aid: string;
    agentEid: string;
    agentOobi: string;
    witnessOobi: string;
}

export interface GroupMember {
    client: SignifyClient;
    memberAid: HabState;
    groupAid: HabState;
}

/** Load concrete member and group identifiers from connected wallets. */
export async function loadGroupMembers(
    clients: SignifyClient[],
    memberNames: string[],
    groupName: string
): Promise<GroupMember[]> {
    if (clients.length !== memberNames.length) {
        throw new Error(
            'Group member clients and identifier names must have equal length'
        );
    }
    const memberAids = await Promise.all(
        memberNames.map((name, index) =>
            clients[index].identifiers().get(name)
        )
    );
    const groupAids = await Promise.all(
        clients.map((client) => client.identifiers().get(groupName))
    );
    return clients.map((client, index) => ({
        client,
        memberAid: memberAids[index],
        groupAid: groupAids[index],
    }));
}

/** Read the public AID and OOBI evidence for one prepared participant. */
export async function readParticipantEvidence(
    client: SignifyClient,
    participant: Participant,
    aid: HabState
): Promise<ParticipantEvidence> {
    const [agentResponse, witnessResponse] = await Promise.all([
        client.oobis().get(participant.name, 'agent'),
        client.oobis().get(participant.name, 'witness'),
    ]);
    const agentEid = client.agent?.pre;
    if (typeof agentEid !== 'string' || agentEid.length === 0) {
        throw new Error(`${participant.name} has no connected agent AID`);
    }
    return {
        aid: aid.prefix,
        agentEid,
        agentOobi: requireOobiResponse(
            agentResponse,
            `${participant.name} agent role`
        ),
        witnessOobi: requireOobiResponse(
            witnessResponse,
            `${participant.name} witness role`
        ),
    };
}
