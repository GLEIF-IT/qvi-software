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
import {requireCoordinatedEventDigest} from './multisig-coordination.ts';
import {
    waitForMatchingNotification,
    type MatchedNotification,
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
 * @param options coordination role and designated initiator
 */
export interface MultisigCoordinationOptions {
    isInitiator?: boolean;
    coordinator?: string;
}

export interface EndRoleRequest {
    members: GroupMember[];
    initiatorPrefix: string;
    eid: string;
    timestamp: string;
}

export interface MultisigEventResult {
    operation: Operation;
    coordination: MatchedNotification[];
    groupPrefix: string;
    eventSaid: string;
    eventSequence: string;
}

function requireCoordinator(
    options: MultisigCoordinationOptions,
    participantIsFollower: boolean,
    route: string
): string | undefined {
    if (participantIsFollower === false) {
        return undefined;
    }
    const coordinatorIsMissing =
        typeof options.coordinator !== 'string' ||
        options.coordinator.length === 0;
    if (coordinatorIsMissing) {
        throw new Error(
            `${route} follower requires an explicit coordinator prefix`
        );
    }
    return options.coordinator;
}

export async function createAIDMultisig(
    client: SignifyClient,
    aid: HabState,
    otherMembersAIDs: HabState[],
    groupName: string,
    kargs: CreateIdentiferArgs,
    options: MultisigCoordinationOptions
): Promise<MultisigEventResult> {
    const participantIsFollower = options.isInitiator !== true;
    const coordinator = requireCoordinator(
        options,
        participantIsFollower,
        '/multisig/icp'
    );
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

    let coordination: MatchedNotification | undefined;
    if (participantIsFollower) {
        coordination = await waitForMatchingNotification(client, {
            notificationRoute: '/multisig/icp',
            exchangeRoute: '/multisig/icp',
            sender: coordinator,
            recipient: aid.prefix,
            groupPrefix: serder.pre,
            embeddedDigest: serder.said,
        });
    }

    if (coordination !== undefined) {
        requireCoordinatedEventDigest(
            coordination.exchange,
            '/multisig/icp',
            serder.said
        );
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
        coordination:
            coordination === undefined ? [] : [coordination],
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
    options: MultisigCoordinationOptions
): Promise<{
    operation: Operation;
    coordination: MatchedNotification[];
}> {
    const participantIsFollower = options.isInitiator !== true;
    const coordinator = requireCoordinator(
        options,
        participantIsFollower,
        '/multisig/rpy'
    );

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
    let coordination: MatchedNotification | undefined;
    if (participantIsFollower) {
        coordination = await waitForMatchingNotification(client, {
            notificationRoute: '/multisig/rpy',
            exchangeRoute: '/multisig/rpy',
            sender: coordinator,
            recipient: aid.prefix,
            groupPrefix: multisigAID.prefix,
            payloadFields: {eid},
            embeddedDigest: rpy.said,
        });
    }
    if (coordination !== undefined) {
        requireCoordinatedEventDigest(
            coordination.exchange,
            '/multisig/rpy',
            rpy.said
        );
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
        coordination:
            coordination === undefined ? [] : [coordination],
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
                {
                    isInitiator: context.isInitiator,
                    coordinator: context.coordinatorPrefix,
                }
            );
        }
    );
}
