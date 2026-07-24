import signify, {
    assertMultisigRot,
    type CreateIdentiferArgs,
    type HabState,
    type KeyState,
    type Operation,
    Serder,
} from 'signify-ts';

import {sendExchangeToEachRecipient} from './exchanges.ts';
import {createAIDMultisig} from './multisig-creation.ts';
import {
    completeSavedMemberResults,
    memberContexts,
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
    members: MultisigMember[];
    signingThreshold: readonly string[];
    nextThreshold: readonly string[];
    witnessId: string;
}

export interface GroupRotationRequest {
    groupName: string;
    signingMembers: MultisigMember[];
    rotationMembers: HabState[];
}

export interface JoiningMemberRotationRequest {
    groupName: string;
    groupPrefix: string;
    existingMembers: MultisigMember[];
    joiningMember: MultisigMember;
}

export interface CompleteGroupEventRequest {
    signingMembers: MultisigMember[];
    rotationMembers: HabState[];
    event: SavedGroupEvent;
}

interface SubmittedMemberEvent {
    member: MemberSubmission;
    groupPrefix: string;
    eventSaid: string;
    eventSequence: string;
}

interface MemberEventResult {
    operation: Operation;
    coordination: MatchedNotification[];
    groupPrefix: string;
    eventSaid: string;
    eventSequence: string;
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
async function submitMemberRotation(
    context: MultisigMemberContext,
    groupName: string,
    states: KeyState[],
    rstates: KeyState[],
    recipientAids: HabState[]
): Promise<MemberEventResult> {
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
        groupPrefix: serder.pre,
        eventSaid: serder.said,
        eventSequence: String(serder.sn),
    };
}

/** Convert one member event result into a concrete submission record. */
function submittedMemberEvent(
    memberPrefix: string,
    result: MemberEventResult
): SubmittedMemberEvent {
    return {
        member: {
            memberPrefix,
            operation: result.operation,
            notifications: result.coordination,
        },
        groupPrefix: result.groupPrefix,
        eventSaid: result.eventSaid,
        eventSequence: result.eventSequence,
    };
}

/** Require every member contribution to describe the same group event. */
function commonEvent(
    events: SubmittedMemberEvent[]
): SubmittedMemberEvent {
    const first = events[0];
    if (first === undefined) {
        throw new Error('No multisig member event was submitted');
    }
    const eventsAgree = events.every(
        (event) =>
            event.groupPrefix === first.groupPrefix &&
            event.eventSaid === first.eventSaid &&
            event.eventSequence === first.eventSequence
    );
    if (eventsAgree === false) {
        throw new Error('Multisig members submitted divergent group events');
    }
    return first;
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

/** Submit delegated group inception from concrete member wallets. */
export async function submitGroupInception(
    request: GroupInceptionRequest
): Promise<GroupEventSubmission> {
    const states = request.members.map(({aid}) => aid.state);
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
    const events: SubmittedMemberEvent[] = [];
    for (const context of memberContexts(request.members)) {
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
        events.push(
            submittedMemberEvent(context.aid.prefix, result)
        );
    }
    const event = commonEvent(events);
    return groupEventSubmission(
        event.groupPrefix,
        event.eventSaid,
        event.eventSequence,
        states.map(({i}) => i),
        states.map(({i}) => i),
        events.map(({member}) => member)
    );
}

/** Submit one group rotation from concrete signing and next rosters. */
export async function submitGroupRotation(
    request: GroupRotationRequest
): Promise<GroupEventSubmission> {
    const signingAids = request.signingMembers.map(({aid}) => aid);
    const rotationAids = request.rotationMembers;
    if (
        rotationAids.length !== 3 ||
        new Set(rotationAids.map(({prefix}) => prefix)).size !== 3
    ) {
        throw new Error(
            'Group rotation requires three unique next members'
        );
    }
    const states = signingAids.map(({state}) => state);
    const rstates = rotationAids.map(({state}) => state);
    const events: SubmittedMemberEvent[] = [];
    for (const context of memberContexts(request.signingMembers)) {
        const result = await submitMemberRotation(
            context,
            request.groupName,
            states,
            rstates,
            signingAids
        );
        events.push(
            submittedMemberEvent(context.aid.prefix, result)
        );
    }
    const event = commonEvent(events);
    return groupEventSubmission(
        event.groupPrefix,
        event.eventSaid,
        event.eventSequence,
        states.map(({i}) => i),
        rstates.map(({i}) => i),
        events.map(({member}) => member)
    );
}

/**
 * Submit a group rotation while one explicitly named member joins.
 *
 * This cohesive protocol operation validates the recipient-bound EXN, creates
 * the joining member's indexed signature, fans it out, and joins the group.
 */
export async function joinGroupRotation(
    request: JoiningMemberRotationRequest
): Promise<GroupEventSubmission> {
    if (request.existingMembers.length !== 2) {
        throw new Error(
            'Joining-member rotation requires two existing members'
        );
    }
    const members = [
        ...request.existingMembers,
        request.joiningMember,
    ];
    const contexts = memberContexts(members);
    const states = members.map(({aid}) => aid.state);
    const existing = request.existingMembers;
    const joining = request.joiningMember;

    const first = await submitMemberRotation(
        contexts[0],
        request.groupName,
        states,
        states,
        members.map(({aid}) => aid)
    );
    const second = await submitMemberRotation(
        contexts[1],
        request.groupName,
        states,
        states,
        members.map(({aid}) => aid)
    );
    commonEvent([
        submittedMemberEvent(existing[0].aid.prefix, first),
        submittedMemberEvent(existing[1].aid.prefix, second),
    ]);

    const notification = await waitForMatchingNotification(
        joining.client,
        {
            notificationRoute: '/multisig/rot',
            exchangeRoute: '/multisig/rot',
            sender: members[0].aid.prefix,
            recipient: joining.aid.prefix,
            groupPrefix: request.groupPrefix,
            embeddedDigest: first.eventSaid,
        }
    );
    const requests = await joining.client
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
        exn.a.gid !== request.groupPrefix ||
        JSON.stringify(smids) !== JSON.stringify(expectedIds) ||
        JSON.stringify(rmids) !== JSON.stringify(expectedIds)
    ) {
        throw new Error('Joining member received a divergent rotation proposal');
    }
    const serder = new Serder(exn.e.rot);
    if (serder.said !== first.eventSaid) {
        throw new Error('Joining member received the wrong rotation event');
    }
    const keeper = joining.client.manager?.get(joining.aid);
    if (keeper === undefined) {
        throw new Error('Joining member has no local key manager');
    }
    const lateIndex = smids.indexOf(joining.aid.prefix);
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
    await sendExchangeToEachRecipient(joining.client, {
        name: joining.aid.name,
        topic: request.groupName,
        sender: joining.aid,
        route: '/multisig/rot',
        payload: {gid: request.groupPrefix, smids, rmids},
        embeds: {rot: [serder, attachment]},
        recipients: existing.map(({aid}) => aid.prefix),
    });
    const joinOperation = await joining.client
        .groups()
        .join(
            request.groupName,
            serder,
            signatures,
            request.groupPrefix,
            smids,
            rmids
        );
    const submissions: MemberSubmission[] = [
        {
            memberPrefix: existing[0].aid.prefix,
            operation: first.operation,
            notifications: first.coordination,
        },
        {
            memberPrefix: existing[1].aid.prefix,
            operation: second.operation,
            notifications: second.coordination,
        },
        {
            memberPrefix: joining.aid.prefix,
            operation: joinOperation,
            notifications: [notification],
        },
    ];
    return groupEventSubmission(
        request.groupPrefix,
        first.eventSaid,
        first.eventSequence,
        expectedIds,
        expectedIds,
        submissions
    );
}

/** Validate, complete, and retain evidence for one GEDA-approved group event. */
export async function completeGroupEvent(
    request: CompleteGroupEventRequest
): Promise<SavedGroupEvent> {
    const event = request.event;
    const expectedSigning = request.signingMembers.map(
        ({aid}) => aid.prefix
    );
    const expectedRotation = request.rotationMembers.map(
        ({prefix}) => prefix
    );
    if (
        JSON.stringify(event.signingMembers) !==
            JSON.stringify(expectedSigning) ||
        JSON.stringify(event.rotationMembers) !==
            JSON.stringify(expectedRotation)
    ) {
        throw new Error('Pending event rosters do not match active participants');
    }
    const clientsByPrefix = new Map(
        request.signingMembers.map(({client, aid}) => [
            aid.prefix,
            client,
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
    await completeSavedMemberResults(clientsByPrefix, event.members);
    return event;
}
