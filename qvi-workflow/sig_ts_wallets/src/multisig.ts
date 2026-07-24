import signify, {
    assertMultisigRot,
    type CreateIdentiferArgs,
    type HabState,
    type KeyState,
    Serder,
} from 'signify-ts';

import {sendExchangeToEachRecipient} from './exchanges.ts';
import {createAIDMultisig} from './multisig-creation.ts';
import {
    memberContexts,
    type MemberSubmission,
    type MultisigMember,
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

export interface GroupInceptionRequest {
    groupName: string;
    delegatorPrefix: string;
    members: MultisigMember[];
    initiatorPrefix: string;
    signingThreshold: readonly string[];
    nextThreshold: readonly string[];
    witnessIds: string[];
    witnessThreshold: number;
}

export interface GroupRotationRequest {
    groupName: string;
    signingMembers: MultisigMember[];
    rotationMembers: HabState[];
    initiatorPrefix: string;
}

export interface RotationRequest {
    groupName: string;
    member: MultisigMember;
    initiatorPrefix: string;
    signingMembers: HabState[];
    rotationMembers: HabState[];
    recipients: HabState[];
}

export interface JoinRotationRequest {
    groupName: string;
    groupPrefix: string;
    member: MultisigMember;
    initiatorPrefix: string;
    signingMembers: HabState[];
    rotationMembers: HabState[];
    recipients: HabState[];
    event: GroupEventSubmission;
}

export interface GroupMemberEvent {
    member: MemberSubmission;
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

/** Submit one member's group rotation and correlated EXN fan-out. */
export async function submitRotation(
    request: RotationRequest
): Promise<GroupMemberEvent> {
    const member = request.member;
    const states: KeyState[] = request.signingMembers.map(
        ({state}) => state
    );
    const rstates: KeyState[] = request.rotationMembers.map(
        ({state}) => state
    );
    const result = await member.client
        .identifiers()
        .rotate(request.groupName, {states, rstates});
    const operation = await result.op();
    const serder = result.serder;
    const sigers = result.sigs.map(
        (signature) => new signify.Siger({qb64: signature})
    );
    const message = signify.d(signify.messagize(serder, sigers));
    const attachment = eventAttachment(serder, result.sigs, message);
    let coordination: MatchedNotification[] = [];
    if (member.aid.prefix !== request.initiatorPrefix) {
        const notification = await waitForMatchingNotification(
            member.client,
            {
                notificationRoute: '/multisig/rot',
                exchangeRoute: '/multisig/rot',
                sender: request.initiatorPrefix,
                recipient: member.aid.prefix,
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
    await sendExchangeToEachRecipient(member.client, {
        name: member.aid.name,
        topic: request.groupName,
        sender: member.aid,
        route: '/multisig/rot',
        payload: {
            gid: serder.pre,
            smids: states.map(({i}) => i),
            rmids: rstates.map(({i}) => i),
        },
        embeds: {rot: [serder, attachment]},
        recipients: request.recipients
            .filter(({prefix}) => prefix !== member.aid.prefix)
            .map(({prefix}) => prefix),
    });
    return {
        member: {
            memberPrefix: member.aid.prefix,
            operation,
            notifications: coordination,
        },
        groupPrefix: serder.pre,
        eventSaid: serder.said,
        eventSequence: String(serder.sn),
    };
}

/** Require every member contribution to describe the same group event. */
function commonEvent(
    events: GroupMemberEvent[]
): GroupMemberEvent {
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

/** Combine matching member contributions into one group event result. */
export function buildGroupEvent(
    signingMembers: HabState[],
    rotationMembers: HabState[],
    events: GroupMemberEvent[]
): GroupEventSubmission {
    const event = commonEvent(events);
    return {
        groupPrefix: event.groupPrefix,
        eventSaid: event.eventSaid,
        eventSequence: event.eventSequence,
        signingMembers: signingMembers.map(({prefix}) => prefix),
        rotationMembers: rotationMembers.map(({prefix}) => prefix),
        members: events.map(({member}) => member),
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
        toad: request.witnessThreshold,
        wits: request.witnessIds,
        states,
        rstates: states,
    };
    const events: GroupMemberEvent[] = [];
    for (const context of memberContexts(
        request.members,
        request.initiatorPrefix
    )) {
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
        events.push({
            member: {
                memberPrefix: context.aid.prefix,
                operation: result.operation,
                notifications: result.coordination,
            },
            groupPrefix: result.groupPrefix,
            eventSaid: result.eventSaid,
            eventSequence: result.eventSequence,
        });
    }
    return buildGroupEvent(
        request.members.map(({aid}) => aid),
        request.members.map(({aid}) => aid),
        events
    );
}

/** Submit one group rotation from concrete signing and next rosters. */
export async function submitGroupRotation(
    request: GroupRotationRequest
): Promise<GroupEventSubmission> {
    const signingAids = request.signingMembers.map(({aid}) => aid);
    const rotationAids = request.rotationMembers;
    if (rotationAids.length === 0) {
        throw new Error('Group rotation requires next members');
    }
    if (
        new Set(rotationAids.map(({prefix}) => prefix)).size !==
        rotationAids.length
    ) {
        throw new Error(
            'Group rotation requires unique next members'
        );
    }
    const events: GroupMemberEvent[] = [];
    for (const context of memberContexts(
        request.signingMembers,
        request.initiatorPrefix
    )) {
        events.push(
            await submitRotation({
                groupName: request.groupName,
                member: context,
                initiatorPrefix: request.initiatorPrefix,
                signingMembers: signingAids,
                rotationMembers: rotationAids,
                recipients: signingAids,
            })
        );
    }
    return buildGroupEvent(signingAids, rotationAids, events);
}

/**
 * Join one concrete member to an already submitted group rotation.
 *
 * This protocol operation validates the recipient-bound EXN, creates the
 * joining member's indexed signature, fans it out, and joins the group.
 */
export async function joinRotation(
    request: JoinRotationRequest
): Promise<GroupMemberEvent> {
    const joining = request.member;
    const notification = await waitForMatchingNotification(
        joining.client,
        {
            notificationRoute: '/multisig/rot',
            exchangeRoute: '/multisig/rot',
            sender: request.initiatorPrefix,
            recipient: joining.aid.prefix,
            groupPrefix: request.groupPrefix,
            embeddedDigest: request.event.eventSaid,
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
    const expectedSigning = request.signingMembers.map(
        ({prefix}) => prefix
    );
    const expectedRotation = request.rotationMembers.map(
        ({prefix}) => prefix
    );
    if (
        exn.a.gid !== request.groupPrefix ||
        JSON.stringify(smids) !== JSON.stringify(expectedSigning) ||
        JSON.stringify(rmids) !== JSON.stringify(expectedRotation)
    ) {
        throw new Error('Joining member received a divergent rotation proposal');
    }
    const serder = new Serder(exn.e.rot);
    if (
        serder.said !== request.event.eventSaid ||
        String(serder.sn) !== request.event.eventSequence
    ) {
        throw new Error('Joining member received the wrong rotation event');
    }
    const keeper = joining.client.manager?.get(joining.aid);
    if (keeper === undefined) {
        throw new Error('Joining member has no local key manager');
    }
    const signingIndex = smids.indexOf(joining.aid.prefix);
    const rotationIndex = rmids.indexOf(joining.aid.prefix);
    if (signingIndex < 0 || rotationIndex < 0) {
        throw new Error('Joining member is absent from the signing roster');
    }
    const signatures = await keeper.sign(
        signify.b(serder.raw),
        true,
        [signingIndex],
        [rotationIndex]
    );
    const siger = new signify.Siger({qb64: signatures[0]});
    if (
        siger.index !== signingIndex ||
        siger.ondex !== rotationIndex
    ) {
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
        recipients: request.recipients.map(({prefix}) => prefix),
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
    return {
        member: {
            memberPrefix: joining.aid.prefix,
            operation: joinOperation,
            notifications: [notification],
        },
        groupPrefix: request.groupPrefix,
        eventSaid: request.event.eventSaid,
        eventSequence: request.event.eventSequence,
    };
}
