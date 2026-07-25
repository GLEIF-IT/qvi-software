import {promises as fs, readFileSync} from 'node:fs';
import {resolve as resolvePath} from 'node:path';
import {pathToFileURL} from 'node:url';

import {
    Salter,
    type CredentialData,
    type CredentialSubject,
    type HabState,
    type SignifyClient,
} from 'signify-ts';

import {
    assertSignifyVersion,
    authorizeAidAgent,
    bootClient,
    connectClient,
    getAid,
    inceptAid,
    loadGroupMembers,
    readWorkflowConfig,
    readParticipantEvidence,
    requireHttpUrl,
    resolveAidOobi,
    resolveOobi,
    type ParticipantEvidence,
    type GroupMember,
    type WorkflowConfig,
    type ParticipantRole,
    waitOperation,
} from './client.ts';
import {
    assertGroupConvergence,
    assertPersonCredentialState,
    assertQviEndRoles,
    assertQviCredentialConvergence,
    type AgentEndpoint,
    type ExpectedCredentialState,
} from './assertions.ts';
import {
    buildGroupEvent,
    joinRotation,
    submitGroupInception,
    submitGroupRotation,
    submitRotation,
    type GroupEventSubmission,
    type GroupMemberEvent,
} from './multisig.ts';
import {completeSavedMultisigOps} from './coordinated-operation.ts';
import {notificationReference} from './notifications.ts';
import {
    admitCredential as admitGroupCredential,
    createRegistry,
    ECR_SCHEMA_SAID,
    grantCredential,
    issueCredential,
    LE_SCHEMA_SAID,
    OOR_SCHEMA_SAID,
    revokeCredential,
} from './credentials.ts';
import {createTimestamp} from './create-aid.ts';
import {presentCredential} from './qars/qars-present-credential.ts';
import {authorizeEndRole} from './multisig-creation.ts';
import {admitCredential as admitPersonCredential} from './person/person-admit-credential.ts';
import {presentPersonCredential} from './person/person-grant-credential.ts';
import {
    credentialSnapshot,
    getCredential,
    type CredentialSnapshot,
} from './credential-state.ts';
import {retry} from './retry.ts';

const SCHEMA_SAIDS = [
    'EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao',
    LE_SCHEMA_SAID,
    'EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g',
    'EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E',
    ECR_SCHEMA_SAID,
    OOR_SCHEMA_SAID,
] as const;

const SETUP_ROLES: readonly ParticipantRole[] = [
    'qar1',
    'qar2',
    'qar3',
    'qar4',
    'person',
];

interface SetupWallet {
    role: ParticipantRole;
    client: SignifyClient;
}

interface ReadyWallet extends SetupWallet {
    aid: HabState;
}

interface PreparedWallet extends ReadyWallet {
    evidence: ParticipantEvidence;
}

/** Connect concrete participants in the requested workflow order. */
async function connectWallets(
    config: WorkflowConfig,
    roles: readonly ParticipantRole[]
): Promise<SetupWallet[]> {
    return await Promise.all(
        roles.map(async (role) => ({
            role,
            client: await connectClient(config.participants[role]),
        }))
    );
}

/** Connect and load concrete wallets in the requested roster order. */
async function loadWallets(
    config: WorkflowConfig,
    roles: readonly ParticipantRole[]
): Promise<ReadyWallet[]> {
    const wallets = await connectWallets(config, roles);
    return await Promise.all(
        wallets.map(async ({role, client}) => {
            return {
                role,
                client,
                aid: await getAid(
                    client,
                    config.participants[role].name
                ),
            };
        })
    );
}

/** Select concrete wallets in an explicit roster order. */
function selectWallets(
    wallets: ReadyWallet[],
    roles: readonly ParticipantRole[]
): ReadyWallet[] {
    return roles.map((role) => {
        const wallet = wallets.find(
            (candidate) => candidate.role === role
        );
        if (wallet === undefined) {
            throw new Error(`Wallet ${role} was not loaded`);
        }
        return wallet;
    });
}

/** Convert one prepared workflow wallet to the multisig wallet interface. */
function multisigMember(wallet: ReadyWallet) {
    return {client: wallet.client, aid: wallet.aid};
}

/** Convert prepared workflow wallets to the multisig wallet interface. */
function multisigMembers(wallets: ReadyWallet[]) {
    return wallets.map(multisigMember);
}

/** Load the concrete final QVI member and group identifiers. */
async function loadFinalQviMembers(
    config: WorkflowConfig
): Promise<GroupMember[]> {
    const wallets = await loadWallets(
        config,
        config.qvi.finalMembers
    );
    return await loadGroupMembers(
        wallets.map(({client}) => client),
        wallets.map(({aid}) => aid.name),
        config.qvi.name
    );
}

/** Return the explicitly ordered initiator for one group operation. */
function firstGroupMember(members: GroupMember[]): GroupMember {
    const member = members[0];
    if (member === undefined) {
        throw new Error('Group operation requires at least one member');
    }
    return member;
}

/** Build the exact final QVI agent endpoint set from workflow config. */
function qviAgentEndpoints(
    config: WorkflowConfig,
    members: GroupMember[]
): AgentEndpoint[] {
    if (members.length !== config.qvi.finalMembers.length) {
        throw new Error(
            'Final QVI members do not match the configured roster'
        );
    }
    return members.map(({client}, index) => {
        const role = config.qvi.finalMembers[index];
        const eid = client.agent?.pre;
        if (
            role === undefined ||
            typeof eid !== 'string' ||
            eid.length === 0
        ) {
            throw new Error(
                'Final QVI member has no configured agent endpoint'
            );
        }
        return {
            eid,
            url: new URL(
                config.participants[role].oobiUrl
            ).toString(),
        };
    });
}

/** Load the concrete person wallet used by holder actions. */
async function loadPersonWallet(
    config: WorkflowConfig
): Promise<ReadyWallet> {
    return (await loadWallets(config, ['person']))[0];
}

export interface PendingWorkflowEvent {
    eventKind: 'inception' | 'rotation';
    groupPrefix: string;
    eventSaid: string;
    eventSequence: string;
    signingMembers: string[];
    rotationMembers: string[];
    members: Array<{
        memberPrefix: string;
        operationName: string;
        notificationIds: string[];
    }>;
}

export class UsageError extends Error {}

/** Parse the strict named arguments accepted by one explicit action. */
function parseArguments(
    argv: string[],
    allowedNames: readonly string[],
    requiredNames: readonly string[]
): Record<string, string> {
    const allowed = new Set<string>(allowedNames);
    const result: Record<string, string> = {};
    if (argv.length % 2 !== 0) {
        throw new UsageError(
            'Arguments must use named --option value pairs'
        );
    }
    for (let index = 0; index < argv.length; index += 2) {
        const option = argv[index];
        const value = argv[index + 1];
        if (option?.startsWith('--') !== true || value === undefined) {
            throw new UsageError(
                'Arguments must use named --option value pairs'
            );
        }
        const name = option.slice(2);
        if (allowed.has(name) === false) {
            throw new UsageError(
                `Unknown argument --${name}`
            );
        }
        if (result[name] !== undefined) {
            throw new UsageError(`Duplicate argument --${name}`);
        }
        result[name] = value;
    }
    required(result, ...requiredNames);
    return result;
}

/** Parse an action whose accepted arguments are all mandatory. */
function parseExactArguments(
    argv: string[],
    ...names: string[]
): Record<string, string> {
    return parseArguments(argv, names, names);
}

/** Require the named options used by the selected phase action. */
function required(
    args: Record<string, string>,
    ...names: string[]
): void {
    const missing = names.filter(
        (name) =>
            typeof args[name] !== 'string' || args[name].length === 0
    );
    if (missing.length > 0) {
        throw new UsageError(
            `Missing required argument(s): ${missing
                .map((name) => `--${name}`)
                .join(', ')}`
        );
    }
}

/** Parse an explicit comma-separated participant roster. */
function parseRoles(
    value: string | undefined,
    description: string
): ParticipantRole[] {
    const roles = value?.split(',') ?? [];
    const allowed: readonly ParticipantRole[] = [
        'qar1',
        'qar2',
        'qar3',
        'qar4',
        'person',
    ];
    if (
        roles.length === 0 ||
        roles.some(
            (role) =>
                allowed.includes(role as ParticipantRole) === false
        ) ||
        new Set(roles).size !== roles.length
    ) {
        throw new UsageError(
            `${description} must be a comma-separated unique participant roster`
        );
    }
    return roles as ParticipantRole[];
}

/** Build the credential postcondition required by admission or assertion. */
function expectedCredential(
    args: Record<string, string>
): ExpectedCredentialState {
    required(
        args,
        'credential-said',
        'issuer-prefix',
        'schema',
        'issuee-prefix',
        'status-sequence'
    );
    return {
        credentialSaid: args['credential-said'],
        issuerPrefix: args['issuer-prefix'],
        schema: args.schema,
        issueePrefix: args['issuee-prefix'],
        statusSequence: args['status-sequence'],
    };
}

/** Persist one exclusive pending event for the KLI delegation boundary. */
async function writePendingArtifact(
    path: string,
    event: unknown
): Promise<void> {
    await fs.writeFile(path, `${JSON.stringify(event)}\n`, {
        flag: 'wx',
    });
}

/** Convert one live group result into the exact persisted resume handle. */
function saveGroupEvent(
    eventKind: 'inception' | 'rotation',
    submission: GroupEventSubmission
): PendingWorkflowEvent {
    return {
        eventKind,
        groupPrefix: submission.groupPrefix,
        eventSaid: submission.eventSaid,
        eventSequence: submission.eventSequence,
        signingMembers: submission.signingMembers,
        rotationMembers: submission.rotationMembers,
        members: submission.members.map((member) => ({
            memberPrefix: member.memberPrefix,
            operationName:
                typeof member.operation === 'string'
                    ? member.operation
                    : member.operation.name,
            notificationIds: member.notifications.flatMap(
                (notification) =>
                    notificationReference(notification).notificationIds
            ),
        })),
    };
}

/** Return whether a JSON value is a non-null object. */
function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
}

/** Require a nonempty string at the persisted JSON boundary. */
function persistedString(value: unknown, description: string): string {
    if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${description} must be a nonempty string`);
    }
    return value;
}

/** Require a unique persisted string array with the expected length. */
function persistedStrings(
    value: unknown,
    description: string,
    expectedLength?: number
): string[] {
    if (
        Array.isArray(value) === false ||
        (expectedLength !== undefined &&
            value.length !== expectedLength) ||
        value.some(
            (entry) =>
                typeof entry !== 'string' || entry.length === 0
        )
    ) {
        throw new Error(
            `${description} must contain ${
                expectedLength ?? 'only'
            } nonempty strings`
        );
    }
    const values = value as string[];
    if (new Set(values).size !== values.length) {
        throw new Error(`${description} contains duplicate values`);
    }
    return [...values];
}

/** Reject extra persisted fields so the KLI boundary remains intentional. */
function requireExactFields(
    value: Record<string, unknown>,
    expected: readonly string[],
    description: string
): void {
    const actual = Object.keys(value).sort();
    const requiredFields = [...expected].sort();
    if (JSON.stringify(actual) !== JSON.stringify(requiredFields)) {
        throw new Error(`${description} has incompatible fields`);
    }
}

/**
 * Read and fully validate the one JSON value that crosses TypeScript to KLI
 * and back. In-process multisig values remain ordinarily typed.
 */
export async function readPendingWorkflowEvent(
    path: string
): Promise<PendingWorkflowEvent> {
    const value = JSON.parse(await fs.readFile(path, 'utf8')) as unknown;
    if (isRecord(value) === false) {
        throw new Error('Pending workflow event must be an object');
    }
    requireExactFields(
        value,
        [
            'eventKind',
            'groupPrefix',
            'eventSaid',
            'eventSequence',
            'signingMembers',
            'rotationMembers',
            'members',
        ],
        'Pending workflow event'
    );
    const eventKind = value.eventKind;
    if (eventKind !== 'inception' && eventKind !== 'rotation') {
        throw new Error('Pending workflow event has an unknown event kind');
    }
    if (Array.isArray(value.members) === false || value.members.length !== 3) {
        throw new Error(
            'Pending workflow event requires exactly three member operations'
        );
    }
    const members = value.members.map((member, index) => {
        if (isRecord(member) === false) {
            throw new Error(`Pending member ${index} must be an object`);
        }
        requireExactFields(
            member,
            ['memberPrefix', 'operationName', 'notificationIds'],
            `Pending member ${index}`
        );
        return {
            memberPrefix: persistedString(
                member.memberPrefix,
                `Pending member ${index} prefix`
            ),
            operationName: persistedString(
                member.operationName,
                `Pending member ${index} operation`
            ),
            notificationIds: persistedStrings(
                member.notificationIds,
                `Pending member ${index} notification identifiers`
            ),
        };
    });
    const memberPrefixes = members.map(({memberPrefix}) => memberPrefix);
    if (new Set(memberPrefixes).size !== memberPrefixes.length) {
        throw new Error('Pending member prefixes must be unique');
    }
    return {
        eventKind,
        groupPrefix: persistedString(
            value.groupPrefix,
            'Pending group prefix'
        ),
        eventSaid: persistedString(value.eventSaid, 'Pending event SAID'),
        eventSequence: persistedString(
            value.eventSequence,
            'Pending event sequence'
        ),
        signingMembers: persistedStrings(
            value.signingMembers,
            'Pending signing roster',
            3
        ),
        rotationMembers: persistedStrings(
            value.rotationMembers,
            'Pending rotation roster',
            3
        ),
        members,
    };
}

/** Validate and complete the concrete operations in one pending event. */
async function completePendingEvent(
    event: PendingWorkflowEvent,
    signingWallets: ReadyWallet[],
    rotationWallets: ReadyWallet[]
): Promise<void> {
    const signingMembers = signingWallets.map(({aid}) => aid.prefix);
    const rotationMembers = rotationWallets.map(({aid}) => aid.prefix);
    if (
        JSON.stringify(event.signingMembers) !==
            JSON.stringify(signingMembers) ||
        JSON.stringify(event.rotationMembers) !==
            JSON.stringify(rotationMembers) ||
        JSON.stringify(
            event.members.map(({memberPrefix}) => memberPrefix)
        ) !== JSON.stringify(signingMembers)
    ) {
        throw new Error(
            'Pending event members do not match the requested rosters'
        );
    }
    const clients = new Map(
        signingWallets.map(({client, aid}) => [aid.prefix, client])
    );
    await completeSavedMultisigOps(
        event.members.map((member) => {
            const client = clients.get(member.memberPrefix);
            if (client === undefined) {
                throw new Error(
                    `No wallet for pending member ${member.memberPrefix}`
                );
            }
            return {
                client,
                result: {
                    operationName: member.operationName,
                    notificationIds: member.notificationIds,
                },
            };
        })
    );
}

/** Complete one delegated event, assert convergence, then remove its handle. */
async function completeAndAssert(
    config: WorkflowConfig,
    args: Record<string, string>,
    eventKind: 'inception' | 'rotation'
) {
    required(
        args,
        'delegator-prefix',
        'artifact',
        'expected-sequence',
        'signing-roles',
        'rotation-roles'
    );
    const signingRoles = parseRoles(
        args['signing-roles'],
        'Signing roles'
    );
    const rotationRoles = parseRoles(
        args['rotation-roles'],
        'Rotation roles'
    );
    const event = await readPendingWorkflowEvent(args.artifact);
    if (
        event.eventKind !== eventKind ||
        event.eventSequence !== args['expected-sequence']
    ) {
        throw new Error(
            `Expected ${eventKind} sequence ${args['expected-sequence']}; found ${event.eventKind} sequence ${event.eventSequence}`
        );
    }
    const wallets = await loadWallets(config, [
        ...new Set([...signingRoles, ...rotationRoles]),
    ]);
    const signingWallets = selectWallets(wallets, signingRoles);
    const rotationWallets = selectWallets(wallets, rotationRoles);
    await completePendingEvent(
        event,
        signingWallets,
        rotationWallets
    );
    const state = await assertGroupConvergence(
        signingWallets,
        config.qvi.name,
        {
            prefix: event.groupPrefix,
            delegator: args['delegator-prefix'],
            sequence: event.eventSequence,
            signingThreshold: config.qvi.signingThreshold,
            nextThreshold: config.qvi.nextThreshold,
            members: signingWallets.map(({aid}) => aid.prefix),
            signingMembers: signingWallets.map(
                ({aid}) => aid.prefix
            ),
            rotationMembers: rotationWallets.map(
                ({aid}) => aid.prefix
            ),
        },
        event.eventSaid
    );
    await fs.unlink(args.artifact);
    return {status: 'completed', event, state};
}

/** Perform one challenge response or verification with exact result checks. */
async function challenge(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    required(args, 'participant', 'action', 'peer-prefix', 'words');
    const role = args.participant as ParticipantRole;
    if (
        ['qar1', 'qar2', 'qar3', 'qar4', 'person'].includes(role) ===
        false
    ) {
        throw new UsageError(`Unknown participant ${args.participant}`);
    }
    const words = args.words.trim().split(/\s+/);
    if (words.length !== 12) {
        throw new UsageError('Challenge must contain exactly 12 words');
    }
    const client = await connectClient(config.participants[role]);
    if (args.action === 'respond') {
        const exchange = await client
            .challenges()
            .respond(
                config.participants[role].name,
                args['peer-prefix'],
                words
            );
        if (typeof exchange.d !== 'string' || exchange.d.length === 0) {
            throw new Error('Challenge response returned no EXN SAID');
        }
        return {status: 'responded'};
    }
    if (args.action !== 'verify') {
        throw new UsageError(`Unknown challenge action ${args.action}`);
    }
    const completed = await waitOperation(
        client,
        await client
            .challenges()
            .verify(args['peer-prefix'], words)
    );
    const response = completed.response as {
        exn?: {d?: unknown};
    };
    const exchangeSaid = response.exn?.d;
    if (typeof exchangeSaid !== 'string' || exchangeSaid.length === 0) {
        throw new Error(
            'Challenge verification returned an incompatible response'
        );
    }
    const accepted = await client
        .challenges()
        .responded(args['peer-prefix'], exchangeSaid);
    if (accepted.ok !== true) {
        throw new Error('Challenge response was not accepted');
    }
    return {status: 'verified'};
}

/** Resolve an explicit external OOBI list from every generated participant. */
async function resolveExternalOobis(
    config: WorkflowConfig,
    value: string
) {
    const entries = value.split(',').map((entry) => {
        const separator = entry.indexOf('|');
        if (separator <= 0 || separator === entry.length - 1) {
            throw new UsageError(`Invalid OOBI entry ${entry}`);
        }
        return {
            alias: entry.slice(0, separator),
            oobi: requireHttpUrl(
                entry.slice(separator + 1),
                `${entry.slice(0, separator)} OOBI`
            ),
        };
    });
    const roles: ParticipantRole[] = [
        'qar1',
        'qar2',
        'qar3',
        'qar4',
        'person',
    ];
    const wallets = await connectWallets(config, roles);
    await Promise.all(
        wallets.flatMap(({client}) =>
            entries.map(({alias, oobi}) =>
                resolveOobi(client, oobi, alias)
            )
        )
    );
    return {status: 'resolved', count: roles.length * entries.length};
}

/** Boot each configured wallet exactly once. */
async function bootSetupWallets(
    config: WorkflowConfig
): Promise<SetupWallet[]> {
    return await Promise.all(
        SETUP_ROLES.map(async (role) => ({
            role,
            client: await bootClient(config.participants[role]),
        }))
    );
}

/** Resolve all configured witness AIDs in each fresh wallet. */
async function resolveSetupWitnesses(
    config: WorkflowConfig,
    wallets: SetupWallet[]
): Promise<void> {
    const oobis = config.services.witnesses.map(
        ({id, url}, index) =>
            `${url}/oobi/${id}/controller?name=Witness${index + 1}&tag=witness`
    );
    await Promise.all(
        wallets.flatMap(({client}) =>
            oobis.map((oobi) => resolveAidOobi(client, oobi))
        )
    );
}

/** Create each participant AID with its explicitly selected witness. */
async function createSetupAids(
    config: WorkflowConfig,
    wallets: SetupWallet[]
): Promise<ReadyWallet[]> {
    return await Promise.all(
        wallets.map(async (wallet) => {
            const participant = config.participants[wallet.role];
            const witness =
                wallet.role === 'person'
                    ? config.services.witnesses[2]
                    : config.services.witnesses[1];
            const aid = await inceptAid(
                wallet.client,
                participant.name,
                {toad: 1, wits: [witness.id]}
            );
            await authorizeAidAgent(wallet.client, aid);
            return {...wallet, aid};
        })
    );
}

/** Read the public endpoint evidence produced for each participant. */
async function readSetupEvidence(
    config: WorkflowConfig,
    wallets: ReadyWallet[]
): Promise<PreparedWallet[]> {
    return await Promise.all(
        wallets.map(async (wallet) => ({
            ...wallet,
            evidence: await readParticipantEvidence(
                wallet.client,
                config.participants[wallet.role],
                wallet.aid
            ),
        }))
    );
}

/** Resolve every other participant's agent OOBI in each wallet. */
async function resolveSetupPeers(
    config: WorkflowConfig,
    wallets: PreparedWallet[]
): Promise<void> {
    await Promise.all(
        wallets.flatMap((observer) =>
            wallets
                .filter(({role}) => role !== observer.role)
                .map((subject) =>
                    resolveAidOobi(
                        observer.client,
                        subject.evidence.agentOobi,
                        config.participants[subject.role].name
                    )
                )
        )
    );
}

/** Resolve every credential schema in each prepared wallet. */
async function resolveSetupSchemas(
    config: WorkflowConfig,
    wallets: ReadyWallet[]
): Promise<void> {
    const oobis = SCHEMA_SAIDS.map(
        (said) => `${config.services.vleiServerUrl}/oobi/${said}`
    );
    await Promise.all(
        wallets.flatMap(({client}) =>
            oobis.map((oobi) => resolveOobi(client, oobi))
        )
    );
}

/** Return setup evidence for one required participant role. */
function setupEvidence(
    wallets: PreparedWallet[],
    role: ParticipantRole
): ParticipantEvidence {
    const wallet = wallets.find((candidate) => candidate.role === role);
    if (wallet === undefined) {
        throw new Error(`Setup produced no wallet for ${role}`);
    }
    return wallet.evidence;
}

/** Run the explicit fresh-wallet setup sequence and return public evidence. */
async function setupAction(config: WorkflowConfig) {
    assertSignifyVersion();
    const wallets = await bootSetupWallets(config);
    await resolveSetupWitnesses(config, wallets);
    const readyWallets = await createSetupAids(config, wallets);
    const preparedWallets = await readSetupEvidence(
        config,
        readyWallets
    );
    await resolveSetupPeers(config, preparedWallets);
    await resolveSetupSchemas(config, preparedWallets);
    return {
        status: 'ready',
        participants: {
            QAR1: setupEvidence(preparedWallets, 'qar1'),
            QAR2: setupEvidence(preparedWallets, 'qar2'),
            QAR3: setupEvidence(preparedWallets, 'qar3'),
            QAR4: setupEvidence(preparedWallets, 'qar4'),
            PERSON: setupEvidence(preparedWallets, 'person'),
        },
    };
}

/** Resolve one OOBI from the exact participant roles named by Bash. */
async function resolveOobiAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const roles = parseRoles(args.roles, 'Resolution roles');
    const wallets = await connectWallets(config, roles);
    await Promise.all(
        wallets.map(({client}) =>
            resolveAidOobi(
                client,
                args.oobi,
                args.alias
            )
        )
    );
    return {status: 'resolved', roles};
}

/** Refresh one delegator state from the exact participant roles named by Bash. */
async function refreshDelegatorAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const roles = parseRoles(args.roles, 'Refresh roles');
    const wallets = await connectWallets(config, roles);
    await Promise.all(
        wallets.map(async ({client}) => {
            await waitOperation(
                client,
                await client.keyStates().query(args['delegator-prefix'])
            );
        })
    );
    return {status: 'refreshed', roles};
}

/** Rotate the exact member AIDs selected by the outer workflow. */
async function rotateMembersAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const roles = parseRoles(args.roles, 'Member rotation roles');
    const before = await loadWallets(config, roles);
    await Promise.all(
        before.map(async ({client, aid}) => {
            const result = await client.identifiers().rotate(aid.name);
            await waitOperation(client, await result.op());
        })
    );
    const after = await loadWallets(config, roles);
    after.forEach((wallet, index) => {
        const previous = before[index].aid;
        if (
            wallet.aid.prefix !== previous.prefix ||
            wallet.aid.state.s === previous.state.s
        ) {
            throw new Error(
                `Member ${wallet.role} did not complete its key rotation`
            );
        }
    });
    return {
        status: 'rotated',
        members: after.map(({role, aid}) => ({
            role,
            prefix: aid.prefix,
            sequence: aid.state.s,
        })),
    };
}

/** Serially refresh exact subject key states in one observer's KERIA store. */
export async function refreshSubjectsForObserver(
    observer: ReadyWallet,
    subjects: readonly ReadyWallet[]
): Promise<number> {
    let queryCount = 0;

    for (const subject of subjects) {
        if (subject.aid.prefix === observer.aid.prefix) {
            continue;
        }

        const operation = await observer.client
            .keyStates()
            .query(subject.aid.prefix, subject.aid.state.s);
        await waitOperation(observer.client, operation);
        queryCount += 1;
    }

    return queryCount;
}

/** Synchronize subject key states across independent observer stores. */
async function synchronizeKeyStatesAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const observerRoles = parseRoles(
        args['observer-roles'],
        'Observer roles'
    );
    const subjectRoles = parseRoles(
        args['subject-roles'],
        'Subject roles'
    );
    const rolesToLoad = [
        ...new Set([...observerRoles, ...subjectRoles]),
    ];
    const wallets = await loadWallets(config, rolesToLoad);
    const observers = selectWallets(wallets, observerRoles);
    const subjects = selectWallets(wallets, subjectRoles);
    const queryCounts = await Promise.all(
        observers.map((observer) =>
            refreshSubjectsForObserver(observer, subjects)
        )
    );
    return {
        status: 'synchronized',
        queryCount: queryCounts.reduce(
            (total, count) => total + count,
            0
        ),
    };
}

/** Resolve and refresh the group state needed by one joining wallet. */
async function prepareJoiningMemberAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const sourceRoles = parseRoles(
        args['source-role'],
        'Join source role'
    );
    const joiningRoles = parseRoles(
        args['joining-role'],
        'Joining role'
    );
    if (sourceRoles.length !== 1 || joiningRoles.length !== 1) {
        throw new UsageError(
            'Join preparation requires one source and one joining role'
        );
    }
    const [source, joining] = await loadWallets(config, [
        sourceRoles[0],
        joiningRoles[0],
    ]);
    const group = await source.client
        .identifiers()
        .get(config.qvi.name);
    if (group.prefix !== args['group-prefix']) {
        throw new Error(
            `Join source resolved group ${group.prefix}; expected ${args['group-prefix']}`
        );
    }
    if (group.state.s !== args['expected-sequence']) {
        throw new Error(
            `Join source group is at sequence ${group.state.s}; expected ${args['expected-sequence']}`
        );
    }
    const groupOobi = new URL(
        `/oobi/${group.prefix}`,
        config.participants[source.role].oobiUrl
    ).toString();
    const resolved = await resolveAidOobi(
        joining.client,
        groupOobi,
        config.qvi.name
    );
    if (
        resolved.i !== group.prefix ||
        resolved.s !== args['expected-sequence']
    ) {
        throw new Error(
            'Joining wallet did not resolve the expected group state'
        );
    }
    await waitOperation(
        joining.client,
        await joining.client.keyStates().query(group.prefix)
    );
    return {
        status: 'prepared',
        joiningRole: joining.role,
        groupPrefix: group.prefix,
        sequence: group.state.s,
    };
}

/** Submit group inception and persist its typed cross-process handle. */
async function submitInceptionAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const roles = parseRoles(
        args['member-roles'],
        'Inception member roles'
    );
    const wallets = await loadWallets(config, roles);
    const initiator = wallets[0];
    if (initiator === undefined) {
        throw new UsageError('Inception requires at least one member');
    }
    const event = saveGroupEvent(
        'inception',
        await submitGroupInception({
            groupName: config.qvi.name,
            delegatorPrefix: args['delegator-prefix'],
            members: multisigMembers(wallets),
            initiatorPrefix: initiator.aid.prefix,
            signingThreshold: config.qvi.signingThreshold,
            nextThreshold: config.qvi.nextThreshold,
            witnessIds: [config.services.witnesses[1].id],
            witnessThreshold: 1,
        })
    );
    await writePendingArtifact(args.artifact, event);
    return {status: 'submitted', event};
}

/** Submit an ordinary rotation for explicit current and next rosters. */
async function submitRotationAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const signingRoles = parseRoles(
        args['signing-roles'],
        'Signing roles'
    );
    const rotationRoles = parseRoles(
        args['rotation-roles'],
        'Rotation roles'
    );
    const wallets = await loadWallets(config, [
        ...new Set([...signingRoles, ...rotationRoles]),
    ]);
    const signingWallets = selectWallets(wallets, signingRoles);
    const rotationWallets = selectWallets(wallets, rotationRoles);
    const initiator = signingWallets[0];
    if (initiator === undefined) {
        throw new UsageError('Rotation requires at least one signing member');
    }
    const event = saveGroupEvent(
        'rotation',
        await submitGroupRotation({
            groupName: config.qvi.name,
            signingMembers: multisigMembers(signingWallets),
            rotationMembers: rotationWallets.map(({aid}) => aid),
            initiatorPrefix: initiator.aid.prefix,
        })
    );
    await writePendingArtifact(args.artifact, event);
    return {status: 'submitted', event};
}

/** Submit a rotation in which one explicit member joins the group. */
async function submitJoiningRotationAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const joiningRoles = parseRoles(
        args['joining-role'],
        'Joining role'
    );
    if (joiningRoles.length !== 1) {
        throw new UsageError(
            'Joining role must contain exactly one participant'
        );
    }
    const existingRoles = parseRoles(
        args['existing-roles'],
        'Existing roles'
    );
    const signingRoles = parseRoles(
        args['signing-roles'],
        'Signing roles'
    );
    const rotationRoles = parseRoles(
        args['rotation-roles'],
        'Rotation roles'
    );
    const expectedRoles = [...existingRoles, joiningRoles[0]];
    if (
        existingRoles.length !== 2 ||
        JSON.stringify(signingRoles) !==
            JSON.stringify(expectedRoles) ||
        JSON.stringify(rotationRoles) !==
            JSON.stringify(expectedRoles)
    ) {
        throw new UsageError(
            'Joining rotation rosters must contain the existing roles followed by the joining role'
        );
    }
    const wallets = await loadWallets(config, signingRoles);
    const existingWallets = selectWallets(wallets, existingRoles);
    const joiningWallet = selectWallets(
        wallets,
        joiningRoles
    )[0];
    const initiator = existingWallets[0];
    if (initiator === undefined || joiningWallet === undefined) {
        throw new UsageError(
            'Joining rotation requires existing and joining members'
        );
    }
    const signingWallets = selectWallets(wallets, signingRoles);
    const rotationWallets = selectWallets(wallets, rotationRoles);
    const signingAids = signingWallets.map(({aid}) => aid);
    const rotationAids = rotationWallets.map(({aid}) => aid);
    const group = await existingWallets[0].client
        .identifiers()
        .get(config.qvi.name);
    const events: GroupMemberEvent[] = [];
    for (const wallet of existingWallets) {
        events.push(
            await submitRotation({
                groupName: config.qvi.name,
                member: multisigMember(wallet),
                initiatorPrefix: initiator.aid.prefix,
                signingMembers: signingAids,
                rotationMembers: rotationAids,
                recipients: signingAids,
            })
        );
    }
    const proposed = buildGroupEvent(
        signingAids,
        rotationAids,
        events
    );
    events.push(
        await joinRotation({
            groupName: config.qvi.name,
            groupPrefix: group.prefix,
            member: multisigMember(joiningWallet),
            initiatorPrefix: initiator.aid.prefix,
            signingMembers: signingAids,
            rotationMembers: rotationAids,
            recipients: existingWallets.map(({aid}) => aid),
            event: proposed,
        })
    );
    const event = saveGroupEvent(
        'rotation',
        buildGroupEvent(signingAids, rotationAids, events)
    );
    await writePendingArtifact(args.artifact, event);
    return {status: 'submitted', event};
}

/** Authorize the exact final QVI member-agent endpoint set once. */
async function authorizeAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const members = await loadFinalQviMembers(config);
    const initiator = firstGroupMember(members);
    const qviPrefix = initiator.groupAid.prefix;
    if (
        members.some(
            ({groupAid}) => groupAid.prefix !== qviPrefix
        )
    ) {
        throw new Error('QVI members disagree on the group prefix');
    }
    const endpoints = qviAgentEndpoints(config, members);
    const existing = await Promise.all(
        members.map(({client}) =>
            client.oobis().endroles(qviPrefix, 'agent')
        )
    );
    if (existing.some((roles) => roles.length > 0)) {
        throw new Error(
            'QVI agent roles already exist before authorization'
        );
    }
    const timestamp = createTimestamp();
    for (const {eid} of endpoints) {
        await authorizeEndRole({
            members,
            initiatorPrefix: initiator.memberAid.prefix,
            eid,
            timestamp,
        });
    }
    const qviOobi = await retry(() =>
        assertQviEndRoles(
            members.map(({client}) => client),
            config.qvi.name,
            qviPrefix,
            endpoints
        )
    );
    await fs.writeFile(
        `${args['data-dir']}/qvi-oobi.json`,
        JSON.stringify(qviOobi)
    );
    return {
        status: 'authorized',
        ...qviOobi,
    };
}

/** Resolve the validated QVI OOBI from the holder client. */
async function resolvePersonOobiAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const value = JSON.parse(
        readFileSync(args['oobi-file'], 'utf8')
    ) as {qviPrefix?: unknown; multisigOobi?: unknown};
    if (
        typeof value.qviPrefix !== 'string' ||
        typeof value.multisigOobi !== 'string'
    ) {
        throw new Error('QVI OOBI artifact is malformed');
    }
    const client = await connectClient(config.participants.person);
    const state = await resolveAidOobi(
        client,
        value.multisigOobi,
        config.qvi.name
    );
    if (state.i !== value.qviPrefix) {
        throw new Error('Person resolved the wrong QVI prefix');
    }
    return {status: 'resolved', qviPrefix: state.i};
}

/** Create the post-rotation QVI credential registry. */
async function registryAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const members = await loadFinalQviMembers(config);
    const initiator = firstGroupMember(members);
    await createRegistry({
        members,
        initiatorPrefix: initiator.memberAid.prefix,
        groupName: config.qvi.name,
        registryName: args['registry-name'],
    });
    return {
        status: 'created',
        registryRegk: await retry(
            () => loadQviRegistry(members, config.qvi.name)
        ),
    };
}

/** Read one workflow-owned credential fragment from disk. */
async function readCredentialJson(path: string) {
    return JSON.parse(await fs.readFile(path, 'utf8'));
}

/** Require the one QVI registry created by the outer workflow. */
async function loadQviRegistry(
    members: GroupMember[],
    groupName: string
): Promise<string> {
    const registryLists = await Promise.all(
        members.map(({client}) =>
            client.registries().list(groupName)
        )
    );
    const registryId = registryLists[0]?.[0]?.regk;
    const registryConverged =
        registryId !== undefined &&
        registryLists.every(
            (registries) =>
                registries.length === 1 &&
                registries[0].regk === registryId
        );
    if (registryConverged === false) {
        throw new Error(
            'QVI members do not share exactly one credential registry'
        );
    }
    return registryId;
}

/** Build one LE credential from explicit workflow inputs. */
async function leCredentialData(
    members: GroupMember[],
    registryId: string,
    dataDir: string,
    issueePrefix: string
): Promise<CredentialData> {
    const issuer = firstGroupMember(members);
    const subject: CredentialSubject = {
        i: issueePrefix,
        dt: createTimestamp(),
        ...(await readCredentialJson(
            `${dataDir}/temp-data/legal-entity-data.json`
        )),
    };
    return {
        i: issuer.groupAid.prefix,
        ri: registryId,
        s: LE_SCHEMA_SAID,
        a: subject,
        e: await readCredentialJson(
            `${dataDir}/temp-data/qvi-edge.json`
        ),
        r: await readCredentialJson(`${dataDir}/rules/rules.json`),
    };
}

/** Build one OOR credential from explicit workflow inputs. */
async function oorCredentialData(
    members: GroupMember[],
    registryId: string,
    dataDir: string,
    issueePrefix: string
): Promise<CredentialData> {
    const issuer = firstGroupMember(members);
    const subject: CredentialSubject = {
        i: issueePrefix,
        dt: createTimestamp(),
        ...(await readCredentialJson(
            `${dataDir}/temp-data/oor-data.json`
        )),
    };
    return {
        i: issuer.groupAid.prefix,
        ri: registryId,
        s: OOR_SCHEMA_SAID,
        a: subject,
        e: await readCredentialJson(
            `${dataDir}/temp-data/oor-auth-edge.json`
        ),
        r: await readCredentialJson(
            `${dataDir}/rules/oor-rules.json`
        ),
    };
}

/** Build one ECR credential from explicit workflow inputs. */
async function ecrCredentialData(
    members: GroupMember[],
    registryId: string,
    dataDir: string,
    issueePrefix: string
): Promise<CredentialData> {
    const issuer = firstGroupMember(members);
    const subject: CredentialSubject = {
        i: issueePrefix,
        dt: createTimestamp(),
        u: new Salter({}).qb64,
        ...(await readCredentialJson(
            `${dataDir}/temp-data/ecr-data.json`
        )),
    };
    return {
        u: new Salter({}).qb64,
        i: issuer.groupAid.prefix,
        ri: registryId,
        s: ECR_SCHEMA_SAID,
        a: subject,
        e: await readCredentialJson(
            `${dataDir}/temp-data/ecr-auth-edge.json`
        ),
        r: await readCredentialJson(
            `${dataDir}/rules/ecr-rules.json`
        ),
    };
}

/** Build the credential kind selected explicitly by the workflow. */
async function buildCredentialData(
    kind: string,
    members: GroupMember[],
    registryId: string,
    dataDir: string,
    issueePrefix: string
): Promise<CredentialData> {
    switch (kind) {
        case 'le':
            return await leCredentialData(
                members,
                registryId,
                dataDir,
                issueePrefix
            );
        case 'oor':
            return await oorCredentialData(
                members,
                registryId,
                dataDir,
                issueePrefix
            );
        case 'ecr':
            return await ecrCredentialData(
                members,
                registryId,
                dataDir,
                issueePrefix
            );
        default:
            throw new UsageError(`Unknown credential kind ${kind}`);
    }
}

/** Assert one known credential state across the exact QVI observers. */
async function assertKnownQviCredential(
    members: GroupMember[],
    credentialSaid: string,
    statusSequence: string
): Promise<CredentialSnapshot> {
    const initiator = firstGroupMember(members);
    const credential = await getCredential(
        initiator.client,
        credentialSaid
    );
    const snapshot = credentialSnapshot(
        credential,
        initiator.memberAid.prefix
    );
    return await retry(() =>
        assertQviCredentialConvergence(
            members.map(({client, memberAid}) => ({
                client,
                aid: memberAid,
            })),
            {
                credentialSaid,
                issuerPrefix: snapshot.issuer,
                schema: snapshot.schema,
                issueePrefix: snapshot.issuee,
                statusSequence,
            }
        )
    );
}

/** Issue and assert one workflow-selected credential without granting it. */
async function issueAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const members = await loadFinalQviMembers(config);
    const registryId = await loadQviRegistry(
        members,
        config.qvi.name
    );
    const credentialData = await buildCredentialData(
        args.kind,
        members,
        registryId,
        args['data-dir'],
        args['issuee-prefix']
    );
    const initiator = firstGroupMember(members);
    const credentials = await issueCredential({
        members,
        initiatorPrefix: initiator.memberAid.prefix,
        groupName: config.qvi.name,
        issueePrefix: args['issuee-prefix'],
        credentialData,
    });
    const issued = credentials[0];
    if (issued === undefined) {
        throw new Error('Credential issuance returned no credential');
    }
    const credentialSaid = issued.sad.d;
    if (
        typeof credentialSaid !== 'string' ||
        credentialSaid.length === 0
    ) {
        throw new Error('Issued credential has no SAID');
    }
    const snapshot = await assertKnownQviCredential(
        members,
        credentialSaid,
        '0'
    );
    return {
        status: 'issued',
        credentialSaid: snapshot.said,
        registryId: snapshot.registry,
        telDigest: snapshot.currentTelDigest,
    };
}

/** Grant one already-issued credential to its explicit recipient. */
async function grantAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const members = await loadFinalQviMembers(config);
    const initiator = firstGroupMember(members);
    const credentials = await Promise.all(
        members.map(({client}) =>
            getCredential(client, args['credential-said'])
        )
    );
    await grantCredential({
        members,
        initiatorPrefix: initiator.memberAid.prefix,
        recipientPrefix: args['recipient-prefix'],
        credentials,
        timestamp: createTimestamp(),
    });
    return {
        status: 'granted',
        credentialSaid: args['credential-said'],
        recipientPrefix: args['recipient-prefix'],
    };
}

/** Admit one credential and require the actor's immediate postcondition. */
async function admitAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const expected = expectedCredential(args);
    if (args.actor === 'qvi') {
        const members = await loadFinalQviMembers(config);
        const initiator = firstGroupMember(members);
        await admitGroupCredential({
            members,
            initiatorPrefix: initiator.memberAid.prefix,
            issuerPrefix: expected.issuerPrefix,
            credentialSaid: expected.credentialSaid,
            timestamp: createTimestamp(),
        });
        return {
            status: 'admitted',
            state: await retry(() =>
                assertQviCredentialConvergence(
                    members.map(({client, memberAid}) => ({
                        client,
                        aid: memberAid,
                    })),
                    expected
                )
            ),
        };
    }
    if (args.actor === 'person') {
        const person = await loadPersonWallet(config);
        await admitPersonCredential(
            person.client,
            person.aid,
            expected.issuerPrefix,
            expected.credentialSaid
        );
        return {
            status: 'admitted',
            state: await assertPersonCredentialState(
                person,
                expected
            ),
        };
    }
    throw new UsageError(`Unknown admission actor ${args.actor}`);
}

/** Present one credential from the explicitly selected actor. */
async function presentAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    if (args.actor === 'qvi') {
        const members = await loadFinalQviMembers(config);
        return await presentCredential({
            members,
            initiatorPrefix:
                firstGroupMember(members).memberAid.prefix,
            credentialSaid: args['credential-said'],
            recipientPrefix: args['recipient-prefix'],
        });
    }
    if (args.actor === 'person') {
        const person = await loadPersonWallet(config);
        return await presentPersonCredential({
            client: person.client,
            personAid: person.aid,
            credentialSaid: args['credential-said'],
            recipientPrefix: args['recipient-prefix'],
        });
    }
    throw new UsageError(`Unknown presentation actor ${args.actor}`);
}

/** Revoke one QVI-issued credential and return its TEL evidence. */
async function revokeAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const members = await loadFinalQviMembers(config);
    const initiator = firstGroupMember(members);
    await assertKnownQviCredential(
        members,
        args['credential-said'],
        '0'
    );
    const timestamp = createTimestamp();
    await revokeCredential({
        members,
        initiatorPrefix: initiator.memberAid.prefix,
        groupName: config.qvi.name,
        credentialSaid: args['credential-said'],
        timestamp,
    });
    const state = await assertKnownQviCredential(
        members,
        args['credential-said'],
        '1'
    );
    return {
        status: 'revoked' as const,
        credentialSaid: state.said,
        qviPrefix: state.issuer,
        revocationTelDigest: state.currentTelDigest,
        revocationTimestamp: timestamp,
    };
}

/** Assert exact group convergence for Bash's explicit sequence and rosters. */
async function assertGroupAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const signingRoles = parseRoles(
        args['signing-roles'],
        'Signing roles'
    );
    const rotationRoles = parseRoles(
        args['rotation-roles'],
        'Rotation roles'
    );
    const wallets = await loadWallets(config, [
        ...new Set([...signingRoles, ...rotationRoles]),
    ]);
    const signingWallets = selectWallets(wallets, signingRoles);
    const rotationWallets = selectWallets(wallets, rotationRoles);
    return {
        status: 'converged',
        state: await assertGroupConvergence(
            signingWallets,
            config.qvi.name,
            {
                prefix: args['group-prefix'],
                delegator: args['delegator-prefix'],
                sequence: args.sequence,
                signingThreshold: config.qvi.signingThreshold,
                nextThreshold: config.qvi.nextThreshold,
                members: signingWallets.map(({aid}) => aid.prefix),
                signingMembers: signingWallets.map(
                    ({aid}) => aid.prefix
                ),
                rotationMembers: rotationWallets.map(
                    ({aid}) => aid.prefix
                ),
            }
        ),
    };
}

/** Assert exact credential and TEL state for the selected actor. */
async function assertCredentialAction(
    config: WorkflowConfig,
    args: Record<string, string>
) {
    const expected = expectedCredential(args);
    if (args.actor === 'person') {
        return {
            status: 'converged',
            state: await assertPersonCredentialState(
                await loadPersonWallet(config),
                expected
            ),
        };
    }
    if (args.actor === 'qvi') {
        const members = await loadFinalQviMembers(config);
        return {
            status: 'converged',
            state: await assertQviCredentialConvergence(
                members.map(({client, memberAid}) => ({
                    client,
                    aid: memberAid,
                })),
                expected
            ),
        };
    }
    throw new UsageError(`Unknown assertion actor ${args.actor}`);
}

/** Parse and dispatch one explicit wallet action without hidden transitions. */
export async function run(
    argv: string[]
): Promise<Record<string, unknown>> {
    const action = argv[0];
    const values = argv.slice(1);
    let args: Record<string, string>;
    let config: WorkflowConfig;

    switch (action) {
        case 'preflight': {
            args = parseExactArguments(values, 'config');
            readWorkflowConfig(args.config);
            assertSignifyVersion();
            return {status: 'compatible', signifyTs: '0.4.0'};
        }
        case 'ms-setup': {
            args = parseExactArguments(values, 'config');
            return await setupAction(readWorkflowConfig(args.config));
        }
        case 'ms-resolve-external': {
            args = parseExactArguments(values, 'config', 'oobis');
            return await resolveExternalOobis(
                readWorkflowConfig(args.config),
                args.oobis
            );
        }
        case 'ms-resolve-oobi': {
            args = parseExactArguments(
                values,
                'config',
                'alias',
                'oobi',
                'roles'
            );
            return await resolveOobiAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-refresh-delegator': {
            args = parseExactArguments(
                values,
                'config',
                'delegator-prefix',
                'roles'
            );
            return await refreshDelegatorAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-rotate-members': {
            args = parseExactArguments(values, 'config', 'roles');
            return await rotateMembersAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-sync-key-states': {
            args = parseExactArguments(
                values,
                'config',
                'observer-roles',
                'subject-roles'
            );
            return await synchronizeKeyStatesAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-prepare-join': {
            args = parseExactArguments(
                values,
                'config',
                'source-role',
                'joining-role',
                'group-prefix',
                'expected-sequence'
            );
            return await prepareJoiningMemberAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-challenge': {
            args = parseExactArguments(
                values,
                'config',
                'participant',
                'action',
                'peer-prefix',
                'words'
            );
            return await challenge(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-incept-submit': {
            args = parseExactArguments(
                values,
                'config',
                'delegator-prefix',
                'artifact',
                'member-roles'
            );
            return await submitInceptionAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-incept-complete':
        case 'ms-rotate-complete': {
            args = parseExactArguments(
                values,
                'config',
                'delegator-prefix',
                'artifact',
                'expected-sequence',
                'signing-roles',
                'rotation-roles'
            );
            config = readWorkflowConfig(args.config);
            return await completeAndAssert(
                config,
                args,
                action === 'ms-incept-complete'
                    ? 'inception'
                    : 'rotation'
            );
        }
        case 'ms-rotate-submit': {
            args = parseExactArguments(
                values,
                'config',
                'artifact',
                'signing-roles',
                'rotation-roles'
            );
            return await submitRotationAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-join-rotation-submit': {
            args = parseExactArguments(
                values,
                'config',
                'artifact',
                'existing-roles',
                'joining-role',
                'signing-roles',
                'rotation-roles'
            );
            return await submitJoiningRotationAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-authorize': {
            args = parseExactArguments(values, 'config', 'data-dir');
            return await authorizeAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-resolve-person-oobi': {
            args = parseExactArguments(values, 'config', 'oobi-file');
            return await resolvePersonOobiAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-registry': {
            args = parseExactArguments(
                values,
                'config',
                'registry-name'
            );
            return await registryAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-issue': {
            args = parseExactArguments(
                values,
                'config',
                'kind',
                'data-dir',
                'issuee-prefix'
            );
            return await issueAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-grant': {
            args = parseExactArguments(
                values,
                'config',
                'credential-said',
                'recipient-prefix'
            );
            return await grantAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-admit':
        case 'ms-assert-credential': {
            args = parseExactArguments(
                values,
                'config',
                'actor',
                'issuer-prefix',
                'credential-said',
                'schema',
                'issuee-prefix',
                'status-sequence'
            );
            config = readWorkflowConfig(args.config);
            return action === 'ms-admit'
                ? await admitAction(config, args)
                : await assertCredentialAction(config, args);
        }
        case 'ms-present': {
            args = parseExactArguments(
                values,
                'config',
                'actor',
                'credential-said',
                'recipient-prefix'
            );
            return await presentAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        case 'ms-revoke': {
            args = parseExactArguments(
                values,
                'config',
                'credential-said'
            );
            return {
                ...(await revokeAction(
                    readWorkflowConfig(args.config),
                    args
                )),
            };
        }
        case 'ms-assert-group': {
            args = parseExactArguments(
                values,
                'config',
                'group-prefix',
                'delegator-prefix',
                'sequence',
                'signing-roles',
                'rotation-roles'
            );
            return await assertGroupAction(
                readWorkflowConfig(args.config),
                args
            );
        }
        default:
            throw new UsageError(
                `Unknown or missing action ${String(action)}`
            );
    }
}

/** Execute one CLI action and return its single JSON response object. */
export async function main(argv = process.argv.slice(2)): Promise<number> {
    const originalLog = console.log;
    const originalInfo = console.info;
    console.log = (...values: unknown[]) => console.error(...values);
    console.info = (...values: unknown[]) => console.error(...values);
    try {
        const result = await run(argv);
        process.stdout.write(`${JSON.stringify({ok: true, ...result})}\n`);
        return 0;
    } catch (error: unknown) {
        const usage = error instanceof UsageError;
        const message =
            error instanceof Error ? error.message : String(error);
        const stack = error instanceof Error ? error.stack : undefined;
        process.stderr.write(
            `${JSON.stringify({
                ok: false,
                type: usage ? 'usage' : 'workflow',
                error: message,
                ...(stack === undefined ? {} : {stack}),
            })}\n`
        );
        return usage ? 2 : 1;
    } finally {
        console.log = originalLog;
        console.info = originalInfo;
    }
}

const entrypoint = process.argv[1];
if (
    entrypoint !== undefined &&
    pathToFileURL(resolvePath(entrypoint)).href === import.meta.url
) {
    process.exitCode = await main();
}
