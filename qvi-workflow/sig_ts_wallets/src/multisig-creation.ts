import signify, {
    type CreateIdentiferArgs,
    type HabState,
    type Operation,
    type SignifyClient,
} from 'signify-ts';

import type {GroupMember} from './client.ts';
import {coordinateMultisigOperation} from './multisig-coordinator.ts';
import {
    sendExchangeToEachRecipient,
} from './exchanges.ts';
import {
    waitForMatchingNotification,
} from './notifications.ts';

/**
 * Creates a multisig group with the given delegate member AID and other delegate member AIDs.
 * If not the initiator, waits for a "/multisig/icp" exchange (exn)
 * notification before sending the member's coordination messages. The
 * notification remains unread until the caller proves terminal inception
 * success.
 * Each member sends exn messages to each of the other participants.
 *
 * @param client The SignifyClient instance of the Controller AID making this request
 * @param aid The delegate member AID participating in the multisig group
 * @param otherMembersAIDs The other delegate member AIDs participating in the multisig group
 * @param groupName The name label of the multisig group. Should be the same across all multisig participants.
 * @param kargs The arguments for creating the identifier
 * @param initiatorPrefix member prefix that submits the proposal
 */
export interface EndRoleRequest {
    members: GroupMember[];
    initiatorPrefix: string;
    eid: string;
    timestamp: string;
}

export interface MultisigEventResult {
    operation: Operation;
    notificationIds: string[];
    groupPrefix: string;
    eventSaid: string;
    eventSequence: string;
}

export async function createAIDMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    groupName: string,
    kargs: CreateIdentiferArgs,
    initiatorPrefix: string
): Promise<MultisigEventResult> {
    const participantIsFollower = aid.prefix !== initiatorPrefix;
    const icpResult = await client.identifiers().create(groupName, kargs);
    const op = await icpResult.op();

    const serder = icpResult.serder;
    const sigs = icpResult.sigs;
    const sigers = sigs.map((sig) => new signify.Siger({ qb64: sig }));
    const ims = signify.d(signify.messagize(serder, sigers));
    const atc = ims.substring(serder.size);
    const embeds = {
        icp: [serder, atc],
    };
    const smids = kargs.states?.map((state) => state['i']);
    const recp = otherMembersAIDs.map((aid) => aid.prefix);

    let notificationIds: string[] = [];
    if (participantIsFollower) {
        const notification = await waitForMatchingNotification(client, {
            exchangeRoute: '/multisig/icp',
            sender: initiatorPrefix,
            recipient: aid.prefix,
            groupPrefix: serder.pre,
            embeddedDigest: serder.said,
        });
        notificationIds = notification.notificationIds;
    }

    await sendExchangeToEachRecipient(client, {
        name: aid.name,
        topic: 'multisig',
        sender: aid,
        route: '/multisig/icp',
        payload: {gid: serder.pre, smids, rmids: smids},
        embeds,
        recipients: recp,
    });

    return {
        operation: op,
        notificationIds,
        groupPrefix: serder.pre,
        eventSaid: serder.said,
        eventSequence: String(serder.sn),
    };
}

export async function addEndRoleMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    multisigAID: HabState,
    eid: string,
    timestamp: string,
    initiatorPrefix: string
): Promise<{
    operation: Operation;
    notificationIds: string[];
}> {
    const participantIsFollower = aid.prefix !== initiatorPrefix;

    const endRoleResult = await client
        .identifiers()
        .addEndRole(multisigAID.name, 'agent', eid, timestamp);
    const op = await endRoleResult.op();
    const rpy = endRoleResult.serder;
    const sigs = endRoleResult.sigs;
    const ghabState1 = multisigAID.state;
    const seal = [
        'SealEvent',
        {
            i: multisigAID.prefix,
            s: ghabState1['ee']['s'],
            d: ghabState1['ee']['d'],
        },
    ];
    const sigers = sigs.map(
        (sig: string) => new signify.Siger({qb64: sig})
    );
    const roleims = signify.d(
        signify.messagize(rpy, sigers, seal, undefined, undefined, false)
    );
    const atc = roleims.substring(rpy.size);
    const roleembeds = {
        rpy: [rpy, atc],
    };
    const recp = otherMembersAIDs.map((member) => member.prefix);
    let notificationIds: string[] = [];
    if (participantIsFollower) {
        const notification = await waitForMatchingNotification(client, {
            exchangeRoute: '/multisig/rpy',
            sender: initiatorPrefix,
            recipient: aid.prefix,
            groupPrefix: multisigAID.prefix,
            payloadFields: {eid},
            embeddedDigest: rpy.said,
        });
        notificationIds = notification.notificationIds;
    }
    await sendExchangeToEachRecipient(client, {
        name: aid.name,
        topic: 'multisig',
        sender: aid,
        route: '/multisig/rpy',
        payload: {gid: multisigAID.prefix, eid},
        embeds: roleembeds,
        recipients: recp,
    });
    return {
        operation: op,
        notificationIds,
    };
}

/** Authorize one explicit endpoint through concrete group members. */
export async function authorizeEndRole(
    request: EndRoleRequest
): Promise<void> {
    await coordinateMultisigOperation(
        request.members.map(({client, memberAid}) => ({
            client,
            aid: memberAid,
        })),
        request.initiatorPrefix,
        (context) => {
            const member = request.members.find(
                ({memberAid}) =>
                    memberAid.prefix === context.aid.prefix
            );
            if (member === undefined) {
                throw new Error(
                    `Missing group member ${context.aid.prefix}`
                );
            }
            return addEndRoleMultisig(
                context.client,
                context.aid,
                context.otherMembers,
                member.groupAid,
                request.eid,
                request.timestamp,
                context.initiatorPrefix
            );
        }
    );
}
