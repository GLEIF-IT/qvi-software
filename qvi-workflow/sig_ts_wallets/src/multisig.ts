import signify, {
    assertMultisigRot,
    type CreateIdentiferArgs,
    type HabState,
    type KeyState,
    type Operation,
    Serder,
    type SignifyClient,
} from 'signify-ts';

import {
    connectParticipants,
    getAid,
    resolveAidOobi,
    type WorkflowConfig,
    type ParticipantRole,
    waitOperation,
} from './client.ts';
import {sendExchangeToEachRecipient} from './exchanges.ts';
import {createAIDMultisig} from './multisig-creation.ts';
import {
    completeSavedMemberResults,
    memberContexts,
    submitMemberContributions,
    type MemberSubmission,
    type MultisigMember,
    type MultisigMemberContext,
    type SavedMemberResult,
} from './multisig-coordinator.ts';
import {requireCoordinatedEventDigest} from './multisig-coordination.ts';
import {
    waitForMatchingNotification,
    type MatchedNotification,
} from './notifications.ts';

export interface GroupEventSubmission {
    groupPrefix: string;
    eventSaid: string;
    eventSequence: string;
    signingMembers: string[];
    rotationMembers: string[];
    members: MemberSubmission[];
}

export interface SavedGroupEvent {
    groupPrefix: string;
    eventSaid: string;
    eventSequence: string;
    signingMembers: string[];
    rotationMembers: string[];
    members: SavedMemberResult[];
}

export interface GroupInceptionRequest {
    groupName: string;
    delegatorPrefix: string;
    memberRoles: readonly ParticipantRole[];
    signingThreshold: readonly string[];
    nextThreshold: readonly string[];
    witnessId: string;
}

export interface GroupRotationRequest {
    groupName: string;
    signingRoles: readonly ParticipantRole[];
    rotationRoles: readonly ParticipantRole[];
}

export interface JoiningMemberRotationRequest
    extends GroupRotationRequest {
    existingRoles: readonly ParticipantRole[];
    joiningRole: ParticipantRole;
}

export interface CompleteSavedGroupEventRequest {
    delegatorPrefix: string;
    expectedSigningRoles: readonly ParticipantRole[];
    expectedRotationRoles: readonly ParticipantRole[];
    event: SavedGroupEvent;
}

interface MemberRuntime {
    role: ParticipantRole;
    client: SignifyClient;
    memberAid: HabState;
}

/** Load connected clients and current member AIDs for an explicit roster. */
async function loadMembers(
    config: WorkflowConfig,
    roles: readonly ParticipantRole[]
): Promise<MemberRuntime[]> {
    const clients = await connectParticipants(config, roles);
    return await Promise.all(
        roles.map(async (role) => ({
            role,
            client: clients.get(role)!,
            memberAid: await getAid(
                clients.get(role)!,
                config.participants[role].name
            ),
        }))
    );
}

/** Query every subject from every other roster member before coordination. */
async function synchronizeMemberStates(
    observers: readonly MemberRuntime[],
    subjects: readonly MemberRuntime[]
): Promise<void> {
    for (const observer of observers) {
        for (const subject of subjects) {
            if (observer.memberAid.prefix === subject.memberAid.prefix) {
                continue;
            }
            const operation = await observer.client
                .keyStates()
                .query(subject.memberAid.prefix, subject.memberAid.state.s);
            await waitOperation(observer.client, operation);
        }
    }
}

/** Rotate each explicit member AID and converge the resulting member states. */
async function rotateMemberAids(
    members: MemberRuntime[]
): Promise<MemberRuntime[]> {
    await synchronizeMemberStates(members, members);
    await Promise.all(
        members.map(async ({client, memberAid}) => {
            const result = await client
                .identifiers()
                .rotate(memberAid.name);
            await waitOperation(client, await result.op());
        })
    );
    const rotated = await Promise.all(
        members.map(async (member) => ({
            ...member,
            memberAid: await getAid(
                member.client,
                member.memberAid.name
            ),
        }))
    );
    await synchronizeMemberStates(rotated, rotated);
    return rotated;
}

/** Extract the signature attachment from a signed KERI event message. */
function eventAttachment(
    serder: {size: number},
    signatures: string[],
    message: string
): string {
    if (signatures.length === 0 || message.length <= serder.size) {
        throw new Error('Multisig event has no signature attachment');
    }
    return message.substring(serder.size);
}

/** Submit one current member's group rotation and correlated EXN fan-out. */
async function submitExistingMemberRotation(
    context: MultisigMemberContext,
    groupName: string,
    states: KeyState[],
    rstates: KeyState[],
    recipientAids: HabState[]
): Promise<{
    operation: Operation;
    coordination: MatchedNotification[];
    eventSaid: string;
    eventSequence: string;
}> {
    const result = await context.client
        .identifiers()
        .rotate(groupName, {states, rstates});
    const operation = await result.op();
    const serder = result.serder;
    const sigers = result.sigs.map(
        (signature) => new signify.Siger({qb64: signature})
    );
    const message = signify.d(signify.messagize(serder, sigers));
    const attachment = eventAttachment(serder, result.sigs, message);
    let coordination: MatchedNotification[] = [];
    if (context.isInitiator === false) {
        const notification = await waitForMatchingNotification(
            context.client,
            {
                notificationRoute: '/multisig/rot',
                exchangeRoute: '/multisig/rot',
                sender: context.coordinatorPrefix,
                recipient: context.aid.prefix,
                groupPrefix: serder.pre,
                embeddedDigest: serder.said,
            }
        );
        requireCoordinatedEventDigest(
            notification.exchange,
            '/multisig/rot',
            serder.said
        );
        coordination = [notification];
    }
    await sendExchangeToEachRecipient(context.client, {
        name: context.aid.name,
        topic: groupName,
        sender: context.aid,
        route: '/multisig/rot',
        payload: {
            gid: serder.pre,
            smids: states.map(({i}) => i),
            rmids: rstates.map(({i}) => i),
        },
        embeds: {rot: [serder, attachment]},
        recipients: recipientAids
            .filter(({prefix}) => prefix !== context.aid.prefix)
            .map(({prefix}) => prefix),
    });
    return {
        operation,
        coordination,
        eventSaid: serder.said,
        eventSequence: String(serder.sn),
    };
}

/** Build the live group-event result returned to the workflow boundary. */
function groupEventSubmission(
    groupPrefix: string,
    eventSaid: string,
    eventSequence: string,
    signingMembers: string[],
    rotationMembers: string[],
    members: MemberSubmission[]
): GroupEventSubmission {
    return {
        groupPrefix,
        eventSaid,
        eventSequence,
        signingMembers,
        rotationMembers,
        members,
    };
}

/** Submit delegated QVI inception for the configured initial roster. */
export async function submitGroupInception(
    config: WorkflowConfig,
    request: GroupInceptionRequest
): Promise<GroupEventSubmission> {
    const members = await loadMembers(config, request.memberRoles);
    const states = members.map(({memberAid}) => memberAid.state);
    const createArgs: CreateIdentiferArgs = {
        delpre: request.delegatorPrefix,
        algo: signify.Algos.group,
        isith: [...request.signingThreshold],
        nsith: [...request.nextThreshold],
        toad: 1,
        wits: [request.witnessId],
        states,
        rstates: states,
    };
    let eventSaid = '';
    let groupPrefix = '';
    let eventSequence = '';
    const submissions = await submitMemberContributions(
        members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        async (context) => {
            const result = await createAIDMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                request.groupName,
                {...createArgs, mhab: context.aid},
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            );
            groupPrefix = result.groupPrefix;
            eventSaid = result.eventSaid;
            eventSequence = result.eventSequence;
            return result;
        }
    );
    return groupEventSubmission(
        groupPrefix,
        eventSaid,
        eventSequence,
        states.map(({i}) => i),
        states.map(({i}) => i),
        submissions
    );
}

/**
 * Submit a rotation for explicit signing and next rosters.
 *
 * Workflow policy selects the rosters; this function only executes the
 * supplied protocol plan.
 */
async function submitRosterRotation(
    config: WorkflowConfig,
    request: GroupRotationRequest
): Promise<GroupEventSubmission> {
    const current = await rotateMemberAids(
        await loadMembers(config, request.signingRoles)
    );
    const currentByRole = new Map(
        current.map((member) => [member.role, member])
    );
    const missingRotationRoles = request.rotationRoles.filter(
        (role) => currentByRole.has(role) === false
    );
    const newRotationMembers = await loadMembers(
        config,
        missingRotationRoles
    );
    const allByRole = new Map(
        [...current, ...newRotationMembers].map((member) => [
            member.role,
            member,
        ])
    );
    const next = request.rotationRoles.map((role) => {
        const member = allByRole.get(role);
        if (member === undefined) {
            throw new Error(`Rotation member ${role} was not loaded`);
        }
        return member;
    });
    await synchronizeMemberStates(current, next);
    const states = current.map(({memberAid}) => memberAid.state);
    const rstates = next.map(({memberAid}) => memberAid.state);
    const groupAids = await Promise.all(
        current.map(({client}) =>
            client.identifiers().get(request.groupName)
        )
    );
    let eventSaid = '';
    let eventSequence = '';
    const submissions = await submitMemberContributions(
        current.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        async (context) => {
            const result = await submitExistingMemberRotation(
                context,
                request.groupName,
                states,
                rstates,
                current.map(({memberAid}) => memberAid)
            );
            eventSaid = result.eventSaid;
            eventSequence = result.eventSequence;
            return result;
        }
    );
    return groupEventSubmission(
        groupAids[0].prefix,
        eventSaid,
        eventSequence,
        states.map(({i}) => i),
        rstates.map(({i}) => i),
        submissions
    );
}

/**
 * Rotate a group while one explicitly named member joins.
 *
 * This cohesive protocol operation validates the recipient-bound EXN, creates
 * the joining member's indexed signature, fans it out, and joins the group.
 */
export async function submitJoiningMemberRotation(
    config: WorkflowConfig,
    request: JoiningMemberRotationRequest
): Promise<GroupEventSubmission> {
    if (
        request.existingRoles.length !== 2 ||
        request.signingRoles.length !== 3 ||
        JSON.stringify(request.signingRoles) !==
            JSON.stringify(request.rotationRoles) ||
        JSON.stringify(request.signingRoles) !==
            JSON.stringify([
                ...request.existingRoles,
                request.joiningRole,
            ]) ||
        request.existingRoles.some(
            (role) =>
                role === request.joiningRole ||
                request.signingRoles.includes(role) === false
        )
    ) {
        throw new Error(
            'Joining-member rotation requires two existing roles and identical three-member signing and next rosters'
        );
    }
    let members = await loadMembers(config, request.signingRoles);
    let membersByRole = new Map(
        members.map((member) => [member.role, member])
    );
    const existing = request.existingRoles.map((role) => {
        const member = membersByRole.get(role);
        if (member === undefined) {
            throw new Error(`Existing member ${role} was not loaded`);
        }
        return member;
    });
    const late = membersByRole.get(request.joiningRole);
    if (late === undefined) {
        throw new Error(
            `Joining member ${request.joiningRole} was not loaded`
        );
    }
    const group = await existing[0].client
        .identifiers()
        .get(request.groupName);
    const groupOobi = new URL(
        `/oobi/${group.prefix}`,
        config.participants[request.existingRoles[0]].oobiUrl
    ).toString();
    await resolveAidOobi(late.client, groupOobi, request.groupName);
    await waitOperation(
        late.client,
        await late.client.keyStates().query(group.prefix)
    );

    members = await rotateMemberAids(members);
    membersByRole = new Map(
        members.map((member) => [member.role, member])
    );
    const rotatedExisting = request.existingRoles.map((role) => {
        const member = membersByRole.get(role);
        if (member === undefined) {
            throw new Error(`Rotated existing member ${role} is missing`);
        }
        return member;
    });
    const rotatedLate = membersByRole.get(request.joiningRole);
    if (rotatedLate === undefined) {
        throw new Error('Rotated joining member is missing');
    }
    const states = members.map(({memberAid}) => memberAid.state);
    await synchronizeMemberStates(members, members);
    const multisigMembers: MultisigMember[] = members.map(
        ({client, memberAid}) => ({client, aid: memberAid})
    );
    const contexts = memberContexts(multisigMembers);

    const first = await submitExistingMemberRotation(
        contexts[0],
        request.groupName,
        states,
        states,
        members.map(({memberAid}) => memberAid)
    );
    const second = await submitExistingMemberRotation(
        contexts[1],
        request.groupName,
        states,
        states,
        members.map(({memberAid}) => memberAid)
    );

    const notification = await waitForMatchingNotification(
        rotatedLate.client,
        {
            notificationRoute: '/multisig/rot',
            exchangeRoute: '/multisig/rot',
            sender: members[0].memberAid.prefix,
            recipient: rotatedLate.memberAid.prefix,
            groupPrefix: group.prefix,
            embeddedDigest: first.eventSaid,
        }
    );
    const requests = await rotatedLate.client
        .groups()
        .getRequest(notification.exchangeSaid);
    const matchingRequests = requests.filter(
        ({exn}) => exn.d === notification.exchangeSaid
    );
    if (matchingRequests.length !== 1) {
        throw new Error(
            `Joining member expected one request for ${notification.exchangeSaid}; received ${matchingRequests.length} among ${requests.length}`
        );
    }
    const rotationRequest = assertMultisigRot(matchingRequests[0]);
    const exn = rotationRequest.exn;
    const smids = exn.a.smids;
    const rmids = exn.a.rmids ?? smids;
    const expectedIds = states.map(({i}) => i);
    if (
        exn.a.gid !== group.prefix ||
        JSON.stringify(smids) !== JSON.stringify(expectedIds) ||
        JSON.stringify(rmids) !== JSON.stringify(expectedIds)
    ) {
        throw new Error('Joining member received a divergent rotation proposal');
    }
    const serder = new Serder(exn.e.rot);
    if (serder.said !== first.eventSaid) {
        throw new Error('Joining member received the wrong rotation event');
    }
    const keeper = rotatedLate.client.manager?.get(
        rotatedLate.memberAid
    );
    if (keeper === undefined) {
        throw new Error('Joining member has no local key manager');
    }
    const lateIndex = smids.indexOf(rotatedLate.memberAid.prefix);
    if (lateIndex < 0) {
        throw new Error('Joining member is absent from the signing roster');
    }
    const signatures = await keeper.sign(
        signify.b(serder.raw),
        true,
        [lateIndex],
        [lateIndex]
    );
    const siger = new signify.Siger({qb64: signatures[0]});
    if (siger.index !== lateIndex || siger.ondex !== lateIndex) {
        throw new Error(
            'Joining-member signature indices do not match its roster position'
        );
    }
    const signatureMessage = signify.d(
        signify.messagize(
            serder,
            signatures.map(
                (signature) => new signify.Siger({qb64: signature})
            )
        )
    );
    const attachment = eventAttachment(
        serder,
        signatures,
        signatureMessage
    );
    await sendExchangeToEachRecipient(rotatedLate.client, {
        name: rotatedLate.memberAid.name,
        topic: request.groupName,
        sender: rotatedLate.memberAid,
        route: '/multisig/rot',
        payload: {gid: group.prefix, smids, rmids},
        embeds: {rot: [serder, attachment]},
        recipients: rotatedExisting
            .map(({memberAid}) => memberAid.prefix),
    });
    const joinOperation = await rotatedLate.client
        .groups()
        .join(
            request.groupName,
            serder,
            signatures,
            group.prefix,
            smids,
            rmids
        );
    const submissions: MemberSubmission[] = [
        {
            memberPrefix: rotatedExisting[0].memberAid.prefix,
            operation: first.operation,
            notifications: first.coordination,
        },
        {
            memberPrefix: rotatedExisting[1].memberAid.prefix,
            operation: second.operation,
            notifications: second.coordination,
        },
        {
            memberPrefix: rotatedLate.memberAid.prefix,
            operation: joinOperation,
            notifications: [notification],
        },
    ];
    return groupEventSubmission(
        group.prefix,
        first.eventSaid,
        first.eventSequence,
        expectedIds,
        expectedIds,
        submissions
    );
}

/** Rotate an existing signing roster toward an explicit next roster. */
export async function submitGroupRotation(
    config: WorkflowConfig,
    request: GroupRotationRequest
): Promise<GroupEventSubmission> {
    return await submitRosterRotation(config, request);
}

/** Derive the expected member AID prefixes for persisted-event validation. */
async function expectedRosters(
    config: WorkflowConfig,
    signingRoles: readonly ParticipantRole[],
    rotationRoles: readonly ParticipantRole[]
): Promise<{signing: string[]; rotation: string[]}> {
    const roles = [...new Set([...signingRoles, ...rotationRoles])];
    const clients = await connectParticipants(config, roles);
    const aids = new Map(
        await Promise.all(
            roles.map(async (role) => [
                role,
                await getAid(
                    clients.get(role)!,
                    config.participants[role].name
                ),
            ] as const)
        )
    );
    return {
        signing: signingRoles.map((role) => aids.get(role)!.prefix),
        rotation: rotationRoles.map((role) => aids.get(role)!.prefix),
    };
}

/** Validate, complete, and retain evidence for one GEDA-approved group event. */
export async function completeSavedGroupEvent(
    config: WorkflowConfig,
    request: CompleteSavedGroupEventRequest
): Promise<SavedGroupEvent> {
    const event = request.event;
    const expected = await expectedRosters(
        config,
        request.expectedSigningRoles,
        request.expectedRotationRoles
    );
    if (
        JSON.stringify(event.signingMembers) !==
            JSON.stringify(expected.signing) ||
        JSON.stringify(event.rotationMembers) !==
            JSON.stringify(expected.rotation)
    ) {
        throw new Error('Pending event rosters do not match active participants');
    }
    const signingRoles = request.expectedSigningRoles;
    const clients = await connectParticipants(config, signingRoles);
    const memberAids = await Promise.all(
        signingRoles.map((role) =>
            getAid(
                clients.get(role)!,
                config.participants[role].name
            )
        )
    );
    const clientsByPrefix = new Map(
        signingRoles.map((role, index) => [
            memberAids[index].prefix,
            clients.get(role)!,
        ])
    );
    if (
        new Set(event.members.map(({memberPrefix}) => memberPrefix)).size !==
            3 ||
        event.members.some(
            ({memberPrefix}) => clientsByPrefix.has(memberPrefix) === false
        )
    ) {
        throw new Error(
            'Pending operation members do not match the signing roster'
        );
    }
    await Promise.all(
        signingRoles.map(async (role) => {
            const client = clients.get(role)!;
            await waitOperation(
                client,
                await client
                    .keyStates()
                    .query(request.delegatorPrefix)
            );
        })
    );
    await completeSavedMemberResults(clientsByPrefix, event.members);
    return event;
}
